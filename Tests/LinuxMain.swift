import XCTest
@testable import JSONTests

XCTMain([
     testCase(JSONParsingTests.allTests),
     testCase(JSONPrintingTests.allTests),
])
