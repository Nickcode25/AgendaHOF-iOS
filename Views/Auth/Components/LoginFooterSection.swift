import SwiftUI

// MARK: - Login Footer Section

/// Seção de footer do login com link para criação de conta
/// Componente reutilizável para navegação entre login e signup
struct LoginFooterSection: View {

    // MARK: - Properties

    let onSignUpTap: () -> Void

    // MARK: - Body

    var body: some View {
        HStack(spacing: 4) {
            Text("Não tem uma conta?")
                .font(.system(size: 14, weight: .regular))
                .foregroundStyle(.secondary)

            Button {
                onSignUpTap()
            } label: {
                Text("Criar conta")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Constants.primaryColor)
            }
        }
    }
}

// MARK: - Preview

#Preview {
    VStack(spacing: 20) {
        LoginFooterSection {
            print("Sign up tapped")
        }

        Divider()

        LoginFooterSection {
            print("Sign up tapped")
        }
        .preferredColorScheme(.dark)
    }
    .padding()
}
