import SwiftUI

// MARK: - Login Form Section

/// Formulário de login com campos de email, senha e botão de entrar
/// Componente modular que pode ser reutilizado em diferentes contextos
struct LoginFormSection: View {

    // MARK: - Bindings

    @Binding var email: String
    @Binding var password: String
    @Binding var rememberMe: Bool
    @State private var showPassword = false

    // MARK: - Actions

    let onLogin: () -> Void
    let onForgotPassword: () -> Void
    let isLoading: Bool

    // MARK: - Body

    var body: some View {
        VStack(spacing: 16) {
            // Campo Email
            emailField

            // Campo Senha
            passwordField

            // Remember Me
            rememberMeToggle

            // Botão Entrar
            loginButton
        }
    }

    // MARK: - Email Field

    private var emailField: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Email")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.secondary)

            TextField("seu@email.com", text: $email)
                .textContentType(.username)
                .keyboardType(.emailAddress)
                .autocapitalization(.none)
                .disableAutocorrection(true)
                .foregroundStyle(.primary)
                .tint(Constants.primaryColor)
                .padding(.horizontal, 16)
                .padding(.vertical, 15)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color(.systemBackground))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(Color(.systemGray4), lineWidth: 1)
                        )
                )
        }
    }

    // MARK: - Password Field

    private var passwordField: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Label com botão "Esqueceu?"
            HStack(alignment: .center, spacing: 0) {
                Text("Senha")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.secondary)

                Spacer()

                Button {
                    onForgotPassword()
                } label: {
                    Text("Esqueceu?")
                        .font(.system(size: 13, weight: .regular))
                        .foregroundStyle(.secondary)
                }
            }

            // Campo de senha com toggle de visibilidade
            HStack(spacing: 12) {
                Group {
                    if showPassword {
                        TextField("Digite sua senha", text: $password)
                            .textContentType(.password)
                    } else {
                        SecureField("Digite sua senha", text: $password)
                            .textContentType(.password)
                    }
                }
                .foregroundStyle(.primary)
                .tint(Constants.primaryColor)

                // Botão mostrar/ocultar senha
                Button {
                    showPassword.toggle()
                } label: {
                    Image(systemName: showPassword ? "eye.slash.fill" : "eye.fill")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(.secondary.opacity(0.6))
                        .frame(width: 24, height: 24)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 15)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color(.systemBackground))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color(.systemGray4), lineWidth: 1)
                    )
            )
        }
    }

    // MARK: - Remember Me Toggle

    private var rememberMeToggle: some View {
        HStack(spacing: 8) {
            Button {
                rememberMe.toggle()
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: rememberMe ? "checkmark.square.fill" : "square")
                        .font(.system(size: 20, weight: .regular))
                        .foregroundStyle(rememberMe ? Constants.primaryColor : Color(.systemGray3))

                    Text("Lembrar-me")
                        .font(.system(size: 14, weight: .regular))
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()
        }
    }

    // MARK: - Login Button

    private var loginButton: some View {
        Button {
            onLogin()
        } label: {
            HStack(spacing: 8) {
                if isLoading {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                        .scaleEffect(0.9)
                } else {
                    Text("Entrar")
                        .font(.system(size: 16, weight: .semibold))
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(Constants.primaryColor)
            .foregroundColor(.white)
            .cornerRadius(12)
        }
        .disabled(isLoading || email.isEmpty || password.isEmpty)
        .opacity((isLoading || email.isEmpty || password.isEmpty) ? 0.6 : 1.0)
    }
}

// MARK: - Preview

#Preview {
    VStack {
        LoginFormSection(
            email: .constant("teste@email.com"),
            password: .constant("senha123"),
            rememberMe: .constant(true),
            onLogin: { print("Login") },
            onForgotPassword: { print("Forgot") },
            isLoading: false
        )

        LoginFormSection(
            email: .constant(""),
            password: .constant(""),
            rememberMe: .constant(false),
            onLogin: { print("Login") },
            onForgotPassword: { print("Forgot") },
            isLoading: true
        )
    }
    .padding()
    .background(Color(.systemGroupedBackground))
}
