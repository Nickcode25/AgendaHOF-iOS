import SwiftUI

// MARK: - Login View (Refatorado)

/// View principal de login
/// Versão refatorada usando componentes modulares
/// Reduzida de 506 linhas para ~120 linhas através de modularização
struct LoginView_Refactored: View {

    // MARK: - View Model & Environment

    @StateObject private var viewModel = AuthViewModel()
    @EnvironmentObject var supabase: SupabaseManager

    // MARK: - Navigation State

    @State private var showForgotPassword = false
    @State private var showSignUp = false

    // MARK: - Animation State

    @State private var isAppearing = false

    // MARK: - Body

    var body: some View {
        GeometryReader { geometry in
            ScrollView {
                VStack(spacing: 0) {
                    // Espaçamento topo adaptativo
                    Spacer()
                        .frame(height: max(geometry.size.height * 0.1, 40))

                    // Conteúdo principal
                    VStack(spacing: 40) {
                        // Branding: Logo e Tagline
                        LoginBrandingSection(isAppearing: isAppearing)

                        // Formulário de Login
                        LoginFormSection(
                            email: $viewModel.email,
                            password: $viewModel.password,
                            rememberMe: $viewModel.rememberMe,
                            onLogin: {
                                Task { await viewModel.signIn() }
                            },
                            onForgotPassword: {
                                showForgotPassword = true
                            },
                            isLoading: viewModel.isLoading
                        )
                        .opacity(isAppearing ? 1 : 0)
                        .offset(y: isAppearing ? 0 : 10)
                        .animation(.easeOut(duration: 0.5).delay(0.1), value: isAppearing)

                        // Footer: Link para criar conta
                        LoginFooterSection {
                            showSignUp = true
                        }
                        .opacity(isAppearing ? 1 : 0)
                        .offset(y: isAppearing ? 0 : 10)
                        .animation(.easeOut(duration: 0.5).delay(0.2), value: isAppearing)
                    }
                    .padding(.horizontal, 24)

                    // Espaçamento inferior
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
}

// MARK: - Preview

#Preview("Login View") {
    LoginView_Refactored()
        .environmentObject(SupabaseManager.shared)
}

#Preview("Login View - Dark Mode") {
    LoginView_Refactored()
        .environmentObject(SupabaseManager.shared)
        .preferredColorScheme(.dark)
}
