#if os(macOS) || os(iOS) || os(tvOS) || os(watchOS)
  import Darwin
#elseif os(Linux) || os(FreeBSD) || os(Android)
  import Glibc
#endif

public struct JSONParsingError : Error, CustomStringConvertible {
    public enum Kind {
        case unknownToken
        case unknownKeyword
        case unterminatedString
        case invalidString
        case invalidNumber
        case unexpectedToken
        case expectedString
        case expectedValue
        case expectedArrayClose
        case expectedObjectClose
        case expectedColon
        case expectedEOF
        case maxDepthExceeded
        
        public var description: String {
            switch self {
            case .unknownToken: return "unknown token"
            case .unknownKeyword: return "unknown keyword"
            case .unterminatedString: return "unterminated string"
            case .invalidString: return "invalid character in string"
            case .invalidNumber: return "invalid number"
            case .unexpectedToken: return "unexpected token"
            case .expectedString: return "expected string"
            case .expectedValue: return "expected value"
            case .expectedArrayClose: return "expected closing ']'"
            case .expectedObjectClose: return "expected closing '}'"
            case .expectedColon: return "expected ':'"
            case .expectedEOF: return "expected EOF"
            case .maxDepthExceeded: return "max depth exceeded"
            }
        }
    }
    
    public let kind: Kind
    public let line: Int
    public let column: Int

    public var description: String {
        return "\(kind.description) at \(line):\(column)"
    }
}

typealias Pointer = UnsafePointer<UInt8>

private struct Token {
    enum Kind {
        case l_brace
        case r_brace
        case l_square
        case r_square
        case colon
        case comma
        case true_
        case false_
        case null
        case string
        case integer
        case real
        case eof
        case unknown
    }
    
    typealias Range = Swift.CountableRange<Pointer>
    
    let kind: Kind
    let range: Range
    init(_ _kind: Kind, _ _range: Range) {
        kind = _kind
        range = _range
    }
    
    var loc: Pointer {
        return range.lowerBound
    }
}

/// Lexer implementation
private struct Lexer {
    
    let startPtr: Pointer
    let endPtr: Pointer
    var ptr: Pointer
    
    init(start: Pointer, end: Pointer) {
        self.startPtr = start
        self.endPtr = end
        self.ptr = start
    }

    /// Create a token with given kind and the start location.
    /// The current location of the lexer is used as a end location of the token.
    func createToken(_ kind: Token.Kind, _ start: Pointer) -> Token {
        return Token(kind, start ..< ptr)
    }

    /// Get line number and column number of the pointer in the buffer of this
    /// lexer.
    /// Precondition: target pointer must be in startPtr...endPtr
    func getLineAndColumn(_ target: Pointer) -> (Int, Int) {
        assert(target >= startPtr && target <= endPtr)
        
        var ptr = startPtr
        var line = 1
        var column = 1
        
        while ptr != target {
            if ptr.pointee == ascii8("\n") {
                line += 1
                column = 1
            }
            else {
                column += 1
            }
            ptr += 1
        }
        
        return (line, column)
    }

    /// create Error object with given kind and position.
    func createError(_ kind: JSONParsingError.Kind, _ ptr: Pointer) -> JSONParsingError {
        let (line, column) = getLineAndColumn(ptr)
        return JSONParsingError(kind: kind, line: line, column: column)
    }

    /// Tokenize next token and return it.
    mutating func lexImpl() -> Token {
        var start = ptr
        repeat {
            if ptr == endPtr {
                return createToken(.eof, ptr)
            }
            let c = ptr.pointee
            ptr += 1
            switch c {
            case ascii8(" "), // Space
                 ascii8("\n"), // Line feed or New line
                 ascii8("\r"), // Carriage return
                 ascii8("\t"): // Horizontal tab
                start += 1
                continue
            case ascii8("\""): // quotation mark
                return lexString()
            case ascii8("{"): // left curly bracket
                return createToken(.l_brace, start)
            case ascii8("}"): // right curly bracket
                return createToken(.r_brace, start)
            case ascii8(":"): // colon
                return createToken(.colon, start)
            case ascii8(","): // comma
                return createToken(.comma, start)
            case ascii8("["): // left square bracket
                return createToken(.l_square, start)
            case ascii8("]"): // right square bracket
                return createToken(.r_square, start)
            case ascii8("0")...ascii8("9"), // 0...9
            ascii8("-"): // minus
                return lexNumber()
            case ascii8("a")...ascii8("z"), // a-z
            ascii8("A")...ascii8("Z"): // A-Z
                return lexKeyword()
            default:
                return createToken(.unknown, start)
            }
        } while ptr != endPtr
        
        return createToken(.eof, ptr)
    }

    /// Tokenize a keyword.
    mutating func lexKeyword() -> Token {
        let start = ptr - 1
        if endPtr - ptr >= 3 {
            let char4 = start.withMemoryRebound(to: UInt32.self, capacity: 1, { $0.pointee.bigEndian })
            switch char4 {
            // null
            case ascii32("n") << 24 |
                 ascii32("u") << 16 |
                 ascii32("l") << 8 |
                 ascii32("l"):
                ptr += 3
                return createToken(.null, start)
            // true
            case ascii32("t") << 24 |
                 ascii32("r") << 16 |
                 ascii32("u") << 8 |
                 ascii32("e"):
                ptr += 3
                return createToken(.true_, start)
            // false
            case ascii32("f") << 24 |
                 ascii32("a") << 16 |
                 ascii32("l") << 8 |
                 ascii32("s") where
                 endPtr - ptr >= 4 && ptr[3] == ascii8("e"):
                ptr += 4
                return createToken(.false_, start)
            default:
                break
            }
        }
        
        return createToken(.unknown, start)
    }

    /// Tokenize a string literal.
    mutating func lexString() -> Token {
        let start = ptr - 1
        while ptr != endPtr {
            // Find '"'.
            if ptr.pointee == ascii8("\"") {
                // back track to validate this is NOT escaped '"'.
                var backtrack = ptr - 1
                var close = true
                while backtrack.pointee == ascii8("\\") {
                    close = !close
                    backtrack -= 1
                }
                if close {
                    ptr += 1
                    return createToken(.string, start)
                }
            }
            ptr += 1
        }
        return createToken(.unknown, start)
    }

    /// Tokenize a number literal.
    mutating func lexNumber() -> Token {
        let start = ptr-1
        let digit = ascii8("0")...ascii8("9")

        while ptr != endPtr && digit ~= ptr.pointee {
            ptr += 1
        }
        
        var isInteger = true
        
        if (
            // '-'; Minus sign without integer part.
            ptr - start == 1 && start.pointee == ascii8("-") ||
            // '0' DIGIT*N; Number cannot start with zero.
            ptr - start > 1 && start.pointee == ascii8("0") ||
            // '-0' DIGIT*N;
            ptr - start > 2 && start.pointee == ascii8("-") && (start+1).pointee == ascii8("0") 
        ) {
            return createToken(.unknown, start)
        }
        
        // Eat fraction part....
        if ptr.pointee == ascii8(".") {
            ptr += 1
            let ptrAfterDot = ptr;
            while ptr != endPtr && digit ~= ptr.pointee {
                ptr += 1
            }
            if ptr == ptrAfterDot {
                // Fraction without following digits.
                return createToken(.unknown, start)
            }
            isInteger = false
        }
        
        // Eat exponent part.
        if ptr.pointee == ascii8("e") || ptr.pointee == ascii8("E") {
            ptr += 1
            if ptr == endPtr {
                return createToken(.unknown, start)
            }
            
            // Eat '+' or '-'
            if ptr.pointee == ascii8("+") || ptr.pointee == ascii8("-") {
                ptr += 1
            }
            
            let ptrAfterExp = ptr;
            while ptr != endPtr && digit ~= ptr.pointee {
                ptr += 1
            }
            if ptr == ptrAfterExp {
                // Exponent without following digits.
                return createToken(.unknown, start)
            }
            isInteger = false
        }
        
        if isInteger {
            return createToken(.integer, start)
        } else {
            return createToken(.real, start)
        }
    }
}

extension Lexer {

    /// Iterator for escaped characters.
    /// Stops when next character is not '\'.
    struct EscapedCharacterIterator : IteratorProtocol {
        var ptr: Pointer
        var end: Pointer
        var hasError = false
        init(ptr: Pointer, end: Pointer) {
            self.ptr = ptr
            self.end = end
        }
        
        mutating func next() -> UTF16.CodeUnit? {
            if ptr == end || ptr.pointee != ascii8("\\") {
                return nil
            }
            
            // Eat '\'.
            ptr += 1
            
            let c = UTF16.CodeUnit(ptr.pointee)
            ptr += 1
            switch c {
            case ascii16("\""): return ascii16("\"") // quotation mark
            case ascii16("\\"): return ascii16("\\") // reverse solidus
            case ascii16("/"): return ascii16("/") // solidus
            case ascii16("b"): return 0x08 // backspace
            case ascii16("f"): return 0x0C // form feed
            case ascii16("n"): return 0x0A // line feed
            case ascii16("r"): return 0x0D // carriage return
            case ascii16("t"): return 0x09 // tab
            case ascii16("u"): // uXXXX
                break;
            default:
                hasError = true
                return nil
            }
            
            if (end - ptr) < 4 {
                hasError = true
                return nil
            }
            
            func fromHex(c: UTF16.CodeUnit) -> UTF16.CodeUnit {
                switch c {
                case ascii16("0")...ascii16("9"): return c &- ascii16("0")
                case ascii16("a")...ascii16("f"): return c &- ascii16("a") &+ 10
                case ascii16("A")...ascii16("F"): return c &- ascii16("A") &+ 10
                default:
                    hasError = true
                    return 0
                }
            }
            
            let result =
                fromHex(c: UTF16.CodeUnit(ptr[0])) << 12 |
                fromHex(c: UTF16.CodeUnit(ptr[1])) << 8 |
                fromHex(c: UTF16.CodeUnit(ptr[2])) << 4 |
                fromHex(c: UTF16.CodeUnit(ptr[3]))
            ptr += 4
            return result
        }
    }

    /// Iterator for unescaped characters.
    /// Stops on '\' or at the end.
    struct NormalCharacterIterator : IteratorProtocol {
        var ptr: Pointer
        let end: Pointer
        var hasError = false
        init(ptr: Pointer, end: Pointer) {
            self.ptr = ptr
            self.end = end
        }
        
        mutating func next() -> UTF8.CodeUnit? {
            if ptr == end || ptr.pointee == ascii8("\\") {
                return nil
            }
            let result = UTF8.CodeUnit(ptr.pointee)
            if result < 0x20 {
                hasError = true;
                return nil
            }
            ptr += 1
            return result
        }
    }

    /// Get string value of the string literal token.
    static func getStringValue(_ range: Token.Range) -> String? {
        var ptr = range.lowerBound + 1
        let end = range.upperBound - 1
        let byteLength = end - ptr
        
        var ret = String.UnicodeScalarView()
        ret.reserveCapacity(byteLength)
        var isASCII = true

        while ptr != end {
            if ptr.pointee == ascii8("\\") {
                var utf16Dec = UTF16()
                var iter = EscapedCharacterIterator(ptr: ptr, end: end)
                LOOP: while true {
                    switch utf16Dec.decode(&iter) {
                    case .scalarValue(let us):
                        if us.value >= 0x80 && isASCII {
                            ret.reserveCapacity(byteLength &* 2)
                            isASCII = false
                        }
                        ret.append(us)
                    case .error:
                        ret.append("\u{fffd}")
                    case .emptyInput:
                        break LOOP
                    }
                }
                if iter.hasError {
                    return nil
                }
                ptr = iter.ptr
            }
            else {
                var utf8Dec = UTF8()
                var iter = NormalCharacterIterator(ptr: ptr, end: end)
                LOOP: while true {
                    switch utf8Dec.decode(&iter) {
                    case .scalarValue(let us):
                        ret.append(us)
                    case .error:
                        // Reject error
                        return nil
                    case .emptyInput:
                        break LOOP
                    }
                }
                if iter.hasError {
                    return nil
                }
                ptr = iter.ptr
            }
        }
        return String(ret)
    }

    private static func withMakingCString<T>(_ range: Token.Range, fn: (UnsafePointer<Int8>) -> T) -> T? {
        let tmpBuf = UnsafeMutablePointer<Int8>.allocate(capacity: range.count &+ 1)
        defer { tmpBuf.deallocate(capacity: range.count &+ 1) }
        range.lowerBound.withMemoryRebound(to: Int8.self, capacity: range.count) {
            tmpBuf.assign(from: $0, count: range.count)
        }
        tmpBuf[range.count] = 0 // NUL terminate
        
        errno = 0
        let result = fn(tmpBuf)
        guard errno == 0 || errno == ERANGE else {
            return nil
        }
        return result
    }

    /// Get real value of the real number literal token.
    static func getRealValue(_ range: Token.Range) -> Double? {
        // Use strtod instead of Double.init(_:String) because the latter returns
        // `nil` for out of range values
        return withMakingCString(range) { strtod($0, nil) }
    }

    /// Get integer value of the integer number literal token.
    static func getIntegerValue(_ range: Token.Range) -> Int? {
        // Use strtol instead of Double.init(_:String) because the latter returns
        // `nil` for out of range values
        return withMakingCString(range) { strtol($0, nil, 10) }
    }
}

/// Implmentation detail of the JSON parser.
struct ParserImpl<NullType> {
    let maxDepth: Int
    let nullValue: NullType
    private var lexer: Lexer
    private var depth: Int
    private var token: Token
    
    init(start: Pointer, end: Pointer, null: NullType, maxDepth: Int) {
        self.maxDepth = maxDepth
        self.nullValue = null
        self.lexer = Lexer(start: start, end: end)
        self.depth = 0
        self.token = lexer.lexImpl()
    }

    /// Parse JSON number(integer) at the current token.
    mutating func parseRoot() throws -> Any {
        let value = try parseValue()
        if token.kind != .eof {
            throw lexer.createError(.expectedEOF, token.loc)
        }
        return value
    }

    /// Consume current token.
    /// Asserts the currentToken is the given kind.
    private mutating func consumeToken(_ kind: Token.Kind) {
        assert(token.kind == kind)
        token = lexer.lexImpl()
    }

    /// Consume current token only if it is a given token kind.
    ///
    /// Returns: true if consumed, false otherwise
    private mutating func consumeIf(_ kind: Token.Kind) -> Bool {
        if token.kind != kind {
            return false
        }
        token = lexer.lexImpl()
        return true;
    }

    /// Parse single JSON value starting from the current token.
    ///
    /// value:
    ///   object
    ///   array
    ///   string
    ///   integer-number
    ///   real-number
    ///   true
    ///   false
    ///   null
    private mutating func parseValue() throws -> Any {
        switch(token.kind) {
        case .l_brace:
            return try parseObject()
        case .l_square:
            return try parseArray()
        case .true_:
            consumeToken(.true_)
            return true
        case .false_:
            consumeToken(.false_)
            return false
        case .string:
            return try parseString()
        case .integer:
            return try parseIntegerNumber()
        case .real:
            return try parseRealNumber()
        case .null:
            consumeToken(.null)
            return nullValue
        case .eof:
            throw lexer.createError(.expectedValue, token.loc)
        case .comma, .colon, .r_brace, .r_square:
            throw lexer.createError(.unexpectedToken, token.loc)
        case .unknown:
            throw lexer.createError(.unknownToken, token.loc)
        }
    }

    /// Parse JSON object starting from the current token.
    ///
    /// object:
    ///   '{' (string ':' value)* '}'
    private mutating func parseObject() throws -> Any {
        consumeToken(.l_brace)

        var obj: [String: Any] = [:]
        
        if consumeIf(.r_brace) {
            return obj
        }
        
        if depth >= maxDepth {
          throw lexer.createError(.maxDepthExceeded, token.loc)
        }
        
        depth = depth &+ 1
        repeat {
            if token.kind != .string {
                throw lexer.createError(.expectedString, token.loc)
            }
            let key = try parseString() as! String;
            if !consumeIf(.colon) {
                throw lexer.createError(.expectedColon, token.loc)
            }
            let value = try parseValue()
            
            obj[key] = value
        } while consumeIf(.comma)
        depth = depth &- 1
        
        if !consumeIf(.r_brace) {
            throw lexer.createError(.expectedObjectClose, token.loc)
        }
        return obj
    }

    /// Parse JSON array starting from the current token.
    ///
    /// object:
    ///   '[' (value)* ']'
    private mutating func parseArray() throws -> Any {
        consumeToken(.l_square)
        
        var ary: [Any] = []
        
        // Short circuit
        if consumeIf(.r_square) {
            return ary
        }

        if depth >= maxDepth {
          throw lexer.createError(.maxDepthExceeded, token.loc)
        }
        
        depth = depth &+ 1
        repeat {
            try ary.append(parseValue())
        } while consumeIf(.comma)
        depth = depth &- 1
        
        if !consumeIf(.r_square) {
            throw lexer.createError(.expectedArrayClose, token.loc)
        }
        return ary
    }

    /// Parse JSON string at the current token.
    ///
    /// string:
    ///   string-literal
    private mutating func parseString() throws -> Any {
        assert(token.kind == .string)
        guard let result = Lexer.getStringValue(token.range) else {
            throw lexer.createError(.invalidString, token.loc)
        }
        consumeToken(.string)
        return result
    }

    /// Parse JSON number(real) at the current token.
    ///
    /// real-numer:
    ///   number-literal(real)
    private mutating func parseRealNumber() throws -> Any {
        assert(token.kind == .real)
        guard let result = Lexer.getRealValue(token.range) else {
            throw lexer.createError(.invalidNumber, token.loc)
        }
        consumeToken(.real)
        return result
    }

    /// Parse JSON number(integer) at the current token.
    ///
    /// integer-number:
    ///   number-literal(integer)
    private mutating func parseIntegerNumber() throws -> Any {
        assert(token.kind == .integer)
        guard let result = Lexer.getIntegerValue(token.range) else {
            throw lexer.createError(.invalidNumber, token.loc)
        }
        consumeToken(.integer)
        return result
    }
}
