
public struct JSONParsingError : Error, CustomStringConvertible {
  enum Kind {
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

    var description: String {
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
      }
    }
  }
  var kind: Kind
  var line: Int
  var column: Int

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

func ascii16(_ x: UnicodeScalar) -> UTF16.CodeUnit {
  return UTF16.CodeUnit(truncatingBitPattern: x.value)
}

func ascii8(_ x: UnicodeScalar) -> UTF8.CodeUnit {
  return UTF8.CodeUnit(truncatingBitPattern: x.value)
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
  mutating func lexImpl() throws -> Token {
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
        return try lexString()
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
        return try lexNumber()
      case ascii8("a")...ascii8("z"), // a-z
           ascii8("A")...ascii8("Z"): // A-Z
        return try lexKeyword()
      default:
        throw createError(.unexpectedToken, start)
      }
    } while ptr != endPtr

    return createToken(.eof, ptr)
  }

  /// Tokenize a keyword.
  mutating func lexKeyword() throws -> Token {
    let start = ptr - 1
    // true
    if start.pointee == ascii8("t") &&
        endPtr - ptr >= 3 &&
        (ptr + 0).pointee == ascii8("r") &&
        (ptr + 1).pointee == ascii8("u") &&
        (ptr + 2).pointee == ascii8("e") {
      ptr += 3
      return createToken(.true_, start)
    }
    // false
    if start.pointee == ascii8("f") &&
        endPtr - ptr >= 4 &&
        (ptr + 0).pointee == ascii8("a") &&
        (ptr + 1).pointee == ascii8("l") &&
        (ptr + 2).pointee == ascii8("s") &&
        (ptr + 3).pointee == ascii8("e") {
      ptr += 4
      return createToken(.false_, start)
    }
    // null
    if start.pointee == ascii8("n") &&
        endPtr - ptr >= 3 &&
        (ptr + 0).pointee == ascii8("u") &&
        (ptr + 1).pointee == ascii8("l") &&
        (ptr + 2).pointee == ascii8("l") {
      ptr += 3
      return createToken(.null, start)
    }

    throw createError(.unknownKeyword, start)
  }

  /// Tokenize a string literal.
  mutating func lexString() throws -> Token {
    let start = ptr - 1
    while ptr != endPtr {
      // Find 
      if ptr.pointee == ascii8("\"") {
        // back track to validate this is NOT escaped '"'
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
    throw createError(.unterminatedString, start)
  }

  /// Tokenize a number literal.
  mutating func lexNumber() throws -> Token {
    let start = ptr-1
    let digit = ascii8("0")...ascii8("9")

    while ptr != endPtr && digit ~= ptr.pointee {
      ptr += 1
    }

    var isInteger = true

    // Minus sign without integer part.
    if ptr - start == 1 && start.pointee == ascii8("-") {
      throw createError(.invalidNumber, start)
    }
    // Number cannot start with zero.
    if ptr - start != 1 && start.pointee == ascii8("0") {
      throw createError(.invalidNumber, start)
    }

    // Eat fraction part
    if ptr.pointee == ascii8(".") {
      ptr += 1
      let ptrAfterDot = ptr;
      while ptr != endPtr && digit ~= ptr.pointee {
        ptr += 1
      }
      if ptr == ptrAfterDot {
        // Fraction without following digits.
        throw createError(.invalidNumber, start)
      }
      isInteger = false
    }

    // Eat exponent part
    if ptr.pointee == ascii8("e") || ptr.pointee == ascii8("E") {
      ptr += 1
      if ptr == endPtr {
        throw createError(.invalidNumber, start)
      }

      // Eat + or -
      if ptr.pointee == ascii8("+") || ptr.pointee == ascii8("-") {
        ptr += 1
      }

      let ptrAfterExp = ptr;
      while ptr != endPtr && digit ~= ptr.pointee {
        ptr += 1
      }
      if ptr == ptrAfterExp {
        // Exponent without following digits.
        throw createError(.invalidNumber, start)
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
  enum GetValueAbort : Error {
    case dummy
    init() { self = .dummy }
  }

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

      // Eat '\'
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

      let digit = ascii16("0")...ascii16("9")
      let lower = ascii16("a")...ascii16("f")
      let upper = ascii16("A")...ascii16("F")

      var result: UTF16.CodeUnit = 0
      let term = ptr + 4
      while ptr != term {
        let c = UTF16.CodeUnit(ptr.pointee)
        let n: UTF16.CodeUnit
        switch c {
        case digit: n = UTF16.CodeUnit(c) - digit.lowerBound
        case lower: n = UTF16.CodeUnit(c) - lower.lowerBound + 10
        case upper: n = UTF16.CodeUnit(c) - upper.lowerBound + 10
        default:
          hasError = true;
          return nil
        }
        result = (result << 4) + n
        ptr += 1
      }
      return result;
    }
  }

  /// Iterator for unescaped characters.
  /// Stops on '\' or the and
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
      if 0x00...0x19 ~= result {
        hasError = true;
        return nil
      }
      ptr += 1
      return result
    }
  }

  /// Get string value of the string literal token.
  static func getStringValue(_ range: Token.Range) throws -> String {
    var ptr = range.lowerBound + 1
    let end = range.upperBound - 1

    var ret: String = ""
    ret.reserveCapacity(end - ptr)
    func appendResult(_ result: UnicodeDecodingResult, _ hasError: Bool) throws -> Bool {
      if hasError {
        throw GetValueAbort()
      }
      switch result {
      case .scalarValue(let us):
        ret.unicodeScalars.append(us)
        return true
      case .error:
        throw GetValueAbort()
      case .emptyInput:
        return false
      }
    }

    while ptr != end {
      if ptr.pointee == ascii8("\\") {
        var utf16Dec = UTF16()
        var iter = EscapedCharacterIterator(ptr: ptr, end: end)
        while try appendResult(utf16Dec.decode(&iter), iter.hasError) { /* noop */ }
        ptr = iter.ptr
      }
      else {
        var utf8Dec = UTF8()
        var iter = NormalCharacterIterator(ptr: ptr, end: end)
        while try appendResult(utf8Dec.decode(&iter), iter.hasError) { /* noop */ }
        ptr = iter.ptr
      }
    }
    return ret
  }

  /// Get real value of the real number literal token.
  static func getRealValue(_ range: Token.Range) throws -> Double {
    var tmpBuf = Array<UTF8.CodeUnit>()
    tmpBuf.reserveCapacity(range.count + 1)
    tmpBuf.append(contentsOf: UnsafeBufferPointer(start: range.lowerBound, count: range.count))
    tmpBuf.append(0)

    guard let ret = Double(String(cString: tmpBuf)) else {
      throw GetValueAbort()
    }
    return ret
  }

  /// Get integer value of the integer number literal token.
  static func getIntegerValue(_ range: Token.Range) throws -> Int {
    var tmpBuf = Array<UTF8.CodeUnit>()
    tmpBuf.reserveCapacity(range.count + 1)
    tmpBuf.append(contentsOf: UnsafeBufferPointer(start: range.lowerBound, count: range.count))
    tmpBuf.append(0)

    guard let ret = Int(String(cString: tmpBuf)) else {
      throw GetValueAbort()
    }
    return ret
  }
}

/// Implmentation detail of the JSON parser.
struct ParserImpl<NullType> {
  let maxDepth: Int
  let nullValue: NullType
  private var lexer: Lexer
  private var depth: Int
  private var token: Token

  init(start: Pointer, end: Pointer, null: NullType, maxDepth: Int) throws {
    self.maxDepth = maxDepth
    self.nullValue = null
    self.lexer = Lexer(start: start, end: end)
    self.depth = 0
    self.token = try lexer.lexImpl()
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
  private mutating func consumeToken(_ kind: Token.Kind) throws {
    assert(token.kind == kind)
    token = try lexer.lexImpl()
  }

  /// Consume current token only if it is a given token kind.
  ///
  /// Returns: true if consumed, false otherwise
  private mutating func consumeIf(_ kind: Token.Kind) throws -> Bool {
    if token.kind != kind {
      return false
    }
    token = try lexer.lexImpl()
    return true;
  }

  /// Parse single JSON value starting from the current token
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
      try consumeToken(.true_)
      return true
    case .false_:
      try consumeToken(.false_)
      return false
    case .string:
      return try parseString()
    case .integer:
      return try parseIntegerNumber()
    case .real:
      return try parseRealNumber()
    case .null:
      try consumeToken(.null)
      return nullValue
    case .eof:
      throw lexer.createError(.expectedValue, token.loc)
    case .comma, .colon, .r_brace, .r_square:
      throw lexer.createError(.unexpectedToken, token.loc)
    }
  }

  /// Parse JSON object starting from the current token.
  ///
  /// object:
  ///   '{' (string ':' value)* '}'
  private mutating func parseObject() throws -> Any {
    try consumeToken(.l_brace)

    var obj: [String: Any] = [:]

    if try consumeIf(.r_brace) {
      return obj
    }

    depth += 1
    repeat {
      if token.kind != .string {
        throw lexer.createError(.expectedString, token.loc)
      }
      let key = try parseString() as! String;
      if try !consumeIf(.colon) {
        throw lexer.createError(.expectedColon, token.loc)
      }
      let value = try parseValue()

      obj[key] = value
    } while try consumeIf(.comma)
    depth -= 1

    if try !consumeIf(.r_brace) {
      throw lexer.createError(.expectedObjectClose, token.loc)
    }
    return obj
  }

  /// Parse JSON array starting from the current token.
  ///
  /// object:
  ///   '[' (value)* ']'
  private mutating func parseArray() throws -> Any {
    try consumeToken(.l_square)

    var ary: [Any] = []
    
    // Short circuit
    if try consumeIf(.r_square) {
      return ary
    }

    depth += 1
    repeat {
      try ary.append(parseValue())
    } while try consumeIf(.comma)
    depth -= 1

    if try !consumeIf(.r_square) {
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
    do {
      let result = try Lexer.getStringValue(token.range)
      try consumeToken(.string)
      return result
    } catch _ as Lexer.GetValueAbort {
      throw lexer.createError(.invalidString, token.loc)
    }
  }

  /// Parse JSON number(real) at the current token.
  /// 
  /// real-numer:
  ///   number-literal(real)
  private mutating func parseRealNumber() throws -> Any {
    assert(token.kind == .real)
    do {
      let result = try Lexer.getRealValue(token.range)
      try consumeToken(.real)
      return result
    } catch _ as Lexer.GetValueAbort {
      throw lexer.createError(.invalidNumber, token.loc)
    }
  }

  /// Parse JSON number(integer) at the current token.
  /// 
  /// integer-number:
  ///   number-literal(integer)
  private mutating func parseIntegerNumber() throws -> Any {
    assert(token.kind == .integer)
    do {
      let result = try Lexer.getIntegerValue(token.range)
      try consumeToken(.integer)
      return result
    } catch _ as Lexer.GetValueAbort {
      throw lexer.createError(.invalidNumber, token.loc)
    }
  }
}
