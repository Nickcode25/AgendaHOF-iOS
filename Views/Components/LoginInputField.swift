import SwiftUI

/// Campo de entrada minimalista para telas de autenticação
struct LoginInputField: View {
    let label: String
    let placeholder: String
    @Binding var text: String
    var isSecure: Bool = false
    var keyboardType: UIKeyboardType = .default
    var showVisibilityToggle: Bool = false
    @Binding var isPasswordVisible: Bool
    var trailingAction: (() -> Void)? = nil
    var trailingActionLabel: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Label + Trailing action (ex: "Esqueceu a senha?")
            HStack(alignment: .center, spacing: 0) {
                Text(label)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.secondary)

                if let action = trailingAction, let actionLabel = trailingActionLabel {
                    Spacer()
                    Button(action: action) {
                        Text(actionLabel)
                            .font(.system(size: 13, weight: .regular))
                            .foregroundStyle(.secondary)
                    }
                }
            }

            // Campo de entrada
            HStack(spacing: 12) {
                Group {
                    if isSecure && !isPasswordVisible {
                        SecureField(placeholder, text: $text)
                    } else {
                        TextField(placeholder, text: $text)
                            .keyboardType(keyboardType)
                            .autocapitalization(.none)
                            .disableAutocorrection(true)
                    }
                }
                .foregroundStyle(.primary)
                .tint(.primary)

                // Botão de visibilidade da senha
                if showVisibilityToggle {
                    Button {
                        isPasswordVisible.toggle()
                    } label: {
                        Image(systemName: isPasswordVisible ? "eye.slash.fill" : "eye.fill")
                            .font(.system(size: 15, weight: .regular))
                            .foregroundStyle(.quaternary)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 15)
            .background(Color(.systemGray6))
            .cornerRadius(12)
        }
    }
}

// MARK: - Binding wrapper para usar sem password toggle

extension LoginInputField {
    init(
        label: String,
        placeholder: String,
        text: Binding<String>,
        isSecure: Bool = false,
        keyboardType: UIKeyboardType = .default,
        trailingAction: (() -> Void)? = nil,
        trailingActionLabel: String? = nil
    ) {
        self.label = label
        self.placeholder = placeholder
        self._text = text
        self.isSecure = isSecure
        self.keyboardType = keyboardType
        self.showVisibilityToggle = false
        self._isPasswordVisible = .constant(false)
        self.trailingAction = trailingAction
        self.trailingActionLabel = trailingActionLabel
    }
}

// MARK: - Preview

#Preview {
    VStack(spacing: 24) {
        LoginInputField(
            label: "Email",
            placeholder: "seu@email.com",
            text: .constant(""),
            keyboardType: .emailAddress
        )

        LoginInputField(
            label: "Senha",
            placeholder: "Digite sua senha",
            text: .constant(""),
            isSecure: true,
            showVisibilityToggle: true,
            isPasswordVisible: .constant(false),
            trailingAction: {},
            trailingActionLabel: "Esqueceu?"
        )
    }
    .padding(24)
}
