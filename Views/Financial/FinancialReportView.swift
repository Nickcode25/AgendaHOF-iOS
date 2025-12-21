import SwiftUI
import Foundation

// MARK: - Financial Report View (CORRIGIDO - v2.0)

struct FinancialReportView: View {
    @Environment(\.dismiss) var dismiss
    @EnvironmentObject var supabase: SupabaseManager

    @State private var selectedPeriod: PeriodFilter = .month
    @State private var isLoading = true
    @State private var reportData: FinancialReportData?
    @State private var errorMessage: String?
    @State private var isAppearing = false

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

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Header com seletor de período
                headerSection

                // Conteúdo
                if isLoading {
                    loadingView
                } else if let error = errorMessage {
                    errorView(error)
                } else if let data = reportData {
                    contentView(data)
                } else {
                    emptyView
                }
            }
            .background(Color(.systemBackground))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(.secondary)
                            .frame(width: 30, height: 30)
                            .background(Color(.systemGray6))
                            .clipShape(Circle())
                    }
                }
            }
            .task {
                await loadData()
            }
            .onChange(of: selectedPeriod) {
                Task { await loadData() }
            }
            .onAppear {
                withAnimation(.easeOut(duration: 0.5)) {
                    isAppearing = true
                }
            }
        }
    }

    // MARK: - Header Section

    private var headerSection: some View {
        VStack(spacing: 24) {
            // Título
            Text("Relatório Financeiro")
                .font(.system(size: 28, weight: .semibold))
                .foregroundStyle(.primary)

            // Seletor de período
            HStack(spacing: 0) {
                ForEach(PeriodFilter.allCases, id: \.self) { period in
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            selectedPeriod = period
                        }
                    } label: {
                        Text(period.displayName)
                            .font(.subheadline)
                            .fontWeight(.medium)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .background(
                                selectedPeriod == period
                                ? Color(.label)
                                : Color.clear
                            )
                            .foregroundColor(
                                selectedPeriod == period
                                ? Color(.systemBackground)
                                : .secondary
                            )
                    }
                }
            }
            .background(Color(.systemGray6))
            .cornerRadius(10)
        }
        .padding(.horizontal, 32)
        .padding(.top, 20)
        .padding(.bottom, 24)
        .opacity(isAppearing ? 1 : 0)
        .offset(y: isAppearing ? 0 : 10)
    }

    // MARK: - Content View

    private func contentView(_ data: FinancialReportData) -> some View {
        ScrollView {
            VStack(spacing: 32) {
                // Cards principais
                mainCardsSection(data)

                // Detalhamento de receitas
                revenueBreakdownSection(data)

                // Detalhamento de despesas
                if data.totalExpenses > 0 {
                    expensesSection(data)
                }
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 40)
        }
        .opacity(isAppearing ? 1 : 0)
        .animation(.easeOut(duration: 0.5).delay(0.1), value: isAppearing)
    }

    // MARK: - Main Cards

    private func mainCardsSection(_ data: FinancialReportData) -> some View {
        VStack(spacing: 16) {
            // Lucro Líquido (card grande)
            VStack(spacing: 8) {
                Text("Lucro Líquido")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                Text(formatCurrency(data.netProfit))
                    .font(.system(size: 36, weight: .semibold))
                    .foregroundColor(data.netProfit >= 0 ? Color.primary : Color.red)

                // Indicador de variação
                HStack(spacing: 4) {
                    Image(systemName: data.netProfit >= 0 ? "arrow.up.right" : "arrow.down.right")
                        .font(.system(size: 12, weight: .medium))
                    Text(data.netProfit >= 0 ? "Positivo" : "Negativo")
                        .font(.caption)
                }
                .foregroundColor(data.netProfit >= 0 ? Color.green : Color.red)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(
                    (data.netProfit >= 0 ? Color.green : Color.red).opacity(0.1)
                )
                .cornerRadius(20)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 24)
            .background(Color(.systemGray6).opacity(0.5))
            .cornerRadius(16)

            // Cards de receita e despesa
            HStack(spacing: 12) {
                // Receita
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Image(systemName: "arrow.up.circle")
                            .font(.system(size: 20))
                            .foregroundStyle(.green)
                        Spacer()
                    }

                    Text("Receita Total")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Text(formatCurrency(data.totalRevenue))
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(.primary)
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(.systemGray6).opacity(0.5))
                .cornerRadius(12)

                // Despesas
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Image(systemName: "arrow.down.circle")
                            .font(.system(size: 20))
                            .foregroundColor(.red)
                        Spacer()
                    }

                    Text("Despesas")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Text(formatCurrency(data.totalExpenses))
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(.primary)
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(.systemGray6).opacity(0.5))
                .cornerRadius(12)
            }
        }
    }

    // MARK: - Revenue Breakdown

    private func revenueBreakdownSection(_ data: FinancialReportData) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Receitas por categoria")
                .font(.subheadline)
                .fontWeight(.medium)
                .foregroundStyle(.primary)

            VStack(spacing: 0) {
                RevenueRow(
                    title: "Procedimentos",
                    value: data.proceduresRevenue,
                    icon: "cross.case",
                    showDivider: true
                )

                RevenueRow(
                    title: "Vendas",
                    value: data.salesRevenue,
                    icon: "bag",
                    showDivider: true
                )

                RevenueRow(
                    title: "Mensalidades",
                    value: data.subscriptionsRevenue,
                    icon: "creditcard",
                    showDivider: true
                )

                RevenueRow(
                    title: "Cursos",
                    value: data.coursesRevenue,
                    icon: "book",
                    showDivider: data.otherRevenue > 0
                )

                if data.otherRevenue > 0 {
                    RevenueRow(
                        title: "Outras receitas",
                        value: data.otherRevenue,
                        icon: "ellipsis.circle",
                        showDivider: false
                    )
                }
            }
            .background(Color(.systemGray6).opacity(0.5))
            .cornerRadius(12)
        }
    }

    // MARK: - Expenses Section

    private func expensesSection(_ data: FinancialReportData) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Despesas")
                .font(.subheadline)
                .fontWeight(.medium)
                .foregroundStyle(.primary)

            VStack(spacing: 0) {
                ForEach(Array(data.expensesByCategory.enumerated()), id: \.element.category) { index, expense in
                    ExpenseRow(
                        title: expense.category,
                        value: expense.amount,
                        showDivider: index < data.expensesByCategory.count - 1
                    )
                }
            }
            .background(Color(.systemGray6).opacity(0.5))
            .cornerRadius(12)
        }
    }

    // MARK: - Loading View

    private var loadingView: some View {
        VStack {
            Spacer()
            VStack(spacing: 16) {
                ProgressView()
                    .scaleEffect(1.2)
                Text("Carregando dados...")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
    }

    // MARK: - Error View

    private func errorView(_ error: String) -> some View {
        VStack {
            Spacer()
            VStack(spacing: 20) {
                Image(systemName: "exclamationmark.triangle")
                    .font(.system(size: 44, weight: .light))
                    .foregroundStyle(.secondary)

                Text("Erro ao carregar")
                    .font(.system(size: 20, weight: .semibold))

                Text(error)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)

                Button {
                    Task { await loadData() }
                } label: {
                    Text("Tentar novamente")
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundStyle(.primary)
                        .padding(.horizontal, 24)
                        .padding(.vertical, 12)
                        .background(Color(.systemGray6))
                        .cornerRadius(10)
                }
            }
            Spacer()
        }
    }

    // MARK: - Empty View

    private var emptyView: some View {
        VStack {
            Spacer()
            VStack(spacing: 16) {
                Image(systemName: "chart.bar")
                    .font(.system(size: 44, weight: .light))
                    .foregroundStyle(.secondary)

                Text("Sem dados")
                    .font(.system(size: 20, weight: .semibold))

                Text("Não há dados financeiros para este período")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
    }

    // MARK: - Load Data

    private func loadData() async {
        isLoading = true
        errorMessage = nil

        guard let userId = supabase.effectiveUserId else {
            errorMessage = "Usuário não encontrado"
            isLoading = false
            return
        }

        let (startDate, endDate) = getDateRange(for: selectedPeriod)
        let formatter = ISO8601DateFormatter()
        let startStr = formatter.string(from: startDate)
        let endStr = formatter.string(from: endDate)

        #if DEBUG
        print("📊 [Financial Report] Loading data for period: \(selectedPeriod.displayName)")
        print("📊 [Financial Report] Date range: \(startDate) to \(endDate)")
        print("📊 [Financial Report] User ID: \(userId)")
        #endif

        // 1. Buscar procedimentos de pacientes
        let proceduresRevenue = await fetchProceduresRevenue(userId: userId, startDate: startDate, endDate: endDate)

        // 2. Buscar vendas
        let salesRevenue = await fetchSalesRevenue(userId: userId, startStr: startStr, endStr: endStr)

        // 3. Buscar mensalidades
        let subscriptionsRevenue = await fetchSubscriptionsRevenue(userId: userId, startStr: startStr, endStr: endStr)

        // 4. Buscar cursos/matrículas
        let coursesRevenue = await fetchCoursesRevenue(userId: userId, startStr: startStr, endStr: endStr)

        // 5. Buscar despesas
        let (totalExpenses, expensesByCategory) = await fetchExpenses(userId: userId, startStr: startStr, endStr: endStr)

        // Calcular totais
        // ✅ CORREÇÃO: Removido otherRevenue (tabela não existe no projeto)
        let totalRevenue = proceduresRevenue + salesRevenue + subscriptionsRevenue + coursesRevenue
        let netProfit = totalRevenue - totalExpenses

        #if DEBUG
        print("📊 [Financial Report] Results:")
        print("   Procedures: \(formatCurrency(proceduresRevenue))")
        print("   Sales: \(formatCurrency(salesRevenue))")
        print("   Subscriptions: \(formatCurrency(subscriptionsRevenue))")
        print("   Courses: \(formatCurrency(coursesRevenue))")
        print("   Total Revenue: \(formatCurrency(totalRevenue))")
        print("   Total Expenses: \(formatCurrency(totalExpenses))")
        print("   Net Profit: \(formatCurrency(netProfit))")
        #endif

        reportData = FinancialReportData(
            proceduresRevenue: proceduresRevenue,
            salesRevenue: salesRevenue,
            subscriptionsRevenue: subscriptionsRevenue,
            coursesRevenue: coursesRevenue,
            otherRevenue: 0,  // ✅ Sempre 0 (tabela não existe)
            totalRevenue: totalRevenue,
            totalExpenses: totalExpenses,
            netProfit: netProfit,
            expensesByCategory: expensesByCategory
        )

        isLoading = false
    }

    // MARK: - Fetch Procedures Revenue (CORRIGIDO v3.0)

    private func fetchProceduresRevenue(userId: String, startDate: Date, endDate: Date) async -> Decimal {
        do {
            // Buscar pacientes com planned_procedures (usando modelo simplificado)
            let patients: [SimplifiedPatient] = try await supabase.client
                .from("patients")
                .select("id, name, planned_procedures")
                .eq("user_id", value: userId)
                .execute()
                .value

            var total = Decimal(0)
            var count = 0

            // ✅ Formatters para diferentes formatos de data
            let isoFormatter = ISO8601DateFormatter()
            isoFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

            let isoBasicFormatter = ISO8601DateFormatter()

            let dateOnlyFormatter = DateFormatter()
            dateOnlyFormatter.dateFormat = "yyyy-MM-dd"
            dateOnlyFormatter.timeZone = TimeZone(identifier: "UTC")

            for patient in patients {
                guard let procedures = patient.plannedProcedures else { continue }

                for procedure in procedures {
                    // ✅ REGRA 1: Considerar apenas status === 'completed'
                    guard procedure.status?.lowercased() == "completed" else { continue }

                    // ✅ REGRA 2: Usar performedAt ou completedAt
                    let dateString = procedure.performedAt ?? procedure.completedAt
                    guard let dateStr = dateString else { continue }

                    // ✅ Parse da data com múltiplos formatters
                    let performedDate = isoFormatter.date(from: dateStr)
                        ?? isoBasicFormatter.date(from: dateStr)
                        ?? dateOnlyFormatter.date(from: dateStr)

                    guard let performedDate = performedDate else {
                        #if DEBUG
                        print("⚠️ [Procedures] Failed to parse date: \(dateStr)")
                        #endif
                        continue
                    }

                    // ✅ REGRA 3: Data dentro do período selecionado
                    if performedDate >= startDate && performedDate <= endDate {
                        // ✅ REGRA 4: Considerar paymentSplits se disponível
                        if let splits = procedure.paymentSplits, !splits.isEmpty {
                            let splitTotal = splits.reduce(Decimal(0)) { $0 + Decimal($1.amount ?? 0) }
                            total += splitTotal
                            #if DEBUG
                            print("📊 [Procedures] Patient: \(patient.name), Procedure: \(procedure.displayName), Split Total: \(splitTotal)")
                            #endif
                        } else {
                            // ✅ REGRA 5: Somar totalValue
                            let value = Decimal(procedure.totalValue ?? 0)
                            total += value
                            #if DEBUG
                            print("📊 [Procedures] Patient: \(patient.name), Procedure: \(procedure.displayName), Value: \(value)")
                            #endif
                        }
                        count += 1
                    }
                }
            }

            #if DEBUG
            print("📊 [Procedures] Found \(count) completed procedures, total: \(total)")
            #endif

            return total
        } catch {
            print("❌ [Procedures] Error: \(error)")
            errorMessage = "Erro ao buscar procedimentos: \(error.localizedDescription)"
            return 0
        }
    }

    // MARK: - Fetch Sales Revenue (CORRIGIDO v5.0 - implementação completa)

    private func fetchSalesRevenue(userId: String, startStr: String, endStr: String) async -> Decimal {
        do {
            // ✅ REGRAS:
            // - payment_status === 'paid'
            // - sold_at dentro do período
            // - Somar total_amount
            let sales: [ProductSaleRecord] = try await supabase.client
                .from("sales")
                .select("total_amount, sold_at, payment_status")
                .eq("user_id", value: userId)  // ✅ RLS: Filtrar por owner
                .eq("payment_status", value: "paid")  // ✅ REGRA 1: Apenas vendas pagas
                .gte("sold_at", value: startStr)  // ✅ REGRA 2: Início do período
                .lte("sold_at", value: endStr)  // ✅ REGRA 3: Fim do período (inclusivo)
                .execute()
                .value

            // ✅ REGRA 4: Somar total_amount
            let total = sales.reduce(Decimal(0)) { $0 + ($1.totalAmount ?? 0) }

            #if DEBUG
            print("📊 [Sales] User: \(userId)")
            print("📊 [Sales] Period: \(startStr) to \(endStr)")
            print("📊 [Sales] Found \(sales.count) paid sales")
            print("📊 [Sales] Total: \(total)")
            if sales.count > 0 {
                print("📊 [Sales] Sample sales: \(sales.prefix(3).map { "R$ \($0.totalAmount ?? 0)" }.joined(separator: ", "))")
            }
            #endif

            return total
        } catch {
            print("❌ [Sales] Error: \(error)")
            // Se a tabela não existir, retornar 0 ao invés de erro
            if error.localizedDescription.contains("not find the table") ||
               error.localizedDescription.contains("relation") ||
               error.localizedDescription.contains("does not exist") {
                #if DEBUG
                print("⚠️ [Sales] Table 'sales' does not exist - returning 0")
                #endif
                return 0
            }
            errorMessage = "Erro ao buscar vendas: \(error.localizedDescription)"
            return 0
        }
    }

    // MARK: - Fetch Subscriptions Revenue (CORRIGIDO v4.0 - patient_subscriptions)

    private func fetchSubscriptionsRevenue(userId: String, startStr: String, endStr: String) async -> Decimal {
        do {
            // ✅ PASSO 1: Buscar assinaturas dos pacientes do usuário
            let subscriptions: [PatientSubscriptionRecord] = try await supabase.client
                .from("patient_subscriptions")
                .select("id, patient_id, plan_name")
                .eq("user_id", value: userId)
                .execute()
                .value

            guard !subscriptions.isEmpty else {
                #if DEBUG
                print("📊 [Subscriptions] No patient subscriptions found for user")
                #endif
                return 0
            }

            let subscriptionIds = subscriptions.map { $0.id }

            #if DEBUG
            print("📊 [Subscriptions] Found \(subscriptions.count) patient subscriptions")
            #endif

            // ✅ PASSO 2: Buscar pagamentos dessas assinaturas
            // REGRAS:
            // - status === 'paid'
            // - paid_at dentro do período
            // - Somar amount
            let payments: [SubscriptionPaymentRecord] = try await supabase.client
                .from("subscription_payments")
                .select("amount, paid_at, subscription_id")
                .in("subscription_id", values: subscriptionIds)
                .eq("status", value: "paid")  // ✅ REGRA 1: Apenas pagamentos confirmados
                .gte("paid_at", value: startStr)  // ✅ REGRA 2: Início do período
                .lte("paid_at", value: endStr)  // ✅ REGRA 3: Fim do período (inclusivo)
                .execute()
                .value

            // ✅ REGRA 4: Somar amount
            let total = payments.reduce(Decimal(0)) { $0 + ($1.amount ?? 0) }

            #if DEBUG
            print("📊 [Subscriptions] User: \(userId)")
            print("📊 [Subscriptions] Period: \(startStr) to \(endStr)")
            print("📊 [Subscriptions] Found \(payments.count) paid payments in period")
            print("📊 [Subscriptions] Total: \(total)")
            if payments.count > 0 {
                print("📊 [Subscriptions] Sample payments: \(payments.prefix(3).map { "R$ \($0.amount ?? 0)" }.joined(separator: ", "))")
            }
            #endif

            return total
        } catch {
            print("❌ [Subscriptions] Error: \(error)")
            errorMessage = "Erro ao buscar mensalidades: \(error.localizedDescription)"
            return 0
        }
    }

    // MARK: - Fetch Courses Revenue (CORRIGIDO v2.0)

    private func fetchCoursesRevenue(userId: String, startStr: String, endStr: String) async -> Decimal {
        do {
            // ✅ REGRAS:
            // - amount_paid > 0
            // - enrollment_date dentro do período
            // - Somar amount_paid
            let enrollments: [EnrollmentRecord] = try await supabase.client
                .from("enrollments")
                .select("amount_paid, enrollment_date")
                .eq("user_id", value: userId)  // ✅ RLS: Filtrar por owner
                .gt("amount_paid", value: 0)  // ✅ REGRA 1: Apenas matrículas pagas
                .gte("enrollment_date", value: startStr)  // ✅ REGRA 2: Início do período
                .lte("enrollment_date", value: endStr)  // ✅ REGRA 3: Fim do período (inclusivo)
                .execute()
                .value

            // ✅ REGRA 4: Somar amount_paid
            let total = enrollments.reduce(Decimal(0)) { $0 + ($1.amountPaid ?? 0) }

            #if DEBUG
            print("📊 [Courses] User: \(userId)")
            print("📊 [Courses] Period: \(startStr) to \(endStr)")
            print("📊 [Courses] Found \(enrollments.count) paid enrollments")
            print("📊 [Courses] Total: \(total)")
            #endif

            return total
        } catch {
            print("❌ [Courses] Error: \(error)")
            errorMessage = "Erro ao buscar matrículas: \(error.localizedDescription)"
            return 0
        }
    }

    // MARK: - Fetch Expenses (CORRIGIDO v2.0)

    private func fetchExpenses(userId: String, startStr: String, endStr: String) async -> (Decimal, [ExpenseCategory]) {
        do {
            // ✅ REGRAS:
            // - payment_status === 'paid'
            // - paid_at ou due_date dentro do período
            // - Somar amount
            let expenses: [ExpenseRecord] = try await supabase.client
                .from("expenses")
                .select("amount, category_name, paid_at")
                .eq("user_id", value: userId)  // ✅ RLS: Filtrar por owner
                .eq("payment_status", value: "paid")  // ✅ REGRA 1: Apenas despesas pagas
                .gte("paid_at", value: startStr)  // ✅ REGRA 2: Início do período
                .lte("paid_at", value: endStr)  // ✅ REGRA 3: Fim do período (inclusivo)
                .execute()
                .value

            // ✅ Agrupar por categoria
            var categoryTotals: [String: Decimal] = [:]
            var total = Decimal(0)

            for expense in expenses {
                let amount = expense.amount ?? 0
                total += amount
                let category = expense.categoryName ?? "Outros"
                categoryTotals[category, default: 0] += amount
            }

            let categories = categoryTotals.map { ExpenseCategory(category: $0.key, amount: $0.value) }
                .sorted { $0.amount > $1.amount }

            #if DEBUG
            print("📊 [Expenses] User: \(userId)")
            print("📊 [Expenses] Period: \(startStr) to \(endStr)")
            print("📊 [Expenses] Found \(expenses.count) paid expenses")
            print("📊 [Expenses] Total: \(total)")
            print("📊 [Expenses] Categories: \(categories.map { "\($0.category): \($0.amount)" }.joined(separator: ", "))")
            #endif

            return (total, categories)
        } catch {
            print("❌ [Expenses] Error: \(error)")
            errorMessage = "Erro ao buscar despesas: \(error.localizedDescription)"
            return (0, [])
        }
    }

    // MARK: - Date Range Helper

    private func getDateRange(for period: PeriodFilter) -> (Date, Date) {
        let calendar = Calendar.current
        let now = Date()

        switch period {
        case .day:
            let startOfDay = calendar.startOfDay(for: now)
            let endOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay)!
            return (startOfDay, endOfDay)

        case .week:
            let weekday = calendar.component(.weekday, from: now)
            let daysToSubtract = (weekday == 1) ? 6 : (weekday - 2)
            let startOfWeek = calendar.date(byAdding: .day, value: -daysToSubtract, to: calendar.startOfDay(for: now))!
            let endOfWeek = calendar.date(byAdding: .day, value: 7, to: startOfWeek)!
            return (startOfWeek, endOfWeek)

        case .month:
            let startOfMonth = calendar.date(from: calendar.dateComponents([.year, .month], from: now))!
            let endOfMonth = calendar.date(byAdding: .month, value: 1, to: startOfMonth)!
            return (startOfMonth, endOfMonth)

        case .year:
            let startOfYear = calendar.date(from: calendar.dateComponents([.year], from: now))!
            let endOfYear = calendar.date(byAdding: .year, value: 1, to: startOfYear)!
            return (startOfYear, endOfYear)
        }
    }

    // MARK: - Format Currency

    private func formatCurrency(_ value: Decimal) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.locale = Locale(identifier: "pt_BR")
        formatter.minimumFractionDigits = 2
        formatter.maximumFractionDigits = 2
        return formatter.string(from: value as NSDecimalNumber) ?? "R$ 0,00"
    }
}

// MARK: - Revenue Row

private struct RevenueRow: View {
    let title: String
    let value: Decimal
    let icon: String
    let showDivider: Bool

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 14) {
                Image(systemName: icon)
                    .font(.system(size: 16))
                    .foregroundStyle(.secondary)
                    .frame(width: 24)

                Text(title)
                    .font(.subheadline)
                    .foregroundStyle(.primary)

                Spacer()

                Text(formatCurrency(value))
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundStyle(value > 0 ? .primary : .secondary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)

            if showDivider {
                Divider()
                    .padding(.leading, 54)
            }
        }
    }

    private func formatCurrency(_ value: Decimal) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.locale = Locale(identifier: "pt_BR")
        formatter.minimumFractionDigits = 2
        formatter.maximumFractionDigits = 2
        return formatter.string(from: value as NSDecimalNumber) ?? "R$ 0,00"
    }
}

// MARK: - Expense Row

private struct ExpenseRow: View {
    let title: String
    let value: Decimal
    let showDivider: Bool

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 14) {
                Image(systemName: "minus.circle")
                    .font(.system(size: 16))
                    .foregroundColor(Color.red.opacity(0.7))
                    .frame(width: 24)

                Text(title)
                    .font(.subheadline)
                    .foregroundColor(.primary)

                Spacer()

                Text(formatCurrency(value))
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundColor(.red)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)

            if showDivider {
                Divider()
                    .padding(.leading, 54)
            }
        }
    }

    private func formatCurrency(_ value: Decimal) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.locale = Locale(identifier: "pt_BR")
        formatter.minimumFractionDigits = 2
        formatter.maximumFractionDigits = 2
        return formatter.string(from: value as NSDecimalNumber) ?? "R$ 0,00"
    }
}

// MARK: - Data Models (CORRIGIDO - usando Decimal)

struct FinancialReportData {
    let proceduresRevenue: Decimal
    let salesRevenue: Decimal
    let subscriptionsRevenue: Decimal
    let coursesRevenue: Decimal
    let otherRevenue: Decimal
    let totalRevenue: Decimal
    let totalExpenses: Decimal
    let netProfit: Decimal
    let expensesByCategory: [ExpenseCategory]
}

struct ExpenseCategory: Identifiable {
    let id = UUID()
    let category: String
    let amount: Decimal
}

// MARK: - Database Models (CORRIGIDO)

// ✅ Modelo simplificado apenas para o relatório financeiro
private struct SimplifiedPatient: Codable {
    let id: String
    let name: String
    let plannedProcedures: [PlannedProcedure]?

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case plannedProcedures = "planned_procedures"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)

        // planned_procedures pode ser array, string JSON, ou null
        if let procedures = try? container.decodeIfPresent([PlannedProcedure].self, forKey: .plannedProcedures) {
            plannedProcedures = procedures
        } else if let jsonString = try? container.decodeIfPresent(String.self, forKey: .plannedProcedures),
                  let data = jsonString.data(using: .utf8) {
            // Tentar parsear string JSON
            let decoder = JSONDecoder()
            decoder.keyDecodingStrategy = .convertFromSnakeCase
            plannedProcedures = try? decoder.decode([PlannedProcedure].self, from: data)
        } else {
            plannedProcedures = nil
        }
    }
}

private struct ProductSaleRecord: Codable {
    let totalAmount: Decimal?
    let soldAt: String?
    let paymentStatus: String?

    enum CodingKeys: String, CodingKey {
        case totalAmount = "total_amount"
        case soldAt = "sold_at"
        case paymentStatus = "payment_status"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        soldAt = try container.decodeIfPresent(String.self, forKey: .soldAt)
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

private struct ExpenseRecord: Codable {
    let amount: Decimal?
    let categoryName: String?
    let paidAt: String?

    enum CodingKeys: String, CodingKey {
        case amount
        case categoryName = "category_name"
        case paidAt = "paid_at"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        categoryName = try container.decodeIfPresent(String.self, forKey: .categoryName)
        paidAt = try container.decodeIfPresent(String.self, forKey: .paidAt)

        if let value = try container.decodeIfPresent(Double.self, forKey: .amount) {
            amount = Decimal(value)
        } else {
            amount = nil
        }
    }
}

#Preview {
    FinancialReportView()
        .environmentObject(SupabaseManager.shared)
}
