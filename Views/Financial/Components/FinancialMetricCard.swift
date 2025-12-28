import SwiftUI

// MARK: - Financial Metric Card

/// Card reutilizável para exibir métricas financeiras
/// Segue o padrão visual do Agenda HOF: card branco, cantos arredondados, sombra suave
struct FinancialMetricCard: View {

    // MARK: - Properties

    let title: String
    let value: String
    let icon: String
    let iconColor: Color
    let valueColor: Color

    // MARK: - Initializer

    init(
        title: String,
        value: String,
        icon: String,
        iconColor: Color = Constants.primaryColor,
        valueColor: Color = .primary
    ) {
        self.title = title
        self.value = value
        self.icon = icon
        self.iconColor = iconColor
        self.valueColor = valueColor
    }

    // MARK: - Body

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Cabeçalho: Ícone + Título
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(iconColor)

                Text(title)
                    .font(.subheadline)
                    .foregroundColor(.secondary)

                Spacer()
            }

            // Valor principal
            Text(value)
                .font(.system(size: 24, weight: .bold))
                .foregroundColor(valueColor)
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

// MARK: - Financial Summary Cards

/// Cards de resumo financeiro pré-configurados para o relatório
struct FinancialSummaryCards: View {

    let data: FinancialReportData

    var body: some View {
        VStack(spacing: 12) {
            // Receita Total
            FinancialMetricCard(
                title: "Receita Total",
                value: data.formatCurrency(data.totalRevenue),
                icon: "arrow.up.circle.fill",
                iconColor: .green,
                valueColor: .green
            )

            HStack(spacing: 12) {
                // Despesas
                FinancialMetricCard(
                    title: "Despesas",
                    value: data.formatCurrency(data.totalExpenses),
                    icon: "arrow.down.circle.fill",
                    iconColor: .red,
                    valueColor: .red
                )

                // Lucro
                FinancialMetricCard(
                    title: "Lucro",
                    value: data.formatCurrency(data.profit),
                    icon: "dollarsign.circle.fill",
                    iconColor: data.profit >= 0 ? .blue : .red,
                    valueColor: data.profit >= 0 ? .blue : .red
                )
            }
        }
    }
}

// MARK: - Preview

#Preview {
    VStack(spacing: 20) {
        FinancialMetricCard(
            title: "Receita Total",
            value: "R$ 15.450,00",
            icon: "arrow.up.circle.fill",
            iconColor: .green,
            valueColor: .green
        )

        HStack {
            FinancialMetricCard(
                title: "Despesas",
                value: "R$ 3.200,00",
                icon: "arrow.down.circle.fill",
                iconColor: .red,
                valueColor: .red
            )

            FinancialMetricCard(
                title: "Lucro",
                value: "R$ 12.250,00",
                icon: "dollarsign.circle.fill",
                iconColor: .blue,
                valueColor: .blue
            )
        }
    }
    .padding()
    .background(Color(.systemGroupedBackground))
}
