import Foundation
import SwiftUI

// MARK: - Financial Report ViewModel

/// ViewModel responsável pela lógica de negócio do relatório financeiro
/// Separa a lógica de dados da apresentação visual
@MainActor
class FinancialReportViewModel: ObservableObject {

    // MARK: - Published Properties

    @Published var selectedPeriod: PeriodFilter = .month
    @Published var isLoading = true
    @Published var reportData: FinancialReportData?
    @Published var errorMessage: String?

    // MARK: - Private Properties

    private let supabase: SupabaseManager

    // MARK: - Initialization

    init(supabase: SupabaseManager = .shared) {
        self.supabase = supabase
    }

    // MARK: - Data Loading

    /// Carrega os dados financeiros para o período selecionado
    func loadData() async {
        isLoading = true
        errorMessage = nil

        guard let userId = supabase.currentUser?.id.uuidString else {
            errorMessage = "Usuário não autenticado"
            isLoading = false
            return
        }

        do {
            let (start, end) = dateRange(for: selectedPeriod)

            #if DEBUG
            print("📊 [FinancialReport] Carregando dados...")
            print("   Período: \(selectedPeriod.displayName)")
            print("   Início: \(start)")
            print("   Fim: \(end)")
            #endif

            // Carregar dados em paralelo para melhor performance
            async let proceduresTask = fetchProceduresRevenue(userId: userId, start: start, end: end)
            async let salesTask = fetchSalesRevenue(userId: userId, start: start, end: end)
            async let subscriptionsTask = fetchSubscriptionsRevenue(userId: userId, start: start, end: end)
            async let coursesTask = fetchCoursesRevenue(userId: userId, start: start, end: end)
            async let expensesTask = fetchExpenses(userId: userId, start: start, end: end)

            let (procedures, sales, subscriptions, courses, expenses) = await (
                proceduresTask,
                salesTask,
                subscriptionsTask,
                coursesTask,
                expensesTask
            )

            // Calcular totais
            let totalRevenue = procedures + sales + subscriptions + courses
            let totalExpenses = expenses
            let profit = totalRevenue - totalExpenses

            reportData = FinancialReportData(
                totalRevenue: totalRevenue,
                totalExpenses: totalExpenses,
                profit: profit,
                proceduresRevenue: procedures,
                salesRevenue: sales,
                subscriptionsRevenue: subscriptions,
                coursesRevenue: courses
            )

            #if DEBUG
            print("✅ [FinancialReport] Dados carregados com sucesso")
            print("   Receita Total: R$ \(totalRevenue.formatted())")
            print("   Despesas: R$ \(totalExpenses.formatted())")
            print("   Lucro: R$ \(profit.formatted())")
            #endif

        } catch {
            errorMessage = "Erro ao carregar dados: \(error.localizedDescription)"
            #if DEBUG
            print("❌ [FinancialReport] Erro: \(error)")
            #endif
        }

        isLoading = false
    }

    // MARK: - Data Fetching Methods

    /// Busca receita de procedimentos realizados
    private func fetchProceduresRevenue(userId: String, start: Date, end: Date) async -> Decimal {
        do {
            let patients: [Patient] = try await supabase.client
                .from("patients")
                .select()
                .eq("user_id", value: userId)
                .execute()
                .value

            var total: Decimal = 0

            for patient in patients {
                guard let procedures = patient.plannedProcedures else { continue }

                for procedure in procedures {
                    // Verificar se foi realizado no período
                    guard let performedAtStr = procedure.performedAt ?? procedure.completedAt else { continue }
                    guard let performedAt = parseDate(performedAtStr) else { continue }

                    if performedAt >= start && performedAt < end {
                        if let valueStr = procedure.value, let value = Decimal(string: valueStr) {
                            total += value
                        }
                    }
                }
            }

            return total

        } catch {
            #if DEBUG
            print("⚠️ [FinancialReport] Erro ao buscar procedimentos: \(error)")
            #endif
            return 0
        }
    }

    /// Busca receita de vendas de produtos
    private func fetchSalesRevenue(userId: String, start: Date, end: Date) async -> Decimal {
        do {
            let sales: [ProductSaleDB] = try await supabase.client
                .from("product_sales")
                .select()
                .eq("user_id", value: userId)
                .execute()
                .value

            let filtered = sales.filter { sale in
                guard let saleDate = parseDate(sale.saleDate) else { return false }
                return saleDate >= start && saleDate < end
            }

            return filtered.reduce(Decimal(0)) { total, sale in
                total + (Decimal(string: sale.totalValue) ?? 0)
            }

        } catch {
            #if DEBUG
            print("⚠️ [FinancialReport] Erro ao buscar vendas: \(error)")
            #endif
            return 0
        }
    }

    /// Busca receita de assinaturas/mensalidades
    private func fetchSubscriptionsRevenue(userId: String, start: Date, end: Date) async -> Decimal {
        do {
            let subscriptions: [PatientSubscriptionDB] = try await supabase.client
                .from("patient_subscriptions")
                .select()
                .eq("user_id", value: userId)
                .execute()
                .value

            let filtered = subscriptions.filter { sub in
                guard let startDate = parseDate(sub.startDate) else { return false }
                return startDate >= start && startDate < end
            }

            return filtered.reduce(Decimal(0)) { total, sub in
                total + (Decimal(string: sub.monthlyValue) ?? 0)
            }

        } catch {
            #if DEBUG
            print("⚠️ [FinancialReport] Erro ao buscar assinaturas: \(error)")
            #endif
            return 0
        }
    }

    /// Busca receita de cursos
    private func fetchCoursesRevenue(userId: String, start: Date, end: Date) async -> Decimal {
        do {
            let courses: [CourseEnrollmentDB] = try await supabase.client
                .from("course_enrollments")
                .select()
                .eq("user_id", value: userId)
                .execute()
                .value

            let filtered = courses.filter { course in
                guard let enrollDate = parseDate(course.enrollmentDate) else { return false }
                return enrollDate >= start && enrollDate < end
            }

            return filtered.reduce(Decimal(0)) { total, course in
                total + (Decimal(string: course.totalValue) ?? 0)
            }

        } catch {
            #if DEBUG
            print("⚠️ [FinancialReport] Erro ao buscar cursos: \(error)")
            #endif
            return 0
        }
    }

    /// Busca despesas do período
    private func fetchExpenses(userId: String, start: Date, end: Date) async -> Decimal {
        do {
            let expenses: [ExpenseDB] = try await supabase.client
                .from("expenses")
                .select()
                .eq("user_id", value: userId)
                .execute()
                .value

            let filtered = expenses.filter { expense in
                guard let expenseDate = parseDate(expense.date) else { return false }
                return expenseDate >= start && expenseDate < end
            }

            return filtered.reduce(Decimal(0)) { total, expense in
                total + (Decimal(string: expense.value) ?? 0)
            }

        } catch {
            #if DEBUG
            print("⚠️ [FinancialReport] Erro ao buscar despesas: \(error)")
            #endif
            return 0
        }
    }

    // MARK: - Helper Methods
    
    /// Retorna o intervalo de datas para o período selecionado
    /// Regra de Negócio:
    /// - Dia: De 00:00 de hoje até 00:00 de amanhã
    /// - Semana: Da semana atual (Segunda ou Domingo dependendo da Locale)
    /// - Mês: Do dia 1 do mês atual até dia 1 do próximo mês
    /// - Ano: Do dia 1 de Jan até 1 de Jan do próximo ano
    private func dateRange(for period: PeriodFilter) -> (start: Date, end: Date) {
        let calendar = Calendar.current
        let now = Date()
        
        switch period {
        case .day:
            let start = calendar.startOfDay(for: now)
            let end = calendar.date(byAdding: .day, value: 1, to: start) ?? start.addingTimeInterval(86400)
            return (start, end)
            
        case .week:
            guard let start = calendar.date(from: calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: now)),
                  let end = calendar.date(byAdding: .weekOfYear, value: 1, to: start) else {
                // Fallback seguro se falhar cálculo de calendário
                return (now, now)
            }
            return (start, end)
            
        case .month:
            guard let start = calendar.date(from: calendar.dateComponents([.year, .month], from: now)),
                  let end = calendar.date(byAdding: .month, value: 1, to: start) else {
                return (now, now)
            }
            return (start, end)
            
        case .year:
            guard let start = calendar.date(from: calendar.dateComponents([.year], from: now)),
                  let end = calendar.date(byAdding: .year, value: 1, to: start) else {
                return (now, now)
            }
            return (start, end)
        }
    }

    /// Parseia string de data em múltiplos formatos
    private func parseDate(_ dateString: String) -> Date? {
        let iso8601 = ISO8601DateFormatter()

        // Tentar com frações de segundo
        iso8601.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = iso8601.date(from: dateString) {
            return date
        }

        // Tentar sem frações de segundo
        iso8601.formatOptions = [.withInternetDateTime]
        if let date = iso8601.date(from: dateString) {
            return date
        }

        // Tentar formato simples
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter.date(from: dateString)
    }
}

// MARK: - Period Filter Enum

enum PeriodFilter: String, CaseIterable {
    case day, week, month, year

    var displayName: String {
        switch self {
        case .day: return "Hoje"
        case .week: return "Semana"
        case .month: return "Mês"
        case .year: return "Ano"
        }
    }
}

// MARK: - Financial Report Data Model

/// Modelo de dados do relatório financeiro
struct FinancialReportData {
    let totalRevenue: Decimal
    let totalExpenses: Decimal
    let profit: Decimal
    let proceduresRevenue: Decimal
    let salesRevenue: Decimal
    let subscriptionsRevenue: Decimal
    let coursesRevenue: Decimal

    /// Formata valor monetário em formato brasileiro
    func formatCurrency(_ value: Decimal) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.locale = Locale(identifier: "pt_BR")
        formatter.currencySymbol = "R$"
        return formatter.string(from: value as NSDecimalNumber) ?? "R$ 0,00"
    }
}

// MARK: - Database Models

struct ProductSaleDB: Codable {
    let saleDate: String
    let totalValue: String

    enum CodingKeys: String, CodingKey {
        case saleDate = "sale_date"
        case totalValue = "total_value"
    }
}

struct PatientSubscriptionDB: Codable {
    let startDate: String
    let monthlyValue: String

    enum CodingKeys: String, CodingKey {
        case startDate = "start_date"
        case monthlyValue = "monthly_value"
    }
}

struct CourseEnrollmentDB: Codable {
    let enrollmentDate: String
    let totalValue: String

    enum CodingKeys: String, CodingKey {
        case enrollmentDate = "enrollment_date"
        case totalValue = "total_value"
    }
}

struct ExpenseDB: Codable {
    let date: String
    let value: String
}
