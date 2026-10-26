import Foundation
#if canImport(CoreGraphics)
import CoreGraphics
#endif

// MARK: - InkNote canonical stroke model, format v1
//
// This file is the single source of truth for note data. It is intentionally
// Foundation-only (no SwiftUI, no PencilKit, no PDFKit) so that:
//  - the same model can be compiled into the iOS app and into a macOS
//    command-line validation tool,
//  - a future renderer (custom Metal ink, a new PencilKit version, a web
//    renderer) can read the same files without a migration,
//  - the importer can write canonical notes without depending on any UI code.
//
// Global consumers of this model (checked before every model change):
//  iPhone: NotebookListView, NoteEditorView, PDFNoteView, ImportView, thumbnail
//  iPad:   NotebookListView, NoteEditorView, PDFNoteView, ImportView, thumbnail
//  Shared, non-UI: DocumentStore (persistence), NoteImporter (.note -> model),
//    PDF export (model -> PDF), thumbnail generation, future NAS sync,
//    future handwriting recognition, future formula evaluation.
//  Changing a field here therefore requires checking all of the above and
//  bumping formatVersion with a migration in NoteFormatMigration, never a
//  silent in-place reinterpretation of old files.

/// Canonical model version. v1 is the first shipped format.
/// Future versions MUST be handled by NoteFormatMigration, not by editing
/// v1 files in place without a version check.
public enum InkNoteFormat {
    public static let currentVersion = 1
}

/// Shared JSON codec for all InkNote on-disk files.
/// Date strategy MUST be identical on encode and decode: .iso8601.
/// Bug fixed 2026-10-26: saveDocument used .iso8601 but loadManifests,
/// loadDocument and renameNote used the default secondsSince1970
/// decoder, so every saved note failed to load and the editor spun
/// forever on Loading note. Never reintroduce a bare JSONDecoder or
/// JSONEncoder for InkNote files; use InkNoteCodec everywhere.
public enum InkNoteCodec {
    public static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()
    public static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()
}

/// A single sampled or control point of one stroke.
///
/// - sampled: points as recorded by the source device / imported file
///   (e.g. .note curvespoints, which are float32 x,y pairs).
/// - control: B-spline control points as produced by PencilKit
///   (PKStrokePath points). A renderer MUST NOT treat control points as
///   sampled points; it must interpolate the spline.
/// The distinction is stored per stroke in InkStroke.pointKind, because
/// converting one kind to the other is lossy and must never be silent.
public struct InkPoint: Codable, Equatable, Sendable {
    public var x: Double
    public var y: Double
    /// Apple Pencil force, 0...1 for PencilKit, 1.0 when the source has none.
    public var force: Double
    /// Azimuth in radians, 0 when unknown.
    public var azimuth: Double
    /// Altitude in radians, pi/2 (vertical) when unknown.
    public var altitude: Double
    /// Seconds since the stroke started. Used later for audio sync.
    public var timestamp: Double
    public init(x: Double, y: Double, force: Double = 1.0, azimuth: Double = 0, altitude: Double = Double.pi / 2, timestamp: Double = 0) {
        self.x = x; self.y = y; self.force = force; self.azimuth = azimuth; self.altitude = altitude; self.timestamp = timestamp
    }
}

public struct RGBAColor: Codable, Equatable, Sendable {
    public var red: Double
    public var green: Double
    public var blue: Double
    public var alpha: Double
    public init(red: Double, green: Double, blue: Double, alpha: Double = 1) {
        self.red = red; self.green = green; self.blue = blue; self.alpha = alpha
    }
    public static let black = RGBAColor(red: 0, green: 0, blue: 0, alpha: 1)
    public static let blue = RGBAColor(red: 0, green: 0.45, blue: 1, alpha: 1)
    public static let red = RGBAColor(red: 1, green: 0.2, blue: 0.2, alpha: 1)
}

public enum InkTool: String, Codable, Sendable, CaseIterable {
    case pen
    case marker
    case pencil
    case calligraphy
    case highlighter
}

public enum PointKind: String, Codable, Sendable {
    case sampled
    case control
}

public struct InkStroke: Codable, Equatable, Sendable {
    public var id: UUID
    public var tool: InkTool
    public var color: RGBAColor
    /// Base width in page points, before per-point force scaling.
    public var baseWidth: Double
    public var points: [InkPoint]
    public var pointKind: PointKind
    /// Extension dictionary for future tools (e.g. calligraphy angle).
    /// Values are strings so old readers can ignore unknown keys safely.
    public var extended: [String: String]
    public init(id: UUID = UUID(), tool: InkTool, color: RGBAColor, baseWidth: Double, points: [InkPoint], pointKind: PointKind, extended: [String: String] = [:]) {
        self.id = id; self.tool = tool; self.color = color; self.baseWidth = baseWidth; self.points = points; self.pointKind = pointKind; self.extended = extended
    }
}

public struct TextBoxItem: Codable, Equatable, Sendable {
    public var id: UUID
    public var text: String
    public var x: Double
    public var y: Double
    public var width: Double
    public var height: Double
    public var fontSize: Double
    public init(id: UUID = UUID(), text: String, x: Double, y: Double, width: Double, height: Double, fontSize: Double = 17) {
        self.id = id; self.text = text; self.x = x; self.y = y; self.width = width; self.height = height; self.fontSize = fontSize
    }
}

public struct ImageItem: Codable, Equatable, Sendable {
    public var id: UUID
    /// File name inside the note package, never an absolute path.
    public var fileName: String
    public var x: Double
    public var y: Double
    public var width: Double
    public var height: Double
    public init(id: UUID = UUID(), fileName: String, x: Double, y: Double, width: Double, height: Double) {
        self.id = id; self.fileName = fileName; self.x = x; self.y = y; self.width = width; self.height = height
    }
}

public enum PaperTemplate: String, Codable, Sendable, CaseIterable {
    case blank
    case lines
    case grid
    case dotted
}

/// One page. Coordinates are page points in a page-local system whose
/// origin is the top-left of the page, independent of device, screen scale
/// and PDF page rotation. The page size is stored on the page itself so a
/// future page-size change cannot silently shift old strokes.
public struct NotePage: Codable, Equatable, Sendable {
    public var id: UUID
    public var index: Int
    public var width: Double
    public var height: Double
    public var template: PaperTemplate
    /// For PDF notes: the index of the PDF page this page annotates, if any.
    public var pdfPageIndex: Int?
    public var strokes: [InkStroke]
    public var textBoxes: [TextBoxItem]
    public var images: [ImageItem]
    public init(id: UUID = UUID(), index: Int, width: Double, height: Double, template: PaperTemplate = .lines, pdfPageIndex: Int? = nil, strokes: [InkStroke] = [], textBoxes: [TextBoxItem] = [], images: [ImageItem] = []) {
        self.id = id; self.index = index; self.width = width; self.height = height; self.template = template; self.pdfPageIndex = pdfPageIndex; self.strokes = strokes; self.textBoxes = textBoxes; self.images = images
    }
}

public struct NoteManifest: Codable, Equatable, Sendable, Identifiable {
    public var formatVersion: Int
    public var id: UUID
    public var name: String
    public var folder: String
    public var createdAt: Date
    public var modifiedAt: Date
    /// Source of this note: "inknote" for native notes, "imported-note"
    /// for notes converted from a .note package. The original .note file
    /// is never modified; it remains the user's backup.
    public var source: String
    /// Original file name / identifier of the imported source, if any.
    public var sourceName: String?
    public init(formatVersion: Int = InkNoteFormat.currentVersion, id: UUID = UUID(), name: String, folder: String = "Unsorted", createdAt: Date = Date(), modifiedAt: Date = Date(), source: String = "inknote", sourceName: String? = nil) {
        self.formatVersion = formatVersion; self.id = id; self.name = name; self.folder = folder; self.createdAt = createdAt; self.modifiedAt = modifiedAt; self.source = source; self.sourceName = sourceName
    }
}

/// A complete note document. The package on disk is:
///   <id>.inknote/manifest.json   (NoteManifest)
///   <id>.inknote/pages.json      (all NotePage values)
///   <id>.inknote/thumb.png       (rendered cache, regenerable, NOT truth)
///   <id>.inknote/<pdf file>      (only for PDF notes, copied verbatim)
/// Only manifest.json + pages.json (+ the PDF file, if any) are truth.
/// thumb.png may be deleted and regenerated at any time.
public struct InkNoteDocument: Codable, Equatable, Sendable {
    public var manifest: NoteManifest
    public var pages: [NotePage]
    /// File name of the imported PDF inside the package, if this is a PDF note.
    public var pdfFileName: String?
    public init(manifest: NoteManifest, pages: [NotePage], pdfFileName: String? = nil) {
        self.manifest = manifest; self.pages = pages; self.pdfFileName = pdfFileName
    }
    public static func blank(name: String, folder: String = "Unsorted", width: Double = 612, height: Double = 792, template: PaperTemplate = .lines) -> InkNoteDocument {
        let manifest = NoteManifest(name: name, folder: folder)
        let page = NotePage(index: 0, width: width, height: height, template: template)
        return InkNoteDocument(manifest: manifest, pages: [page])
    }
}

// MARK: - Format migration (v1 -> future)

/// Migration skeleton. v1 documents pass through unchanged. A future v2
/// MUST add a branch here, bump InkNoteFormat.currentVersion, and keep a
/// v1 sample note in ValidationSamples for regression testing. Never edit
/// a v1 file in place without going through this function.
public enum NoteFormatMigration {
    public static func migrateIfNeeded(document: inout InkNoteDocument) -> Bool {
        if document.manifest.formatVersion == InkNoteFormat.currentVersion {
            return false
        }
        if document.manifest.formatVersion < InkNoteFormat.currentVersion {
            // Future: apply stepwise migrations here, one version at a time,
            // and record the original version in the document's extended data.
            // v1 has no earlier version to migrate from, so this is a guard.
            document.manifest.formatVersion = InkNoteFormat.currentVersion
            return true
        }
        // A file from a newer version than this build understands: do not
        // silently reinterpret it. Callers must refuse to open it.
        return false
    }
    public static func canOpen(formatVersion: Int) -> Bool {
        return formatVersion <= InkNoteFormat.currentVersion
    }
}

// MARK: - Performance / power rules for the model layer
//
// These are not comments for decoration; the store and views are written
// to honour them, and the development log records where each is enforced:
//  1. File parsing, thumbnail generation and PDF loading run off the main
//     thread (DocumentStore uses a background queue; see Store.swift).
//  2. The notebook list loads only manifest.json + thumb.png, never
//     pages.json. Full strokes load only when a note is opened.
//  3. The canvas redraws only on drawing-change callbacks (PencilKit
//     delegate), never on a timer. No polling, no continuous rendering.
//  4. No background rendering loop. Thumbnails and exports are one-shot
//     jobs, cancelled if the note is closed first.
//  5. Large files are lazy: PDF pages render one page at a time, images
//     load per page, and the importer streams zip entries instead of
//     holding the whole 445 MB backup in memory.
