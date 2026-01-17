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
    @Published var reportData: FinancialReportViewModelData?
    @Published var errorMessage: String?

    // MARK: - Private Properties

    private let supabase: SupabaseManager

    // MARK: - Initialization

    nonisolated init(supabase: SupabaseManager) {
        self.supabase = supabase
    }
    
    @MainActor
    convenience init() {
        self.init(supabase: .shared)
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

        reportData = FinancialReportViewModelData(
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

        isLoading = false
    }

    // MARK: - Data Fetching Methods

    /// Busca receita de procedimentos realizados
    /// Implementa a mesma lógica de 3 casos da versão web:
    /// - Caso 1: Parcelado (permitirParcelado + pagamentos[]) → somar pagamentos por data
    /// - Caso 2: Múltiplas formas (paymentSplits[]) → somar splits por data do procedimento
    /// - Caso 3: Tradicional → somar totalValue por data do procedimento
    private func fetchProceduresRevenue(userId: String, start: Date, end: Date) async -> Decimal {
        do {
            // Formatar datas para comparação de strings (como na web)
            let startString = formatDateString(start)
            let endString = formatDateString(end)
            
            #if DEBUG
            print("📊 [FinancialReport] Buscando procedimentos...")
            print("   Período: \(startString) até \(endString)")
            #endif
            
            // Buscar apenas pacientes ativos
            let patients: [Patient] = try await supabase.client
                .from("patients")
                .select()
                .eq("user_id", value: userId)
                .eq("is_active", value: true)
                .execute()
                .value

            var total: Decimal = 0

            for patient in patients {
                guard let procedures = patient.plannedProcedures else { continue }
                
                // Filtrar apenas procedimentos concluídos (status == "completed")
                let completedProcedures = procedures.filter { $0.status == "completed" }

                for proc in completedProcedures {
                    let procedureDate = proc.performedAt ?? proc.completedAt ?? ""
                    let procedureDateOnly = String(procedureDate.prefix(10)) // Extrair YYYY-MM-DD
                    
                    // ══════════════════════════════════════════════════════════
                    // CASO 1: Procedimento com pagamento parcelado (PIX/Dinheiro)
                    // ══════════════════════════════════════════════════════════
                    if proc.permitirParcelado == true,
                       let pagamentos = proc.pagamentos,
                       !pagamentos.isEmpty {
                        
                        for pagamento in pagamentos {
                            let paymentDate = String(pagamento.data.prefix(10))
                            if isDateInRange(paymentDate, start: startString, end: endString) {
                                total += Decimal(pagamento.valor)
                                
                                #if DEBUG
                                print("   💳 [Parcelado] \(proc.displayName) - \(patient.name): R$ \(pagamento.valor) em \(paymentDate)")
                                #endif
                            }
                        }
                    }
                    // ══════════════════════════════════════════════════════════
                    // CASO 2: Procedimento com múltiplas formas de pagamento
                    // ══════════════════════════════════════════════════════════
                    else if let splits = proc.paymentSplits,
                            !splits.isEmpty,
                            isDateInRange(procedureDateOnly, start: startString, end: endString) {
                        
                        for split in splits {
                            if let amount = split.amount {
                                total += Decimal(amount)
                                
                                #if DEBUG
                                print("   💳 [Split] \(proc.displayName) - \(patient.name): R$ \(amount) (\(split.method ?? "?"))")
                                #endif
                            }
                        }
                    }
                    // ══════════════════════════════════════════════════════════
                    // CASO 3: Procedimento tradicional (pagamento único)
                    // ══════════════════════════════════════════════════════════
                    else if proc.permitirParcelado != true,
                            isDateInRange(procedureDateOnly, start: startString, end: endString) {
                        
                        let value = proc.totalValue ?? proc.value ?? 0
                        total += Decimal(value)
                        
                        #if DEBUG
                        print("   💰 [Tradicional] \(proc.displayName) - \(patient.name): R$ \(value) em \(procedureDateOnly)")
                        #endif
                    }
                }
            }
            
            #if DEBUG
            print("   ✅ Total Procedimentos: R$ \(total)")
            #endif

            return total

        } catch {
            #if DEBUG
            print("⚠️ [FinancialReport] Erro ao buscar procedimentos: \(error)")
            #endif
            return 0
        }
    }
    
    /// Formata Date para string YYYY-MM-DD no timezone de São Paulo
    private func formatDateString(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = TimeZone(identifier: "America/Sao_Paulo")
        return formatter.string(from: date)
    }
    
    /// Verifica se uma data (string YYYY-MM-DD) está dentro do período
    private func isDateInRange(_ dateString: String, start: String, end: String) -> Bool {
        return dateString >= start && dateString <= end
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
                total + Decimal(sale.totalValue)
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
                total + Decimal(sub.monthlyValue)
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
                total + Decimal(course.totalValue)
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
                total + Decimal(expense.value)
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
    /// Regra de Negócio (sincronizado com a versão web):
    /// - Dia: De hoje (YYYY-MM-DD)
    /// - Semana: De domingo a sábado da semana atual
    /// - Mês: Do dia 1 até o último dia do mês atual
    /// - Ano: Do dia 1 de Jan até 31 de Dez do ano atual
    private func dateRange(for period: PeriodFilter) -> (start: Date, end: Date) {
        // Usar calendário com timezone de São Paulo para consistência com a web
        var calendar = Calendar(identifier: .gregorian)
        let saoPauloTimeZone = TimeZone(identifier: "America/Sao_Paulo") ?? .current
        calendar.timeZone = saoPauloTimeZone
        calendar.firstWeekday = 1 // Domingo = 1 (como na web)
        
        let now = Date()
        
        // Obter data atual no timezone de São Paulo
        let todayComponents = calendar.dateComponents([.year, .month, .day, .weekday], from: now)
        
        switch period {
        case .day:
            let start = calendar.startOfDay(for: now)
            let end = calendar.date(byAdding: .day, value: 1, to: start) ?? start.addingTimeInterval(86400)
            return (start, end)
            
        case .week:
            // Calcular semana de domingo a sábado (como na web)
            // weekday: 1 = Domingo, 2 = Segunda, ..., 7 = Sábado
            let weekday = todayComponents.weekday ?? 1
            let daysToSunday = weekday - 1 // Quantos dias voltar para chegar ao domingo
            
            // Construir o domingo da semana atual
            var sundayComponents = todayComponents
            sundayComponents.day = (todayComponents.day ?? 1) - daysToSunday
            sundayComponents.hour = 0
            sundayComponents.minute = 0
            sundayComponents.second = 0
            sundayComponents.weekday = nil
            
            guard let sunday = calendar.date(from: sundayComponents) else {
                return (now, now)
            }
            
            // Sábado é domingo + 6 dias, e o fim é domingo + 7 (início do próximo domingo)
            guard let nextSunday = calendar.date(byAdding: .day, value: 7, to: sunday) else {
                return (now, now)
            }
            
            #if DEBUG
            let saturdayForLog = calendar.date(byAdding: .day, value: 6, to: sunday)!
            print("📅 [FinancialReport] Período da semana:")
            print("   Hoje: \(formatDateString(now)) (weekday: \(weekday))")
            print("   Início (Domingo): \(formatDateString(sunday))")
            print("   Fim (Sábado): \(formatDateString(saturdayForLog))")
            #endif
            
            return (sunday, nextSunday)
            
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
// ⚠️ FinancialReportData is defined in FinancialReportView.swift
// This ViewModel uses a simplified version defined locally

/// Modelo de dados do relatório financeiro (versão simplificada para o ViewModel)
struct FinancialReportViewModelData {
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
    let totalValue: Double

    enum CodingKeys: String, CodingKey {
        case saleDate = "sale_date"
        case totalValue = "total_value"
    }
}

struct PatientSubscriptionDB: Codable {
    let startDate: String
    let monthlyValue: Double

    enum CodingKeys: String, CodingKey {
        case startDate = "start_date"
        case monthlyValue = "monthly_value"
    }
}

struct CourseEnrollmentDB: Codable {
    let enrollmentDate: String
    let totalValue: Double

    enum CodingKeys: String, CodingKey {
        case enrollmentDate = "enrollment_date"
        case totalValue = "total_value"
    }
}

struct ExpenseDB: Codable {
    let date: String
    let value: Double
}
