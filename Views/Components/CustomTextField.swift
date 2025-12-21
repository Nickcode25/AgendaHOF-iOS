import SwiftUI

/// TextField customizado com estilo consistente para todo o app
/// Corrige o problema do campo de email ficar azul no iOS
struct CustomTextField: View {
    let title: String
    let placeholder: String
    @Binding var text: String
    var isSecure: Bool = false
    var keyboardType: UIKeyboardType = .default
    var textContentType: UITextContentType? = nil
    var autocapitalizationType: UITextAutocapitalizationType = .none
    var autocorrectionDisabled: Bool = true
    var trailingButton: (() -> AnyView)? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.subheadline)
                .fontWeight(.medium)
                .foregroundStyle(.primary)

            HStack(spacing: 12) {
                if isSecure {
                    SecureField(placeholder, text: $text)
                        .textFieldStyle()
                } else {
                    TextField(placeholder, text: $text)
                        .textFieldStyle()
                        .keyboardType(keyboardType)
                        .autocapitalization(autocapitalizationType)
                        .disableAutocorrection(autocorrectionDisabled)
                        // ✅ SOLUÇÃO: Aplicar textContentType apenas se fornecido
                        .if(textContentType != nil) { view in
                            view.textContentType(textContentType)
                        }
                        // ✅ SOLUÇÃO: Forçar cor primária para evitar azul do sistema
                        .foregroundStyle(.primary)
                        // ✅ SOLUÇÃO: Desabilitar detecção de links
                        .tint(.primary)
                }

                if let trailingButton = trailingButton {
                    trailingButton()
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .background(Color(.systemGray6))
            .cornerRadius(10)
            // ✅ SOLUÇÃO: Aplicar accentColor para controlar cor de seleção
            .accentColor(.primary)
        }
    }
}

// MARK: - TextField Style Extension

private extension TextField {
    func textFieldStyle() -> some View {
        self
            // ✅ Força cor do texto para primária (não azul)
            .foregroundStyle(.primary)
            // ✅ Controla cor do cursor/tint
            .tint(.primary)
    }
}

private extension SecureField {
    func textFieldStyle() -> some View {
        self
            // ✅ Força cor do texto para primária
            .foregroundStyle(.primary)
            // ✅ Controla cor do cursor/tint
            .tint(.primary)
    }
}

// MARK: - View Extension para conditional modifier

extension View {
    @ViewBuilder
    func `if`<Transform: View>(_ condition: Bool, transform: (Self) -> Transform) -> some View {
        if condition {
            transform(self)
        } else {
            self
        }
    }
}

// MARK: - Preview

#Preview {
    VStack(spacing: 20) {
        CustomTextField(
            title: "Email",
            placeholder: "seu@email.com",
            text: .constant("teste@email.com"),
            keyboardType: .emailAddress,
            textContentType: .emailAddress
        )

        CustomTextField(
            title: "Nome",
            placeholder: "Seu nome",
            text: .constant("João Silva"),
            textContentType: .name,
            autocapitalizationType: .words
        )

        CustomTextField(
            title: "Senha",
            placeholder: "Digite sua senha",
            text: .constant(""),
            isSecure: true
        )
    }
    .padding()
}
