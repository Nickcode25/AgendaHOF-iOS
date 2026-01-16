import SwiftUI

struct ResetPasswordView: View {
    @Environment(\.dismiss) var dismiss
    @StateObject private var viewModel: ResetPasswordViewModel

    init(token: String) {
        #if DEBUG
        print("🔨 [ResetPasswordView] Init chamado com token: \(token.prefix(20))...")
        #endif
        _viewModel = StateObject(wrappedValue: ResetPasswordViewModel(token: token))
    }

    var body: some View {
        ZStack {
            Color(.systemBackground).ignoresSafeArea()

            if viewModel.isValidating {
                // Loading inicial
                VStack {
                    ProgressView("Validando...")
                        .progressViewStyle(CircularProgressViewStyle(tint: Color(hex: "ff6b00")))
                        .foregroundColor(.primary)
                }
                .onAppear {
                    #if DEBUG
                    print("📱 [ResetPasswordView] Mostrando: Loading (isValidating=true)")
                    #endif
                }
            } else if !viewModel.isTokenValid {
                // Token inválido
                invalidTokenView
                    .onAppear {
                        #if DEBUG
                        print("📱 [ResetPasswordView] Mostrando: Token Inválido")
                        #endif
                    }
            } else if viewModel.success {
                // Sucesso
                successView
                    .onAppear {
                        #if DEBUG
                        print("📱 [ResetPasswordView] Mostrando: Sucesso")
                        #endif
                    }
            } else {
                // Formulário
                formView
                    .onAppear {
                        #if DEBUG
                        print("📱 [ResetPasswordView] Mostrando: Formulário")
                        #endif
                    }
            }
        }
        .alert("Erro", isPresented: $viewModel.showError) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(viewModel.errorMessage)
        }
        .task {
            #if DEBUG
            print("🔄 [ResetPasswordView] Task iniciada - validando token...")
            #endif
            await viewModel.validateToken()
        }
    }

    // MARK: - Form View
    private var formView: some View {
        ScrollView {
            VStack(spacing: 24) {
                // Cabeçalho
                VStack(spacing: 16) {
                    ZStack {
                        Circle()
                            .fill(Color(hex: "ff6b00").opacity(0.1))
                            .frame(width: 80, height: 80)

                        Image(systemName: "lock.rotation")
                            .font(.system(size: 32))
                            .foregroundStyle(Color(hex: "ff6b00"))
                    }

                    Text("Redefinir Senha")
                        .font(.system(size: 26, weight: .semibold))

                    Text("Digite sua nova senha")
                        .font(.system(size: 15))
                        .foregroundStyle(.secondary)
                }
                .padding(.top, 60)

                // Campo Nova Senha
                VStack(alignment: .leading, spacing: 8) {
                    Text("Nova Senha")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(.secondary)

                    HStack {
                        ZStack(alignment: .leading) {
                            if viewModel.password.isEmpty {
                                Text("Digite sua senha")
                                    .foregroundStyle(.tertiary)
                            }

                            if viewModel.showPassword {
                                TextField("", text: $viewModel.password)
                                    .foregroundStyle(.primary)
                                    .tint(Color(hex: "ff6b00"))
                            } else {
                                SecureField("", text: $viewModel.password)
                                    .foregroundStyle(.primary)
                                    .tint(Color(hex: "ff6b00"))
                            }
                        }

                        Button {
                            viewModel.showPassword.toggle()
                        } label: {
                            Image(systemName: viewModel.showPassword ? "eye.slash.fill" : "eye.fill")
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

                    // Indicador de Força da Senha
                    if !viewModel.password.isEmpty {
                        PasswordStrengthIndicator(password: viewModel.password)
                            .padding(.top, 4)
                    }
                }
                .padding(.horizontal, 24)

                // Campo Confirmar Senha
                VStack(alignment: .leading, spacing: 8) {
                    Text("Confirmar Senha")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(.secondary)

                    HStack {
                        ZStack(alignment: .leading) {
                            if viewModel.confirmPassword.isEmpty {
                                Text("Confirme sua senha")
                                    .foregroundStyle(.tertiary)
                            }

                            if viewModel.showConfirmPassword {
                                TextField("", text: $viewModel.confirmPassword)
                                    .foregroundStyle(.primary)
                                    .tint(Color(hex: "ff6b00"))
                            } else {
                                SecureField("", text: $viewModel.confirmPassword)
                                    .foregroundStyle(.primary)
                                    .tint(Color(hex: "ff6b00"))
                            }
                        }

                        Button {
                            viewModel.showConfirmPassword.toggle()
                        } label: {
                            Image(systemName: viewModel.showConfirmPassword ? "eye.slash.fill" : "eye.fill")
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

                    // Match de Senhas
                    if !viewModel.confirmPassword.isEmpty {
                        HStack(spacing: 4) {
                            Image(systemName: viewModel.password == viewModel.confirmPassword ? "checkmark.circle.fill" : "xmark.circle.fill")
                                .foregroundColor(viewModel.password == viewModel.confirmPassword ? .green : .red)

                            Text(viewModel.password == viewModel.confirmPassword ? "Senhas coincidem" : "As senhas não coincidem")
                                .font(.system(size: 12))
                                .foregroundColor(viewModel.password == viewModel.confirmPassword ? .green : .red)
                        }
                        .padding(.top, 4)
                    }
                }
                .padding(.horizontal, 24)

                // Checkbox Logout Global
                VStack(alignment: .leading, spacing: 8) {
                    Toggle(isOn: $viewModel.logoutAllDevices) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Desconectar de todos os dispositivos")
                                .font(.system(size: 14, weight: .medium))
                                .foregroundStyle(.primary)

                            Text("Recomendado: encerra todas as sessões ativas em outros dispositivos para maior segurança")
                                .font(.system(size: 12))
                                .foregroundStyle(.secondary)
                        }
                    }
                    .toggleStyle(SwitchToggleStyle(tint: Color(hex: "ff6b00")))
                }
                .padding()
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color(.systemBackground))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(Color(.systemGray4), lineWidth: 1)
                        )
                )
                .padding(.horizontal, 24)

                // Botão Redefinir
                Button {
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    Task {
                        await viewModel.resetPassword()
                    }
                } label: {
                    HStack(spacing: 10) {
                        if viewModel.isLoading {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                .scaleEffect(0.9)
                        } else {
                            Text("Redefinir Senha")
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
                .disabled(!viewModel.isFormValid || viewModel.isLoading)
                .opacity(!viewModel.isFormValid || viewModel.isLoading ? 0.5 : 1)
                .padding(.horizontal, 24)
                .padding(.top, 8)
            }
            .padding(.bottom, 40)
        }
    }

    // MARK: - Success View
    private var successView: some View {
        VStack(spacing: 24) {
            Spacer()

            ZStack {
                Circle()
                    .fill(.green.opacity(0.1))
                    .frame(width: 100, height: 100)

                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 50))
                    .foregroundColor(.green)
            }
            .scaleEffect(viewModel.success ? 1.0 : 0.5)
            .animation(.spring(response: 0.5, dampingFraction: 0.6), value: viewModel.success)

            Text("Senha Redefinida!")
                .font(.system(size: 26, weight: .semibold))

            Text("Sua senha foi alterada com sucesso")
                .font(.system(size: 15))
                .foregroundStyle(.secondary)

            Spacer()

            Button {
                dismiss()
            } label: {
                Text("Fazer Login")
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
    }

    // MARK: - Invalid Token View
    private var invalidTokenView: some View {
        VStack(spacing: 24) {
            Spacer()

            ZStack {
                Circle()
                    .fill(.red.opacity(0.1))
                    .frame(width: 100, height: 100)

                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 50))
                    .foregroundColor(.red)
            }

            Text("Link Inválido")
                .font(.system(size: 26, weight: .semibold))

            Text("O link de recuperação expirou ou é inválido")
                .font(.system(size: 15))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)

            Spacer()

            Button {
                dismiss()
            } label: {
                Text("Voltar")
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
    }
}
