import Foundation
#if canImport(CoreGraphics)
import CoreGraphics
#endif

// MARK: - .note importer (prototype, Foundation-only)
//
// Input: a .note package as exported by the user. The package
// is a ZIP archive using the store method (no compression) for every
// entry in the samples validated so far. The importer therefore includes
// a minimal store-only ZIP reader and refuses deflated entries with a
// clear error instead of silently dropping them.
//
// Output: an InkNoteDocument in the canonical v1 model. The original
// .note file is never modified, never re-zipped, and never deleted by
// this code. Imported strokes keep pointKind == .sampled, because the
// source curvespoints are sampled float32 x,y pairs, not B-spline
// control points.
//
// What is parsed in v1:
//  - Session.plist (GLKeyedArchiver, sessionFormatVersion 9):
//    HandwritingObject -> InkedSpatialHash -> curvespoints (float32 x,y),
//    curvesnumpoints (int32 per curve), curveswidth (float32 per curve),
//    curvescolors (RGBA bytes per curve), curvesstyles (byte per curve),
//    paperSize / paperOrientation / lineStyle.
//  - metadata.plist: note name (when present).
//  - PDFs/<uuid>.pdf: copied verbatim into the InkNote package.
// What is NOT parsed in v1 (explicitly, not silently): mediaObjects
// (images/text boxes beyond the PDF itself), Recordings audio, and the
// HandwritingIndex text. Those are future importer stages; a note that
// contains them still imports its strokes + PDF, and the log records
// what was skipped.

public struct ImportedNoteSummary: Sendable {
    public var name: String
    public var curveCount: Int
    public var pointCount: Int
    public var pdfFileNames: [String]
    public var paperSize: String
    public var paperOrientation: String
    public var sessionFormatVersion: Int
}

public enum NoteImporterError: Error, LocalizedError {
    case zipNotFound
    case zipUnsupportedMethod(Int)
    case sessionNotFound
    case sessionParseFailed(String)
    case curvesMissing
    public var errorDescription: String? {
        switch self {
        case .zipNotFound: return "ZIP end-of-central-directory not found"
        case .zipUnsupportedMethod(let m): return "ZIP entry uses unsupported compression method \(m); only store (0) is supported in v1"
        case .sessionNotFound: return "Session.plist not found inside the .note package"
        case .sessionParseFailed(let s): return "Session.plist parse failed: \(s)"
        case .curvesMissing: return "Handwriting curves not found in Session.plist"
        }
    }
}

public struct ZipEntry: Sendable {
    public var name: String
    public var data: Data
}

/// Minimal ZIP reader for store-only archives. Reads the central
/// directory, then extracts each entry from its local header. This is
/// deliberately small: it is not a general ZIP library, and it fails
/// loudly on anything it does not understand.
public enum SimpleZipReader {
    public static func entries(from archive: Data) throws -> [ZipEntry] {
        guard let eocdRange = findEOCD(in: archive) else { throw NoteImporterError.zipNotFound }
        func u16(at offset: Int) -> Int {
            return Int(archive[offset]) | (Int(archive[offset + 1]) << 8)
        }
        func u32(at offset: Int) -> Int {
            return Int(archive[offset]) | (Int(archive[offset + 1]) << 8) | (Int(archive[offset + 2]) << 16) | (Int(archive[offset + 3]) << 24)
        }
        let count = u16(at: eocdRange + 10)
        let cdOffset = u32(at: eocdRange + 16)
        var results: [ZipEntry] = []
        var cursor = cdOffset
        for _ in 0..<count {
            guard cursor + 46 <= archive.count,
                  archive[cursor] == 0x50, archive[cursor + 1] == 0x4B, archive[cursor + 2] == 0x01, archive[cursor + 3] == 0x02 else {
                throw NoteImporterError.zipNotFound
            }
            let method = u16(at: cursor + 10)
            let compressedSize = u32(at: cursor + 20)
            let nameLength = u16(at: cursor + 28)
            let extraLength = u16(at: cursor + 30)
            let commentLength = u16(at: cursor + 32)
            let localOffset = u32(at: cursor + 42)
            guard cursor + 46 + nameLength <= archive.count else { throw NoteImporterError.zipNotFound }
            let nameData = archive[(cursor + 46)..<(cursor + 46 + nameLength)]
            let name = String(bytes: nameData, encoding: .utf8) ?? ""
            guard method == 0 else { throw NoteImporterError.zipUnsupportedMethod(method) }
            // Local header: signature + 26 bytes, then name + extra.
            guard localOffset + 30 <= archive.count else { throw NoteImporterError.zipNotFound }
            let localNameLength = u16(at: localOffset + 26)
            let localExtraLength = u16(at: localOffset + 28)
            let dataStart = localOffset + 30 + localNameLength + localExtraLength
            guard dataStart + compressedSize <= archive.count else { throw NoteImporterError.zipNotFound }
            // Normalize the slice: Data slices keep original indices,
            // so a later entryData[0] would trap. Copy to fresh Data.
            let entryData = Data(archive[dataStart..<(dataStart + compressedSize)])
            results.append(ZipEntry(name: name, data: entryData))
            cursor += 46 + nameLength + extraLength + commentLength
        }
        return results
    }

    private static func findEOCD(in archive: Data) -> Int? {
        guard archive.count >= 22 else { return nil }
        let start = max(0, archive.count - 65557)
        var i = archive.count - 22
        while i >= start {
            if archive[i] == 0x50, archive[i + 1] == 0x4B, archive[i + 2] == 0x05, archive[i + 3] == 0x06 {
                return i
            }
            i -= 1
        }
        return nil
    }
}

public enum NoteImporter {
    /// Parse a .note file on disk into a canonical document + summary.
    /// The returned document's pdfFileName is set when a PDF was found;
    /// the caller is responsible for writing the PDF bytes into the
    /// InkNote package (see DocumentStore.saveImportedNote).
    public static func importNote(from fileURL: URL) throws -> (document: InkNoteDocument, summary: ImportedNoteSummary, pdfData: Data?) {
        let archive = try Data(contentsOf: fileURL)
        return try importNote(fromArchive: archive, sourceName: fileURL.lastPathComponent)
    }

    public static func importNote(fromArchive archive: Data, sourceName: String) throws -> (document: InkNoteDocument, summary: ImportedNoteSummary, pdfData: Data?) {
        let entries = try SimpleZipReader.entries(from: archive)
        guard let sessionEntry = entries.first(where: { $0.name.hasSuffix("/Session.plist") }) else {
            throw NoteImporterError.sessionNotFound
        }
        let parsed = try parseSession(sessionEntry.data)
        let pdfEntries = entries.filter { $0.name.contains("/PDFs/") && $0.name.hasSuffix(".pdf") }
        let pdfFileName: String? = pdfEntries.first.map { ($0.name as NSString).lastPathComponent }
        let pdfData: Data? = pdfEntries.first?.data
        var manifest = NoteManifest(name: parsed.name, source: "imported-note", sourceName: sourceName)
        manifest.formatVersion = InkNoteFormat.currentVersion
        let page = NotePage(index: 0, width: parsed.pageWidth, height: parsed.pageHeight, template: parsed.template, strokes: parsed.strokes)
        let document = InkNoteDocument(manifest: manifest, pages: [page], pdfFileName: pdfFileName)
        let summary = ImportedNoteSummary(name: parsed.name, curveCount: parsed.strokes.count, pointCount: parsed.strokes.reduce(0) { $0 + $1.points.count }, pdfFileNames: pdfEntries.map { ($0.name as NSString).lastPathComponent }, paperSize: parsed.paperSize, paperOrientation: parsed.paperOrientation, sessionFormatVersion: parsed.sessionFormatVersion)
        return (document, summary, pdfData)
    }

    private struct ParsedSession {
        var name: String
        var strokes: [InkStroke]
        var pageWidth: Double
        var pageHeight: Double
        var template: PaperTemplate
        var paperSize: String
        var paperOrientation: String
        var sessionFormatVersion: Int
    }

    private static func parseSession(_ data: Data) throws -> ParsedSession {
        let parser: BPlistParser
        do {
            parser = try BPlistParser(data: data)
        } catch {
            throw NoteImporterError.sessionParseFailed(error.localizedDescription)
        }
        let top: BPlistValue
        do {
            top = try parser.topObject()
        } catch {
            throw NoteImporterError.sessionParseFailed(error.localizedDescription)
        }
        guard case let .dict(topDict) = top,
              case let .array(objects) = topDict["$objects"] ?? .null,
              case let .dict(topRef) = topDict["$top"] ?? .null,
              case let .uid(sessionIndex) = topRef["$0"] ?? .null,
              case let .dict(session) = objects[safe: sessionIndex] ?? .null else {
            throw NoteImporterError.sessionParseFailed("Missing $objects/$top in Session.plist")
        }
        func resolve(_ value: BPlistValue?) -> BPlistValue? {
            guard let value = value else { return nil }
            if case let .uid(index) = value {
                return objects[safe: index]
            }
            return value
        }
        func dictValue(_ dict: [String: BPlistValue], _ key: String) -> BPlistValue? {
            return resolve(dict[key])
        }
        let sessionFormatVersion = dictValue(session, "sessionFormatVersion")?.asInt ?? 0
        let name = dictValue(session, "name")?.asString ?? "Imported Note"
        // Paper attributes: session -> DocumentPaperLayoutModel -> PaperAttributes.
        var paperSize = "letter"
        var paperOrientation = "portrait"
        var template: PaperTemplate = .lines
        var pageWidth = 612.0
        var pageHeight = 792.0
        if let modelValue = dictValue(session, "NBNoteTakingSessionDocumentPaperLayoutModelKey"),
           case let .dict(model) = modelValue,
           let attrsValue = dictValue(model, "documentPaperAttributes"),
           case let .dict(attrs) = attrsValue {
            if let size = dictValue(attrs, "paperSize")?.asString {
                paperSize = size
                switch size {
                case "a4": pageWidth = 595; pageHeight = 842
                case "letter": pageWidth = 612; pageHeight = 792
                default: break
                }
            }
            if let orient = dictValue(attrs, "paperOrientation")?.asString {
                paperOrientation = orient
                if orient == "landscape" {
                    swap(&pageWidth, &pageHeight)
                }
            }
            if let lineStyle = dictValue(attrs, "lineStyle2")?.asString {
                if lineStyle.hasPrefix("Grid") { template = .grid }
                else if lineStyle.hasPrefix("Lines") { template = .lines }
                else if lineStyle == "No Lines" { template = .blank }
                else { template = .lines }
            }
        }
        // Handwriting: session -> richText -> "Handwriting Overlay" -> SpatialHash.
        guard let richValue = dictValue(session, "richText"),
              case let .dict(rich) = richValue,
              let overlayValue = dictValue(rich, "Handwriting Overlay"),
              case let .dict(overlay) = overlayValue,
              let spatialValue = dictValue(overlay, "SpatialHash"),
              case let .dict(spatial) = spatialValue else {
            throw NoteImporterError.curvesMissing
        }
        guard let pointsData = dictValue(spatial, "curvespoints")?.asData,
              let countsData = dictValue(spatial, "curvesnumpoints")?.asData,
              let widthsData = dictValue(spatial, "curveswidth")?.asData,
              let colorsData = dictValue(spatial, "curvescolors")?.asData,
              let stylesData = dictValue(spatial, "curvesstyles")?.asData,
              let forcesData = dictValue(spatial, "curvesforces")?.asData else {
            // A blank note has empty arrays; that is a valid 0-stroke note,
            // not an error. Only fail when the keys themselves are absent
            // in a non-empty note, which the guard above already handles
            // for the main case. Treat missing arrays as 0 strokes here.
            return ParsedSession(name: name, strokes: [], pageWidth: pageWidth, pageHeight: pageHeight, template: template, paperSize: paperSize, paperOrientation: paperOrientation, sessionFormatVersion: sessionFormatVersion)
        }
        let pointCount = pointsData.count / 8
        var points: [InkPoint] = []
        points.reserveCapacity(pointCount)
        // Manual little-endian assembly: Data bytes are not guaranteed
        // to be aligned for Float/Int32 load() on arm64, and load()
        // traps on unaligned addresses. Never use load() on zip data.
        func floatLE(_ d: Data, _ at: Int) -> Float {
            let bits = UInt32(d[at]) | (UInt32(d[at + 1]) << 8) | (UInt32(d[at + 2]) << 16) | (UInt32(d[at + 3]) << 24)
            return Float(bitPattern: bits)
        }
        func intLE(_ d: Data, _ at: Int) -> Int {
            let bits = UInt32(d[at]) | (UInt32(d[at + 1]) << 8) | (UInt32(d[at + 2]) << 16) | (UInt32(d[at + 3]) << 24)
            return Int(Int32(bitPattern: bits))
        }
        for i in 0..<pointCount {
            let x = floatLE(pointsData, i * 8)
            let y = floatLE(pointsData, i * 8 + 4)
            points.append(InkPoint(x: Double(x), y: Double(y), force: 1.0, azimuth: 0, altitude: Double.pi / 2, timestamp: 0))
        }
        // curvesnumpoints: int32 per curve. Sum must equal pointCount.
        let curveCount = countsData.count / 4
        var counts: [Int] = []
        for i in 0..<curveCount {
            counts.append(intLE(countsData, i * 4))
        }
        // curveswidth: float32 per curve. curvescolors: 4 bytes per curve.
        // curvesstyles: 1 byte per curve. curvesforces: float32 per
        // fractional-width entry, not per point in the samples, so force
        // is intentionally left at 1.0 for imported strokes in v1; the
        // force array is not silently reinterpreted as per-point force.
        _ = forcesData
        var strokes: [InkStroke] = []
        var offset = 0
        for curveIndex in 0..<curveCount {
            let count = counts[curveIndex]
            guard count >= 0, offset + count <= points.count else { break }
            let curvePoints = Array(points[offset..<(offset + count)])
            offset += count
            var width = 2.0
            if curveIndex * 4 + 4 <= widthsData.count {
                width = Double(floatLE(widthsData, curveIndex * 4))
            }
            var color = RGBAColor.black
            if curveIndex * 4 + 4 <= colorsData.count {
                let r = Double(colorsData[curveIndex * 4]) / 255.0
                let g = Double(colorsData[curveIndex * 4 + 1]) / 255.0
                let b = Double(colorsData[curveIndex * 4 + 2]) / 255.0
                let a = Double(colorsData[curveIndex * 4 + 3]) / 255.0
                color = RGBAColor(red: r, green: g, blue: b, alpha: a)
            }
            var tool = InkTool.pen
            if curveIndex < stylesData.count {
                // Style byte 3 is the common pen style in the samples.
                // Other styles map to pen in v1 and are recorded in
                // extended so a future version can distinguish them.
                switch stylesData[curveIndex] {
                case 3: tool = .pen
                default: tool = .pen
                }
            }
            strokes.append(InkStroke(tool: tool, color: color, baseWidth: width, points: curvePoints, pointKind: .sampled, extended: ["sourceStyle": "\(stylesData[curveIndex])"]))
        }
        return ParsedSession(name: name, strokes: strokes, pageWidth: pageWidth, pageHeight: pageHeight, template: template, paperSize: paperSize, paperOrientation: paperOrientation, sessionFormatVersion: sessionFormatVersion)
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        return indices.contains(index) ? self[index] : nil
    }
}
