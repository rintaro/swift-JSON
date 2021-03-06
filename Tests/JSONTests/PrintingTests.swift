import Foundation
import XCTest
@testable import JSON

private func str(_ data: Data) -> String {
    return String(data: data, encoding: .utf8)!
}

class Foo {}
struct Bar {}

class JSONPrintingTests: XCTestCase {
    func testKeyword() throws {
        try XCTAssertEqual(str(JSON.encode(NSNull())), "null")
        try XCTAssertEqual(str(JSON.encode(true)), "true")
        try XCTAssertEqual(str(JSON.encode(false)), "false")
    }
    
    func testNumber() throws {
        try XCTAssertEqual(str(JSON.encode(42 as Int)), "42")
        try XCTAssertEqual(str(JSON.encode(42 as Int8)), "42")
        try XCTAssertEqual(str(JSON.encode(42 as Int16)), "42")
        try XCTAssertEqual(str(JSON.encode(42 as Int32)), "42")
        try XCTAssertEqual(str(JSON.encode(42 as Int64)), "42")
        try XCTAssertEqual(str(JSON.encode(42 as UInt)), "42")
        try XCTAssertEqual(str(JSON.encode(42 as UInt8)), "42")
        try XCTAssertEqual(str(JSON.encode(42 as UInt16)), "42")
        try XCTAssertEqual(str(JSON.encode(42 as UInt32)), "42")
        try XCTAssertEqual(str(JSON.encode(42 as UInt64)), "42")
        try XCTAssertEqual(str(JSON.encode(-42 as Int)), "-42")
        try XCTAssertEqual(str(JSON.encode(-42 as Int8)), "-42")
        try XCTAssertEqual(str(JSON.encode(-42 as Int16)), "-42")
        try XCTAssertEqual(str(JSON.encode(-42 as Int32)), "-42")
        try XCTAssertEqual(str(JSON.encode(-42 as Int64)), "-42")
        try XCTAssertEqual(str(JSON.encode(42.5 as Double)), "42.5")
        try XCTAssertEqual(str(JSON.encode(-42.5 as Double)), "-42.5")
        try XCTAssertEqual(str(JSON.encode(0.0000000001 as Double)), "1e-10")
    }
    
    
    func testString_simpleEscape() throws {
        try XCTAssertEqual(str(JSON.encode("\"")), "\"\\\"\"")
        try XCTAssertEqual(str(JSON.encode("\\")), "\"\\\\\"")
        try XCTAssertEqual(str(JSON.encode("/")), "\"/\"")
        try XCTAssertEqual(str(JSON.encode("\u{08}")), "\"\\b\"")
        try XCTAssertEqual(str(JSON.encode("\u{0C}")), "\"\\f\"")
        try XCTAssertEqual(str(JSON.encode("\u{0A}")), "\"\\n\"")
        try XCTAssertEqual(str(JSON.encode("\u{0D}")), "\"\\r\"")
        try XCTAssertEqual(str(JSON.encode("\u{09}")), "\"\\t\"")
    }

    
    func testString_unicodeEscape() throws {
        try XCTAssertEqual(str(JSON.encode("\u{1}")), "\"\\u0001\"")
        try XCTAssertEqual(str(JSON.encode("\u{19}")), "\"\\u0019\"")
        
        try XCTAssertEqual(str(JSON.encode("✨")), "\"✨\"")
        try XCTAssertEqual(str(JSON.encode("\u{1D11E}")), "\"𝄞\"")
        
        try XCTAssertEqual(str(JSON.encode("✨", asciiOnly: true)), "\"\\u2728\"")
        try XCTAssertEqual(str(JSON.encode("\u{1D11E}", asciiOnly: true)), "\"\\uD834\\uDD1E\"")
    }
    
    func testObject_empty() throws {
        try XCTAssertEqual(str(JSON.encode([:] as [String: Any])), "{}")
    }

    func testObject_multiString() throws {
        let result = try str(JSON.encode(["hello": "world", "swift": "rocks🐦"]))
        XCTAssertTrue(
           result == "{\"hello\":\"world\",\"swift\":\"rocks🐦\"}" ||
           result == "{\"swift\":\"rocks🐦\",\"hello\":\"world\"}"
        )
    }

    func testArray_empty() throws {
        try XCTAssertEqual(str(JSON.encode([] as [Any])), "[]")
    }

    func testArray_multiString() throws {
        try XCTAssertEqual(str(JSON.encode(["hello", "swift⚡️"])), "[\"hello\",\"swift⚡️\"]")
    }
    
    func testUnicodeString() throws {
        try XCTAssertEqual(str(JSON.encode(["Ģ", "😢"])), "[\"Ģ\",\"😢\"]")
        try XCTAssertEqual(str(JSON.encode(["Ģ", "😢"], asciiOnly: true)), "[\"\\u0122\",\"\\uD83D\\uDE22\"]")
    }
    
    func testError_numericKeyword() throws {
        try XCTAssertThrowsError(str(JSON.encode(-Float.nan))) {
            let err = $0 as? JSONPrintingError
            XCTAssertNotNil(err)
            XCTAssertEqual(err!.description, "invalid numeric value 'nan'")
        }
        try XCTAssertThrowsError(str(JSON.encode(-Double.infinity))) {
            let err = $0 as? JSONPrintingError
            XCTAssertNotNil(err)
            XCTAssertEqual(err!.description, "invalid numeric value '-inf'")
        }
    }

    func testError_unknownValue() {
        try XCTAssertThrowsError(str(JSON.encode([Foo()]))) {
            let err = $0 as? JSONPrintingError
            XCTAssertNotNil(err)
            XCTAssertEqual(err!.description, "invalid value of type 'Foo'")
        }
        try XCTAssertThrowsError(str(JSON.encode([Bar()]))) {
            let err = $0 as? JSONPrintingError
            XCTAssertNotNil(err)
            XCTAssertEqual(err!.description, "invalid value of type 'Bar'")
        }
    }
    
    func testIndent_array() {
        try XCTAssertEqual(str(JSON.encode([], indentShift: 2)), "[]\n")
        try XCTAssertEqual(str(JSON.encode([1], indentShift: 2)), "[\n  1\n]\n")
        try XCTAssertEqual(str(JSON.encode([42, 12], indentShift: 2)), "[\n  42,\n  12\n]\n")
        try XCTAssertEqual(str(JSON.encode([42, [1,2]], indentShift: 2)), "[\n  42,\n  [\n    1,\n    2\n  ]\n]\n")
    }
    
    func testIndent_object() {
        try XCTAssertEqual(str(JSON.encode([:], indentShift: 2)), "{}\n")

        let result1 = try! str(JSON.encode(["foo": true, "bar": -1], indentShift: 2))
        XCTAssertTrue(
           result1 == "{\n  \"foo\":true,\n  \"bar\":-1\n}\n" ||
           result1 == "{\n  \"bar\":-1,\n  \"foo\":true\n}\n"
        )
        let result2 = try! str(JSON.encode(["foo": true, "bar": ["baz": 1]], indentShift: 2))
        XCTAssertTrue(
           result2 == "{\n  \"foo\":true,\n  \"bar\":{\n    \"baz\":1\n  }\n}\n" ||
           result2 == "{\n  \"bar\":{\n    \"baz\":1\n  },\n  \"foo\":true\n}\n"
        )
    }

    func testIndent_mixed() {
        try XCTAssertEqual(str(JSON.encode([42, ["foo": [1, NSNull()]]], indentShift: 2)),
                           "[\n  42,\n  {\n    \"foo\":[\n      1,\n      null\n    ]\n  }\n]\n")
    }

    func testSpatial() {
        try XCTAssertEqual(str(JSON.encode([42, ["foo": [1, NSNull()]], -12], spatial: true)),
                           "[42, {\"foo\": [1, null]}, -12]")

        try XCTAssertEqual(str(JSON.encode([42, ["foo": [1, NSNull()]], -12], indentShift: 2, spatial: true)),
                           "[\n  42,\n  {\n    \"foo\": [\n      1,\n      null\n    ]\n  },\n  -12\n]\n")
    }
    
    static var allTests : [(String, (JSONPrintingTests) -> () throws -> Void)] {
        return [
            ("testKeyword", testKeyword),
            ("testNumber", testNumber),
            ("testString_simpleEscape", testString_simpleEscape),
            ("testString_unicodeEscape", testString_unicodeEscape),
            ("testObject_empty", testObject_empty),
            ("testObject_multiString", testObject_multiString),
            ("testArray_empty", testArray_empty),
            ("testArray_multiString", testArray_multiString),
            ("testUnicodeString", testUnicodeString),
            
            ("testError_numericKeyword", testError_numericKeyword),
            ("testError_unknownValue", testError_unknownValue),
        ]
    }
}
