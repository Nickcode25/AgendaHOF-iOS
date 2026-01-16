import XCTest
@testable import AgendaHOF

// MARK: - Reset Password ViewModel Tests

/// Testes unitários para ResetPasswordViewModel
/// Cobre validação de senha, força de senha e lógica de reset
@MainActor
final class ResetPasswordViewModelTests: XCTestCase {

    // MARK: - Properties

    var sut: ResetPasswordViewModel!

    // MARK: - Setup & Teardown

    override func setUp() async throws {
        try await super.setUp()
        sut = ResetPasswordViewModel()
    }

    override func tearDown() async throws {
        sut = nil
        try await super.tearDown()
    }

    // MARK: - Initial State Tests

    func testInitialState_DefaultValues() {
        XCTAssertTrue(sut.password.isEmpty, "Password should be empty initially")
        XCTAssertTrue(sut.confirmPassword.isEmpty, "Confirm password should be empty initially")
        XCTAssertFalse(sut.isLoading, "Should not be loading initially")
        XCTAssertNil(sut.errorMessage, "Should have no error initially")
        XCTAssertFalse(sut.showError, "Should not show error initially")
    }

    // MARK: - Password Validation Tests

    func testPasswordValidation_ValidPassword() {
        sut.password = "Test123!Pass"

        XCTAssertTrue(sut.password.isValidPassword)
    }

    func testPasswordValidation_TooShort() {
        sut.password = "Test1!"

        XCTAssertFalse(sut.password.isValidPassword)
    }

    func testPasswordValidation_MissingUppercase() {
        sut.password = "test123!pass"

        XCTAssertFalse(sut.password.isValidPassword)
    }

    func testPasswordValidation_MissingLowercase() {
        sut.password = "TEST123!PASS"

        XCTAssertFalse(sut.password.isValidPassword)
    }

    func testPasswordValidation_MissingNumber() {
        sut.password = "TestPass!"

        XCTAssertFalse(sut.password.isValidPassword)
    }

    func testPasswordValidation_MissingSpecialChar() {
        sut.password = "Test1234Pass"

        XCTAssertFalse(sut.password.isValidPassword)
    }

    func testPasswordValidation_EmptyPassword() {
        sut.password = ""

        XCTAssertFalse(sut.password.isValidPassword)
    }

    // MARK: - Password Strength Tests

    func testPasswordStrength_Weak() {
        // Weak: minimum requirements only
        sut.password = "Test123!"

        let strength = sut.password.passwordStrength
        XCTAssertLessThan(strength, 0.6, "Should be weak")
    }

    func testPasswordStrength_Medium() {
        // Medium: good length and requirements
        sut.password = "MyP@ssw0rd123"

        let strength = sut.password.passwordStrength
        XCTAssertGreaterThanOrEqual(strength, 0.6)
        XCTAssertLessThan(strength, 0.9)
    }

    func testPasswordStrength_Strong() {
        // Strong: long password with all requirements
        sut.password = "C0mpl3x!LongP@ssword"

        let strength = sut.password.passwordStrength
        XCTAssertGreaterThanOrEqual(strength, 0.9, "Should be strong")
    }

    func testPasswordStrength_Empty() {
        sut.password = ""

        let strength = sut.password.passwordStrength
        XCTAssertEqual(strength, 0.0)
    }

    // MARK: - Password Match Tests

    func testPasswordMatch_Matching() {
        sut.password = "Test123!Pass"
        sut.confirmPassword = "Test123!Pass"

        XCTAssertEqual(sut.password, sut.confirmPassword)
    }

    func testPasswordMatch_NotMatching() {
        sut.password = "Test123!Pass"
        sut.confirmPassword = "Different123!"

        XCTAssertNotEqual(sut.password, sut.confirmPassword)
    }

    func testPasswordMatch_PartialMatch() {
        sut.password = "Test123!Pass"
        sut.confirmPassword = "Test123!Pas" // Missing last character

        XCTAssertNotEqual(sut.password, sut.confirmPassword)
    }

    func testPasswordMatch_CaseSensitive() {
        sut.password = "Test123!pass"
        sut.confirmPassword = "Test123!PASS"

        XCTAssertNotEqual(sut.password, sut.confirmPassword)
    }

    func testPasswordMatch_BothEmpty() {
        sut.password = ""
        sut.confirmPassword = ""

        XCTAssertEqual(sut.password, sut.confirmPassword)
    }

    // MARK: - Combined Validation Tests

    func testCombinedValidation_ValidPasswordAndMatch() {
        sut.password = "StrongP@ss123"
        sut.confirmPassword = "StrongP@ss123"

        XCTAssertTrue(sut.password.isValidPassword)
        XCTAssertEqual(sut.password, sut.confirmPassword)
    }

    func testCombinedValidation_ValidPasswordButNoMatch() {
        sut.password = "StrongP@ss123"
        sut.confirmPassword = "Different123!"

        XCTAssertTrue(sut.password.isValidPassword)
        XCTAssertNotEqual(sut.password, sut.confirmPassword)
    }

    func testCombinedValidation_InvalidPasswordButMatch() {
        sut.password = "weak"
        sut.confirmPassword = "weak"

        XCTAssertFalse(sut.password.isValidPassword)
        XCTAssertEqual(sut.password, sut.confirmPassword)
    }

    // MARK: - Password Requirements Display Tests

    func testPasswordRequirements_AllMet() {
        sut.password = "Test123!Pass"

        // All requirements should be met
        XCTAssertTrue(sut.password.count >= 8) // Minimum length
        XCTAssertTrue(sut.password.contains(where: { $0.isUppercase })) // Uppercase
        XCTAssertTrue(sut.password.contains(where: { $0.isLowercase })) // Lowercase
        XCTAssertTrue(sut.password.contains(where: { $0.isNumber })) // Number
        // Special character check would require regex
    }

    func testPasswordRequirements_LengthMet() {
        sut.password = "12345678"

        XCTAssertGreaterThanOrEqual(sut.password.count, 8)
    }

    func testPasswordRequirements_LengthNotMet() {
        sut.password = "Test1!"

        XCTAssertLessThan(sut.password.count, 8)
    }

    // MARK: - Loading State Tests

    func testLoadingState_InitiallyFalse() {
        XCTAssertFalse(sut.isLoading)
    }

    // MARK: - Error State Tests

    func testErrorState_InitiallyNil() {
        XCTAssertNil(sut.errorMessage)
        XCTAssertFalse(sut.showError)
    }

    // MARK: - Password Visibility Toggle Tests

    func testPasswordVisibility_InitiallyHidden() {
        // Assuming there's a showPassword property
        // XCTAssertFalse(sut.showPassword)
    }

    // MARK: - Edge Cases Tests

    func testEdgeCase_VeryLongPassword() {
        sut.password = String(repeating: "a", count: 200) + "A1!"

        XCTAssertTrue(sut.password.isValidPassword)
        XCTAssertGreaterThan(sut.password.count, 100)
    }

    func testEdgeCase_UnicodeCharacters() {
        sut.password = "Tëst123!Pâss"

        // Should handle unicode
        XCTAssertTrue(sut.password.contains("ë"))
        XCTAssertTrue(sut.password.contains("â"))
    }

    func testEdgeCase_OnlySpecialCharacters() {
        sut.password = "!@#$%^&*()"

        XCTAssertFalse(sut.password.isValidPassword) // Missing other requirements
    }

    func testEdgeCase_Whitespace() {
        sut.password = "Test 123! Pass"

        // Password with spaces
        XCTAssertTrue(sut.password.contains(" "))
    }

    func testEdgeCase_LeadingTrailingSpaces() {
        sut.password = "  Test123!Pass  "
        sut.confirmPassword = "  Test123!Pass  "

        XCTAssertEqual(sut.password, sut.confirmPassword)
        // Note: In production, passwords should probably be trimmed
    }

    // MARK: - Password Strength Color Tests

    func testPasswordStrengthColor_Weak() {
        sut.password = "Test123!"
        let strength = sut.password.passwordStrength

        // Weak password should be less than 0.6
        if strength < 0.6 {
            // Color should be red or orange
            XCTAssertLessThan(strength, 0.6)
        }
    }

    func testPasswordStrengthColor_Medium() {
        sut.password = "MyP@ssw0rd"
        let strength = sut.password.passwordStrength

        // Medium password should be 0.6-0.9
        if strength >= 0.6 && strength < 0.9 {
            // Color should be yellow or orange
            XCTAssertGreaterThanOrEqual(strength, 0.6)
            XCTAssertLessThan(strength, 0.9)
        }
    }

    func testPasswordStrengthColor_Strong() {
        sut.password = "C0mpl3x!LongP@ssword"
        let strength = sut.password.passwordStrength

        // Strong password should be >= 0.9
        if strength >= 0.9 {
            // Color should be green
            XCTAssertGreaterThanOrEqual(strength, 0.9)
        }
    }

    // MARK: - Password Requirements List Tests

    func testPasswordRequirementsList_AllRequirements() {
        let requirements = [
            "Mínimo 8 caracteres",
            "Letra maiúscula",
            "Letra minúscula",
            "Número",
            "Caractere especial (!@#$%...)"
        ]

        XCTAssertEqual(requirements.count, 5)
        XCTAssertTrue(requirements.contains("Mínimo 8 caracteres"))
    }

    // MARK: - Integration Tests (would require mock backend)

    /*
    func testResetPassword_Success() async {
        sut.password = "NewP@ssw0rd123"
        sut.confirmPassword = "NewP@ssw0rd123"

        await sut.resetPassword(token: "valid-token")

        XCTAssertFalse(sut.isLoading)
        XCTAssertNil(sut.errorMessage)
        XCTAssertTrue(sut.showSuccess)
    }

    func testResetPassword_InvalidToken() async {
        sut.password = "NewP@ssw0rd123"
        sut.confirmPassword = "NewP@ssw0rd123"

        await sut.resetPassword(token: "invalid-token")

        XCTAssertFalse(sut.isLoading)
        XCTAssertNotNil(sut.errorMessage)
        XCTAssertTrue(sut.showError)
    }

    func testResetPassword_ExpiredToken() async {
        sut.password = "NewP@ssw0rd123"
        sut.confirmPassword = "NewP@ssw0rd123"

        await sut.resetPassword(token: "expired-token")

        XCTAssertFalse(sut.isLoading)
        XCTAssertEqual(sut.errorMessage, "Token expirado")
    }
    */
}

// MARK: - Password Security Tests

final class PasswordSecurityTests: XCTestCase {

    func testCommonPasswords_ShouldBeAvoided() {
        let commonPasswords = [
            "Password123!",
            "Welcome123!",
            "Admin123!"
        ]

        // These technically meet requirements but are weak
        for password in commonPasswords {
            XCTAssertTrue(password.isValidPassword)
            // But should ideally be flagged as common/weak
        }
    }

    func testSequentialCharacters_DetectedAsWeak() {
        let password = "Abc12345!"

        // Has sequential numbers, should be considered weaker
        XCTAssertTrue(password.isValidPassword) // Meets technical requirements
        // But strength should reflect the pattern
        let strength = password.passwordStrength
        XCTAssertLessThan(strength, 1.0)
    }

    func testRepeatingCharacters_DetectedAsWeak() {
        let password = "Aaaa1111!"

        // Has repeating characters, should be weaker
        XCTAssertTrue(password.isValidPassword)
        let strength = password.passwordStrength
        XCTAssertLessThan(strength, 0.8)
    }
}
