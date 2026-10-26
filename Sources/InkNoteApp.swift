import SwiftUI

// MARK: - InkNote v1 app entry
//
// InkNote is a personal-use handwriting note app built from scratch.
// It does not use, copy or embed any other note app's code, assets,
// icons or trademarked name. Paper templates are drawn in code
// (PaperTemplateView), the ink model is canonical (CanonicalModel),
// and PencilKit / PDFKit are Apple's public frameworks.
//
// iPhone and iPad share the same NotebookListView and the same
// DocumentStore. On iPad the list is shown in a split view; on iPhone
// it is a stack navigation. Both idioms must be verified on device
// (see DEVELOPMENT_LOG.md, device checklist).
//
// Localization (0.1.2): the iPad detail placeholder is a real empty
// state (icon + sentence + New Note button), not a single grey line.
// Its New Note button creates a note in the Unsorted folder, which
// then appears in the list to open; the detail pane itself is not a
// navigation destination in v1, so the button does not jump straight
// into the editor. That limit is recorded in the development log.

@main
public struct InkNoteApp: App {
    @StateObject private var store = DocumentStore()

    public init() {}

    public var body: some Scene {
        WindowGroup {
            #if os(iOS)
            if UIDevice.current.userInterfaceIdiom == .pad {
                NavigationSplitView {
                    NotebookListView(store: store)
                } detail: {
                    VStack(spacing: 16) {
                        Image(systemName: "note.text")
                            .font(.largeTitle)
                            .foregroundStyle(.secondary)
                        Text("Select a note, or create a new one.")
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                        Button {
                            _ = store.createNote(name: String(localized: "Untitled"), folder: "Unsorted")
                        } label: {
                            Label("New Note", systemImage: "square.and.pencil")
                        }
                        .buttonStyle(.bordered)
                    }
                    .padding()
                }
            } else {
                NavigationStack {
                    NotebookListView(store: store)
                }
            }
            #else
            NavigationStack {
                NotebookListView(store: store)
            }
            #endif
        }
    }
}
