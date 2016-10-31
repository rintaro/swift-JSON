var BUF_SIZE: Int { return 1024 }

public enum JSONPrintingError : Error, CustomStringConvertible {
    case invalidNumericValue(String)
    case maxDepthExceeded(Int)
    case unexpectedValue(Any)

    public var description: String {
        switch self {
        case let .invalidNumericValue(val):
            return "invalid numeric value '\(val)'"
        case let .maxDepthExceeded(maxDepth):
            return "max depth(\(maxDepth)) exceeded"
        case let .unexpectedValue(val):
            return "invalid value of type '\(type(of: val))'"
        }
    }
}

struct PrinterImpl<NullType> {
    typealias Sink = (UnsafeRawBufferPointer) -> Void

    // internal state
    private var buf: UnsafeMutableRawBufferPointer
    private var bufIdx: UnsafeMutableRawBufferPointer.Index
    private var depth: Int = 0
    private var isFreshLine: Bool = false

    private let root: Any
    private let sink: Sink

    // Options
    private let maxDepth: Int
    private let allowNumericKeyword: Bool = false
    private let indentShift: Int
    private let spatial: Bool
    private let asciiOnly: Bool

    init(
        root: Any,
        into sink: @escaping Sink,
        null: NullType,
        maxDepth: Int = 512,
        indentShift: Int = -1,
        spatial: Bool = false,
        asciiOnly: Bool = false
    ) {
        self.root = root
        self.sink = sink
        self.buf = .allocate(count: BUF_SIZE)
        self.bufIdx = buf.startIndex
        self.maxDepth = maxDepth
        self.indentShift = indentShift
        self.spatial = spatial
        self.asciiOnly = asciiOnly
    }

    /// Flush internal buffer.
    mutating func flush() {
        sink(UnsafeRawBufferPointer(buf[buf.startIndex..<bufIdx as Range]))
        bufIdx = buf.startIndex
    }

    mutating func put(_ chr: UTF8.CodeUnit) {
        if bufIdx == buf.endIndex {
            flush()
        }
        buf[bufIdx] = chr
        bufIdx += 1
    }

    mutating func put<S : Sequence>(_ seq: S)
        where S.Iterator.Element == UTF8.CodeUnit {
        for chr in seq {
            put(chr)
        }
    }

    /// Output given string.
    mutating func put(_ str: String) {
        put(str.utf8)
    }

    /// space:
    ///   ' ' ; if spatial
    ///       ; otherwise
    mutating func putSpace() {
        if spatial {
            put(ascii8(" "))
        }
    }

    /// numeric-keyword(enabledNumericKeyword)
    ///   'nan'
    ///   'inf'
    ///   '-inf'
    /// numeric-keyword(disabled)
    ///   ; N/A
    mutating func putNumericKeyword(_ kw: String) throws {
        if !allowNumericKeyword {
            throw JSONPrintingError.invalidNumericValue(kw)
        } else {
            put(kw)
        }
    }

    func toHex(_ x: UTF8.CodeUnit) -> UTF8.CodeUnit {
        return x < 10
            ? x + ascii8("0")
            : x + (ascii8("A") - 10)
    }

    /// escaped:
    ///  '\b'
    ///  '\f'
    ///  '\n'
    ///  '\r'
    ///  '\t'
    ///  '\u' 4*HEX_DIGIT
    mutating func putEscaped(_ unit: UTF16.CodeUnit) {
        put(ascii8("\\")); 
        switch unit {
        case ascii16("\\"): put(ascii8("\\"))
        case ascii16("\""): put(ascii8("\""))
        case 0x08: put(ascii8("b")) // \b
        case 0x0C: put(ascii8("f")) // \f
        case 0x0A: put(ascii8("n")) // \n
        case 0x0D: put(ascii8("r")) // \r
        case 0x09: put(ascii8("t")) // \t
        default:
            put(ascii8("u"))
            put(toHex(UTF8.CodeUnit(unit >> 12 & 0xF)))
            put(toHex(UTF8.CodeUnit(unit >> 8 & 0xF)))
            put(toHex(UTF8.CodeUnit(unit >> 4 & 0xF)))
            put(toHex(UTF8.CodeUnit(unit >> 0 & 0xF)))
        }
    }

    // newline:
    mutating func putNewLine() {
        put(ascii8("\n"))
        isFreshLine = true;
    }

    // newline-or-space:
    //   %x0A   ; if indent-shift >= 0
    //   space  ; if spatial
    //          ; otherwise
    mutating func putNewLineOrSpace() {
        if indentShift >= 0 {
            putNewLine()
        } else if spatial {
            put(ascii8(" "))
        }
    }

    /// indent:
    ///   N*(' ') ; N = indent-shift * depth
    mutating func putIndent() {
        if isFreshLine && indentShift > 0 {
            for _ in 0..<(indentShift * depth) {
                put(ascii8(" "))
            }
        }
    }

    /// interleave(first):
    ///   indent
    ///
    /// interleave(normal):
    ///   ',' indent
    ///   ',' newline-or-space indent
    mutating func putInterleave(_ first: inout Bool) {
        if !first {
            put(ascii8(","))
            putNewLineOrSpace()
        } else {
            first = false
        }
        putIndent()
    }

    /// block(elements):
    ///   bload-head elements block-tail
    /// block-head:
    ///   %x0A ; if indent-shift >= 0
    /// block-tail
    ///   %x0A ; if indent-shift >= 0
    mutating func withBlock(_ fn: () throws -> Void) throws {
        if depth >= maxDepth {
            throw JSONPrintingError.maxDepthExceeded(maxDepth)
        }

        depth += 1
        if indentShift >= 0 {
            putNewLine()
            try fn()
            putNewLine()
        } else {
            try fn()
        }
        depth -= 1
        putIndent()
    }


    // value printers

    /// array:
    ///   '[' block(array-element-list?) ']'
    /// array-element-list
    ///   array-element
    ///   array-element-list ',' array-element
    /// array-element:
    ///   value
    mutating func visitArray(_ arry: [Any]) throws {
        put(ascii8("["))
        try withBlock {
            var first = true
            for value in arry {
                putInterleave(&first)
                try visit(value)
            }
        }
        put(ascii8("]"))
    }

    /// object:
    ///   '{' block(object-element-list?) '}'
    /// object-element-list:
    ///   object-element
    ///   object-element-list ',' object-elemnt
    /// object-element:
    ///   string ':' value
    mutating func visitDictionary(_ dict: [String: Any]) throws {
        put(ascii8("{"))
        try withBlock {
            var first = true
            for (k, value) in dict {
                putInterleave(&first)
                try visitString(k)
                put(ascii8(":"))
                putSpace()
                try visit(value)
            }
        }
        put(ascii8("}"))
    }

    /// string:
    ///   '"' chars '"'
    mutating func visitString(_ str: String) throws {
        put(ascii8("\""))
        if (asciiOnly) {
            for unit in str.utf16 {
                if (0x20..<0x80) ~= unit &&
                    unit != ascii16("\"") &&
                    unit != ascii16("\\") {
                    put(UTF8.CodeUnit(truncatingBitPattern: unit))
                } else {
                    putEscaped(unit)
                }
            }
        } else {
            for unit in str.utf8 {
                if unit < 0x20 ||
                  unit == ascii8("\"") ||
                  unit == ascii8("\\") {
                    putEscaped(UTF16.CodeUnit(unit))
                } else {
                    put(unit)
                }
            }
        }
        put(ascii8("\""))
    }

    // integer:
    //   chars
    mutating func visitInteger<T : Integer>(_ int: T) throws {
        put(String(describing: int))
    }

    // floating-point:
    //   chars
    mutating func visitFloatingPoint<T : FloatingPoint>(_ flt: T) throws {
        switch flt.floatingPointClass {
        case .signalingNaN, .quietNaN:
            try putNumericKeyword("nan")
        case .negativeInfinity,
            .positiveInfinity:
            if flt.sign == .minus {
                try putNumericKeyword("-inf")
            } else {
                try putNumericKeyword("inf")
            }
        case .negativeZero, .positiveZero:
            put(ascii8("0"))
        default:
            put(String(describing: flt))
        }
    }

    /// boolean:
    ///   'true'
    ///   'false'
    mutating func visitBool(_ bool: Bool) throws {
        if bool {
            put("true")
        } else {
            put("false")
        }
    }

    /// null:
    ///   'null'
    mutating func visitNull(_ null: NullType) throws {
        put("null")
    }

    /// value:
    ///   string
    ///   array
    ///   object
    ///   boolean
    ///   null
    ///   integer
    ///   floatingpoint
    mutating func visit(_ value: Any) throws {
        switch value {
        case let str as String: try visitString(str)
        case let arry as [Any]: try visitArray(arry)
        case let obj as [String: Any]: try visitDictionary(obj)
        case let bool as Bool: try visitBool(bool)
        case let null as NullType: try visitNull(null)
        // integers
        case let int as Int: try visitInteger(int)
        case let int as Int8: try visitInteger(int)
        case let int as Int16: try visitInteger(int)
        case let int as Int32: try visitInteger(int)
        case let int as Int64: try visitInteger(int)
        case let int as UInt: try visitInteger(int)
        case let int as UInt8: try visitInteger(int)
        case let int as UInt16: try visitInteger(int)
        case let int as UInt32: try visitInteger(int)
        case let int as UInt64: try visitInteger(int)
        // floating points
        case let flt as Float: try visitFloatingPoint(flt)
        case let dbl as Double: try visitFloatingPoint(dbl)
        default:
            throw JSONPrintingError.unexpectedValue(value)
        }
    }

    mutating func printRoot() throws {
        try visit(root)
        if indentShift >= 0 {
            putNewLine()
        }
        flush()
    }
}
