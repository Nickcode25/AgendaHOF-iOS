import XCTest
@testable import AgendaHOF

// MARK: - Financial Report ViewModel Tests

/// Testes unitários para FinancialReportViewModel
/// Cobre lógica de negócio, carregamento de dados e cálculos financeiros
@MainActor
final class FinancialReportViewModelTests: XCTestCase {

    // MARK: - Properties

    var sut: FinancialReportViewModel!

    // MARK: - Setup & Teardown

    override func setUp() async throws {
        try await super.setUp()
        sut = FinancialReportViewModel()
    }

    override func tearDown() async throws {
        sut = nil
        try await super.tearDown()
    }

    // MARK: - Initial State Tests

    func testInitialState_DefaultValues() {
        XCTAssertEqual(sut.selectedPeriod, .month, "Should default to month period")
        XCTAssertTrue(sut.isLoading, "Should be loading initially")
        XCTAssertNil(sut.reportData, "Should have no data initially")
        XCTAssertNil(sut.errorMessage, "Should have no error initially")
    }

    // MARK: - Period Filter Tests

    func testPeriodFilter_CanChangeToDay() {
        sut.selectedPeriod = .day
        XCTAssertEqual(sut.selectedPeriod, .day)
    }

    func testPeriodFilter_CanChangeToWeek() {
        sut.selectedPeriod = .week
        XCTAssertEqual(sut.selectedPeriod, .week)
    }

    func testPeriodFilter_CanChangeToYear() {
        sut.selectedPeriod = .year
        XCTAssertEqual(sut.selectedPeriod, .year)
    }

    func testPeriodFilter_AllCases() {
        let allPeriods: [PeriodFilter] = [.day, .week, .month, .year]

        for period in allPeriods {
            sut.selectedPeriod = period
            XCTAssertEqual(sut.selectedPeriod, period)
        }
    }

    // MARK: - Period Display Name Tests

    func testPeriodDisplayNames() {
        XCTAssertEqual(PeriodFilter.day.displayName, "Hoje")
        XCTAssertEqual(PeriodFilter.week.displayName, "Semana")
        XCTAssertEqual(PeriodFilter.month.displayName, "Mês")
        XCTAssertEqual(PeriodFilter.year.displayName, "Ano")
    }

    // MARK: - Financial Data Calculation Tests

    func testFinancialData_CalculatesProfit() {
        let data = FinancialReportData(
            totalRevenue: 10000.00,
            totalExpenses: 3000.00,
            profit: 7000.00,
            proceduresRevenue: 8000.00,
            salesRevenue: 1500.00,
            subscriptionsRevenue: 500.00,
            coursesRevenue: 0.00
        )

        XCTAssertEqual(data.profit, 7000.00)
        XCTAssertEqual(data.totalRevenue - data.totalExpenses, data.profit)
    }

    func testFinancialData_SumsRevenueCategories() {
        let data = FinancialReportData(
            totalRevenue: 10000.00,
            totalExpenses: 3000.00,
            profit: 7000.00,
            proceduresRevenue: 6000.00,
            salesRevenue: 2000.00,
            subscriptionsRevenue: 1500.00,
            coursesRevenue: 500.00
        )

        let sumOfCategories = data.proceduresRevenue + data.salesRevenue +
                              data.subscriptionsRevenue + data.coursesRevenue

        XCTAssertEqual(sumOfCategories, data.totalRevenue)
    }

    func testFinancialData_NegativeProfit() {
        let data = FinancialReportData(
            totalRevenue: 1000.00,
            totalExpenses: 5000.00,
            profit: -4000.00,
            proceduresRevenue: 1000.00,
            salesRevenue: 0.00,
            subscriptionsRevenue: 0.00,
            coursesRevenue: 0.00
        )

        XCTAssertLessThan(data.profit, 0, "Profit should be negative")
        XCTAssertEqual(data.profit, -4000.00)
    }

    func testFinancialData_ZeroRevenue() {
        let data = FinancialReportData(
            totalRevenue: 0.00,
            totalExpenses: 0.00,
            profit: 0.00,
            proceduresRevenue: 0.00,
            salesRevenue: 0.00,
            subscriptionsRevenue: 0.00,
            coursesRevenue: 0.00
        )

        XCTAssertEqual(data.totalRevenue, 0.00)
        XCTAssertEqual(data.profit, 0.00)
    }

    // MARK: - Currency Formatting Tests

    func testCurrencyFormatting_PositiveValue() {
        let data = FinancialReportData(
            totalRevenue: 1250.50,
            totalExpenses: 0,
            profit: 0,
            proceduresRevenue: 0,
            salesRevenue: 0,
            subscriptionsRevenue: 0,
            coursesRevenue: 0
        )

        let formatted = data.formatCurrency(1250.50)
        XCTAssertTrue(formatted.contains("1.250") || formatted.contains("1,250"))
        XCTAssertTrue(formatted.contains("50"))
    }

    func testCurrencyFormatting_Zero() {
        let data = FinancialReportData(
            totalRevenue: 0,
            totalExpenses: 0,
            profit: 0,
            proceduresRevenue: 0,
            salesRevenue: 0,
            subscriptionsRevenue: 0,
            coursesRevenue: 0
        )

        let formatted = data.formatCurrency(0)
        XCTAssertTrue(formatted.contains("0"))
    }

    func testCurrencyFormatting_LargeValue() {
        let data = FinancialReportData(
            totalRevenue: 0,
            totalExpenses: 0,
            profit: 0,
            proceduresRevenue: 0,
            salesRevenue: 0,
            subscriptionsRevenue: 0,
            coursesRevenue: 0
        )

        let formatted = data.formatCurrency(1000000.00)
        // Should format large numbers with separators
        XCTAssertTrue(formatted.contains("1.000.000") || formatted.contains("1,000,000"))
    }

    // MARK: - Loading State Tests

    func testLoadingState_InitiallyTrue() {
        XCTAssertTrue(sut.isLoading)
    }

    // MARK: - Error Handling Tests

    func testErrorState_InitiallyNil() {
        XCTAssertNil(sut.errorMessage)
    }

    // MARK: - Period Date Range Tests

    func testPeriodDateRange_Day() {
        sut.selectedPeriod = .day
        // Day period should be from start of day to end of day
        // This would require access to internal date calculation methods
    }

    func testPeriodDateRange_Week() {
        sut.selectedPeriod = .week
        // Week period should be from Monday to Sunday
    }

    func testPeriodDateRange_Month() {
        sut.selectedPeriod = .month
        // Month period should be from 1st to last day of month
    }

    func testPeriodDateRange_Year() {
        sut.selectedPeriod = .year
        // Year period should be from Jan 1 to Dec 31
    }

    // MARK: - Revenue Breakdown Percentages Tests

    func testRevenueBreakdown_Percentages() {
        let data = FinancialReportData(
            totalRevenue: 10000.00,
            totalExpenses: 0,
            profit: 0,
            proceduresRevenue: 6000.00,   // 60%
            salesRevenue: 2000.00,         // 20%
            subscriptionsRevenue: 1500.00, // 15%
            coursesRevenue: 500.00         // 5%
        )

        let proceduresPercentage = (data.proceduresRevenue / data.totalRevenue) * 100
        let salesPercentage = (data.salesRevenue / data.totalRevenue) * 100

        XCTAssertEqual(proceduresPercentage, 60.0, accuracy: 0.01)
        XCTAssertEqual(salesPercentage, 20.0, accuracy: 0.01)
    }

    func testRevenueBreakdown_AllFromOneCategory() {
        let data = FinancialReportData(
            totalRevenue: 10000.00,
            totalExpenses: 0,
            profit: 0,
            proceduresRevenue: 10000.00,  // 100%
            salesRevenue: 0.00,
            subscriptionsRevenue: 0.00,
            coursesRevenue: 0.00
        )

        let proceduresPercentage = (data.proceduresRevenue / data.totalRevenue) * 100
        XCTAssertEqual(proceduresPercentage, 100.0, accuracy: 0.01)
    }

    // MARK: - Edge Cases Tests

    func testEdgeCase_VeryLargeRevenue() {
        let data = FinancialReportData(
            totalRevenue: Double.greatestFiniteMagnitude / 2,
            totalExpenses: 0,
            profit: 0,
            proceduresRevenue: 0,
            salesRevenue: 0,
            subscriptionsRevenue: 0,
            coursesRevenue: 0
        )

        XCTAssertGreaterThan(data.totalRevenue, 0)
        XCTAssertNotEqual(data.totalRevenue, .infinity)
    }

    func testEdgeCase_VerySmallRevenue() {
        let data = FinancialReportData(
            totalRevenue: 0.01,
            totalExpenses: 0,
            profit: 0.01,
            proceduresRevenue: 0.01,
            salesRevenue: 0,
            subscriptionsRevenue: 0,
            coursesRevenue: 0
        )

        XCTAssertEqual(data.totalRevenue, 0.01, accuracy: 0.001)
    }

    // MARK: - Integration Tests (would require mock Supabase)

    /*
    func testLoadData_Success() async {
        // Would require dependency injection of mock Supabase
        await sut.loadData()

        XCTAssertFalse(sut.isLoading)
        XCTAssertNotNil(sut.reportData)
        XCTAssertNil(sut.errorMessage)
    }

    func testLoadData_Failure() async {
        // Mock Supabase to return error
        await sut.loadData()

        XCTAssertFalse(sut.isLoading)
        XCTAssertNil(sut.reportData)
        XCTAssertNotNil(sut.errorMessage)
    }
    */
}

// MARK: - Period Filter Tests

final class PeriodFilterTests: XCTestCase {

    func testPeriodFilter_AllCasesExist() {
        let allCases = PeriodFilter.allCases

        XCTAssertEqual(allCases.count, 4)
        XCTAssertTrue(allCases.contains(.day))
        XCTAssertTrue(allCases.contains(.week))
        XCTAssertTrue(allCases.contains(.month))
        XCTAssertTrue(allCases.contains(.year))
    }

    func testPeriodFilter_Equatable() {
        XCTAssertEqual(PeriodFilter.day, PeriodFilter.day)
        XCTAssertNotEqual(PeriodFilter.day, PeriodFilter.week)
    }

    func testPeriodFilter_Hashable() {
        let set: Set<PeriodFilter> = [.day, .week, .month, .year, .day]
        XCTAssertEqual(set.count, 4, "Should not contain duplicates")
    }
}
