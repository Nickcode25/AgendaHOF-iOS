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
    
    // MARK: - Public Revenue Calculation for Notifications
    
    /// Calcula receita total para um período específico (usado por notificações)
    /// - Parameters:
    ///   - start: Data de início do período
    ///   - end: Data de fim do período (exclusivo)
    /// - Returns: Receita total do período (procedimentos + vendas + assinaturas + cursos)
    func calculateRevenueForNotification(from start: Date, to end: Date) async -> Decimal {
        guard let userId = supabase.currentUser?.id.uuidString else {
            return 0
        }
        
        // Carregar dados em paralelo
        async let proceduresTask = fetchProceduresRevenue(userId: userId, start: start, end: end)
        async let salesTask = fetchSalesRevenue(userId: userId, start: start, end: end)
        async let subscriptionsTask = fetchSubscriptionsRevenue(userId: userId, start: start, end: end)
        async let coursesTask = fetchCoursesRevenue(userId: userId, start: start, end: end)
        
        let (procedures, sales, subscriptions, courses) = await (
            proceduresTask,
            salesTask,
            subscriptionsTask,
            coursesTask
        )
        
        let totalRevenue = procedures + sales + subscriptions + courses
        
        #if DEBUG
        print("💰 [Notification] Receita calculada para \(start.formatted(.dateTime.day().month())):")
        print("   Procedimentos: R$ \(procedures)")
        print("   Vendas: R$ \(sales)")
        print("   Assinaturas: R$ \(subscriptions)")
        print("   Cursos: R$ \(courses)")
        print("   Total: R$ \(totalRevenue)")
        #endif
        
        return totalRevenue
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
            let adjustedEnd = end.addingTimeInterval(-1)
            let endString = formatDateString(adjustedEnd)
            
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
                    // REGRA 1: Procedimento com pagamentos PARCIAIS lançados
                    // CONDIÇÃO: permitirParcelado == true E tem pagamentos lançados
                    // AÇÃO: Somar cada pagamento na sua respectiva data
                    // ══════════════════════════════════════════════════════════
                    if proc.permitirParcelado == true,
                       let pagamentos = proc.pagamentos,
                       !pagamentos.isEmpty {
                        
                        for pagamento in pagamentos {
                            let paymentDate = String(pagamento.data.prefix(10))
                            if isDateInRange(paymentDate, start: startString, end: endString) {
                                total += Decimal(pagamento.valor)
                                
                                #if DEBUG
                                print("   💳 [Regra 1: Parcelado] \(proc.displayName) - \(patient.name): R$ \(pagamento.valor) em \(paymentDate)")
                                #endif
                            }
                        }
                    }
                    // ══════════════════════════════════════════════════════════
                    // REGRA 2: "Pagar Depois" (Sem pagamentos lançados)
                    // CONDIÇÃO: permitirParcelado == true E pagamentos VAZIO
                    // AÇÃO: Receita R$ 0,00 (não soma nada)
                    // ══════════════════════════════════════════════════════════
                    else if proc.permitirParcelado == true {
                        // Se caiu aqui, é porque pagamentos está nil ou vazio
                        #if DEBUG
                        if isDateInRange(procedureDateOnly, start: startString, end: endString) {
                            print("   ⏳ [Regra 2: Pagar Depois] \(proc.displayName) - \(patient.name): Receita R$ 0,00 (Aguardando pagamento)")
                        }
                        #endif
                        continue
                    }
                    // ══════════════════════════════════════════════════════════
                    // CASO EXTRA: Múltiplas formas (Legacy do App)
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
                    // REGRA 3: Procedimento Tradicional (Pagamento Único / Legacy)
                    // CONDIÇÃO: !permitirParcelado (fallback)
                    // AÇÃO: Considerar valor total na data do procedimento
                    // ⚠️ CRITICAL FIX: Se estiver PENDENTE, ignorar (Regime de Caixa)
                    // ══════════════════════════════════════════════════════════
                    else if isDateInRange(procedureDateOnly, start: startString, end: endString) {
                        
                        // 🚨 FIX: Verificar se está pendente explícitamente
                        if let status = proc.statusPagamento?.lowercased(), status == "pendente" {
                            #if DEBUG
                            print("   ⏳ [Regra 3: Pendente] \(proc.displayName) - \(patient.name): Ignorado (Status Pendente)")
                            #endif
                            continue
                        }
                        
                        let value = proc.totalValue ?? proc.value ?? 0
                        total += Decimal(value)
                        
                        #if DEBUG
                        print("   💰 [Regra 3: Tradicional] \(proc.displayName) - \(patient.name): R$ \(value) em \(procedureDateOnly)")
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
            // ✅ BUSCAR TODAS as vendas pagas (filtrar por data no código)
            let allSales: [ProductSaleRecord] = try await supabase.client
                .from("sales")
                .select("total_amount, sold_at, created_at")
                .eq("user_id", value: userId)
                .eq("payment_status", value: "paid")
                .execute()
                .value

            // ✅ Converter período para strings YYYY-MM-DD para comparação
            let startString = formatDateString(start)
            
            // Ajuste para o range inclusivo/exclusivo do dateRange: 
            // O dateRange retorna start=00:00 e end=00:00 do dia seguinte (para .day)
            // ou end=00:00 do mês seguinte.
            // A nossa comparação de strings é inclusiva.
            // Para "Hoje", start="2025-01-27", end="2025-01-28".
            // Se usarmos <= endString, vamos incluir o dia 28 se a string for igual.
            // A função isDateInRange usa <= endString.
            // Então precisamos usar o dia anterior ao end se quisermos "até o fim do dia anterior".
            // MAS, o `fetchProceduresRevenue` já usa o `isDateInRange` com startString e endString retornados por `dateRange`.
            // Vamos verificar `dateRange`:
            // Para .day: start = hoje 00:00, end = amanhã 00:00.
            // formatDateString retorna YYYY-MM-DD.
            // Então start="2025-01-27", end="2025-01-28".
            // isDateInRange faz date >= start && date <= end.
            // Então incluiria o dia 28. ISSO PARECE UM BUG EXISTENTE no fetchProceduresRevenue se a intenção for apenas o dia 27.
            // Porém, `FinancialReportView` faz:
            // let startDateOnly = String(startStr.prefix(10))
            // let endDateOnly = String(endStr.prefix(10))
            // if dateOnly >= startDateOnly && dateOnly <= endDateOnly
            // E lá o getDateRange para .day retorna: startOfDay e endOfDay (23:59:59).
            // Lá as strings são IGUAIS para start e end no caso de .day.
            
            // AQUI no ViewModel, `dateRange` retorna start e end (dia seguinte).
            // Então `endString` será o dia seguinte.
            // Se eu usar `isDateInRange` vou incluir o dia seguinte.
            // PRECISO AJUSTAR `endString` para ser o dia anterior ao `end` atual, OU mudar a comparação.
            // Vou ajustar `endString` subtraindo 1 segundo de `end` antes de formatar.
            
            let adjustedEnd = end.addingTimeInterval(-1)
            let adjustedEndString = formatDateString(adjustedEnd)
            // Agora para .day: start="2025-01-27", end="2025-01-28" -> adjusted="2025-01-27".
            // isDateInRange: date >= "2025-01-27" && date <= "2025-01-27". CORRETO.

            var total = Decimal(0)

            for sale in allSales {
                // ✅ REGRA: Usar sold_at se disponível, senão created_at
                guard let dateStr = sale.soldAt ?? sale.createdAt else { continue }

                // ✅ Extrair apenas YYYY-MM-DD
                let dateOnly = String(dateStr.prefix(10))

                // ✅ Validar formato
                guard dateOnly.count == 10, dateOnly.contains("-") else { continue }

                // ✅ Comparação de strings
                if isDateInRange(dateOnly, start: startString, end: adjustedEndString) {
                    let amount = sale.totalAmount ?? 0
                    total += amount
                }
            }

            return total
        } catch {
            return 0
        }
    }

    /// Busca receita de assinaturas/mensalidades
    private func fetchSubscriptionsRevenue(userId: String, start: Date, end: Date) async -> Decimal {
        do {
            // ✅ PASSO 1: Buscar assinaturas dos pacientes do usuário
            let subscriptions: [PatientSubscriptionRecord] = try await supabase.client
                .from("patient_subscriptions")
                .select("id, patient_id, plan_name")
                .eq("user_id", value: userId)
                .execute()
                .value

            guard !subscriptions.isEmpty else { return 0 }

            let subscriptionIds = subscriptions.map { $0.id }

            // ✅ PASSO 2: Buscar TODOS os pagamentos pagos
            let allPayments: [SubscriptionPaymentRecord] = try await supabase.client
                .from("subscription_payments")
                .select("amount, paid_at, subscription_id")
                .in("subscription_id", values: subscriptionIds)
                .eq("status", value: "paid")
                .execute()
                .value

            let startString = formatDateString(start)
            let adjustedEnd = end.addingTimeInterval(-1)
            let adjustedEndString = formatDateString(adjustedEnd)

            var total = Decimal(0)

            for payment in allPayments {
                guard let dateStr = payment.paidAt else { continue }

                let dateOnly = String(dateStr.prefix(10))

                guard dateOnly.count == 10, dateOnly.contains("-") else { continue }

                if isDateInRange(dateOnly, start: startString, end: adjustedEndString) {
                    let amount = payment.amount ?? 0
                    total += amount
                }
            }

            return total
        } catch {
            return 0
        }
    }

    /// Busca receita de cursos
    private func fetchCoursesRevenue(userId: String, start: Date, end: Date) async -> Decimal {
        do {
            // ✅ BUSCAR TODAS as matrículas pagas
            let allEnrollments: [EnrollmentRecord] = try await supabase.client
                .from("enrollments")
                .select("amount_paid, enrollment_date")
                .eq("user_id", value: userId)
                .gt("amount_paid", value: 0)
                .execute()
                .value

            let startString = formatDateString(start)
            let adjustedEnd = end.addingTimeInterval(-1)
            let adjustedEndString = formatDateString(adjustedEnd)

            var total = Decimal(0)

            for enrollment in allEnrollments {
                guard let dateStr = enrollment.enrollmentDate else { continue }

                let dateOnly = String(dateStr.prefix(10))

                guard dateOnly.count == 10, dateOnly.contains("-") else { continue }

                if isDateInRange(dateOnly, start: startString, end: adjustedEndString) {
                    let amount = enrollment.amountPaid ?? 0
                    total += amount
                }
            }

            return total
        } catch {
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
            let saturdayForLog = calendar.date(byAdding: .day, value: 6, to: sunday) ?? sunday
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
    // NOTA: Campo 'monthly_value' não existe na tabela. Usando valor fixo 0 até schema ser atualizado.
    // let monthlyValue: Double

    enum CodingKeys: String, CodingKey {
        case startDate = "start_date"
        // case monthlyValue = "monthly_value"
    }
    
    // Propriedade computada temporária
    var monthlyValue: Double {
        return 0 // TODO: Atualizar quando campo existir no schema
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

// MARK: - Internal Helper Models

private struct ProductSaleRecord: Codable {
    let totalAmount: Decimal?
    let soldAt: String?
    let createdAt: String?
    let paymentStatus: String?

    enum CodingKeys: String, CodingKey {
        case totalAmount = "total_amount"
        case soldAt = "sold_at"
        case createdAt = "created_at"
        case paymentStatus = "payment_status"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        soldAt = try container.decodeIfPresent(String.self, forKey: .soldAt)
        createdAt = try container.decodeIfPresent(String.self, forKey: .createdAt)
        paymentStatus = try container.decodeIfPresent(String.self, forKey: .paymentStatus)

        if let value = try container.decodeIfPresent(Double.self, forKey: .totalAmount) {
            totalAmount = Decimal(value)
        } else {
            totalAmount = nil
        }
    }
}

private struct PatientSubscriptionRecord: Codable {
    let id: String
    let patientId: String?
    let planName: String?

    enum CodingKeys: String, CodingKey {
        case id
        case patientId = "patient_id"
        case planName = "plan_name"
    }
}

private struct SubscriptionPaymentRecord: Codable {
    let amount: Decimal?
    let paidAt: String?
    let subscriptionId: String?

    enum CodingKeys: String, CodingKey {
        case amount
        case paidAt = "paid_at"
        case subscriptionId = "subscription_id"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        paidAt = try container.decodeIfPresent(String.self, forKey: .paidAt)
        subscriptionId = try container.decodeIfPresent(String.self, forKey: .subscriptionId)

        if let value = try container.decodeIfPresent(Double.self, forKey: .amount) {
            amount = Decimal(value)
        } else {
            amount = nil
        }
    }
}

private struct EnrollmentRecord: Codable {
    let amountPaid: Decimal?
    let enrollmentDate: String?

    enum CodingKeys: String, CodingKey {
        case amountPaid = "amount_paid"
        case enrollmentDate = "enrollment_date"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        enrollmentDate = try container.decodeIfPresent(String.self, forKey: .enrollmentDate)

        if let value = try container.decodeIfPresent(Double.self, forKey: .amountPaid) {
            amountPaid = Decimal(value)
        } else {
            amountPaid = nil
        }
    }
}
