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
//
// Localization (0.1.2): every static label here is a string literal,
// so SwiftUI treats it as a LocalizedStringKey and looks it up in
// Localizable.xcstrings (zh-Hans / en, following the system language).
// User data is the exception and is always shown verbatim: note names,
// user-created folder names, and the already-localized display string
// from DisplayStrings. Never pass user data through Text(String),
// which would re-localize a name that happens to match a catalog key.
// Folder filtering and Picker tags always use the storage value
// ("Unsorted", never the display word), so old notes cannot be lost
// by a language switch; see DisplayStrings for the mapping rule.
// Search filters only the in-memory manifests, never pages.json.

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
    @State private var searchText = ""

    public init(store: DocumentStore) {
        self.store = store
    }

    public var body: some View {
        listView
            .navigationTitle("InkNote")
            .toolbar {
                ToolbarItemGroup(placement: .primaryAction) {
                    Button { showingImport = true } label: {
                        Label("Import .note", systemImage: "square.and.arrow.down")
                    }
                    Button { showingNewFolder = true } label: {
                        Label("Folder", systemImage: "folder")
                    }
                    Button { showingNewNote = true } label: {
                        Label("New Note", systemImage: "square.and.pencil")
                    }
                }
            }
            .searchable(text: $searchText)
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

    private var filteredManifests: [NoteManifest] {
        store.manifests.filter { manifest in
            guard manifest.folder == selectedFolder else { return false }
            if searchText.isEmpty { return true }
            return manifest.name.localizedCaseInsensitiveContains(searchText)
        }
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
                    // Display word localized, tag is the storage value.
                    Text(verbatim: DisplayStrings.folderDisplayName(folder)).tag(folder)
                }
            }
            .pickerStyle(.menu)
        }
    }

    private var notesSection: some View {
        Section {
            if filteredManifests.isEmpty {
                emptyState
            } else {
                ForEach(filteredManifests) { manifest in
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
        } header: {
            Text(verbatim: String(format: String(localized: "Notes in %@"), DisplayStrings.folderDisplayName(selectedFolder)))
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "note.text")
                .font(.largeTitle)
                .foregroundStyle(.secondary)
            if searchText.isEmpty {
                Text("No notes yet")
                    .font(.headline)
                Button { showingNewNote = true } label: {
                    Label("New Note", systemImage: "square.and.pencil")
                }
                .buttonStyle(.bordered)
            } else {
                Text("No matching notes")
                    .font(.headline)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
    }

    private func createNote() {
        // Empty name takes the current system language's default at
        // creation time ("Untitled" / "Untitled" -> "未命名" in zh).
        // It is a name, not a filter key, so existing notes keep
        // whatever name they already have when the language changes.
        let name = newNoteName.isEmpty ? String(localized: "Untitled") : newNoteName
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
                    Text(verbatim: manifest.name).lineLimit(1)
                    HStack(spacing: 4) {
                        Text(verbatim: DisplayStrings.sourceDisplayName(manifest.source))
                        Text(manifest.modifiedAt, style: .date)
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
            }
        }
        .swipeActions {
            Button(action: onRename) {
                Label("Rename", systemImage: "pencil")
            }
            .tint(.blue)
            Button(role: .destructive, action: onDelete) {
                Label("Delete", systemImage: "trash")
            }
        }
    }
}

/// Loads only thumb.png for one row, on a background task. If there is
/// no thumbnail yet, a plain placeholder is shown; the list never
/// renders the full note to make a thumbnail. Thumbnail size is one
/// step up from v1 (56x72, capped below the 60x76 budget) so rows read
/// better without making the list stutter.
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
        .frame(width: 56, height: 72)
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
                    Button {
                        loadFailed = false
                        attempt += 1
                    } label: {
                        Label("Retry", systemImage: "arrow.clockwise")
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
