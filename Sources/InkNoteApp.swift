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
                    Text("Select a note, or create a new one.")
                        .foregroundStyle(.secondary)
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
