import Foundation

var MAX_DEPTH_DEFAULT: Int { return 512 }
var INDENT_SHIFT_OFF: Int { return -1 }

/// JSON encoder/decoder
struct JSON {
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
    static func decode(
        _ data: Data,
        maxDepth: Int = MAX_DEPTH_DEFAULT
    ) throws -> Any {
        return try data.withUnsafeBytes { (ptr: UnsafePointer<UInt8>) -> Any in
            var impl = try ParserImpl(
                start: ptr,
                end: ptr + data.count,
                null: NSNull(),
                maxDepth: maxDepth)
            return try impl.parseRoot()
        }
    }

    static func encode(
        _ value: Any,
        maxDepth: Int = MAX_DEPTH_DEFAULT,
        indentShift: Int = INDENT_SHIFT_OFF,
        spatial: Bool = false,
        asciiOnly: Bool = false
    ) throws -> Data {
        var result = Data();
        let sink = { (chunk: UnsafeRawBufferPointer) -> Void in
          let chunkStart = chunk.baseAddress!.assumingMemoryBound(to: UInt8.self)
          result.append(UnsafeBufferPointer(start: chunkStart, count: chunk.count))
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
    func decode(_ data: Data) throws -> Any {
        return try JSON.decode(data,
            maxDepth: maxDepth
        )
    }

    func encode(_ value: Any) throws -> Data {
        return try JSON.encode(value,
            maxDepth: maxDepth,
            indentShift: indentShift,
            spatial: spatial,
            asciiOnly: asciiOnly
        )
    }
}
