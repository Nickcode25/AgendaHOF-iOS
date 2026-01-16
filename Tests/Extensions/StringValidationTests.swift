import XCTest
@testable import AgendaHOF

// MARK: - String Validation Tests

/// Testes unitários para String+Extensions
/// Valida email, senha, telefone e outras extensões
final class StringValidationTests: XCTestCase {

    // MARK: - Email Validation Tests

    func testValidEmail() {
        // Valid emails
        XCTAssertTrue("test@example.com".isValidEmail)
        XCTAssertTrue("user.name@domain.co".isValidEmail)
        XCTAssertTrue("test+tag@example.com".isValidEmail)
        XCTAssertTrue("123@test.com".isValidEmail)
    }

    func testInvalidEmail() {
        // Invalid emails
        XCTAssertFalse("".isValidEmail)
        XCTAssertFalse("invalid".isValidEmail)
        XCTAssertFalse("@example.com".isValidEmail)
        XCTAssertFalse("user@".isValidEmail)
        XCTAssertFalse("user @example.com".isValidEmail)
        XCTAssertFalse("user@domain".isValidEmail)
    }

    // MARK: - Password Validation Tests

    func testValidPassword() {
        // Valid passwords (8+ chars, upper, lower, number, special)
        XCTAssertTrue("Test123!".isValidPassword)
        XCTAssertTrue("MyP@ssw0rd".isValidPassword)
        XCTAssertTrue("Str0ng#Pass".isValidPassword)
        XCTAssertTrue("C0mpl3x!Password".isValidPassword)
    }

    func testInvalidPassword() {
        // Too short
        XCTAssertFalse("Test1!".isValidPassword)

        // Missing uppercase
        XCTAssertFalse("test123!".isValidPassword)

        // Missing lowercase
        XCTAssertFalse("TEST123!".isValidPassword)

        // Missing number
        XCTAssertFalse("TestPass!".isValidPassword)

        // Missing special character
        XCTAssertFalse("Test1234".isValidPassword)

        // Empty
        XCTAssertFalse("".isValidPassword)
    }

    func testPasswordStrength() {
        // Weak password (short, minimal requirements)
        XCTAssertLessThan("Test123!".passwordStrength, 0.6)

        // Medium password
        let mediumStrength = "MyP@ssw0rd".passwordStrength
        XCTAssertGreaterThanOrEqual(mediumStrength, 0.6)
        XCTAssertLessThan(mediumStrength, 0.9)

        // Strong password (long, all requirements)
        XCTAssertGreaterThanOrEqual("C0mpl3x!LongPassword".passwordStrength, 0.9)

        // Empty password
        XCTAssertEqual("".passwordStrength, 0.0)
    }

    // MARK: - Phone Validation Tests

    func testValidPhone() {
        // Valid Brazilian phones (10 or 11 digits with valid DDD)
        XCTAssertTrue("11999999999".isValidPhone)  // São Paulo mobile
        XCTAssertTrue("1133334444".isValidPhone)   // São Paulo landline
        XCTAssertTrue("21987654321".isValidPhone)  // Rio mobile
        XCTAssertTrue("8533334444".isValidPhone)   // Fortaleza landline
    }

    func testInvalidPhone() {
        // Too short
        XCTAssertFalse("119999999".isValidPhone)

        // Too long
        XCTAssertFalse("119999999999".isValidPhone)

        // Invalid DDD (< 11)
        XCTAssertFalse("0999999999".isValidPhone)

        // Invalid DDD (> 99)
        XCTAssertFalse("100999999999".isValidPhone)

        // Empty
        XCTAssertFalse("".isValidPhone)
    }

    func testPhoneValidationError() {
        // Empty phone (no error)
        XCTAssertNil("".phoneValidationError)

        // Too short
        XCTAssertEqual("119999999".phoneValidationError, "Telefone incompleto. Digite DDD + número")

        // Too long
        XCTAssertEqual("119999999999".phoneValidationError, "Telefone inválido. Máximo 11 dígitos")

        // Invalid DDD
        XCTAssertEqual("0999999999".phoneValidationError, "DDD inválido")

        // Valid phone (no error)
        XCTAssertNil("11999999999".phoneValidationError)
    }

    // MARK: - String Cleaning Tests

    func testOnlyNumbers() {
        XCTAssertEqual("(11) 99999-9999".onlyNumbers, "11999999999")
        XCTAssertEqual("abc123def456".onlyNumbers, "123456")
        XCTAssertEqual("No numbers here!".onlyNumbers, "")
        XCTAssertEqual("".onlyNumbers, "")
    }

    func testTrimmed() {
        XCTAssertEqual("  test  ".trimmed, "test")
        XCTAssertEqual("\n\ntest\n\n".trimmed, "test")
        XCTAssertEqual("  ".trimmed, "")
        XCTAssertEqual("no-whitespace".trimmed, "no-whitespace")
    }

    // MARK: - Phone Formatting Tests

    func testFormattedPhone() {
        // 11 digits (mobile)
        XCTAssertEqual("11999999999".formattedPhone, "(11) 99999-9999")

        // 10 digits (landline)
        XCTAssertEqual("1133334444".formattedPhone, "(11) 3333-4444")

        // Already formatted (should return as-is)
        XCTAssertEqual("(11) 99999-9999".formattedPhone, "(11) 99999-9999")

        // Invalid length
        XCTAssertEqual("119999".formattedPhone, "119999")

        // Empty
        XCTAssertEqual("".formattedPhone, "")
    }
}
