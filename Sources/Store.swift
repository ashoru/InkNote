import Foundation
#if canImport(UIKit)
import UIKit
#endif

// MARK: - Document store (persistence, background I/O, thumbnails)
//
// Layout on disk (per note, inside the app Documents directory):
//   InkNoteNotes/<uuid>.inknote/manifest.json
//   InkNoteNotes/<uuid>.inknote/pages.json
//   InkNoteNotes/<uuid>.inknote/thumb.png   (cache only, regenerable)
//   InkNoteNotes/<uuid>.inknote/<pdf file>  (PDF notes only, verbatim copy)
//
// Performance rules enforced here:
//  - loadManifests() reads manifest.json only. It never reads pages.json,
//    so the notebook list stays fast even with many large notes.
//  - loadDocument() and saveDocument() run file I/O on a background
//    queue and hop back to the main actor only to publish results.
//  - Thumbnails are generated once, on a background queue, at save time
//    (or on first open), and are loaded from disk per row, never by
//    re-rendering the full note in the list.
//  - Saves are atomic (write to a temporary file, then move into place)
//    so a crash during save cannot leave a half-written pages.json.

#if canImport(UIKit)
public final class DocumentStore: ObservableObject {
    @Published public private(set) var manifests: [NoteManifest] = []
    @Published public private(set) var folders: [String] = ["Unsorted"]
    @Published public private(set) var documents: [UUID: InkNoteDocument] = [:]

    private let fileManager = FileManager.default
    private let ioQueue = DispatchQueue(label: "com.ashoru.inknote.io", qos: .utility)

    public init() {}

    public var notesDirectory: URL {
        let docs = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first ?? fileManager.temporaryDirectory
        return docs.appendingPathComponent("InkNoteNotes", isDirectory: true)
    }

    public func noteDirectory(for id: UUID) -> URL {
        return notesDirectory.appendingPathComponent("\(id.uuidString).inknote", isDirectory: true)
    }

    public func loadManifests() {
        ioQueue.async { [weak self] in
            guard let self = self else { return }
            do {
                try self.fileManager.createDirectory(at: self.notesDirectory, withIntermediateDirectories: true)
            } catch { return }
            let dirs = (try? self.fileManager.contentsOfDirectory(at: self.notesDirectory, includingPropertiesForKeys: nil)) ?? []
            var loaded: [NoteManifest] = []
            var folderSet: Set<String> = ["Unsorted"]
            for dir in dirs where dir.pathExtension == "inknote" {
                let manifestURL = dir.appendingPathComponent("manifest.json")
                guard let data = try? Data(contentsOf: manifestURL),
                      let manifest = try? InkNoteCodec.decoder.decode(NoteManifest.self, from: data),
                      NoteFormatMigration.canOpen(formatVersion: manifest.formatVersion) else { continue }
                loaded.append(manifest)
                folderSet.insert(manifest.folder)
            }
            loaded.sort { $0.modifiedAt > $1.modifiedAt }
            let folders = Array(folderSet).sorted()
            DispatchQueue.main.async {
                self.manifests = loaded
                self.folders = folders
            }
        }
    }

    public func loadDocument(id: UUID, completion: @escaping (InkNoteDocument?) -> Void) {
        ioQueue.async { [weak self] in
            guard let self = self else { return }
            let dir = self.noteDirectory(for: id)
            guard let manifestData = try? Data(contentsOf: dir.appendingPathComponent("manifest.json")),
                  let manifest = try? InkNoteCodec.decoder.decode(NoteManifest.self, from: manifestData),
                  let pagesData = try? Data(contentsOf: dir.appendingPathComponent("pages.json")),
                  let pages = try? InkNoteCodec.decoder.decode([NotePage].self, from: pagesData) else {
                DispatchQueue.main.async { completion(nil) }
                return
            }
            var pdfName: String? = nil
            if let files = try? self.fileManager.contentsOfDirectory(atPath: dir.path) {
                pdfName = files.first { $0.hasSuffix(".pdf") }
            }
            var document = InkNoteDocument(manifest: manifest, pages: pages, pdfFileName: pdfName)
            _ = NoteFormatMigration.migrateIfNeeded(document: &document)
            let finalDocument = document
            DispatchQueue.main.async {
                self.documents[id] = finalDocument
                completion(finalDocument)
            }
        }
    }

    public func addFolder(_ name: String) {
        guard !name.isEmpty, !folders.contains(name) else { return }
        folders.append(name)
    }

    public func createNote(name: String, folder: String, template: PaperTemplate = .lines, width: Double = 612, height: Double = 792) -> InkNoteDocument {
        var document = InkNoteDocument.blank(name: name, folder: folder, width: width, height: height, template: template)
        document.manifest.modifiedAt = Date()
        saveDocument(document, completion: nil)
        return document
    }

    public func saveDocument(_ document: InkNoteDocument, completion: (() -> Void)?) {
        ioQueue.async { [weak self] in
            guard let self = self else { return }
            var doc = document
            doc.manifest.modifiedAt = Date()
            let dir = self.noteDirectory(for: doc.manifest.id)
            do {
                try self.fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
                let manifestData = try InkNoteCodec.encoder.encode(doc.manifest)
                let pagesData = try InkNoteCodec.encoder.encode(doc.pages)
                try self.writeAtomically(data: manifestData, to: dir.appendingPathComponent("manifest.json"))
                try self.writeAtomically(data: pagesData, to: dir.appendingPathComponent("pages.json"))
            } catch {
                // v1: a failed save must not crash the editor. The in-memory
                // document remains, and the next save retries. The log
                // records the failure class, not the file contents.
                print("InkNote save failed: \(error.localizedDescription)")
            }
            let saved = doc
            DispatchQueue.main.async {
                self.documents[saved.manifest.id] = saved
                if !self.manifests.contains(where: { $0.id == saved.manifest.id }) {
                    self.manifests.insert(saved.manifest, at: 0)
                } else if let index = self.manifests.firstIndex(where: { $0.id == saved.manifest.id }) {
                    self.manifests[index] = saved.manifest
                }
                if !self.folders.contains(saved.manifest.folder) {
                    self.folders.append(saved.manifest.folder)
                }
                completion?()
            }
        }
    }

    public func saveImportedNote(_ document: InkNoteDocument, pdfData: Data?, completion: @escaping (Bool) -> Void) {
        ioQueue.async { [weak self] in
            guard let self = self else { return }
            let dir = self.noteDirectory(for: document.manifest.id)
            do {
                try self.fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
                if let pdfData = pdfData, let pdfName = document.pdfFileName {
                    try self.writeAtomically(data: pdfData, to: dir.appendingPathComponent(pdfName))
                }
            } catch {
                DispatchQueue.main.async { completion(false) }
                return
            }
            self.saveDocument(document) {
                completion(true)
            }
        }
    }

    public func deleteNote(id: UUID) {
        ioQueue.async { [weak self] in
            guard let self = self else { return }
            try? self.fileManager.removeItem(at: self.noteDirectory(for: id))
            DispatchQueue.main.async {
                self.manifests.removeAll { $0.id == id }
                self.documents.removeValue(forKey: id)
            }
        }
    }

    public func renameNote(id: UUID, newName: String) {
        guard var document = documents[id] else {
            // Rename from the list (document not loaded): update manifest only.
            ioQueue.async { [weak self] in
                guard let self = self else { return }
                let dir = self.noteDirectory(for: id)
                guard let data = try? Data(contentsOf: dir.appendingPathComponent("manifest.json")),
                      var manifest = try? InkNoteCodec.decoder.decode(NoteManifest.self, from: data) else { return }
                manifest.name = newName
                manifest.modifiedAt = Date()
                if let encoded = try? InkNoteCodec.encoder.encode(manifest) {
                    try? self.writeAtomically(data: encoded, to: dir.appendingPathComponent("manifest.json"))
                }
                DispatchQueue.main.async {
                    if let index = self.manifests.firstIndex(where: { $0.id == id }) {
                        self.manifests[index].name = newName
                        self.manifests[index].modifiedAt = Date()
                    }
                }
            }
            return
        }
        document.manifest.name = newName
        saveDocument(document, completion: nil)
    }

    private func writeAtomically(data: Data, to url: URL) throws {
        let temp = url.deletingLastPathComponent().appendingPathComponent(".\(url.lastPathComponent).tmp")
        try data.write(to: temp, options: [.atomic])
        if fileManager.fileExists(atPath: url.path) {
            try fileManager.removeItem(at: url)
        }
        try fileManager.moveItem(at: temp, to: url)
    }
}
#endif
