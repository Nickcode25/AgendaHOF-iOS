import SwiftUI

/// Botão primário minimalista usado em telas de autenticação
struct PrimaryButton: View {
    let title: String
    let isLoading: Bool
    let isEnabled: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                if isLoading {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                        .scaleEffect(0.9)
                } else {
                    Text(title)
                        .font(.system(size: 16, weight: .semibold))
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 54)
            .foregroundColor(.white)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color(.label))
            )
        }
        .disabled(!isEnabled || isLoading)
        .opacity(isEnabled ? 1 : 0.5)
        .animation(.easeInOut(duration: 0.2), value: isEnabled)
    }
}

// MARK: - Preview

#Preview {
    VStack(spacing: 20) {
        PrimaryButton(
            title: "Entrar",
            isLoading: false,
            isEnabled: true,
            action: {}
        )

        PrimaryButton(
            title: "Entrar",
            isLoading: false,
            isEnabled: false,
            action: {}
        )

        PrimaryButton(
            title: "Carregando...",
            isLoading: true,
            isEnabled: true,
            action: {}
        )
    }
    .padding(24)
}
