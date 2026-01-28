import Foundation
import SwiftUI

@MainActor
class AuthViewModel: ObservableObject {
    // MARK: - Published Properties

    @Published var email = ""
    @Published var confirmEmail = "" // Novo campo
    @Published var password = ""
    @Published var confirmPassword = ""
    @Published var name = ""
    @Published var professionalName = "" // Nome Profissional (opcional)
    @Published var phone = ""
    @Published var rememberMe = false
    @Published var showPassword = false
    @Published var isLoading = false
    @Published var errorTitle = "Erro" // Novo campo para o título do erro
    @Published var errorMessage: String?
    @Published var showError = false
    @Published var showSuccess = false
    @Published var successMessage: String?

    // MARK: - Private

    private let supabase = SupabaseManager.shared
    private let keychain = KeychainManager.shared

    // MARK: - Init

    init() {
        loadSavedCredentials()
    }

    // MARK: - Load Saved Credentials

    func loadSavedCredentials() {
        if UserDefaults.standard.bool(forKey: Constants.rememberMeKey) {
            self.rememberMe = true
            self.email = UserDefaults.standard.string(forKey: Constants.savedEmailKey) ?? ""
            self.password = keychain.getPassword(for: email) ?? ""
        }
    }

    // MARK: - Sign In

    func signIn() async {
        // Validação
        guard !email.isEmpty else {
            showError(message: "Digite seu email")
            return
        }

        guard !password.isEmpty else {
            showError(message: "Digite sua senha")
            return
        }

        guard email.isValidEmail else {
            showError(message: "Digite um email válido")
            return
        }

        isLoading = true
        errorMessage = nil

        do {
            try await supabase.signIn(email: email, password: password)

            // Salvar credenciais se "Lembrar-me" estiver ativo
            if rememberMe {
                saveCredentials()
            } else {
                clearSavedCredentials()
            }

        } catch {
            if let nsError = error as NSError?, nsError.code == 403 {
                showError(message: nsError.localizedDescription, title: "Plano não encontrado")
            } else {
                showError(message: error.authErrorMessage)
            }
        }

        isLoading = false
    }

    // MARK: - Sign Up

    func signUp() async {
        // 1. Sanitização
        let cleanEmail = email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let cleanConfirmEmail = confirmEmail.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let cleanPhone = phone.replacingOccurrences(of: "\\D", with: "", options: .regularExpression)
        
        // 2. Validação
        guard !name.isEmpty else {
            showError(message: "Digite seu nome completo")
            return
        }

        // professionalName é opcional - não precisa de validação obrigatória

        guard !cleanEmail.isEmpty else {
            showError(message: "Digite seu email")
            return
        }

        guard cleanEmail.isValidEmail else {
            showError(message: "Digite um email válido")
            return
        }
        
        guard cleanEmail == cleanConfirmEmail else {
            showError(message: "Os emails não coincidem")
            return
        }

        guard !cleanPhone.isEmpty else {
            showError(message: "Digite seu telefone")
            return
        }

        // Validação básica de telefone (10 ou 11 dígitos para BR)
        guard cleanPhone.count >= 10 && cleanPhone.count <= 11 else {
            showError(message: "Digite um telefone válido com DDD")
            return
        }

        guard !password.isEmpty else {
            showError(message: "Digite sua senha")
            return
        }

        guard password.isValidPassword else {
            showError(message: "A senha deve ter:\n• Mínimo 8 caracteres\n• Letra maiúscula (A-Z)\n• Letra minúscula (a-z)\n• Número (0-9)\n• Caractere especial (!@#$...)")
            return
        }

        guard password == confirmPassword else {
            showError(message: "As senhas não coincidem")
            return
        }

        isLoading = true
        errorMessage = nil
        
        // 3. Enriquecimento (Trial Date)
        // Data atual + 7 dias
        let trialEndDate = Calendar.current.date(byAdding: .day, value: 7, to: Date()) ?? Date()
        let trialEndDateString = ISO8601DateFormatter().string(from: trialEndDate)

        do {
            // Passamos os dados sanitizados e enriquecidos
            try await supabase.signUp(
                email: cleanEmail, 
                password: password, 
                name: name, 
                professionalName: professionalName.isEmpty ? nil : professionalName, // Opcional
                phone: cleanPhone, // Telefone limpo (apenas números)
                trialEndDate: trialEndDateString
            )
            showSuccess(message: "Conta criada! Verifique seu email para confirmar.")
        } catch {
            showError(message: error.authErrorMessage)
        }

        isLoading = false
    }

    // MARK: - Sign Out

    func signOut() async {
        isLoading = true

        do {
            try await supabase.signOut()
            clearSavedCredentials()
        } catch {
            showError(message: error.localizedDescription)
        }

        isLoading = false
    }

    // MARK: - Delete Account

    func deleteAccount() async throws {
        guard supabase.currentUser != nil else {
            throw NSError(domain: "Auth", code: 401, userInfo: [
                NSLocalizedDescriptionKey: "Usuário não autenticado"
            ])
        }

        // Delete user account via Supabase RPC function
        try await supabase.client.rpc("delete_my_account").execute()

        // Sign out after successful deletion
        try await supabase.signOut()
        clearSavedCredentials()
    }

    // MARK: - Reset Password

    func resetPassword() async {
        guard !email.isEmpty else {
            showError(message: "Digite seu email")
            return
        }

        guard email.isValidEmail else {
            showError(message: "Digite um email válido")
            return
        }

        isLoading = true

        do {
            try await supabase.resetPassword(email: email)
            showSuccess(message: "Email de recuperação enviado!")
        } catch {
            showError(message: error.authErrorMessage)
        }

        isLoading = false
    }

    // MARK: - Remember Me Toggle

    func toggleRememberMe() {
        rememberMe.toggle()
        if !rememberMe {
            clearSavedCredentials()
        }
    }

    // MARK: - Private Helpers

    private func saveCredentials() {
        UserDefaults.standard.set(true, forKey: Constants.rememberMeKey)
        UserDefaults.standard.set(email, forKey: Constants.savedEmailKey)
        keychain.savePassword(password, for: email)
    }

    private func clearSavedCredentials() {
        UserDefaults.standard.removeObject(forKey: Constants.rememberMeKey)
        UserDefaults.standard.removeObject(forKey: Constants.savedEmailKey)
        keychain.deletePassword(for: email)
    }

    private func showError(message: String, title: String = "Erro") {
        self.errorTitle = title
        self.errorMessage = message
        self.showError = true
    }

    private func showSuccess(message: String) {
        self.successMessage = message
        self.showSuccess = true
    }

    // MARK: - Validation (using String extensions)
    // Validações agora são feitas via String+Extensions para evitar duplicação

    // MARK: - Clear Form

    func clearForm() {
        email = ""
        confirmEmail = ""
        password = ""
        confirmPassword = ""
        name = ""
        professionalName = ""
        phone = ""
        errorMessage = nil
        showError = false
    }
}
