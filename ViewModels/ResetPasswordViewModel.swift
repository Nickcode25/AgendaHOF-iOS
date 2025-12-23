import SwiftUI
import Supabase

@MainActor
class ResetPasswordViewModel: ObservableObject {
    @Published var password: String = ""
    @Published var confirmPassword: String = ""
    @Published var showPassword: Bool = false
    @Published var showConfirmPassword: Bool = false
    @Published var logoutAllDevices: Bool = true
    @Published var isLoading: Bool = false
    @Published var isValidating: Bool = true
    @Published var isTokenValid: Bool = false
    @Published var success: Bool = false
    @Published var showError: Bool = false
    @Published var errorMessage: String = ""

    private let token: String
    private let backendURL = "https://agenda-hof-production.up.railway.app"
    private let supabase = SupabaseManager.shared

    var isFormValid: Bool {
        !password.isEmpty &&
        !confirmPassword.isEmpty &&
        password == confirmPassword &&
        isPasswordStrong(password)
    }

    init(token: String) {
        self.token = token
    }

    // MARK: - Validate Token
    func validateToken() async {
        isValidating = true

        // Por enquanto, considera válido se não estiver vazio
        // O Supabase validará o token ao tentar resetar a senha
        isTokenValid = !token.isEmpty

        isValidating = false
    }

    // MARK: - Reset Password
    func resetPassword() async {
        guard isFormValid else {
            errorMessage = "Preencha todos os campos corretamente"
            showError = true
            return
        }

        isLoading = true

        do {
            #if DEBUG
            print("🔐 [ResetPassword] Iniciando reset de senha...")
            print("   - Token: \(token.prefix(20))...")
            print("   - Logout todos dispositivos: \(logoutAllDevices)")
            #endif

            // 1. O token que recebemos já é um access_token JWT do Supabase
            // Vamos usar setSession para criar a sessão temporária
            #if DEBUG
            print("🔐 [ResetPassword] Passo 1: Criando sessão temporária com access_token...")
            #endif

            // Criar sessão temporária com o access_token que veio do deep link
            // Nota: refreshToken vazio porque essa é uma sessão temporária apenas para resetar a senha
            try await supabase.client.auth.setSession(accessToken: token, refreshToken: "")

            // Obter o usuário da sessão atual
            let user = try await supabase.client.auth.session.user

            #if DEBUG
            print("✅ [ResetPassword] Passo 1: Sessão criada com sucesso!")
            print("   - User ID: \(user.id.uuidString)")
            print("   - Email: \(user.email ?? "nil")")
            #endif

            // Agora que temos uma sessão válida, podemos validar a senha duplicada
            let userId = user.id.uuidString

            #if DEBUG
            print("🔐 [ResetPassword] Passo 2: Verificando senha duplicada...")
            #endif

            let isDuplicate = await checkPasswordDuplicate(userId: userId, password: password)

            #if DEBUG
            print("   - Senha duplicada: \(isDuplicate)")
            #endif

            if isDuplicate {
                errorMessage = "Esta senha já foi utilizada recentemente. Escolha uma senha diferente."
                showError = true
                isLoading = false

                // Fazer logout pois criamos uma sessão mas não vamos continuar
                try? await supabase.client.auth.signOut()
                return
            }

            // 2. Atualizar a senha usando o método correto
            #if DEBUG
            print("🔐 [ResetPassword] Passo 3: Atualizando senha...")
            #endif

            let userAttributes = UserAttributes(password: password)
            _ = try await supabase.client.auth.update(user: userAttributes)

            #if DEBUG
            print("✅ [ResetPassword] Passo 3: Senha atualizada com sucesso!")
            #endif

            // 3. Adicionar ao histórico de senhas
            #if DEBUG
            print("🔐 [ResetPassword] Passo 4: Adicionando ao histórico...")
            #endif

            await addPasswordToHistory(userId: userId, password: password)

            #if DEBUG
            print("✅ [ResetPassword] Passo 4: Histórico atualizado!")
            #endif

            // 4. Enviar email de notificação
            if let userEmail = user.email {
                #if DEBUG
                print("🔐 [ResetPassword] Passo 5: Enviando email de notificação...")
                #endif

                await sendPasswordChangedNotification(email: userEmail, userId: userId)

                #if DEBUG
                print("✅ [ResetPassword] Passo 5: Email enviado!")
                #endif
            }

            // 5. Fazer logout da sessão atual (usuário precisará fazer login novamente)
            if logoutAllDevices {
                #if DEBUG
                print("🔐 [ResetPassword] Passo 6: Fazendo logout da sessão atual...")
                #endif

                // Fazer logout da sessão que criamos
                try? await supabase.client.auth.signOut()

                #if DEBUG
                print("✅ [ResetPassword] Passo 6: Logout concluído!")
                #endif
            }

            #if DEBUG
            print("🎉 [ResetPassword] Reset de senha concluído com sucesso!")
            #endif

            success = true

        } catch {
            #if DEBUG
            print("❌ [ResetPassword] ERRO ao resetar senha:")
            print("   - Tipo: \(type(of: error))")
            print("   - Descrição: \(error)")
            print("   - LocalizedDescription: \(error.localizedDescription)")

            // Se for um erro do Supabase, tentar extrair mais detalhes
            if let authError = error as? AuthError {
                print("   - AuthError específico: \(authError)")
            }

            // Tentar imprimir a representação completa do erro
            dump(error)
            #endif

            errorMessage = "Erro ao redefinir senha. O link pode ter expirado."
            showError = true
        }

        isLoading = false
    }

    // MARK: - Check Password Duplicate
    private func checkPasswordDuplicate(userId: String, password: String) async -> Bool {
        do {
            guard let url = URL(string: "\(backendURL)/api/auth/validate-password-change") else {
                return false
            }

            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")

            let body = [
                "userId": userId,
                "newPassword": password
            ]
            request.httpBody = try JSONEncoder().encode(body)

            let (data, _) = try await URLSession.shared.data(for: request)

            let response = try JSONDecoder().decode(ValidationResponse.self, from: data)

            return !response.valid

        } catch {
            // Fail-open: permite a troca se houver erro
            print("Erro ao validar senha duplicada: \(error)")
            return false
        }
    }

    // MARK: - Add Password to History
    private func addPasswordToHistory(userId: String, password: String) async {
        do {
            guard let url = URL(string: "\(backendURL)/api/auth/add-password-to-history") else {
                return
            }

            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")

            let body = [
                "userId": userId,
                "password": password
            ]
            request.httpBody = try JSONEncoder().encode(body)

            let (_, _) = try await URLSession.shared.data(for: request)

        } catch {
            print("Erro ao adicionar ao histórico: \(error)")
        }
    }

    // MARK: - Send Notification Email
    private func sendPasswordChangedNotification(email: String, userId: String) async {
        do {
            guard let url = URL(string: "\(backendURL)/api/auth/password-changed-notification") else {
                #if DEBUG
                print("❌ [Email Notificação] URL inválida")
                #endif
                return
            }

            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")

            let body = [
                "email": email,
                "userId": userId,
                "timestamp": ISO8601DateFormatter().string(from: Date())
            ]
            request.httpBody = try JSONEncoder().encode(body)

            #if DEBUG
            print("📧 [Email Notificação] Enviando para: \(email)")
            print("   - URL: \(url)")
            print("   - User ID: \(userId)")
            #endif

            let (data, response) = try await URLSession.shared.data(for: request)

            #if DEBUG
            if let httpResponse = response as? HTTPURLResponse {
                print("📧 [Email Notificação] Status: \(httpResponse.statusCode)")
            }
            if let responseString = String(data: data, encoding: .utf8) {
                print("📧 [Email Notificação] Resposta: \(responseString)")
            }
            #endif

        } catch {
            #if DEBUG
            print("❌ [Email Notificação] Erro ao enviar: \(error)")
            #endif
        }
    }

    // MARK: - Helper Functions
    private func getCurrentUserId() async -> String? {
        do {
            let user = try await supabase.client.auth.session.user
            return user.id.uuidString
        } catch {
            return nil
        }
    }

    private func getCurrentUserEmail() async -> String? {
        do {
            let user = try await supabase.client.auth.session.user
            return user.email
        } catch {
            return nil
        }
    }

    private func isPasswordStrong(_ password: String) -> Bool {
        // Mínimo 8 caracteres
        guard password.count >= 8 else { return false }

        // Pelo menos uma letra maiúscula
        let uppercaseLetterRegex = ".*[A-Z]+.*"
        guard password.range(of: uppercaseLetterRegex, options: .regularExpression) != nil else { return false }

        // Pelo menos uma letra minúscula
        let lowercaseLetterRegex = ".*[a-z]+.*"
        guard password.range(of: lowercaseLetterRegex, options: .regularExpression) != nil else { return false }

        // Pelo menos um número
        let numberRegex = ".*[0-9]+.*"
        guard password.range(of: numberRegex, options: .regularExpression) != nil else { return false }

        // Pelo menos um caractere especial
        let specialCharacterRegex = ".*[!@#$%^&*(),.?\":{}|<>]+.*"
        guard password.range(of: specialCharacterRegex, options: .regularExpression) != nil else { return false }

        return true
    }
}

// MARK: - Response Models
struct ValidationResponse: Codable {
    let valid: Bool
    let message: String
}
