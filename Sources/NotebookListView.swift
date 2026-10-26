import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

// MARK: - Notebook / folder list
//
// Global impact: this is the only place that lists notes. It loads
// manifests + thumbnails only (DocumentStore.loadManifests), never
// pages.json, so a large note cannot slow the list. Opening a note
// loads its full pages on a background queue (DocumentStore).
// iPhone and iPad share this view; iPad gets a split view in
// InkNoteApp, iPhone gets a stack navigation. Both paths call the
// same store methods, so a store change must be verified on both
// idioms (see DEVELOPMENT_LOG.md, device checklist).
//
// The body is deliberately broken into small computed properties and
// a separate row view: a single large SwiftUI expression in this file
// previously timed out the type checker, so do not re-merge it.

public struct NotebookListView: View {
    @ObservedObject public var store: DocumentStore
    @State private var selectedFolder = "Unsorted"
    @State private var showingNewNote = false
    @State private var showingNewFolder = false
    @State private var showingImport = false
    @State private var newNoteName = ""
    @State private var newFolderName = ""
    @State private var renameTarget: NoteManifest?
    @State private var renameText = ""
    @State private var deleteTarget: NoteManifest?
    @State private var selectedNoteID: UUID?

    public init(store: DocumentStore) {
        self.store = store
    }

    public var body: some View {
        listView
            .navigationTitle("InkNote")
            .toolbar {
                ToolbarItemGroup(placement: .primaryAction) {
                    Button("Import .note") { showingImport = true }
                    Button("Folder") { showingNewFolder = true }
                    Button("New Note") { showingNewNote = true }
                }
            }
            .onAppear { store.loadManifests() }
            .alert("New Note", isPresented: $showingNewNote) {
                TextField("Note name", text: $newNoteName)
                Button("Create") { createNote() }
                Button("Cancel", role: .cancel) { newNoteName = "" }
            }
            .alert("New Folder", isPresented: $showingNewFolder) {
                TextField("Folder name", text: $newFolderName)
                Button("Create") { createFolder() }
                Button("Cancel", role: .cancel) { newFolderName = "" }
            }
            .alert("Rename Note", isPresented: renameBinding) {
                TextField("Name", text: $renameText)
                Button("Save") { saveRename() }
                Button("Cancel", role: .cancel) { renameTarget = nil }
            }
            .alert("Delete Note?", isPresented: deleteBinding) {
                Button("Delete", role: .destructive) { confirmDelete() }
                Button("Cancel", role: .cancel) { deleteTarget = nil }
            } message: {
                Text("This deletes the InkNote package. An imported original .note file is never deleted by InkNote.")
            }
            .sheet(isPresented: $showingImport) {
                ImportView(store: store)
            }
            .navigationDestination(item: $selectedNoteID) { noteID in
                NoteDestinationView(store: store, noteID: noteID)
            }
    }

    private var renameBinding: Binding<Bool> {
        Binding(get: { renameTarget != nil }, set: { if !$0 { renameTarget = nil } })
    }

    private var deleteBinding: Binding<Bool> {
        Binding(get: { deleteTarget != nil }, set: { if !$0 { deleteTarget = nil } })
    }

    private var listView: some View {
        List {
            folderSection
            notesSection
        }
    }

    private var folderSection: some View {
        Section("Folder") {
            Picker("Folder", selection: $selectedFolder) {
                ForEach(store.folders, id: \.self) { folder in
                    Text(folder).tag(folder)
                }
            }
            .pickerStyle(.menu)
        }
    }

    private var notesSection: some View {
        Section("Notes in \(selectedFolder)") {
            ForEach(store.manifests.filter { $0.folder == selectedFolder }) { manifest in
                NoteRowView(store: store, manifest: manifest, onOpen: {
                    selectedNoteID = manifest.id
                }, onRename: {
                    renameTarget = manifest
                    renameText = manifest.name
                }, onDelete: {
                    deleteTarget = manifest
                })
            }
        }
    }

    private func createNote() {
        let name = newNoteName.isEmpty ? "Untitled" : newNoteName
        let document = store.createNote(name: name, folder: selectedFolder)
        newNoteName = ""
        selectedNoteID = document.manifest.id
    }

    private func createFolder() {
        if !newFolderName.isEmpty {
            store.addFolder(newFolderName)
            selectedFolder = newFolderName
        }
        newFolderName = ""
    }

    private func saveRename() {
        if let target = renameTarget, !renameText.isEmpty {
            store.renameNote(id: target.id, newName: renameText)
        }
        renameTarget = nil
    }

    private func confirmDelete() {
        if let target = deleteTarget { store.deleteNote(id: target.id) }
        deleteTarget = nil
    }
}

private struct NoteRowView: View {
    var store: DocumentStore
    var manifest: NoteManifest
    var onOpen: () -> Void
    var onRename: () -> Void
    var onDelete: () -> Void

    var body: some View {
        Button(action: onOpen) {
            HStack {
                ThumbnailView(store: store, noteID: manifest.id)
                VStack(alignment: .leading) {
                    Text(manifest.name).lineLimit(1)
                    HStack(spacing: 4) {
                        Text(manifest.source == "imported-note" ? "Imported" : "InkNote")
                        Text(manifest.modifiedAt, style: .date)
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
            }
        }
        .swipeActions {
            Button("Rename", action: onRename).tint(.blue)
            Button("Delete", role: .destructive, action: onDelete)
        }
    }
}

/// Loads only thumb.png for one row, on a background task. If there is
/// no thumbnail yet, a plain placeholder is shown; the list never
/// renders the full note to make a thumbnail.
private struct ThumbnailView: View {
    var store: DocumentStore
    var noteID: UUID
    @State private var image: UIImage?
    var body: some View {
        Group {
            if let image = image {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                Color.gray.opacity(0.2)
            }
        }
        .frame(width: 44, height: 56)
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .task(id: noteID) {
            let dir = store.noteDirectory(for: noteID)
            let url = dir.appendingPathComponent("thumb.png")
            let loaded = await Task.detached(priority: .utility) {
                return UIImage(contentsOfFile: url.path)
            }.value
            image = loaded
        }
    }
}

private struct NoteDestinationView: View {
    var store: DocumentStore
    var noteID: UUID
    @State private var document: InkNoteDocument?
    @State private var loadFailed = false
    @State private var attempt = 0
    var body: some View {
        Group {
            if let document = document {
                if document.pdfFileName != nil {
                    PDFNoteView(store: store, document: document)
                } else {
                    NoteEditorView(store: store, document: document)
                }
            } else if loadFailed {
                VStack(spacing: 12) {
                    Text("Failed to load note")
                        .font(.headline)
                    Text("Your note file is still on this device and was not deleted. Tap Retry to load it again.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                    Button("Retry") {
                        loadFailed = false
                        attempt += 1
                    }
                    .buttonStyle(.borderedProminent)
                }
                .padding()
            } else {
                ProgressView("Loading note…")
            }
        }
        .task(id: attempt) {
            load()
        }
    }
    private func load() {
        if document != nil { return }
        if let cached = store.documents[noteID] {
            document = cached
            return
        }
        store.loadDocument(id: noteID) { loaded in
            if let loaded = loaded {
                document = loaded
            } else {
                loadFailed = true
            }
        }
    }
}
