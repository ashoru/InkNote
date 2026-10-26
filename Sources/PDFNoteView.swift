import SwiftUI
import PencilKit
import PDFKit
#if canImport(UIKit)
import UIKit
#endif

// MARK: - PDF annotation view (v1, rendered export)
//
// A PDF note keeps its original PDF verbatim in the package. For v1,
// each PDF page is rendered to an image on a background queue, the
// PencilKit canvas is overlaid at exactly that image size, and export
// composites the same page image + the same drawing image into a new
// PDF. Display and export therefore use the same coordinates, so an
// annotation cannot be aligned on screen and misaligned in the export.
// Limitation, stated honestly: the exported PDF is rendered (raster),
// not a vector ink annotation. Vector ink export is a future stage;
// it must not be claimed for v1.

#if canImport(UIKit)
public struct PDFNoteView: View {
    @ObservedObject public var store: DocumentStore
    @State public var document: InkNoteDocument
    @State private var pageImages: [UIImage] = []
    @State private var pageIndex = 0
    @State private var drawing = PKDrawing()
    @State private var exportURL: URL?
    @State private var showingShare = false
    @State private var loadError = ""

    public init(store: DocumentStore, document: InkNoteDocument) {
        self.store = store
        self._document = State(initialValue: document)
    }

    public var body: some View {
        VStack {
            HStack {
                Button("Previous") { saveCurrentPage(); if pageIndex > 0 { pageIndex -= 1; loadCurrentPage() } }
                    .disabled(pageIndex == 0)
                Spacer()
                Text("PDF page \(pageIndex + 1) of \(max(pageImages.count, 1))")
                    .font(.subheadline)
                Spacer()
                Button("Export PDF") { exportAnnotatedPDF() }
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
            if !loadError.isEmpty {
                Text(loadError).foregroundStyle(.red).padding()
            } else if pageImages.isEmpty {
                ProgressView("Loading PDF…")
            } else {
                ScrollView([.horizontal, .vertical]) {
                    let image = pageImages[pageIndex]
                    ZStack(alignment: .topLeading) {
                        Image(uiImage: image)
                            .resizable()
                            .frame(width: image.size.width, height: image.size.height)
                        PencilCanvasView(drawing: $drawing) { newDrawing in
                            drawing = newDrawing
                        }
                        .frame(width: image.size.width, height: image.size.height)
                    }
                }
                .onAppear { loadCurrentPage() }
                .onChange(of: pageIndex) { _, _ in loadCurrentPage() }
            }
        }
        .navigationTitle(document.manifest.name)
        .task { await loadPDFPages() }
        .onDisappear {
            saveCurrentPage()
            store.saveDocument(document, completion: nil)
        }
        .sheet(isPresented: $showingShare) {
            if let url = exportURL {
                ShareLink("Exported PDF", item: url)
            }
        }
    }

    private func loadPDFPages() async {
        guard let pdfName = document.pdfFileName else {
            loadError = "This note has no PDF file."
            return
        }
        let dir = store.noteDirectory(for: document.manifest.id)
        let url = dir.appendingPathComponent(pdfName)
        let images = await Task.detached(priority: .utility) { () -> [UIImage] in
            guard let pdf = PDFDocument(url: url) else { return [] }
            var result: [UIImage] = []
            for i in 0..<pdf.pageCount {
                guard let page = pdf.page(at: i) else { continue }
                let size = page.bounds(for: .mediaBox).size
                let renderSize = CGSize(width: min(size.width, 1024), height: min(size.height, 1024) * (size.height / max(size.width, 1)))
                // Use the page's own size, scaled to a bounded width for
                // memory, preserving aspect ratio.
                let scale = min(1024 / max(size.width, 1), 1024 / max(size.height, 1), 1.0)
                let target = CGSize(width: size.width * scale, height: size.height * scale)
                _ = renderSize
                let image = page.thumbnail(of: target, for: .mediaBox)
                result.append(image)
            }
            return result
        }.value
        if images.isEmpty {
            loadError = "Could not load the PDF file."
        } else {
            pageImages = images
            // Ensure the canonical document has one page per PDF page.
            if document.pages.count != images.count {
                var pages: [NotePage] = []
                for i in 0..<images.count {
                    let existing = document.pages.first { $0.pdfPageIndex == i }
                    pages.append(existing ?? NotePage(index: i, width: Double(images[i].size.width), height: Double(images[i].size.height), template: .blank, pdfPageIndex: i))
                }
                document.pages = pages
            }
            loadCurrentPage()
        }
    }

    private func loadCurrentPage() {
        guard pageIndex < document.pages.count else { return }
        drawing = CanonicalPencilConversion.drawing(from: document.pages[pageIndex].strokes)
    }

    private func saveCurrentPage() {
        guard pageIndex < document.pages.count else { return }
        document.pages[pageIndex].strokes = CanonicalPencilConversion.canonicalStrokes(from: drawing)
    }

    private func exportAnnotatedPDF() {
        saveCurrentPage()
        store.saveDocument(document) {
            // Export on a background queue: render each page image +
            // its drawing image into a PDF context, one page at a time.
            DispatchQueue.global(qos: .utility).async {
                let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("\(document.manifest.name)-annotated.pdf")
                let format = UIGraphicsPDFRendererFormat()
                // Page size: first page image size, in points.
                guard let first = pageImages.first else { return }
                let renderer = UIGraphicsPDFRenderer(bounds: CGRect(origin: .zero, size: first.size), format: format)
                do {
                    try renderer.writePDF(to: tempURL) { context in
                        for (index, image) in pageImages.enumerated() {
                            context.beginPage()
                            image.draw(in: CGRect(origin: .zero, size: image.size))
                            if index < document.pages.count {
                                let strokesImage = CanonicalPencilConversion.image(for: document.pages[index].strokes, pageSize: image.size, scale: 1.0)
                                strokesImage.draw(in: CGRect(origin: .zero, size: image.size))
                            }
                        }
                    }
                    DispatchQueue.main.async {
                        exportURL = tempURL
                        showingShare = true
                    }
                } catch {
                    DispatchQueue.main.async {
                        loadError = "Export failed: \(error.localizedDescription)"
                    }
                }
            }
        }
    }
}
#endif
