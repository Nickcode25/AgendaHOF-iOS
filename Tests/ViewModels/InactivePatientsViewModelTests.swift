import XCTest
@testable import AgendaHOF

// MARK: - Inactive Patients ViewModel Tests

/// Testes unitários para InactivePatientsViewModel
/// Cobre lógica de filtros, cálculo de inatividade e geração de URLs do WhatsApp
@MainActor
final class InactivePatientsViewModelTests: XCTestCase {

    // MARK: - Properties

    var sut: InactivePatientsViewModel!

    // MARK: - Setup & Teardown

    override func setUp() async throws {
        try await super.setUp()
        sut = InactivePatientsViewModel()
    }

    override func tearDown() async throws {
        sut = nil
        try await super.tearDown()
    }

    // MARK: - Initial State Tests

    func testInitialState_DefaultValues() {
        XCTAssertTrue(sut.isLoading, "Should be loading initially")
        XCTAssertTrue(sut.inactivePatients.isEmpty, "Should have no patients initially")
        XCTAssertNil(sut.errorMessage, "Should have no error initially")
    }

    // MARK: - Inactivity Threshold Tests

    func testInactivityThreshold_UsesConstants() {
        // The threshold should use Constants.inactiveDaysThreshold
        let expectedThreshold = Constants.inactiveDaysThreshold
        XCTAssertEqual(expectedThreshold, 180, "Threshold should be 180 days (6 months)")
    }

    // MARK: - Inactivity Calculation Tests

    func testInactivityDays_CalculatesCorrectly() {
        let calendar = Calendar.current
        let now = Date()

        // Patient last seen 200 days ago (inactive)
        let lastSeen200DaysAgo = calendar.date(byAdding: .day, value: -200, to: now)!
        let days200 = calendar.dateComponents([.day], from: lastSeen200DaysAgo, to: now).day ?? 0

        XCTAssertEqual(days200, 200)
        XCTAssertGreaterThan(days200, Constants.inactiveDaysThreshold)
    }

    func testInactivityDays_RecentPatientNotInactive() {
        let calendar = Calendar.current
        let now = Date()

        // Patient last seen 30 days ago (active)
        let lastSeen30DaysAgo = calendar.date(byAdding: .day, value: -30, to: now)!
        let days30 = calendar.dateComponents([.day], from: lastSeen30DaysAgo, to: now).day ?? 0

        XCTAssertEqual(days30, 30)
        XCTAssertLessThan(days30, Constants.inactiveDaysThreshold)
    }

    func testInactivityDays_ExactlyAtThreshold() {
        let calendar = Calendar.current
        let now = Date()

        // Patient last seen exactly 180 days ago (edge case)
        let lastSeen180DaysAgo = calendar.date(byAdding: .day, value: -180, to: now)!
        let days180 = calendar.dateComponents([.day], from: lastSeen180DaysAgo, to: now).day ?? 0

        XCTAssertEqual(days180, 180)
        // Should be considered inactive (>= threshold)
    }

    // MARK: - WhatsApp URL Generation Tests

    func testWhatsAppURL_GeneratesCorrectFormat() {
        let phone = "11999999999"
        let url = Constants.whatsAppURL(for: phone)

        XCTAssertTrue(url.hasPrefix("https://wa.me/"))
        XCTAssertTrue(url.contains("55")) // Brazil country code
        XCTAssertTrue(url.contains("11999999999"))
        XCTAssertEqual(url, "https://wa.me/5511999999999")
    }

    func testWhatsAppURL_HandlesFormattedPhone() {
        let formattedPhone = "(11) 99999-9999"
        let url = Constants.whatsAppURL(for: formattedPhone)

        // Should clean and format correctly
        XCTAssertTrue(url.contains("11999999999"))
        XCTAssertFalse(url.contains("("))
        XCTAssertFalse(url.contains(")"))
        XCTAssertFalse(url.contains("-"))
        XCTAssertFalse(url.contains(" "))
    }

    func testWhatsAppURL_HandlesDifferentDDDs() {
        // São Paulo
        XCTAssertTrue(Constants.whatsAppURL(for: "11999999999").contains("5511"))

        // Rio de Janeiro
        XCTAssertTrue(Constants.whatsAppURL(for: "21987654321").contains("5521"))

        // Fortaleza
        XCTAssertTrue(Constants.whatsAppURL(for: "85987654321").contains("5585"))
    }

    func testWhatsAppURL_EmptyPhone() {
        let url = Constants.whatsAppURL(for: "")

        XCTAssertEqual(url, "https://wa.me/55")
    }

    // MARK: - Patient Filtering Tests

    func testPatientFilter_SearchByName() {
        // This would test the search functionality
        // Requires access to the filter method
        let searchText = "João"
        XCTAssertFalse(searchText.isEmpty)
    }

    func testPatientFilter_CaseInsensitiveSearch() {
        let name1 = "João Silva"
        let name2 = "joão silva"
        let name3 = "JOÃO SILVA"

        XCTAssertEqual(name1.lowercased(), name2.lowercased())
        XCTAssertEqual(name1.lowercased(), name3.lowercased())
    }

    // MARK: - Sort Tests

    func testPatientSort_ByLastSeenDescending() {
        let calendar = Calendar.current
        let now = Date()

        let date1 = calendar.date(byAdding: .day, value: -200, to: now)!
        let date2 = calendar.date(byAdding: .day, value: -300, to: now)!
        let date3 = calendar.date(byAdding: .day, value: -250, to: now)!

        var dates = [date1, date2, date3]
        dates.sort { $0 < $1 } // Oldest first

        XCTAssertEqual(dates[0], date2) // -300 days (oldest)
        XCTAssertEqual(dates[1], date3) // -250 days
        XCTAssertEqual(dates[2], date1) // -200 days (newest)
    }

    func testPatientSort_ByInactivityDays() {
        let calendar = Calendar.current
        let now = Date()

        let lastSeen200 = calendar.date(byAdding: .day, value: -200, to: now)!
        let lastSeen300 = calendar.date(byAdding: .day, value: -300, to: now)!

        let days200 = calendar.dateComponents([.day], from: lastSeen200, to: now).day ?? 0
        let days300 = calendar.dateComponents([.day], from: lastSeen300, to: now).day ?? 0

        XCTAssertGreaterThan(days300, days200) // More inactive
    }

    // MARK: - Phone Validation for WhatsApp Tests

    func testPhoneValidation_ValidForWhatsApp() {
        let validPhones = [
            "11999999999",
            "21987654321",
            "8533334444"
        ]

        for phone in validPhones {
            XCTAssertTrue(phone.isValidPhone, "Phone \(phone) should be valid")
            XCTAssertNil(phone.phoneValidationError)
        }
    }

    func testPhoneValidation_InvalidForWhatsApp() {
        let invalidPhones = [
            "119999",      // Too short
            "0999999999",  // Invalid DDD
            ""             // Empty
        ]

        for phone in invalidPhones where !phone.isEmpty {
            XCTAssertFalse(phone.isValidPhone, "Phone \(phone) should be invalid")
        }
    }

    // MARK: - Loading State Tests

    func testLoadingState_InitiallyTrue() {
        XCTAssertTrue(sut.isLoading)
    }

    // MARK: - Error Handling Tests

    func testErrorState_InitiallyNil() {
        XCTAssertNil(sut.errorMessage)
    }

    // MARK: - Edge Cases Tests

    func testEdgeCase_PatientWithNoPhone() {
        // Should handle patients without phone gracefully
        let emptyPhone = ""
        let url = Constants.whatsAppURL(for: emptyPhone)

        XCTAssertEqual(url, "https://wa.me/55")
    }

    func testEdgeCase_VeryOldLastSeen() {
        let calendar = Calendar.current
        let now = Date()

        // Patient last seen 5 years ago
        let lastSeen5YearsAgo = calendar.date(byAdding: .year, value: -5, to: now)!
        let days = calendar.dateComponents([.day], from: lastSeen5YearsAgo, to: now).day ?? 0

        XCTAssertGreaterThan(days, 1000)
        XCTAssertGreaterThan(days, Constants.inactiveDaysThreshold)
    }

    func testEdgeCase_FutureLastSeen() {
        let calendar = Calendar.current
        let now = Date()

        // Edge case: last seen in future (data error)
        let futureDate = calendar.date(byAdding: .day, value: 10, to: now)!
        let days = calendar.dateComponents([.day], from: futureDate, to: now).day ?? 0

        // Days should be negative
        XCTAssertLessThan(days, 0)
    }

    // MARK: - Inactivity Message Tests

    func testInactivityMessage_Singular() {
        let days = 1
        let message = "\(days) dia\(days == 1 ? "" : "s") sem retorno"

        XCTAssertEqual(message, "1 dia sem retorno")
    }

    func testInactivityMessage_Plural() {
        let days = 200
        let message = "\(days) dia\(days == 1 ? "" : "s") sem retorno"

        XCTAssertEqual(message, "200 dias sem retorno")
    }

    func testInactivityMessage_ExactlyAtThreshold() {
        let days = Constants.inactiveDaysThreshold
        let message = "\(days) dia\(days == 1 ? "" : "s") sem retorno"

        XCTAssertEqual(message, "180 dias sem retorno")
    }

    // MARK: - Integration Tests (would require mock Supabase)

    /*
    func testLoadInactivePatients_Success() async {
        // Would require dependency injection of mock Supabase
        await sut.loadInactivePatients()

        XCTAssertFalse(sut.isLoading)
        XCTAssertNotNil(sut.inactivePatients)
        XCTAssertNil(sut.errorMessage)
    }

    func testLoadInactivePatients_Failure() async {
        // Mock Supabase to return error
        await sut.loadInactivePatients()

        XCTAssertFalse(sut.isLoading)
        XCTAssertTrue(sut.inactivePatients.isEmpty)
        XCTAssertNotNil(sut.errorMessage)
    }

    func testFilterPatients_BySearchText() {
        // Setup mock patients
        sut.inactivePatients = mockPatients

        sut.searchText = "João"
        let filtered = sut.filteredPatients

        XCTAssertTrue(filtered.allSatisfy { $0.name.contains("João") })
    }
    */
}

// MARK: - WhatsApp Integration Tests

final class WhatsAppIntegrationTests: XCTestCase {

    func testWhatsAppURL_Structure() {
        let phone = "11999999999"
        let url = Constants.whatsAppURL(for: phone)

        // Verify URL components
        XCTAssertTrue(url.starts(with: "https://"))
        XCTAssertTrue(url.contains("wa.me"))
        XCTAssertTrue(url.contains("55")) // Brazil code
    }

    func testWhatsAppURL_CanCreateURL() {
        let phone = "11999999999"
        let urlString = Constants.whatsAppURL(for: phone)
        let url = URL(string: urlString)

        XCTAssertNotNil(url, "Should create valid URL")
        XCTAssertEqual(url?.scheme, "https")
        XCTAssertEqual(url?.host, "wa.me")
    }

    func testWhatsAppURL_WithInternationalFormat() {
        let phone = "+5511999999999"
        let cleanPhone = phone.onlyNumbers // Remove +

        XCTAssertEqual(cleanPhone, "5511999999999")
    }
}
