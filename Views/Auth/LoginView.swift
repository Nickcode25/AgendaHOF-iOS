import SwiftUI

struct LoginView: View {
    @StateObject private var viewModel = AuthViewModel()
    @EnvironmentObject var supabase: SupabaseManager
    @Environment(\.colorScheme) var colorScheme
    @State private var showForgotPassword = false
    @State private var showSignUp = false
    @State private var isPasswordVisible = false // Renamed from showPassword to match snippet variable name preference
    
    // Animação de entrada
    @State private var isAppearing = false

    var body: some View {
        ZStack {
            // Gradiente Midnight Fire
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
            
            GeometryReader { geometry in
                ScrollView {
                    VStack(spacing: 0) {
                        Spacer() // Push content to center
                        
                        // Conteúdo centralizado
                        VStack(spacing: 0) {
                            // Logo e título
                            VStack(spacing: 20) {
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
                                
                                VStack(spacing: 8) {
                                    Text("A sua clínica a um toque de distância.")
                                        .font(.system(size: 14))
                                        .foregroundColor(.white.opacity(0.7))
                                }
                            }
                            .padding(.bottom, 50)
                            .opacity(isAppearing ? 1 : 0)
                            .offset(y: isAppearing ? 0 : -20)
                            
                            // Card de Login
                            VStack(spacing: 24) {
                                // Campo Email
                                VStack(alignment: .leading, spacing: 8) {
                                    Text("Email")
                                        .font(.system(size: 14, weight: .medium))
                                        .foregroundColor(.white.opacity(0.9))
                                    
                                    HStack {
                                        Image(systemName: "envelope.fill")
                                            .foregroundColor(.orange.opacity(0.7))
                                            .frame(width: 20)
                                        
                                        TextField("Digite seu email", text: $viewModel.email)
                                            .foregroundColor(.white)
                                            .keyboardType(.emailAddress)
                                            .autocapitalization(.none)
                                            .tint(.orange) // Ensure tint/cursor is orange not blue
                                    }
                                    .padding()
                                    .background(Color.white.opacity(0.1))
                                    .cornerRadius(12)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 12)
                                            .stroke(Color.white.opacity(0.2), lineWidth: 1)
                                    )
                                }
                                
                                // Campo Senha
                                VStack(alignment: .leading, spacing: 8) {
                                    HStack {
                                        Text("Senha")
                                            .font(.system(size: 14, weight: .medium))
                                            .foregroundColor(.white.opacity(0.9))
                                        
                                        Spacer()
                                        
                                        Button(action: {
                                            showForgotPassword = true
                                        }) {
                                            Text("Esqueceu?")
                                                .font(.system(size: 13, weight: .medium))
                                                .foregroundColor(.orange)
                                        }
                                    }
                                    
                                    HStack {
                                        Image(systemName: "lock.fill")
                                            .foregroundColor(.orange.opacity(0.7))
                                            .frame(width: 20)
                                        
                                        if isPasswordVisible {
                                            TextField("Digite sua senha", text: $viewModel.password)
                                                .foregroundColor(.white)
                                        } else {
                                            SecureField("Digite sua senha", text: $viewModel.password)
                                                .foregroundColor(.white)
                                        }
                                        
                                        Button(action: {
                                            isPasswordVisible.toggle()
                                        }) {
                                            Image(systemName: isPasswordVisible ? "eye.fill" : "eye.slash.fill")
                                                .foregroundColor(.white.opacity(0.5))
                                        }
                                    }
                                    .padding()
                                    .background(Color.white.opacity(0.1))
                                    .cornerRadius(12)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 12)
                                            .stroke(Color.white.opacity(0.2), lineWidth: 1)
                                    )
                                }
                                
                                // Botão Entrar
                                Button(action: {
                                    Task { await viewModel.signIn() }
                                }) {
                                    HStack(spacing: 10) {
                                        if viewModel.isLoading {
                                            ProgressView()
                                                .tint(.black)
                                        } else {
                                            Text("Entrar")
                                                .font(.system(size: 17, weight: .semibold))
                                        }
                                    }
                                    .foregroundColor(.black)
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
                                    .cornerRadius(12)
                                    .shadow(color: Color.orange.opacity(0.4), radius: 10, y: 5)
                                }
                                .padding(.top, 8)
                                .disabled(viewModel.isLoading)
                                
                                // Divisor
                                HStack {
                                    Rectangle()
                                        .fill(Color.white.opacity(0.2))
                                        .frame(height: 1)
                                    
                                    Text("ou")
                                        .font(.system(size: 13))
                                        .foregroundColor(.white.opacity(0.6))
                                        .padding(.horizontal, 12)
                                    
                                    Rectangle()
                                        .fill(Color.white.opacity(0.2))
                                        .frame(height: 1)
                                }
                                
                                // Criar conta
                                HStack(spacing: 4) {
                                    Text("Não tem uma conta?")
                                        .font(.system(size: 14))
                                        .foregroundColor(.white.opacity(0.7))
                                    
                                    Button(action: {
                                        showSignUp = true
                                    }) {
                                        Text("Criar conta")
                                            .font(.system(size: 14, weight: .semibold))
                                            .foregroundColor(.orange)
                                    }
                                }
                            }
                            .padding(.horizontal, 32)
                            .opacity(isAppearing ? 1 : 0)
                            .offset(y: isAppearing ? 0 : 20)
                        }
                        
                        Spacer() // Push content to center
                    }
                    .frame(minHeight: geometry.size.height)
                    .padding(.vertical, 20)
                }
                .scrollDismissesKeyboard(.interactively)
            }
        }
        .navigationBarHidden(true)
        .preferredColorScheme(.dark)
        .onAppear {
            withAnimation(.easeOut(duration: 0.6)) {
                isAppearing = true
            }
        }
        .alert(viewModel.errorTitle, isPresented: $viewModel.showError) {
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
