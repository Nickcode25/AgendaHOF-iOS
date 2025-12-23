import SwiftUI

struct LoginView: View {
    @StateObject private var viewModel = AuthViewModel()
    @EnvironmentObject var supabase: SupabaseManager
    @Environment(\.colorScheme) var colorScheme
    @State private var showForgotPassword = false
    @State private var showSignUp = false
    @State private var showPassword = false

    // Animação de entrada
    @State private var isAppearing = false

    var body: some View {
        GeometryReader { geometry in
            ScrollView {
                VStack(spacing: 0) {
                    // Espaçamento topo adaptativo
                    Spacer()
                        .frame(height: max(geometry.size.height * 0.1, 40))

                    // Conteúdo principal
                    VStack(spacing: 40) {
                        // Header: Branding minimalista
                        brandingSection

                        // Formulário
                        formSection

                        // Footer: Criar conta
                        footerSection
                    }
                    .padding(.horizontal, 24)

                    Spacer()
                        .frame(height: 40)
                }
                .frame(minHeight: geometry.size.height)
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .background(Color(.systemBackground))
        .onAppear {
            withAnimation(.easeOut(duration: 0.6)) {
                isAppearing = true
            }
        }
        .alert("Erro", isPresented: $viewModel.showError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(viewModel.errorMessage ?? "Erro desconhecido")
        }
        .sheet(isPresented: $showForgotPassword) {
            ForgotPasswordView(email: viewModel.email)
        }
        .sheet(isPresented: $showSignUp) {
            SignUpView()
        }
    }

    // MARK: - Branding Section

    private var brandingSection: some View {
        VStack(spacing: 12) {
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

            // Tagline
            Text("A sua clínica a um toque de distância.")
                .font(.system(size: 15, weight: .regular))
                .foregroundStyle(.secondary.opacity(0.8))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
        }
        .opacity(isAppearing ? 1 : 0)
        .offset(y: isAppearing ? 0 : -10)
        .animation(.easeOut(duration: 0.5), value: isAppearing)
    }

    // MARK: - Form Section

    private var formSection: some View {
        VStack(spacing: 16) {
            // Campo Email
            VStack(alignment: .leading, spacing: 8) {
                Text("Email")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.secondary)

                TextField("seu@email.com", text: $viewModel.email)
                    .textContentType(.username)
                    .keyboardType(.emailAddress)
                    .autocapitalization(.none)
                    .disableAutocorrection(true)
                    .foregroundStyle(.primary)
                    .tint(Color(hex: "ff6b00"))
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

            // Campo Senha
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .center, spacing: 0) {
                    Text("Senha")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(.secondary)

                    Spacer()

                    Button {
                        showForgotPassword = true
                    } label: {
                        Text("Esqueceu?")
                            .font(.system(size: 13, weight: .regular))
                            .foregroundStyle(.secondary)
                    }
                }

                HStack(spacing: 12) {
                    if showPassword {
                        TextField("Digite sua senha", text: $viewModel.password)
                            .textContentType(.password)
                            .foregroundStyle(.primary)
                            .tint(Color(hex: "ff6b00"))
                    } else {
                        SecureField("Digite sua senha", text: $viewModel.password)
                            .textContentType(.password)
                            .foregroundStyle(.primary)
                            .tint(Color(hex: "ff6b00"))
                    }

                    Button {
                        showPassword.toggle()
                    } label: {
                        Image(systemName: showPassword ? "eye.slash.fill" : "eye.fill")
                            .font(.system(size: 15, weight: .regular))
                            .foregroundStyle(.quaternary)
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

            // Botão Entrar
            Button {
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                Task {
                    await viewModel.signIn()
                }
            } label: {
                HStack(spacing: 10) {
                    if viewModel.isLoading {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: .white))
                            .scaleEffect(0.9)
                    } else {
                        Text("Entrar")
                            .font(.system(size: 16, weight: .semibold))
                    }
                }
                .frame(maxWidth: .infinity)
                .frame(height: 54)
                .foregroundColor(.white)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(.black)
                )
            }
            .disabled(!isFormValid || viewModel.isLoading)
            .opacity(isFormValid ? 1 : 0.5)
            .animation(.easeInOut(duration: 0.2), value: isFormValid)
            .padding(.top, 8)
        }
        .opacity(isAppearing ? 1 : 0)
        .offset(y: isAppearing ? 0 : 10)
        .animation(.easeOut(duration: 0.5).delay(0.1), value: isAppearing)
    }

    // MARK: - Footer Section

    private var footerSection: some View {
        Button {
            showSignUp = true
        } label: {
            HStack(spacing: 4) {
                Text("Não tem uma conta?")
                    .foregroundStyle(.secondary)

                Text("Criar conta")
                    .foregroundStyle(.primary)
                    .fontWeight(.medium)
            }
            .font(.system(size: 15))
        }
        .opacity(isAppearing ? 1 : 0)
        .animation(.easeOut(duration: 0.5).delay(0.15), value: isAppearing)
    }

    // MARK: - Helpers

    private var isFormValid: Bool {
        !viewModel.email.isEmpty && !viewModel.password.isEmpty
    }
}

// MARK: - Forgot Password View

struct ForgotPasswordView: View {
    @Environment(\.dismiss) var dismiss
    @Environment(\.colorScheme) var colorScheme
    @StateObject private var viewModel = ForgotPasswordViewModel()
    @State var email: String

    var body: some View {
        NavigationStack {
            ZStack {
                Color(.systemBackground).ignoresSafeArea()

                if viewModel.success {
                    // Tela de Sucesso
                    successView
                } else {
                    // Tela de Input
                    inputView
                }
            }
            .alert("Erro", isPresented: $viewModel.showError) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(viewModel.errorMessage)
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.secondary)
                            .frame(width: 32, height: 32)
                            .background(Color(.systemGray6))
                            .clipShape(Circle())
                    }
                }
            }
            .onAppear {
                viewModel.email = email
            }
            .onReceive(NotificationCenter.default.publisher(for: .dismissAllSheets)) { _ in
                dismiss()
            }
        }
    }

    // MARK: - Input View
    private var inputView: some View {
        ScrollView {
            VStack(spacing: 0) {
                Spacer()
                    .frame(height: 60)

                VStack(spacing: 32) {
                    // Header
                    VStack(spacing: 16) {
                        Image(systemName: "envelope.fill")
                            .font(.system(size: 44, weight: .light))
                            .foregroundStyle(.secondary.opacity(0.6))

                        VStack(spacing: 8) {
                            Text("Esqueceu a senha?")
                                .font(.system(size: 26, weight: .semibold))

                            Text("Digite seu email para receber um link de recuperação")
                                .font(.system(size: 15))
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 24)
                        }
                    }

                    // Campo Email
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Email")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(.secondary)

                        TextField("seu@email.com", text: $viewModel.email)
                            .keyboardType(.emailAddress)
                            .autocapitalization(.none)
                            .disableAutocorrection(true)
                            .foregroundStyle(.primary)
                            .tint(Color(hex: "ff6b00"))
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
                    .padding(.horizontal, 24)

                    // Botão Enviar
                    Button {
                        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                        Task {
                            await viewModel.sendResetEmail()
                        }
                    } label: {
                        HStack(spacing: 10) {
                            if viewModel.isLoading {
                                ProgressView()
                                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                    .scaleEffect(0.9)
                            } else {
                                Text("Enviar link de recuperação")
                                    .font(.system(size: 16, weight: .semibold))
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .frame(height: 54)
                        .foregroundColor(.white)
                        .background(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .fill(.black)
                        )
                    }
                    .disabled(viewModel.isLoading || viewModel.email.isEmpty)
                    .opacity((viewModel.isLoading || viewModel.email.isEmpty) ? 0.5 : 1)
                    .padding(.horizontal, 24)
                }

                Spacer()
            }
        }
    }

    // MARK: - Success View
    private var successView: some View {
        ScrollView {
            VStack(spacing: 0) {
                Spacer()
                    .frame(height: 60)

                VStack(spacing: 32) {
                    // Ícone de Sucesso
                    ZStack {
                        Circle()
                            .fill(Color(hex: "ff6b00").opacity(0.1))
                            .frame(width: 100, height: 100)

                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 50))
                            .foregroundStyle(Color(hex: "ff6b00"))
                    }
                    .scaleEffect(viewModel.success ? 1.0 : 0.5)
                    .animation(.spring(response: 0.5, dampingFraction: 0.6), value: viewModel.success)

                    // Título
                    Text("Email Enviado!")
                        .font(.system(size: 26, weight: .semibold))

                    // Descrição
                    VStack(spacing: 8) {
                        Text("Enviamos um link de recuperação para")
                            .foregroundStyle(.secondary)

                        Text(viewModel.email)
                            .foregroundStyle(Color(hex: "ff6b00"))
                            .fontWeight(.semibold)
                    }
                    .font(.system(size: 15))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)

                    // Info Box
                    VStack(alignment: .leading, spacing: 12) {
                        HStack(alignment: .top, spacing: 12) {
                            Image(systemName: "envelope")
                                .foregroundStyle(Color(hex: "ff6b00"))

                            VStack(alignment: .leading, spacing: 8) {
                                Text("Verifique sua caixa de entrada e spam")
                                    .fontWeight(.medium)

                                HStack(spacing: 4) {
                                    Text("O link expira em")
                                    Text("1 hora")
                                        .fontWeight(.bold)
                                        .foregroundStyle(Color(hex: "ff6b00"))
                                }
                            }
                            .font(.system(size: 14))
                            .foregroundStyle(.primary)
                        }
                    }
                    .padding()
                    .background(Color(hex: "ff6b00").opacity(0.05))
                    .cornerRadius(12)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color(hex: "ff6b00").opacity(0.2), lineWidth: 1)
                    )
                    .padding(.horizontal, 24)

                    // Botão Reenviar
                    Button {
                        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                        Task {
                            await viewModel.resendEmail()
                        }
                    } label: {
                        HStack {
                            if viewModel.isResending {
                                ProgressView()
                                    .progressViewStyle(CircularProgressViewStyle(tint: Color(hex: "ff6b00")))
                            } else if viewModel.resendTimer > 0 {
                                Text("Reenviar email (aguarde \(viewModel.resendTimer)s)")
                            } else {
                                Text("Não recebeu? Reenviar email")
                            }
                        }
                        .font(.system(size: 14, weight: .medium))
                        .frame(maxWidth: .infinity)
                        .frame(height: 48)
                        .foregroundColor(viewModel.resendTimer > 0 ? .secondary : Color(hex: "ff6b00"))
                        .background(Color(.systemGray6))
                        .cornerRadius(12)
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(viewModel.resendTimer > 0 ? Color.secondary.opacity(0.3) : Color(hex: "ff6b00").opacity(0.3), lineWidth: 2)
                        )
                    }
                    .disabled(viewModel.resendTimer > 0 || viewModel.isResending)
                    .padding(.horizontal, 24)

                    // Botão Voltar
                    Button {
                        dismiss()
                    } label: {
                        Text("Voltar para login")
                            .font(.system(size: 16, weight: .semibold))
                            .frame(maxWidth: .infinity)
                            .frame(height: 54)
                            .foregroundColor(.white)
                            .background(
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .fill(.black)
                            )
                    }
                    .padding(.horizontal, 24)
                }

                Spacer()
            }
        }
    }
}

// MARK: - Preview

#Preview {
    LoginView()
        .environmentObject(SupabaseManager.shared)
}
