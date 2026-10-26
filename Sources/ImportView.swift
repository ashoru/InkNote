import SwiftUI
#if canImport(UIKit)
import UIKit
import UniformTypeIdentifiers
#endif

// MARK: - .note import view (v1 prototype)
//
// The user picks a .note file. The importer parses it on a background
// queue (never the main thread), reports curve count, point count,
// paper size and PDF presence, and only then saves a canonical
// InkNoteDocument. The original .note file is never modified.
// If the file contains media or audio that v1 does not parse, the
// import still succeeds for strokes + PDF and the result screen says
// so explicitly; it does not claim a complete import.

#if canImport(UIKit)
public struct ImportView: View {
    @ObservedObject public var store: DocumentStore
    @State private var showingPicker = false
    @State private var resultText = ""
    @State private var isImporting = false

    public init(store: DocumentStore) {
        self.store = store
    }

    public var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                Text("Import a .note package exported from your own notes. The original file is never modified.")
                    .multilineTextAlignment(.center)
                    .padding()
                Button("Choose .note File") { showingPicker = true }
                    .buttonStyle(.borderedProminent)
                if isImporting {
                    ProgressView("Importing…")
                }
                if !resultText.isEmpty {
                    ScrollView {
                        Text(resultText)
                            .font(.system(.body, design: .monospaced))
                            .padding()
                    }
                }
                Spacer()
                Text("v1 parses: Session.plist strokes, paper size, and the original PDF. Media objects, audio recordings and the handwriting index are not parsed in v1.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding()
            }
            .navigationTitle("Import .note")
            .sheet(isPresented: $showingPicker) {
                DocumentPickerView { url in
                    importFile(url)
                }
            }
        }
    }

    private func importFile(_ url: URL) {
        isImporting = true
        resultText = ""
        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }
        DispatchQueue.global(qos: .utility).async {
            do {
                let (document, summary, pdfData) = try NoteImporter.importNote(from: url)
                DispatchQueue.main.async {
                    store.saveImportedNote(document, pdfData: pdfData) { success in
                        isImporting = false
                        if success {
                            resultText = [
                                "Imported: \(summary.name)",
                                "Curves: \(summary.curveCount)",
                                "Points: \(summary.pointCount)",
                                "Paper: \(summary.paperSize) \(summary.paperOrientation)",
                                "Session format: \(summary.sessionFormatVersion)",
                                "PDF files: \(summary.pdfFileNames.joined(separator: ", "))",
                                "Saved as a canonical InkNote note. Original .note untouched."
                            ].joined(separator: "\n")
                            store.loadManifests()
                        } else {
                            resultText = "Import parsed, but saving failed."
                        }
                    }
                }
            } catch {
                DispatchQueue.main.async {
                    isImporting = false
                    resultText = "Import failed: \(error.localizedDescription)"
                }
            }
        }
    }
}

private struct DocumentPickerView: UIViewControllerRepresentable {
    var onPick: (URL) -> Void
    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.data], asCopy: true)
        picker.delegate = context.coordinator
        return picker
    }
    func updateUIViewController(_ uiViewController: UIDocumentPickerViewController, context: Context) {}
    func makeCoordinator() -> Coordinator { Coordinator(onPick: onPick) }
    final class Coordinator: NSObject, UIDocumentPickerDelegate {
        let onPick: (URL) -> Void
        init(onPick: @escaping (URL) -> Void) { self.onPick = onPick }
        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            if let url = urls.first { onPick(url) }
        }
    }
}
#endif
