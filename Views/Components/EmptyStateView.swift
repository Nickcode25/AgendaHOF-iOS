import SwiftUI

struct EmptyStateView: View {
    let icon: String
    let title: String
    var message: String?
    var buttonTitle: String?
    var action: (() -> Void)?

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: icon)
                .font(.system(size: 50))
                .foregroundColor(.gray.opacity(0.5))

            Text(title)
                .font(.headline)
                .foregroundColor(.primary)

            if let message = message {
                Text(message)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }

            if let buttonTitle = buttonTitle, let action = action {
                Button(action: action) {
                    Text(buttonTitle)
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundColor(.white)
                        .padding(.horizontal, 24)
                        .padding(.vertical, 12)
                        .background(Color.appPrimary)
                        .cornerRadius(10)
                }
                .padding(.top, 8)
            }
        }
        .padding(32)
    }
}

// MARK: - Presets

extension EmptyStateView {
    static func noPatients(action: @escaping () -> Void) -> EmptyStateView {
        EmptyStateView(
            icon: "person.2.slash",
            title: "Nenhum paciente",
            message: "Cadastre seu primeiro paciente para começar",
            buttonTitle: "Adicionar Paciente",
            action: action
        )
    }

    static func noAppointments(action: @escaping () -> Void) -> EmptyStateView {
        EmptyStateView(
            icon: "calendar.badge.exclamationmark",
            title: "Sem agendamentos",
            message: "Nenhum agendamento para este dia",
            buttonTitle: "Novo Agendamento",
            action: action
        )
    }

    static func noResults(query: String) -> EmptyStateView {
        EmptyStateView(
            icon: "magnifyingglass",
            title: "Nenhum resultado",
            message: "Não encontramos resultados para \"\(query)\""
        )
    }

    static func error(message: String, action: @escaping () -> Void) -> EmptyStateView {
        EmptyStateView(
            icon: "exclamationmark.triangle",
            title: "Erro",
            message: message,
            buttonTitle: "Tentar novamente",
            action: action
        )
    }
}

#Preview {
    VStack(spacing: 40) {
        EmptyStateView.noPatients {}
        EmptyStateView.noResults(query: "João")
    }
}
