import SwiftUI

// MARK: - Resources Section

/// Seção de recursos do SettingsView
/// Exibe links para: Pacientes Inativos, Notificações e Relatório Financeiro (apenas owner)
struct ResourcesSection: View {

    // MARK: - Properties

    let isOwner: Bool
    let onInactivePatientsTap: () -> Void
    let onNotificationsTap: () -> Void
    let onFinancialReportTap: () -> Void

    // MARK: - Body

    var body: some View {
        Section("Recursos") {
            // Pacientes Inativos (+6 meses)
            SettingsRow(
                icon: "person.badge.clock.fill",
                iconColor: Constants.primaryColor,
                title: "Pacientes Inativos (+6 meses)",
                action: onInactivePatientsTap
            )

            // Notificações
            SettingsRow(
                icon: "bell.fill",
                iconColor: .red,
                title: "Notificações",
                action: onNotificationsTap
            )

            // Relatório Financeiro (apenas owner)
            if isOwner {
                SettingsRow(
                    icon: "chart.bar.fill",
                    iconColor: .green,
                    title: "Relatório Financeiro",
                    action: onFinancialReportTap
                )
            }
        }
    }
}

// MARK: - Convenience Initializer

extension ResourcesSection {

    /// Inicializador conveniente usando SupabaseManager
    init(
        supabase: SupabaseManager,
        onInactivePatientsTap: @escaping () -> Void,
        onNotificationsTap: @escaping () -> Void,
        onFinancialReportTap: @escaping () -> Void
    ) {
        self.isOwner = supabase.isOwner
        self.onInactivePatientsTap = onInactivePatientsTap
        self.onNotificationsTap = onNotificationsTap
        self.onFinancialReportTap = onFinancialReportTap
    }
}

// MARK: - Preview

#Preview {
    List {
        // Owner view
        ResourcesSection(
            isOwner: true,
            onInactivePatientsTap: {},
            onNotificationsTap: {},
            onFinancialReportTap: {}
        )

        // Non-owner view
        ResourcesSection(
            isOwner: false,
            onInactivePatientsTap: {},
            onNotificationsTap: {},
            onFinancialReportTap: {}
        )
    }
}
