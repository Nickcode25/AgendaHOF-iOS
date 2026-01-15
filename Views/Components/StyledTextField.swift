import SwiftUI

// MARK: - Styled Text Field

/// Campo de texto estilizado seguindo o padrão visual do Agenda HOF
/// Componente reutilizável para todos os formulários do app
struct StyledTextField: View {

    // MARK: - Properties

    let title: String
    let placeholder: String
    @Binding var text: String

    var keyboardType: UIKeyboardType = .default
    var textContentType: UITextContentType? = nil
    var autocapitalization: TextInputAutocapitalization = .sentences
    var isSecure: Bool = false
    var showVisibilityToggle: Bool = false
    var trailingContent: (() -> AnyView)? = nil
    var errorMessage: String? = nil

    // MARK: - State

    @State private var showPassword = false

    // MARK: - Body

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Label
            if !title.isEmpty {
                Text(title)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.secondary)
            }

            // Campo de input
            HStack(spacing: 12) {
                inputField
                    .foregroundStyle(.primary)
                    .tint(Constants.primaryColor)

                // Trailing content (botão mostrar senha, etc)
                if showVisibilityToggle && isSecure {
                    visibilityToggleButton
                } else if let trailingContent = trailingContent {
                    trailingContent()
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 15)
            .background(fieldBackground)

            // Error message
            if let error = errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundColor(.red)
            }
        }
    }

    // MARK: - Input Field

    @ViewBuilder
    private var inputField: some View {
        if isSecure && !showPassword {
            SecureField(placeholder, text: $text)
                .textContentType(textContentType)
        } else {
            TextField(placeholder, text: $text)
                .keyboardType(keyboardType)
                .textContentType(textContentType)
                .textInputAutocapitalization(autocapitalization)
                .disableAutocorrection(keyboardType == .emailAddress)
        }
    }

    // MARK: - Field Background

    private var fieldBackground: some View {
        RoundedRectangle(cornerRadius: 12)
            .fill(Color(.systemBackground))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(
                        errorMessage != nil ? Color.red : Color(.systemGray4),
                        lineWidth: 1
                    )
            )
    }

    // MARK: - Visibility Toggle Button

    private var visibilityToggleButton: some View {
        Button {
            showPassword.toggle()
        } label: {
            Image(systemName: showPassword ? "eye.slash.fill" : "eye.fill")
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(.secondary.opacity(0.6))
                .frame(width: 24, height: 24)
        }
    }
}

// MARK: - Convenience Initializers

extension StyledTextField {

    /// Campo de email
    static func email(
        title: String = "Email",
        placeholder: String = "seu@email.com",
        text: Binding<String>,
        errorMessage: String? = nil
    ) -> StyledTextField {
        StyledTextField(
            title: title,
            placeholder: placeholder,
            text: text,
            keyboardType: .emailAddress,
            textContentType: .username,
            autocapitalization: .never,
            errorMessage: errorMessage
        )
    }

    /// Campo de senha
    static func password(
        title: String = "Senha",
        placeholder: String = "Digite sua senha",
        text: Binding<String>,
        showVisibilityToggle: Bool = true,
        errorMessage: String? = nil
    ) -> StyledTextField {
        StyledTextField(
            title: title,
            placeholder: placeholder,
            text: text,
            textContentType: .password,
            isSecure: true,
            showVisibilityToggle: showVisibilityToggle,
            errorMessage: errorMessage
        )
    }

    /// Campo de telefone
    static func phone(
        title: String = "Telefone",
        placeholder: String = "(00) 00000-0000",
        text: Binding<String>,
        errorMessage: String? = nil
    ) -> StyledTextField {
        StyledTextField(
            title: title,
            placeholder: placeholder,
            text: text,
            keyboardType: .phonePad,
            textContentType: .telephoneNumber,
            errorMessage: errorMessage
        )
    }

    /// Campo de nome
    static func name(
        title: String = "Nome",
        placeholder: String = "Seu nome completo",
        text: Binding<String>,
        errorMessage: String? = nil
    ) -> StyledTextField {
        StyledTextField(
            title: title,
            placeholder: placeholder,
            text: text,
            textContentType: .name,
            autocapitalization: .words,
            errorMessage: errorMessage
        )
    }
}

// MARK: - Preview

#Preview {
    VStack(spacing: 20) {
        // Email
        StyledTextField.email(text: .constant("teste@email.com"))

        // Email com erro
        StyledTextField.email(
            text: .constant("email-invalido"),
            errorMessage: "Email inválido"
        )

        // Senha
        StyledTextField.password(text: .constant("senha123"))

        // Telefone
        StyledTextField.phone(text: .constant("11999999999"))

        // Nome
        StyledTextField.name(text: .constant("João Silva"))

        // Campo customizado
        StyledTextField(
            title: "CPF",
            placeholder: "000.000.000-00",
            text: .constant(""),
            keyboardType: .numberPad
        )
    }
    .padding()
    .background(Color(.systemGroupedBackground))
}
