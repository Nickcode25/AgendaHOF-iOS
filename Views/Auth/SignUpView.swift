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
            ZStack {
                // Background Midnight Fire
                LinearGradient(
                    gradient: Gradient(colors: [
                        Color(red: 0.04, green: 0.04, blue: 0.04),
                        Color(red: 0.12, green: 0.07, blue: 0.03),
                        Color(red: 0.98, green: 0.45, blue: 0.09)
                    ]),
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 0) {
                        // Header
                        headerSection
                            .padding(.top, 40)
                            .padding(.bottom, 32)

                        // Formulário
                        formSection
                            .padding(.horizontal, 24)

                        // Footer (Already has account)
                        footerSection
                            .padding(.vertical, 32)
                    }
                }
                .scrollDismissesKeyboard(.interactively)
            }
            .navigationBarBackButtonHidden(true)

            .navigationBarHidden(true)
            .onAppear {
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
        .preferredColorScheme(.dark)
    }

    // MARK: - Header Section

    private var headerSection: some View {
        VStack(spacing: 16) {
            // Logo Original
            AsyncImage(url: URL(string: "https://AgendaHOF.b-cdn.net/logo-light.png")) { phase in
                if let image = phase.image {
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                } else if phase.error != nil {
                    Image(systemName: "stethoscope")
                        .font(.system(size: 60, weight: .light))
                        .foregroundStyle(.white)
                } else {
                    ProgressView()
                        .tint(.white)
                }
            }
            .frame(height: 120)
            .padding(.bottom, 8)

            VStack(spacing: 4) {
                Text("Criar conta")
                    .font(.system(size: 24, weight: .bold))
                    .foregroundColor(.white)
                
                Text("Preencha seus dados para começar")
                    .font(.system(size: 14))
                    .foregroundColor(.white.opacity(0.6))
            }
        }
        .opacity(isAppearing ? 1 : 0)
        .offset(y: isAppearing ? 0 : 20)
    }

    // MARK: - Form Section

    private var formSection: some View {
        VStack(spacing: 20) {
            
            // Campo Nome Completo
            buildInputGroup(label: "Nome completo", required: true) {
                HStack(spacing: 12) {
                    Image(systemName: "person.fill")
                        .foregroundColor(.orange.opacity(0.7))
                        .frame(width: 20)
                    
                    TextField("Seu nome completo", text: $viewModel.name)
                        .textContentType(.name)
                        .autocapitalization(.words)
                        .foregroundColor(.white)
                }
            }
            
            // Campo Nome Profissional
            VStack(alignment: .leading, spacing: 8) {
                Text("Nome Profissional")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.white.opacity(0.9))
                
                HStack(spacing: 12) {
                    Image(systemName: "briefcase.fill")
                        .foregroundColor(.orange.opacity(0.7))
                        .frame(width: 20)
                    
                    TextField("Ex: Dra. Mariana Vargas", text: $viewModel.professionalName)
                        .textInputAutocapitalization(.words)
                        .foregroundColor(.white)
                }
                .padding(14)
                .background(Color.white.opacity(0.08))
                .cornerRadius(12)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.white.opacity(0.15), lineWidth: 1)
                )
                
                Text("Opcional - Como você deseja ser identificado(a) no sistema")
                    .font(.system(size: 12))
                    .foregroundColor(.white.opacity(0.5))
            }

            // Campo Email
            buildInputGroup(label: "Email", required: true) {
                HStack(spacing: 12) {
                    Image(systemName: "envelope.fill")
                        .foregroundColor(.orange.opacity(0.7))
                        .frame(width: 20)
                    
                    TextField("Digite seu email", text: $viewModel.email)
                        .textContentType(.emailAddress)
                        .keyboardType(.emailAddress)
                        .autocapitalization(.none)
                        .foregroundColor(.white)
                }
            }
            
            // Campo Confirmar Email
            buildInputGroup(label: "Confirme seu Email", required: true) {
                HStack(spacing: 12) {
                    Image(systemName: "envelope.fill")
                        .foregroundColor(.orange.opacity(0.7))
                        .frame(width: 20)
                    
                    TextField("Digite o email novamente", text: $viewModel.confirmEmail)
                        .textContentType(.emailAddress)
                        .keyboardType(.emailAddress)
                        .autocapitalization(.none)
                        .foregroundColor(.white)
                }
            }

            // Campo Telefone
            buildInputGroup(label: "Telefone", required: true) {
                HStack(spacing: 12) {
                    Image(systemName: "phone.fill")
                        .foregroundColor(.orange.opacity(0.7))
                        .frame(width: 20)
                    
                    TextField("(00) 00000-0000", text: $viewModel.phone)
                        .textContentType(.telephoneNumber)
                        .keyboardType(.phonePad)
                        .foregroundColor(.white)
                        .onChange(of: viewModel.phone) { _, newValue in
                            viewModel.phone = formatPhoneBrazil(newValue)
                        }
                }
            }
            
            // Campo Senha
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Senha")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.white.opacity(0.9))
                    Text("*")
                        .foregroundColor(.orange)
                }
                
                HStack(spacing: 12) {
                    Image(systemName: "lock.fill")
                        .foregroundColor(.orange.opacity(0.7))
                        .frame(width: 20)
                    
                    if viewModel.showPassword {
                        TextField("Digite sua senha", text: $viewModel.password)
                            .textContentType(.newPassword)
                            .foregroundColor(.white)
                    } else {
                        SecureField("Digite sua senha", text: $viewModel.password)
                            .textContentType(.newPassword)
                            .foregroundColor(.white)
                    }
                    
                    Button {
                        viewModel.showPassword.toggle()
                    } label: {
                        Image(systemName: viewModel.showPassword ? "eye.fill" : "eye.slash.fill")
                            .foregroundColor(.white.opacity(0.5))
                    }
                }
                .padding(14)
                .background(Color.white.opacity(0.08))
                .cornerRadius(12)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.white.opacity(0.15), lineWidth: 1)
                )
                
                // Requisitos de Senha
                VStack(alignment: .leading, spacing: 4) {
                    Text("A senha deve conter:")
                        .font(.system(size: 13))
                        .foregroundColor(.white.opacity(0.7))
                        .padding(.bottom, 4)
                    
                    Group {
                        requirementRow(isValid: hasMinimumLength, text: "Mínimo 8 caracteres")
                        requirementRow(isValid: hasUppercase, text: "Letra maiúscula (A-Z)")
                        requirementRow(isValid: hasLowercase, text: "Letra minúscula (a-z)")
                        requirementRow(isValid: hasNumber, text: "Número (0-9)")
                        requirementRow(isValid: hasSpecialChar, text: "Caractere especial (!@#$...)")
                    }
                }
                .padding(12)
                .background(Color.white.opacity(0.05))
                .cornerRadius(10)
                .padding(.top, 4)
            }
            
            // Campo Confirmar Senha
            buildInputGroup(label: "Confirmar senha", required: true) {
                HStack(spacing: 12) {
                    Image(systemName: "lock.fill")
                        .foregroundColor(.orange.opacity(0.7))
                        .frame(width: 20)
                    
                    SecureField("Digite novamente", text: $viewModel.confirmPassword)
                        .textContentType(.newPassword)
                        .foregroundColor(.white)
                    
                    // Toggle for confirm password visibility isn't in viewmodel, assuming just hidden or linked to same logic? 
                    // To match reference image which has eye icon for confirm, we could add local state, but viewmodel doesn't have it.
                    // Sticking to standard SecureField for simplicity or adding local state if pivotal.
                    // Reference image has eye icon on confirm password too.
                    // For now, let's keep it simple without extra state unless requested.
                }
            }

            // Checkbox Termos
            Button(action: {
                withAnimation(.easeInOut(duration: 0.2)) {
                    acceptedTerms.toggle()
                }
            }) {
                HStack(alignment: .top, spacing: 12) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(Color.white.opacity(0.3), lineWidth: 2)
                            .frame(width: 24, height: 24)
                            .background(acceptedTerms ? Color.orange : Color.white.opacity(0.05))
                            .cornerRadius(6)
                        
                        if acceptedTerms {
                            Image(systemName: "checkmark")
                                .font(.system(size: 14, weight: .bold))
                                .foregroundColor(.white)
                        }
                    }
                    .frame(width: 24, height: 24)
                    
                    Text("Li e aceito os Termos de Uso e Política de Privacidade")
                        .font(.system(size: 13))
                        .foregroundColor(.white.opacity(0.7))
                        .multilineTextAlignment(.leading)
                }
            }
            .padding(.top, 8)

            // Botão Criar Conta
            Button {
                let impactFeedback = UIImpactFeedbackGenerator(style: .medium)
                impactFeedback.impactOccurred()
                Task {
                    await viewModel.signUp()
                }
            } label: {
                HStack(spacing: 10) {
                    if viewModel.isLoading {
                        ProgressView()
                            .tint(.black)
                    } else {
                        Text("Criar conta")
                            .font(.system(size: 17, weight: .semibold))
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(
                    LinearGradient(
                        gradient: Gradient(colors: [
                            Color.orange,
                            Color(red: 1.0, green: 0.6, blue: 0.2)
                        ]),
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .foregroundColor(.black)
                .cornerRadius(12)
                .shadow(color: Color.orange.opacity(0.4), radius: 10, y: 5)
            }
            .disabled(viewModel.isLoading || !isFormValid)
            .opacity(isFormValid ? 1 : 0.5) // Dim opacity when disabled based on validity
            .animation(.easeInOut(duration: 0.2), value: isFormValid)
            .padding(.top, 16)
        }
        .opacity(isAppearing ? 1 : 0)
        .offset(y: isAppearing ? 0 : 20)
        .animation(.easeOut(duration: 0.6).delay(0.1), value: isAppearing)
    }

    // MARK: - Footer Section

    private var footerSection: some View {
        HStack(spacing: 4) {
            Text("Já tem uma conta?")
                .font(.system(size: 14))
                .foregroundColor(.white.opacity(0.7))

            Button {
                dismiss()
            } label: {
                Text("Entrar")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.orange)
            }
        }
        .opacity(isAppearing ? 1 : 0)
        .animation(.easeOut(duration: 0.6).delay(0.2), value: isAppearing)
    }

    // MARK: - Component Builders

    private func buildInputGroup<Content: View>(label: String, required: Bool = false, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 4) {
                Text(label)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.white.opacity(0.9))
                if required {
                    Text("*")
                        .foregroundColor(.orange)
                }
            }
            
            content()
                .padding(14)
                .background(Color.white.opacity(0.08))
                .cornerRadius(12)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.white.opacity(0.15), lineWidth: 1)
                )
        }
    }
    
    private func requirementRow(isValid: Bool, text: String) -> some View {
        HStack(spacing: 8) {
            Text(isValid ? "✓" : "○")
                .font(.system(size: 12, weight: .bold))
                .foregroundColor(isValid ? .green : .white.opacity(0.5))
            
            Text(text)
                .font(.system(size: 12))
                .foregroundColor(isValid ? .white.opacity(0.9) : .white.opacity(0.5))
        }
    }

    // MARK: - Helpers & Validation

    private var isFormValid: Bool {
        !viewModel.name.isEmpty &&
        isEmailValid &&
        emailsMatch &&
        isPhoneValid &&
        !viewModel.password.isEmpty &&
        !viewModel.confirmPassword.isEmpty &&
        passwordsMatch &&
        viewModel.password.count >= 8 &&
        acceptedTerms
    }
    
    // Validações em tempo real para Email
    private var isEmailValid: Bool {
        !viewModel.email.isEmpty && viewModel.email.isValidEmail
    }
    
    private var emailsMatch: Bool {
        !viewModel.email.isEmpty && !viewModel.confirmEmail.isEmpty && 
        viewModel.email.lowercased().trimmingCharacters(in: .whitespaces) == 
        viewModel.confirmEmail.lowercased().trimmingCharacters(in: .whitespaces)
    }
    
    private var isPhoneValid: Bool {
        let cleanPhone = viewModel.phone.filter { $0.isNumber }
        return cleanPhone.count >= 10 && cleanPhone.count <= 11
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

// MARK: - Preview
#Preview {
    SignUpView()
}
