import SwiftUI

// MARK: - Revenue Breakdown Section

/// Seção que exibe o detalhamento de receitas por categoria
/// (Procedimentos, Vendas, Assinaturas, Cursos)
struct RevenueBreakdownSection: View {

    // MARK: - Properties

    let data: FinancialReportData

    // MARK: - Body

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Título da seção
            Text("Detalhamento de Receitas")
                .font(.headline)
                .foregroundColor(.primary)

            // Cards de receita por categoria
            VStack(spacing: 12) {
                RevenueBreakdownRow(
                    title: "Procedimentos",
                    value: data.formatCurrency(data.proceduresRevenue),
                    icon: "stethoscope",
                    color: .blue
                )

                RevenueBreakdownRow(
                    title: "Vendas de Produtos",
                    value: data.formatCurrency(data.salesRevenue),
                    icon: "cart.fill",
                    color: .purple
                )

                RevenueBreakdownRow(
                    title: "Mensalidades",
                    value: data.formatCurrency(data.subscriptionsRevenue),
                    icon: "calendar.badge.clock",
                    color: .green
                )

                RevenueBreakdownRow(
                    title: "Cursos",
                    value: data.formatCurrency(data.coursesRevenue),
                    icon: "book.fill",
                    color: Constants.primaryColor
                )
            }
        }
        .padding(Constants.horizontalPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Constants.cardBackgroundColor)
        .cornerRadius(Constants.cardCornerRadius)
        .shadow(
            color: .black.opacity(Constants.cardShadowOpacity),
            radius: Constants.cardShadowRadius,
            x: 0,
            y: 2
        )
    }
}

// MARK: - Revenue Breakdown Row

/// Linha individual de receita no breakdown
struct RevenueBreakdownRow: View {

    // MARK: - Properties

    let title: String
    let value: String
    let icon: String
    let color: Color

    // MARK: - Body

    var body: some View {
        HStack(spacing: 12) {
            // Ícone
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(color.opacity(0.15))
                    .frame(width: 40, height: 40)

                Image(systemName: icon)
                    .font(.system(size: 18, weight: .medium))
                    .foregroundColor(color)
            }

            // Título
            Text(title)
                .font(.subheadline)
                .foregroundColor(.primary)

            Spacer()

            // Valor
            Text(value)
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundColor(color)
        }
        .padding(.vertical, 8)
    }
}

// MARK: - Preview

#Preview {
    let sampleData = FinancialReportData(
        proceduresRevenue: 8500.00,
        salesRevenue: 3200.00,
        subscriptionsRevenue: 2500.00,
        coursesRevenue: 1250.00,
        otherRevenue: 0,
        totalRevenue: 15450.00,
        totalExpenses: 3200.00,
        netProfit: 12250.00,
        expensesByCategory: []
    )

    VStack {
        RevenueBreakdownSection(data: sampleData)
            .padding()

        Spacer()
    }
    .background(Color(.systemGroupedBackground))
}
