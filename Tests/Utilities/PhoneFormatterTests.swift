import XCTest
@testable import AgendaHOF // Ajuste o nome do módulo se necessário

final class PhoneFormatterTests: XCTestCase {

    func testNormalizeFormattedMobile() {
        let input = "(31) 98351-6016"
        let expected = "+5531983516016"
        XCTAssertEqual(PhoneFormatter.normalizeBR(input), expected)
    }

    func testNormalizeWithDDI() {
        let input = "+55 31 98351-6016"
        let expected = "+5531983516016"
        XCTAssertEqual(PhoneFormatter.normalizeBR(input), expected)
    }

    func testNormalizeCleanMobile() {
        let input = "31983516016"
        let expected = "+5531983516016"
        XCTAssertEqual(PhoneFormatter.normalizeBR(input), expected)
    }

    func testNormalizeFixedLine() {
        let input = "(31) 3333-4444"
        let expected = "+553133334444" // 10 dígitos + 55 = 12
        XCTAssertEqual(PhoneFormatter.normalizeBR(input), expected)
    }
    
    func testInvalidShortNumber() {
        let input = "996372874" // Sem DDD
        XCTAssertNil(PhoneFormatter.normalizeBR(input))
    }

    func testInvalidEmpty() {
        let input = ""
        XCTAssertNil(PhoneFormatter.normalizeBR(input))
    }

    func testInvalidLetters() {
        let input = "abc"
        XCTAssertNil(PhoneFormatter.normalizeBR(input))
    }
    
    func testInvalidTooLong() {
        let input = "55319999999999" // Muito longo
        XCTAssertNil(PhoneFormatter.normalizeBR(input))
    }
}
