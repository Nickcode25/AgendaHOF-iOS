import SwiftUI

// MARK: - Logout Section

/// Seção de logout no SettingsView
/// Exibe botão destrutivo para sair da conta
struct LogoutSection: View {

    // MARK: - Properties

    let onLogout: () -> Void

    // MARK: - Body

    var body: some View {
        Section {
            Button(role: .destructive) {
                onLogout()
            } label: {
                HStack {
                    Spacer()
                    Text("Sair da Conta")
                        .fontWeight(.medium)
                    Spacer()
                }
            }
        }
    }
}

// MARK: - Preview

#Preview {
    List {
        LogoutSection(onLogout: {
            print("Logout tapped")
        })
    }
}
