import SwiftUI

// MARK: - Period Filter View

/// Componente reutilizável para seleção de período (Hoje, Semana, Mês, Ano)
/// Apresenta um segmented control estilizado conforme o padrão Agenda HOF
struct PeriodFilterView: View {

    // MARK: - Properties

    @Binding var selectedPeriod: PeriodFilter

    // MARK: - Body

    var body: some View {
        HStack(spacing: 0) {
            ForEach(PeriodFilter.allCases, id: \.self) { period in
                periodButton(for: period)
            }
        }
        .background(Color(.systemGray6))
        .cornerRadius(10)
    }

    // MARK: - Period Button

    private func periodButton(for period: PeriodFilter) -> some View {
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
                    : Color(.secondaryLabel)
                )
                .cornerRadius(8)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Preview

#Preview {
    VStack(spacing: 20) {
        PeriodFilterView(selectedPeriod: .constant(.month))
            .padding()

        PeriodFilterView(selectedPeriod: .constant(.week))
            .padding()

        PeriodFilterView(selectedPeriod: .constant(.day))
            .padding()
    }
    .background(Color(.systemBackground))
}
