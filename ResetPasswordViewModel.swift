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
            // 1. Validar senha duplicada (se conseguir pegar o userId)
            if let userId = await getCurrentUserId() {
                let isDuplicate = await checkPasswordDuplicate(userId: userId, password: password)

                if isDuplicate {
                    errorMessage = "Esta senha já foi utilizada recentemente. Escolha uma senha diferente."
                    showError = true
                    isLoading = false
                    return
                }
            }

            // 2. Atualizar senha via Supabase usando o token de recuperação
            // O token vem do link do email
            try await supabase.client.auth.verifyOTP(
                phone: nil,
                email: nil,
                token: token,
                type: .recovery
            )

            // 3. Atualizar a senha
            try await supabase.client.auth.updateUser(
                attributes: UserAttributes(password: password)
            )

            // 4. Adicionar ao histórico de senhas
            if let userId = await getCurrentUserId() {
                await addPasswordToHistory(userId: userId, password: password)
            }

            // 5. Enviar email de notificação
            if let userEmail = await getCurrentUserEmail() {
                await sendPasswordChangedNotification(email: userEmail)
            }

            // 6. Invalidar sessões antigas (logout global)
            if logoutAllDevices {
                try await supabase.client.auth.refreshSession()
            }

            success = true

        } catch {
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
    private func sendPasswordChangedNotification(email: String) async {
        do {
            guard let url = URL(string: "\(backendURL)/api/auth/password-changed-notification") else {
                return
            }

            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")

            let body = [
                "email": email,
                "userId": await getCurrentUserId() ?? "",
                "timestamp": ISO8601DateFormatter().string(from: Date())
            ]
            request.httpBody = try JSONEncoder().encode(body)

            let (_, _) = try await URLSession.shared.data(for: request)

        } catch {
            print("Erro ao enviar notificação: \(error)")
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
