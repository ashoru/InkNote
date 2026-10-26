import Foundation

// MARK: - Future stages: interfaces only in v1 (explicitly not implemented)
//
// The user-approved v1 scope is: canonical model, notebook management,
// PencilKit handwriting, PDF annotation, .note import validation.
// The following are deliberately interface-only in v1, so later stages
// can be added without changing the notebook list, editor or model:
//  - NAS sync: sync a note package to the user's NAS, with version +
//    conflict handling. Not a file copy; it must not silently overwrite.
//  - Audio transcription: record audio with stroke timestamps, then
//    transcribe. The engine (on-device Speech, local Whisper, or a
//    cloud model) is a later decision, after a transcription accuracy test.
//  - Handwriting recognition: sampled/control strokes -> text. No public
//    general handwriting OCR API is assumed; accuracy must be tested
//    on the user's own handwriting before any claim is made.
//  - Formula evaluation: typed formulas already work via
//    FormulaEvaluator. Handwritten formula recognition is the future
//    stage (stroke image -> expression -> FormulaEvaluator).
//
// Each protocol returns a typed "not implemented" error in v1 instead of
// pretending to work. A UI surface that calls one of these in v1 must
// show that state, not a fake result.

public enum FutureServiceError: Error, LocalizedError {
    case notImplementedInV1(String)
    public var errorDescription: String? {
        switch self {
        case .notImplementedInV1(let feature): return "\(feature) is interface-only in InkNote v1 and is not implemented yet"
        }
    }
}

public protocol NASSyncService {
    func sync(document: InkNoteDocument) async throws
    func fetchLatest(documentID: UUID) async throws -> InkNoteDocument
}

public struct NASSyncPlaceholder: NASSyncService {
    public init() {}
    public func sync(document: InkNoteDocument) async throws {
        throw FutureServiceError.notImplementedInV1("NAS sync")
    }
    public func fetchLatest(documentID: UUID) async throws -> InkNoteDocument {
        throw FutureServiceError.notImplementedInV1("NAS sync")
    }
}

public protocol TranscriptionService {
    func transcribe(audioFileName: String) async throws -> String
}

public struct TranscriptionPlaceholder: TranscriptionService {
    public init() {}
    public func transcribe(audioFileName: String) async throws -> String {
        throw FutureServiceError.notImplementedInV1("Audio transcription")
    }
}

public protocol HandwritingRecognitionService {
    func recognize(strokes: [InkStroke]) async throws -> String
}

public struct HandwritingRecognitionPlaceholder: HandwritingRecognitionService {
    public init() {}
    public func recognize(strokes: [InkStroke]) async throws -> String {
        throw FutureServiceError.notImplementedInV1("Handwriting recognition")
    }
}

public protocol HandwrittenFormulaService {
    func solve(strokes: [InkStroke], variables: [String: Double]) async throws -> Double
}

public struct HandwrittenFormulaPlaceholder: HandwrittenFormulaService {
    public init() {}
    public func solve(strokes: [InkStroke], variables: [String: Double]) async throws -> Double {
        throw FutureServiceError.notImplementedInV1("Handwritten formula recognition")
    }
}
