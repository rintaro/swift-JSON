import Foundation

var MAX_DEPTH_DEFAULT: Int { return 512 }
var INDENT_SHIFT_OFF: Int { return -1 }

/// JSON encoder/decoder
public struct JSON {
    let maxDepth: Int
    let indentShift: Int
    let spatial: Bool
    let asciiOnly: Bool

    init(
        maxDepth: Int = MAX_DEPTH_DEFAULT,
        indentShift: Int = INDENT_SHIFT_OFF,
        spatial: Bool = false,
        asciiOnly: Bool = false
    ) {
        self.maxDepth = maxDepth
        self.indentShift = indentShift
        self.spatial = spatial
        self.asciiOnly = asciiOnly
    }
}

/// Static methods
extension JSON {
    public static func decode(
        _ data: Data,
        maxDepth: Int = MAX_DEPTH_DEFAULT
    ) throws -> Any {
        return try ensuringUTF8(data) { (ptr: UnsafePointer<UInt8>, count: Int) -> Any in
            var impl = ParserImpl(
                start: ptr,
                end: ptr + count,
                null: NSNull(),
                maxDepth: maxDepth)
            return try impl.parseRoot()
        }
    }

    public static func encode(
        _ value: Any,
        maxDepth: Int = MAX_DEPTH_DEFAULT,
        indentShift: Int = INDENT_SHIFT_OFF,
        spatial: Bool = false,
        asciiOnly: Bool = false
    ) throws -> Data {
        var result = Data();
        let sink = { (chunk: UnsafeRawBufferPointer) -> Void in
          result.append(
              chunk.baseAddress!.bindMemory(to: UInt8.self, capacity: chunk.count),
              count: chunk.count)
        }
        var impl = PrinterImpl(
          root: value,
          into: sink,
          null: NSNull(),
          maxDepth: maxDepth,
          indentShift: indentShift,
          spatial: spatial,
          asciiOnly: asciiOnly
        )
        try impl.printRoot();
        return result
    }
}

/// Instance methods
extension JSON {
    public func decode(_ data: Data) throws -> Any {
        return try JSON.decode(data,
            maxDepth: maxDepth
        )
    }

    public func encode(_ value: Any) throws -> Data {
        return try JSON.encode(value,
            maxDepth: maxDepth,
            indentShift: indentShift,
            spatial: spatial,
            asciiOnly: asciiOnly
        )
    }
}

// MARK: Internal helper functions

private func detectEncoding(
    _ ptr: UnsafePointer<UInt8>, _ count: Int
) -> (encoding: String.Encoding, skippedCount: Int) {
    if count >= 4 {
        let char4 = ptr.withMemoryRebound(to: UInt32.self, capacity: 1, { $0.pointee.bigEndian })
        switch char4 {
        // UTF32 BOM.
        case 0x0000FEFF: return (.utf32BigEndian, 4)
        case 0xFFFE0000: return (.utf32LittleEndian, 4)
        // UTF32 detection.
        case _ where char4 & ~0x000000FF == 0: return (.utf32BigEndian, 0)
        case _ where char4 & ~0xFF000000 == 0: return (.utf32LittleEndian, 0)
        default: break
        }
    }
    if count >= 2 {
        let char2 = ptr.withMemoryRebound(to: UInt16.self, capacity: 1, { $0.pointee.bigEndian })
        if char2 == 0xFEFF { return (.utf16BigEndian, 2) }
        switch char2 {
        // UTF16 BOM.
        case 0xFEFF: return (.utf16BigEndian, 2)
        case 0xFFFE: return (.utf16LittleEndian, 2)
        // UTF16 detection.
        case _ where char2 & ~0x00FF == 0: return (.utf16BigEndian, 0)
        case _ where char2 & ~0xFF00 == 0: return (.utf16LittleEndian, 0)
        // UTF8 BOM. FIXME: Should we support this?
        case 0xEFBB where count >= 3 && ptr[2] == 0xBF: return (.utf8, 3)
        default: break
        }
    }
    return (.utf8, 0)
}

private func ensuringUTF8(_ data: Data, _ impl: (UnsafePointer<UInt8>, Int) throws -> Any) rethrows -> Any {
    return try data.withUnsafeBytes { (ptr: UnsafePointer<UInt8>) -> Any in
        let (encoding, skipped) = detectEncoding(ptr, data.count)
        if encoding != .utf8 {
            // NOTE: This is very slow operation.
            // But we want to assume UTF16/UTF32 JSON are not commonly used.
            let buf = UnsafeBufferPointer(start: ptr + skipped, count: data.count - skipped)
            let str = String(bytes: buf, encoding: encoding)
            let converted = str?.data(using: .utf8) ?? Data()
            return try converted.withUnsafeBytes { (ptr: UnsafePointer<UInt8>) -> Any in
                try impl(ptr, converted.count)
            }
        }
        return try impl(ptr + skipped, data.count &- skipped)
    }
}
