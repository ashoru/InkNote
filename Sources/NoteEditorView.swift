import SwiftUI
import PencilKit

// MARK: - Paper-note editor
//
// One page at a time, to keep memory bounded on long notes: only the
// current page's PKDrawing is held in the canvas. Switching pages saves
// the current page first (canonical conversion), then loads the next
// page. The canvas is shown at 1:1 page points inside a ScrollView, so
// canvas coordinates are canonical page coordinates on both iPhone and
// iPad.
//
// Localization (0.1.2): static labels are literals (LocalizedStringKey
// via the catalog); the page indicator is a localized format, composed
// with String(format:) and shown verbatim so it is not re-localized.
// The note name is user data and goes through Text(verbatim:) in the
// navigation title.
//
// Look (0.1.2): the chrome background is the system grouped background
// (adapts to light / dark), the paper itself stays white content with
// a margin and a soft shadow, so the page has depth in both modes.
// The paper is never painted dark: it is content, not chrome.
// Save feedback is transient: the "Saved" line clears itself after
// 1.5 seconds instead of occupying a permanent row. Save icon choice:
// checkmark, not tray.and.arrow.down — this is an in-place persist,
// not a download or an export to another location (export already
// uses square.and.arrow.up, import uses square.and.arrow.down), so a
// download-style icon would confuse save with import/export.

public struct NoteEditorView: View {
    @ObservedObject public var store: DocumentStore
    @State public var document: InkNoteDocument
    @State private var pageIndex = 0
    @State private var drawing = PKDrawing()
    @State private var saveMessage = ""
    @State private var saveToken = 0

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
                Button { saveCurrentPage(); if pageIndex > 0 { pageIndex -= 1; loadCurrentPage() } } label: {
                    Label("Previous", systemImage: "chevron.left")
                }
                .disabled(pageIndex == 0)
                Spacer()
                Text(verbatim: String(format: String(localized: "Page %lld of %lld"), pageIndex + 1, document.pages.count))
                    .font(.subheadline)
                Spacer()
                Button { saveCurrentPage(); if pageIndex < document.pages.count - 1 { pageIndex += 1; loadCurrentPage() } } label: {
                    Label("Next", systemImage: "chevron.right")
                }
                .disabled(pageIndex >= document.pages.count - 1)
                Button {
                    saveCurrentPage()
                    let newPage = NotePage(index: document.pages.count, width: currentPage.width, height: currentPage.height, template: currentPage.template)
                    document.pages.append(newPage)
                    pageIndex = document.pages.count - 1
                    loadCurrentPage()
                } label: {
                    Label("Add Page", systemImage: "plus")
                }
                Button { saveCurrentPage(); store.saveDocument(document) { showSaved() } } label: {
                    Label("Save", systemImage: "checkmark")
                }
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
                .frame(width: pageSize.width, height: pageSize.height)
                .background(Color.white)
                .shadow(color: .black.opacity(0.18), radius: 8, x: 0, y: 2)
                .padding(16)
            }
            .onAppear { loadCurrentPage() }
            .onChange(of: pageIndex) { _, _ in loadCurrentPage() }
            if !saveMessage.isEmpty {
                Text(verbatim: saveMessage).font(.caption).foregroundStyle(.secondary).padding(4)
            }
            Text("Future in this editor: NAS sync, audio transcription, handwriting recognition and handwritten formula solving are interface-only in v1 (see FutureServices).")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(8)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle(Text(verbatim: document.manifest.name))
        .onDisappear {
            saveCurrentPage()
            store.saveDocument(document, completion: nil)
        }
    }

    private func showSaved() {
        saveMessage = String(localized: "Saved")
        saveToken += 1
        let token = saveToken
        Task {
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            if token == saveToken {
                saveMessage = ""
            }
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
