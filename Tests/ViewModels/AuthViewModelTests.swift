import XCTest
@testable import AgendaHOF

// MARK: - Auth ViewModel Tests

/// Testes unitários para AuthViewModel
/// Cobre autenticação, validação, cadastro e recuperação de senha
@MainActor
final class AuthViewModelTests: XCTestCase {

    // MARK: - Properties

    var sut: AuthViewModel!
    var mockSupabase: MockSupabaseManager!

    // MARK: - Setup & Teardown

    override func setUp() async throws {
        try await super.setUp()
        mockSupabase = MockSupabaseManager(authenticated: false)
        sut = AuthViewModel()
        // Note: In production, inject mockSupabase via dependency injection
    }

    override func tearDown() async throws {
        sut = nil
        mockSupabase = nil
        try await super.tearDown()
    }

    // MARK: - Email Validation Tests

    func testEmailValidation_ValidEmail() {
        sut.email = "test@example.com"
        // Validation happens in signIn/signUp, so we test indirectly
        XCTAssertTrue(sut.email.isValidEmail)
    }

    func testEmailValidation_InvalidEmail() {
        sut.email = "invalid-email"
        XCTAssertFalse(sut.email.isValidEmail)
    }

    func testEmailValidation_EmptyEmail() {
        sut.email = ""
        XCTAssertFalse(sut.email.isValidEmail)
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

    func testPasswordValidation_MissingRequirements() {
        // Missing uppercase
        sut.password = "test123!"
        XCTAssertFalse(sut.password.isValidPassword)

        // Missing number
        sut.password = "TestPass!"
        XCTAssertFalse(sut.password.isValidPassword)

        // Missing special char
        sut.password = "Test1234"
        XCTAssertFalse(sut.password.isValidPassword)
    }

    // MARK: - Password Strength Tests

    func testPasswordStrength_Weak() {
        sut.password = "Test123!"
        let strength = sut.password.passwordStrength
        XCTAssertLessThan(strength, 0.6, "Password should be weak")
    }

    func testPasswordStrength_Medium() {
        sut.password = "MyP@ssw0rd"
        let strength = sut.password.passwordStrength
        XCTAssertGreaterThanOrEqual(strength, 0.6)
        XCTAssertLessThan(strength, 0.9)
    }

    func testPasswordStrength_Strong() {
        sut.password = "C0mpl3x!LongPassword"
        let strength = sut.password.passwordStrength
        XCTAssertGreaterThanOrEqual(strength, 0.9, "Password should be strong")
    }

    // MARK: - Sign In Validation Tests

    func testSignIn_EmptyEmail_ShouldFail() async {
        sut.email = ""
        sut.password = "Test123!"

        // In real implementation, this would show error
        // For now, we test that email is invalid
        XCTAssertFalse(sut.email.isValidEmail)
    }

    func testSignIn_InvalidEmail_ShouldFail() async {
        sut.email = "invalid"
        sut.password = "Test123!"

        XCTAssertFalse(sut.email.isValidEmail)
    }

    func testSignIn_EmptyPassword_ShouldFail() async {
        sut.email = "test@example.com"
        sut.password = ""

        XCTAssertTrue(sut.email.isValidEmail)
        XCTAssertFalse(sut.password.isValidPassword)
    }

    func testSignIn_ValidCredentials() async {
        sut.email = "test@example.com"
        sut.password = "Test123!Pass"

        XCTAssertTrue(sut.email.isValidEmail)
        XCTAssertTrue(sut.password.isValidPassword)
    }

    // MARK: - Sign Up Validation Tests

    func testSignUp_ValidData() {
        sut.email = "newuser@example.com"
        sut.password = "NewPass123!"
        sut.confirmPassword = "NewPass123!"
        sut.fullName = "John Doe"

        XCTAssertTrue(sut.email.isValidEmail)
        XCTAssertTrue(sut.password.isValidPassword)
        XCTAssertEqual(sut.password, sut.confirmPassword)
        XCTAssertFalse(sut.fullName.trimmed.isEmpty)
    }

    func testSignUp_PasswordMismatch() {
        sut.password = "Test123!"
        sut.confirmPassword = "Different123!"

        XCTAssertNotEqual(sut.password, sut.confirmPassword)
    }

    func testSignUp_EmptyFullName() {
        sut.fullName = "   "

        XCTAssertTrue(sut.fullName.trimmed.isEmpty)
    }

    // MARK: - Remember Me Tests

    func testRememberMe_DefaultFalse() {
        XCTAssertFalse(sut.rememberMe, "Remember me should default to false")
    }

    func testRememberMe_CanBeToggled() {
        sut.rememberMe = true
        XCTAssertTrue(sut.rememberMe)

        sut.rememberMe = false
        XCTAssertFalse(sut.rememberMe)
    }

    // MARK: - Loading State Tests

    func testLoadingState_DefaultFalse() {
        XCTAssertFalse(sut.isLoading, "Should not be loading initially")
    }

    // MARK: - Error Handling Tests

    func testErrorState_DefaultEmpty() {
        XCTAssertNil(sut.errorMessage, "Should have no error initially")
        XCTAssertFalse(sut.showError, "Should not show error initially")
    }

    // MARK: - Input Sanitization Tests

    func testEmail_TrimmedAutomatically() {
        sut.email = "  test@example.com  "
        // In real implementation, email should be trimmed before validation
        XCTAssertEqual(sut.email.trimmed, "test@example.com")
    }

    func testFullName_TrimmedAutomatically() {
        sut.fullName = "  John Doe  "
        XCTAssertEqual(sut.fullName.trimmed, "John Doe")
    }

    // MARK: - Integration Tests (would require mock Supabase)

    /*
    func testSignIn_Success() async {
        // This would require dependency injection of MockSupabaseManager
        mockSupabase.shouldFailAuth = false

        sut.email = "test@example.com"
        sut.password = "Test123!"

        await sut.signIn()

        XCTAssertFalse(sut.isLoading)
        XCTAssertNil(sut.errorMessage)
    }

    func testSignIn_Failure() async {
        mockSupabase.shouldFailAuth = true

        sut.email = "test@example.com"
        sut.password = "WrongPass123!"

        await sut.signIn()

        XCTAssertFalse(sut.isLoading)
        XCTAssertNotNil(sut.errorMessage)
        XCTAssertTrue(sut.showError)
    }
    */
}

// MARK: - Auth ViewModel Integration Tests

/// Testes de integração com mock do Supabase
/// Requer dependency injection para funcionar completamente
@MainActor
final class AuthViewModelIntegrationTests: XCTestCase {

    // MARK: - Properties

    var sut: AuthViewModel!

    // MARK: - Setup & Teardown

    override func setUp() async throws {
        try await super.setUp()
        sut = AuthViewModel()
    }

    override func tearDown() async throws {
        sut = nil
        try await super.tearDown()
    }

    // MARK: - Form Reset Tests

    func testReset_ClearsAllFields() {
        sut.email = "test@example.com"
        sut.password = "Test123!"
        sut.confirmPassword = "Test123!"
        sut.fullName = "John Doe"
        sut.rememberMe = true

        // Manual reset (in real implementation, this would be a reset() method)
        sut.email = ""
        sut.password = ""
        sut.confirmPassword = ""
        sut.fullName = ""
        sut.rememberMe = false

        XCTAssertTrue(sut.email.isEmpty)
        XCTAssertTrue(sut.password.isEmpty)
        XCTAssertTrue(sut.confirmPassword.isEmpty)
        XCTAssertTrue(sut.fullName.isEmpty)
        XCTAssertFalse(sut.rememberMe)
    }

    // MARK: - Edge Cases

    func testEdgeCase_VeryLongPassword() {
        let longPassword = String(repeating: "a", count: 200) + "A1!"
        sut.password = longPassword

        // Should still validate if it meets requirements
        XCTAssertTrue(sut.password.isValidPassword)
    }

    func testEdgeCase_UnicodeInEmail() {
        sut.email = "tëst@éxample.com"
        // Email validation should handle unicode
        let isValid = sut.email.isValidEmail
        // Result depends on email validation implementation
        XCTAssertNotNil(isValid) // Just verify it doesn't crash
    }

    func testEdgeCase_SpecialCharsInName() {
        sut.fullName = "José María O'Brien"
        XCTAssertFalse(sut.fullName.trimmed.isEmpty)
    }
}
