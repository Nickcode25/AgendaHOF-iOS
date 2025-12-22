import SwiftUI

struct SignUpView: View {
    @Environment(\.dismiss) var dismiss
    @Environment(\.colorScheme) var colorScheme
    @StateObject private var viewModel = AuthViewModel()
    @State private var acceptedTerms = false

    // Animação de entrada
    @State private var isAppearing = false

    var body: some View {
        NavigationStack {
            GeometryReader { geometry in
                ScrollView {
                    VStack(spacing: 0) {
                        Spacer(minLength: geometry.size.height * 0.06)

                        // Conteúdo principal
                        VStack(spacing: 40) {
                            // Header
                            headerSection

                            // Formulário
                            formSection

                            // Footer
                            footerSection
                        }
                        .padding(.horizontal, 32)

                        Spacer(minLength: 40)
                    }
                    .frame(minHeight: geometry.size.height)
                }
                .scrollDismissesKeyboard(.interactively)
            }
            .background(Color(.systemBackground))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(.secondary)
                            .frame(width: 30, height: 30)
                            .background(Color(.systemGray6))
                            .clipShape(Circle())
                    }
                }
            }
            .onAppear {
#if DEBUG
                print("SignUpView onAppear from:", #file)
#endif
                withAnimation(.easeOut(duration: 0.6)) {
                    isAppearing = true
                }
            }
        }
        .alert("Conta criada", isPresented: $viewModel.showSuccess) {
            Button("OK") {
                dismiss()
            }
        } message: {
            Text(viewModel.successMessage ?? "Verifique seu email para confirmar a conta.")
        }
        .alert("Erro", isPresented: $viewModel.showError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(viewModel.errorMessage ?? "Erro desconhecido")
        }
    }

    // MARK: - Header Section

    private var headerSection: some View {
        VStack(spacing: 16) {
            // Logo (adapta ao modo claro/escuro)
            let logoURL = colorScheme == .dark
                ? "https://AgendaHOF.b-cdn.net/logo-light.png"
                : "https://AgendaHOF.b-cdn.net/logo-dark.png"

            AsyncImage(url: URL(string: logoURL)) { phase in
                if let image = phase.image {
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                } else if phase.error != nil {
                    Image(systemName: "stethoscope")
                        .font(.system(size: 48, weight: .light))
                        .foregroundStyle(.primary.opacity(0.3))
                } else {
                    ProgressView()
                }
            }
            .frame(height: 80)

            // Título
            Text("Criar conta")
                .font(.system(size: 28, weight: .semibold))
                .foregroundStyle(.primary)

            // Subtítulo
            Text("Preencha seus dados para começar")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .opacity(isAppearing ? 1 : 0)
        .offset(y: isAppearing ? 0 : 20)
    }

    // MARK: - Form Section

    private var formSection: some View {
        VStack(spacing: 20) {
            // Campo Nome
            VStack(alignment: .leading, spacing: 8) {
                Text("Nome completo *")
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundStyle(.primary)

                TextField("Seu nome completo", text: $viewModel.name)
                    .textContentType(.name)
                    .autocapitalization(.words)
                    .foregroundStyle(.primary)
                    .tint(Color(hex: "ff6b00"))
                    .padding(.horizontal, 16)
                    .padding(.vertical, 14)
                    .background(Color(.systemGray6))
                    .cornerRadius(10)
            }

            // Campo Email
            VStack(alignment: .leading, spacing: 8) {
                Text("Email *")
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundStyle(.primary)

                TextField("seu@email.com", text: $viewModel.email)
                    .textContentType(.emailAddress)
                    .keyboardType(.emailAddress)
                    .autocapitalization(.none)
                    .disableAutocorrection(true)
                    .foregroundStyle(.primary)
                    .tint(Color(hex: "ff6b00"))
                    .padding(.horizontal, 16)
                    .padding(.vertical, 14)
                    .background(Color(.systemGray6))
                    .cornerRadius(10)
            }

            // Campo Telefone
            VStack(alignment: .leading, spacing: 8) {
                Text("Telefone *")
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundStyle(.primary)

                TextField("(00) 00000-0000", text: $viewModel.phone)
                    .textContentType(.telephoneNumber)
                    .keyboardType(.phonePad)
                    .foregroundStyle(.primary)
                    .tint(Color(hex: "ff6b00"))
                    .padding(.horizontal, 16)
                    .padding(.vertical, 14)
                    .background(Color(.systemGray6))
                    .cornerRadius(10)
                    .onChange(of: viewModel.phone) { _, newValue in
                        viewModel.phone = formatPhoneBrazil(newValue)
                    }
            }

            // Campo Senha
            VStack(alignment: .leading, spacing: 8) {
                Text("Senha *")
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundStyle(.primary)

                HStack {
                    if viewModel.showPassword {
                        TextField("Digite sua senha", text: $viewModel.password)
                            .textContentType(.newPassword)
                            .foregroundStyle(.primary)
                            .tint(Color(hex: "ff6b00"))
                    } else {
                        SecureField("Digite sua senha", text: $viewModel.password)
                            .textContentType(.newPassword)
                            .foregroundStyle(.primary)
                            .tint(Color(hex: "ff6b00"))
                    }

                    Button {
                        viewModel.showPassword.toggle()
                    } label: {
                        Image(systemName: viewModel.showPassword ? "eye.slash" : "eye")
                            .foregroundStyle(.tertiary)
                            .font(.system(size: 16))
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
                .background(Color(.systemGray6))
                .cornerRadius(10)

                // Requisitos da senha
                VStack(alignment: .leading, spacing: 4) {
                    Text("A senha deve conter:")
                        .font(.caption2)
                        .foregroundStyle(.secondary)

                    HStack(spacing: 6) {
                        Image(systemName: hasMinimumLength ? "checkmark.circle.fill" : "circle")
                            .font(.caption2)
                            .foregroundStyle(hasMinimumLength ? .green : .secondary)
                        Text("Mínimo 8 caracteres")
                            .font(.caption2)
                            .foregroundStyle(hasMinimumLength ? .green : .secondary)
                    }

                    HStack(spacing: 6) {
                        Image(systemName: hasUppercase ? "checkmark.circle.fill" : "circle")
                            .font(.caption2)
                            .foregroundStyle(hasUppercase ? .green : .secondary)
                        Text("Letra maiúscula (A-Z)")
                            .font(.caption2)
                            .foregroundStyle(hasUppercase ? .green : .secondary)
                    }

                    HStack(spacing: 6) {
                        Image(systemName: hasLowercase ? "checkmark.circle.fill" : "circle")
                            .font(.caption2)
                            .foregroundStyle(hasLowercase ? .green : .secondary)
                        Text("Letra minúscula (a-z)")
                            .font(.caption2)
                            .foregroundStyle(hasLowercase ? .green : .secondary)
                    }

                    HStack(spacing: 6) {
                        Image(systemName: hasNumber ? "checkmark.circle.fill" : "circle")
                            .font(.caption2)
                            .foregroundStyle(hasNumber ? .green : .secondary)
                        Text("Número (0-9)")
                            .font(.caption2)
                            .foregroundStyle(hasNumber ? .green : .secondary)
                    }

                    HStack(spacing: 6) {
                        Image(systemName: hasSpecialChar ? "checkmark.circle.fill" : "circle")
                            .font(.caption2)
                            .foregroundStyle(hasSpecialChar ? .green : .secondary)
                        Text("Caractere especial (!@#$...)")
                            .font(.caption2)
                            .foregroundStyle(hasSpecialChar ? .green : .secondary)
                    }
                }
                .padding(.leading, 4)
            }

            // Campo Confirmar Senha
            VStack(alignment: .leading, spacing: 8) {
                Text("Confirmar senha *")
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundStyle(.primary)

                SecureField("Digite novamente", text: $viewModel.confirmPassword)
                    .textContentType(.newPassword)
                    .foregroundStyle(.primary)
                    .tint(Color(hex: "ff6b00"))
                    .padding(.horizontal, 16)
                    .padding(.vertical, 14)
                    .background(Color(.systemGray6))
                    .cornerRadius(10)

                // Indicador de senhas iguais
                if !viewModel.confirmPassword.isEmpty {
                    HStack(spacing: 6) {
                        Image(systemName: passwordsMatch ? "checkmark.circle.fill" : "xmark.circle.fill")
                            .font(.caption2)
                            .foregroundStyle(passwordsMatch ? .green : .red)
                        Text(passwordsMatch ? "As senhas coincidem" : "As senhas não coincidem")
                            .font(.caption2)
                            .foregroundStyle(passwordsMatch ? .green : .red)
                    }
                    .padding(.leading, 4)
                }
            }

            // Termos de uso
            Button {
                acceptedTerms.toggle()
            } label: {
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: acceptedTerms ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 20))
                        .foregroundStyle(acceptedTerms ? .primary : .tertiary)

                    Text("Li e aceito os Termos de Uso e Política de Privacidade")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.leading)
                }
            }
            .padding(.top, 4)

            // Botão Criar Conta
            Button {
                let impactFeedback = UIImpactFeedbackGenerator(style: .medium)
                impactFeedback.impactOccurred()

                Task {
                    await viewModel.signUp()
                }
            } label: {
                HStack(spacing: 8) {
                    if viewModel.isLoading {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: .white))
                    } else {
                        Text("Criar conta")
                            .fontWeight(.semibold)
                    }
                }
                .frame(maxWidth: .infinity)
                .frame(height: 52)
                .background(.black)
                .foregroundColor(.white)
                .cornerRadius(12)
            }
            .disabled(viewModel.isLoading || !isFormValid)
            .opacity(isFormValid ? 1 : 0.6)
            .padding(.top, 8)
        }
        .opacity(isAppearing ? 1 : 0)
        .offset(y: isAppearing ? 0 : 20)
        .animation(.easeOut(duration: 0.6).delay(0.1), value: isAppearing)
    }

    // MARK: - Footer Section

    private var footerSection: some View {
        HStack(spacing: 4) {
            Text("Já tem uma conta?")
                .foregroundStyle(.secondary)

            Button {
                dismiss()
            } label: {
                Text("Entrar")
                    .fontWeight(.medium)
                    .foregroundStyle(.primary)
            }
        }
        .font(.subheadline)
        .opacity(isAppearing ? 1 : 0)
        .animation(.easeOut(duration: 0.6).delay(0.2), value: isAppearing)
    }

    // MARK: - Helpers

    private var isFormValid: Bool {
        !viewModel.name.isEmpty &&
        !viewModel.email.isEmpty &&
        !viewModel.phone.isEmpty &&
        !viewModel.password.isEmpty &&
        !viewModel.confirmPassword.isEmpty &&
        viewModel.password == viewModel.confirmPassword &&
        viewModel.password.count >= 8 &&
        acceptedTerms
    }

    // Validações de senha em tempo real
    private var hasMinimumLength: Bool {
        viewModel.password.count >= 8
    }

    private var hasUppercase: Bool {
        viewModel.password.range(of: "[A-Z]", options: .regularExpression) != nil
    }

    private var hasLowercase: Bool {
        viewModel.password.range(of: "[a-z]", options: .regularExpression) != nil
    }

    private var hasNumber: Bool {
        viewModel.password.range(of: "[0-9]", options: .regularExpression) != nil
    }

    private var hasSpecialChar: Bool {
        viewModel.password.range(of: "[!@#$%^&*(),.?\":{}|<>]", options: .regularExpression) != nil
    }

    private var passwordsMatch: Bool {
        !viewModel.password.isEmpty && viewModel.password == viewModel.confirmPassword
    }

    // Formata telefone no padrão brasileiro (XX) XXXXX-XXXX
    private func formatPhoneBrazil(_ value: String) -> String {
        let numbers = value.filter { $0.isNumber }
        var result = ""

        for (index, char) in numbers.prefix(11).enumerated() {
            if index == 0 {
                result += "("
            }
            if index == 2 {
                result += ") "
            }
            if numbers.count <= 10 && index == 6 {
                result += "-"
            } else if numbers.count == 11 && index == 7 {
                result += "-"
            }
            result += String(char)
        }

        return result
    }
}

#Preview {
    SignUpView()
}
