import SwiftUI
import PencilKit

// MARK: - Paper-note editor
//
// One page at a time, to keep memory bounded on long notes: only the
// current page's PKDrawing is held in the canvas. Switching pages saves
// the current page first (canonical conversion), then loads the next
// page. The canvas size is the page size scaled to fit the available
// width; canonical coordinates are page points, obtained by dividing
// canvas coordinates by that scale on save and multiplying on load.

public struct NoteEditorView: View {
    @ObservedObject public var store: DocumentStore
    @State public var document: InkNoteDocument
    @State private var pageIndex = 0
    @State private var drawing = PKDrawing()
    @State private var saveMessage = ""

    public init(store: DocumentStore, document: InkNoteDocument) {
        self.store = store
        self._document = State(initialValue: document)
    }

    private var currentPage: NotePage {
        document.pages[min(pageIndex, max(0, document.pages.count - 1))]
    }

    public var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button("Previous") { saveCurrentPage(); if pageIndex > 0 { pageIndex -= 1; loadCurrentPage() } }
                    .disabled(pageIndex == 0)
                Spacer()
                Text("Page \(pageIndex + 1) of \(document.pages.count)")
                    .font(.subheadline)
                Spacer()
                Button("Add Page") {
                    saveCurrentPage()
                    let newPage = NotePage(index: document.pages.count, width: currentPage.width, height: currentPage.height, template: currentPage.template)
                    document.pages.append(newPage)
                    pageIndex = document.pages.count - 1
                    loadCurrentPage()
                }
                Button("Save") { saveCurrentPage(); store.saveDocument(document) { saveMessage = "Saved" } }
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
            ScrollView([.horizontal, .vertical]) {
                let pageSize = CGSize(width: currentPage.width, height: currentPage.height)
                ZStack {
                    PaperTemplateView(template: currentPage.template, pageSize: pageSize)
                    PencilCanvasView(drawing: $drawing) { newDrawing in
                        drawing = newDrawing
                    }
                    .frame(width: pageSize.width, height: pageSize.height)
                }
            }
            .onAppear { loadCurrentPage() }
            .onChange(of: pageIndex) { _, _ in loadCurrentPage() }
            if !saveMessage.isEmpty {
                Text(saveMessage).font(.caption).foregroundStyle(.secondary).padding(4)
            }
            Text("Future in this editor: NAS sync, audio transcription, handwriting recognition and handwritten formula solving are interface-only in v1 (see FutureServices).")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(8)
        }
        .navigationTitle(document.manifest.name)
        .onDisappear {
            saveCurrentPage()
            store.saveDocument(document, completion: nil)
        }
    }

    private func loadCurrentPage() {
        // Canvas is shown at 1:1 page points inside a ScrollView, so
        // canvas coordinates ARE canonical page coordinates. No scale
        // transform is needed on load or save, which is what keeps
        // iPhone and iPad strokes aligned to the same page.
        drawing = CanonicalPencilConversion.drawing(from: currentPage.strokes)
    }

    private func saveCurrentPage() {
        var page = currentPage
        page.strokes = CanonicalPencilConversion.canonicalStrokes(from: drawing)
        if pageIndex < document.pages.count {
            document.pages[pageIndex] = page
        }
    }
}
