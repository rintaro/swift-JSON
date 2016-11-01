import Foundation
import XCTest
@testable import JSON

func data(_ str: String) -> Data {
  return str.data(using: .utf8)!
}

class JSONParsingTests: XCTestCase {
    func testKeyword() throws {
        try XCTAssertEqual(JSON.decode(data("null")) as? NSNull, NSNull())
        try XCTAssertEqual(JSON.decode(data("true")) as? Bool, true)
        try XCTAssertEqual(JSON.decode(data("false")) as? Bool, false)
    }

    func testNumber() throws {
        try XCTAssertEqual(JSON.decode(data("42")) as? Int, 42)
        try XCTAssertEqual(JSON.decode(data("-42")) as? Int, -42)
        try XCTAssertEqual(JSON.decode(data("42.5")) as? Double, 42.5)
        try XCTAssertEqual(JSON.decode(data("-42.5")) as? Double, -42.5)
        try XCTAssertEqual(JSON.decode(data("0")) as? Int, 0)
        try XCTAssertEqual(JSON.decode(data("1e3")) as? Double, 1000)
        try XCTAssertEqual(JSON.decode(data("1e+3")) as? Double, 1000)
        try XCTAssertEqual(JSON.decode(data("1e-3")) as? Double, 0.001)

        try XCTAssertEqual(JSON.decode(data("100000000000000000000000000000")) as? Int, Int.max)
        try XCTAssertEqual(JSON.decode(data("-100000000000000000000000000000")) as? Int, Int.min)

        try XCTAssertEqual(JSON.decode(data("1e+999999")) as? Double, Double.infinity)
        try XCTAssertEqual(JSON.decode(data("1e-999999")) as? Double, 0)
    }

    func testString_simpleEscape() throws {
        try XCTAssertEqual(JSON.decode(data("\"\\\"\"")) as? String, "\"")
        try XCTAssertEqual(JSON.decode(data("\"\\\\\"")) as? String, "\\")
        try XCTAssertEqual(JSON.decode(data("\"\\/\"")) as? String, "/")
        try XCTAssertEqual(JSON.decode(data("\"\\b\"")) as? String, "\u{08}")
        try XCTAssertEqual(JSON.decode(data("\"\\f\"")) as? String, "\u{0C}")
        try XCTAssertEqual(JSON.decode(data("\"\\n\"")) as? String, "\u{0A}")
        try XCTAssertEqual(JSON.decode(data("\"\\r\"")) as? String, "\u{0D}")
        try XCTAssertEqual(JSON.decode(data("\"\\t\"")) as? String, "\u{09}")
    }

    func testString_unicodeEscape() throws {
        try XCTAssertEqual(JSON.decode(data("\"\\u2728\"")) as? String, "✨")
        try XCTAssertEqual(JSON.decode(data("\"\\uD834\\udd1E\"")) as? String, "\u{1D11E}")
    }

    func testObject_empty() throws {
        let obj = try JSON.decode(data("{}")) as? [String: Any]
        XCTAssertNotNil(obj)
        XCTAssertEqual(obj!.count, 0)
    }

    func testObject_multiString() throws {
        let obj = try JSON.decode(data("{ \"hello\": \"world\", \"swift\": \"rocks🐦\" }")) as? [String: Any]
        XCTAssertNotNil(obj)
        XCTAssertEqual(obj!.count, 2)
        XCTAssertEqual(obj!["hello"] as? String, "world")
        XCTAssertEqual(obj!["swift"] as? String, "rocks🐦")
    }

    func testArray_empty() throws {
        let obj = try JSON.decode(data("[]")) as? [Any]
        XCTAssertNotNil(obj)
        XCTAssertEqual(obj!.count, 0)
    }

    func testArray_multiString() throws {
        let obj = try JSON.decode(data("[\"hello\", \"swift⚡️\"]")) as? [Any]
        XCTAssertNotNil(obj)
        XCTAssertEqual(obj!.count, 2)
        XCTAssertEqual(obj![0] as? String, "hello")
        XCTAssertEqual(obj![1] as? String, "swift⚡\u{FE0F}")
    }

    func testUnicodeString() throws {
        let obj = try JSON.decode(data("[\"Ģ\", \"😢\"]")) as? [Any]
        XCTAssertNotNil(obj)
        XCTAssertEqual(obj!.count, 2)
        XCTAssertEqual(obj![0] as? String, "Ģ")
        XCTAssertEqual(obj![1] as? String, "😢")
    }

    func testError_keyword() {
        try XCTAssertThrowsError(JSON.decode(data("nan"))) {
            let err = $0 as? JSONParsingError
            XCTAssertNotNil(err)
            XCTAssertEqual(err?.kind, .unknownKeyword)
        }
        try XCTAssertThrowsError(JSON.decode(data("inf"))) {
            let err = $0 as? JSONParsingError
            XCTAssertNotNil(err)
            XCTAssertEqual(err?.kind, .unknownKeyword)
        }
    }
    
    func testError_number() {
        try XCTAssertThrowsError(JSON.decode(data("01"))) {
            let err = $0 as? JSONParsingError
            XCTAssertNotNil(err)
            XCTAssertEqual(err?.kind, .invalidNumber)
        }
        try XCTAssertThrowsError(JSON.decode(data("+12"))) {
            let err = $0 as? JSONParsingError
            XCTAssertNotNil(err)
            XCTAssertEqual(err?.kind, .unexpectedToken)
        }
    }
    
    func testError_string() {
        try XCTAssertThrowsError(JSON.decode(data("\"abc"))) {
            let err = $0 as? JSONParsingError
            XCTAssertNotNil(err)
            XCTAssertEqual(err!.kind, .unterminatedString)
        }
        try XCTAssertThrowsError(JSON.decode(data("\"\u{00}\""))) {
            let err = $0 as? JSONParsingError
            XCTAssertNotNil(err)
            XCTAssertEqual(err!.kind, .invalidString)
        }
        try XCTAssertThrowsError(JSON.decode(data("\"\\x\""))) {
            let err = $0 as? JSONParsingError
            XCTAssertNotNil(err)
            XCTAssertEqual(err!.kind, .invalidString)
        }
        try XCTAssertThrowsError(JSON.decode(data("\"\\u20\""))) {
            let err = $0 as? JSONParsingError
            XCTAssertNotNil(err)
            XCTAssertEqual(err!.kind, .invalidString)
        }
    }
    
    func testError_object() {
        try XCTAssertThrowsError(JSON.decode(data("{12: \"foo\"}"))) {
            let err = $0 as? JSONParsingError
            XCTAssertNotNil(err)
            XCTAssertEqual(err!.kind, .expectedString)
        }
        try XCTAssertThrowsError(JSON.decode(data("{\"foo\", 42}"))) {
            let err = $0 as? JSONParsingError
            XCTAssertNotNil(err)
            XCTAssertEqual(err!.kind, .expectedColon)
        }
        try XCTAssertThrowsError(JSON.decode(data("{\"foo\": 42"))) {
            let err = $0 as? JSONParsingError
            XCTAssertNotNil(err)
            XCTAssertEqual(err!.kind, .expectedObjectClose)
        }
    }
    
    func testError_array() {
        try XCTAssertThrowsError(JSON.decode(data("[\"foo\": 42]"))) {
            let err = $0 as? JSONParsingError
            XCTAssertNotNil(err)
            XCTAssertEqual(err!.kind, .expectedArrayClose)
        }
        try XCTAssertThrowsError(JSON.decode(data("[42, ]"))) {
            let err = $0 as? JSONParsingError
            XCTAssertNotNil(err)
            XCTAssertEqual(err!.kind, .unexpectedToken)
        }
    }
    
    func testError_EOF() {
        try XCTAssertThrowsError(JSON.decode(Data())) {
            let err = $0 as? JSONParsingError
            XCTAssertNotNil(err)
            XCTAssertEqual(err!.kind, .expectedValue)
        }
        try XCTAssertThrowsError(JSON.decode(data("[1,2"))) {
            let err = $0 as? JSONParsingError
            XCTAssertNotNil(err)
            XCTAssertEqual(err!.kind, .expectedArrayClose)
        }
        try XCTAssertThrowsError(JSON.decode(data("{\"foo\""))) {
            let err = $0 as? JSONParsingError
            XCTAssertNotNil(err)
            XCTAssertEqual(err!.kind, .expectedColon)
        }
        try XCTAssertThrowsError(JSON.decode(data("{\"foo\":"))) {
            let err = $0 as? JSONParsingError
            XCTAssertNotNil(err)
            XCTAssertEqual(err!.kind, .expectedValue)
        }
        try XCTAssertThrowsError(JSON.decode(data("{\"foo\": 42"))) {
            let err = $0 as? JSONParsingError
            XCTAssertNotNil(err)
            XCTAssertEqual(err!.kind, .expectedObjectClose)
        }
    }
    
    func testError_trailingGabage() {
        try XCTAssertThrowsError(JSON.decode(data("{\"foo\": 42}, 12"))) {
            let err = $0 as? JSONParsingError
            XCTAssertNotNil(err)
            XCTAssertEqual(err!.kind, .expectedEOF)
        }
    }

    func testJSONTestSuite() {
        let path = URL(fileURLWithPath: #file)
            .deletingLastPathComponent()
            .appendingPathComponent("Inputs", isDirectory: true)
            .appendingPathComponent("test_parsing", isDirectory: true)
        let urls = try! FileManager.default
            .contentsOfDirectory(at: path,
                                 includingPropertiesForKeys: nil,
                                 options: [])
        for url in urls where url.pathExtension == "json" {
            let basename = url.lastPathComponent
            let dat = try! Data(contentsOf: url)
            if basename.hasPrefix("y_") {
                XCTAssertNotNil(try JSON.decode(dat),
                                "\(basename) must be accepted")
            } else if basename.hasPrefix("n_") {
                XCTAssertThrowsError(try JSON.decode(dat),
                                     "\(basename) must be rejected")
            } else {
                _ = try? JSON.decode(dat)
            }
        }
    }

    static var allTests : [(String, (JSONParsingTests) -> () throws -> Void)] {
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
            
            ("testError_keyword", testError_keyword),
            ("testError_number", testError_number),
            ("testError_string", testError_string),
            ("testError_object", testError_object),
            ("testError_array", testError_array),
            ("testError_EOF", testError_EOF),
            ("testError_trailingGabage", testError_trailingGabage),
            ("testJSONTestSuite", testJSONTestSuite),
        ]
    }
}
