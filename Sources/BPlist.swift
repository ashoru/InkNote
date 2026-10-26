import Foundation

// MARK: - Minimal binary-plist parser (Foundation-only, no private API)
//
// Why this file exists: PropertyListSerialization returns keyed-archiver
// UIDs as the private CFKeyedArchiverUID type, which Swift code cannot
// safely read. A .note Session.plist is a keyed archive (GLKeyedArchiver,
// $objects / $top / $class), so the importer needs UID indices, not opaque
// objects. This parser reads the documented bplist00 format directly and
// represents a UID as BPlistValue.uid(Int).
//
// Supported object types: null, bool, int, real, date, data, ASCII string,
// UTF-16 string, UID, array, dictionary. Anything else is a hard error,
// never a silent guess.

public enum BPlistValue: Sendable {
    case null
    case bool(Bool)
    case int(Int)
    case real(Double)
    case date(Date)
    case data(Data)
    case string(String)
    case uid(Int)
    case array([BPlistValue])
    case dict([String: BPlistValue])

    public var asString: String? {
        if case let .string(s) = self { return s }
        return nil
    }
    public var asInt: Int? {
        if case let .int(i) = self { return i }
        return nil
    }
    public var asData: Data? {
        if case let .data(d) = self { return d }
        return nil
    }
    public var asArray: [BPlistValue]? {
        if case let .array(a) = self { return a }
        return nil
    }
    public var asDict: [String: BPlistValue]? {
        if case let .dict(d) = self { return d }
        return nil
    }
}

public enum BPlistError: Error, LocalizedError {
    case notBPlist
    case truncated
    case unsupportedMarker(UInt8)
    case invalidOffset
    public var errorDescription: String? {
        switch self {
        case .notBPlist: return "Not a bplist00 file"
        case .truncated: return "Truncated bplist file"
        case .unsupportedMarker(let m): return "Unsupported bplist marker \(m)"
        case .invalidOffset: return "Invalid bplist offset"
        }
    }
}

public struct BPlistParser {
    private let data: Data
    private let offsetTable: [Int]
    private let refSize: Int
    private let objectCount: Int

    public init(data: Data) throws {
        guard data.count >= 32, data.prefix(6) == Data("bplist".utf8), data[6] == 0x30, data[7] == 0x30 else {
            throw BPlistError.notBPlist
        }
        // Normalize: a Data slice preserves its original indices, so
        // indexing a slice with 0-based offsets traps. Copying to a
        // fresh Data resets indices to 0. This is the root cause of
        // the earlier SIGTRAP (exit 133) on macOS, and the same rule
        // applies to every Data slice in NoteImporter.
        self.data = Data(data)
        let trailer = Array(self.data.suffix(32))
        let offsetIntSize = Int(trailer[6])
        let refSize = Int(trailer[7])
        // Manual big-endian assembly: UnsafeRawBufferPointer.load()
        // traps on arm64 for unaligned addresses, and the trailer is
        // not guaranteed 8-byte aligned, so never use load() here.
        func be64(_ t: [UInt8], _ at: Int) -> Int {
            var value = 0
            for i in 0..<8 { value = (value << 8) | Int(t[at + i]) }
            return value
        }
        let numObjects = be64(trailer, 8)
        let topObject = be64(trailer, 16)
        let offsetTableOffset = be64(trailer, 24)
        _ = topObject
        guard offsetIntSize > 0, refSize > 0, numObjects > 0 else { throw BPlistError.truncated }
        self.refSize = refSize
        self.objectCount = numObjects
        var table: [Int] = []
        table.reserveCapacity(numObjects)
        for i in 0..<numObjects {
            let at = offsetTableOffset + i * offsetIntSize
            guard at + offsetIntSize <= self.data.count else { throw BPlistError.truncated }
            var value = 0
            for j in 0..<offsetIntSize {
                value = (value << 8) | Int(self.data[at + j])
            }
            table.append(value)
        }
        self.offsetTable = table
    }

    public func topObject() throws -> BPlistValue {
        // The top object index is in the trailer; recompute it here so the
        // parser stays self-contained. Trailer layout is fixed (see init).
        // Manual assembly again: no unaligned load().
        let trailer = Array(data.suffix(32))
        var top = 0
        for i in 0..<8 { top = (top << 8) | Int(trailer[16 + i]) }
        return try object(at: top)
    }

    public func object(at index: Int) throws -> BPlistValue {
        guard index >= 0, index < objectCount else { throw BPlistError.invalidOffset }
        let offset = offsetTable[index]
        guard offset < data.count else { throw BPlistError.invalidOffset }
        var cursor = offset
        return try parseObject(cursor: &cursor)
    }

    private func readInt(at offset: Int, byteCount: Int) throws -> Int {
        guard offset + byteCount <= data.count else { throw BPlistError.truncated }
        var value = 0
        for i in 0..<byteCount {
            value = (value << 8) | Int(data[offset + i])
        }
        // Sign-extend for the common integer sizes.
        if byteCount > 0, byteCount < 8, (data[offset] & 0x80) != 0 {
            value -= (1 << (byteCount * 8))
        }
        return value
    }

    private func readUInt(at offset: Int, byteCount: Int) throws -> Int {
        guard offset + byteCount <= data.count else { throw BPlistError.truncated }
        var value = 0
        for i in 0..<byteCount {
            value = (value << 8) | Int(data[offset + i])
        }
        return value
    }

    private func parseObject(cursor: inout Int) throws -> BPlistValue {
        guard cursor < data.count else { throw BPlistError.truncated }
        let marker = data[cursor]
        cursor += 1
        let type = marker >> 4
        let info = marker & 0x0F
        func count() throws -> Int {
            if info != 0x0F { return Int(info) }
            guard cursor < data.count else { throw BPlistError.truncated }
            let intMarker = data[cursor]
            cursor += 1
            guard (intMarker >> 4) == 0x1 else { throw BPlistError.unsupportedMarker(intMarker) }
            let size = 1 << (intMarker & 0x0F)
            // Counts are unsigned. Using the signed readInt here
            // sign-extends counts >= 128 to negative values, which
            // then traps on Range(lowerBound > upperBound). This was
            // the crash on the PDF sample, whose Session contains a
            // longer data/string object than the other samples.
            let value = try readUInt(at: cursor, byteCount: size)
            cursor += size
            return value
        }
        switch type {
        case 0x0:
            switch info {
            case 0x0: return .null
            case 0x8: return .bool(false)
            case 0x9: return .bool(true)
            default: throw BPlistError.unsupportedMarker(marker)
            }
        case 0x1:
            let size = 1 << info
            let value = try readInt(at: cursor, byteCount: size)
            cursor += size
            return .int(value)
        case 0x2:
            if info == 2 {
                guard cursor + 4 <= data.count else { throw BPlistError.truncated }
                var bits: UInt32 = 0
                for i in 0..<4 { bits = (bits << 8) | UInt32(data[cursor + i]) }
                cursor += 4
                return .real(Double(Float(bitPattern: bits)))
            } else if info == 3 {
                guard cursor + 8 <= data.count else { throw BPlistError.truncated }
                var bits: UInt64 = 0
                for i in 0..<8 { bits = (bits << 8) | UInt64(data[cursor + i]) }
                cursor += 8
                return .real(Double(bitPattern: bits))
            } else { throw BPlistError.unsupportedMarker(marker) }
        case 0x3:
            guard cursor + 8 <= data.count else { throw BPlistError.truncated }
            var bits: UInt64 = 0
            for i in 0..<8 { bits = (bits << 8) | UInt64(data[cursor + i]) }
            cursor += 8
            return .date(Date(timeIntervalSinceReferenceDate: Double(bitPattern: bits)))
        case 0x4:
            let length = try count()
            guard cursor + length <= data.count else { throw BPlistError.truncated }
            let value = Data(data[cursor..<cursor + length])
            cursor += length
            return .data(value)
        case 0x5:
            let length = try count()
            guard cursor + length <= data.count else { throw BPlistError.truncated }
            let value = String(bytes: data[cursor..<cursor + length], encoding: .ascii) ?? ""
            cursor += length
            return .string(value)
        case 0x6:
            let length = try count()
            let byteCount = length * 2
            guard cursor + byteCount <= data.count else { throw BPlistError.truncated }
            let value = String(bytes: data[cursor..<cursor + byteCount], encoding: .utf16BigEndian) ?? ""
            cursor += byteCount
            return .string(value)
        case 0x8:
            let size = Int(info) + 1
            let value = try readUInt(at: cursor, byteCount: size)
            cursor += size
            return .uid(value)
        case 0xA:
            let length = try count()
            var refs: [Int] = []
            for _ in 0..<length {
                refs.append(try readUInt(at: cursor, byteCount: refSize))
                cursor += refSize
            }
            var values: [BPlistValue] = []
            for ref in refs {
                // Resolve via the offset table, not by re-parsing at cursor.
                let saved = cursor
                _ = saved
                values.append(try object(at: ref))
            }
            return .array(values)
        case 0xD:
            let length = try count()
            var keyRefs: [Int] = []
            var valueRefs: [Int] = []
            for _ in 0..<length {
                keyRefs.append(try readUInt(at: cursor, byteCount: refSize))
                cursor += refSize
            }
            for _ in 0..<length {
                valueRefs.append(try readUInt(at: cursor, byteCount: refSize))
                cursor += refSize
            }
            var result: [String: BPlistValue] = [:]
            for (k, v) in zip(keyRefs, valueRefs) {
                if case let .string(key) = try object(at: k) {
                    result[key] = try object(at: v)
                }
            }
            return .dict(result)
        default:
            throw BPlistError.unsupportedMarker(marker)
        }
    }
}
