import Foundation
import SwiftUI

@MainActor
class AuthViewModel: ObservableObject {
    // MARK: - Published Properties

    @Published var email = ""
    @Published var password = ""
    @Published var confirmPassword = ""
    @Published var name = ""
    @Published var phone = ""
    @Published var rememberMe = false
    @Published var showPassword = false
    @Published var isLoading = false
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

        guard isValidEmail(email) else {
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
            showError(message: error.authErrorMessage)
        }

        isLoading = false
    }

    // MARK: - Sign Up

    func signUp() async {
        // Validação
        guard !name.isEmpty else {
            showError(message: "Digite seu nome completo")
            return
        }

        guard !email.isEmpty else {
            showError(message: "Digite seu email")
            return
        }

        guard isValidEmail(email) else {
            showError(message: "Digite um email válido")
            return
        }

        guard !phone.isEmpty else {
            showError(message: "Digite seu telefone")
            return
        }

        guard isValidPhone(phone) else {
            showError(message: "Digite um telefone válido")
            return
        }

        guard !password.isEmpty else {
            showError(message: "Digite sua senha")
            return
        }

        guard isValidPassword(password) else {
            showError(message: "A senha deve ter:\n• Mínimo 8 caracteres\n• Letra maiúscula (A-Z)\n• Letra minúscula (a-z)\n• Número (0-9)\n• Caractere especial (!@#$...)")
            return
        }

        guard password == confirmPassword else {
            showError(message: "As senhas não coincidem")
            return
        }

        isLoading = true
        errorMessage = nil

        do {
            try await supabase.signUp(email: email, password: password, name: name, phone: phone)
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

    // MARK: - Reset Password

    func resetPassword() async {
        guard !email.isEmpty else {
            showError(message: "Digite seu email")
            return
        }

        guard isValidEmail(email) else {
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

    private func showError(message: String) {
        self.errorMessage = message
        self.showError = true
    }

    private func showSuccess(message: String) {
        self.successMessage = message
        self.showSuccess = true
    }

    private func isValidEmail(_ email: String) -> Bool {
        let emailRegex = "[A-Z0-9a-z._%+-]+@[A-Za-z0-9.-]+\\.[A-Za-z]{2,64}"
        let emailPredicate = NSPredicate(format: "SELF MATCHES %@", emailRegex)
        return emailPredicate.evaluate(with: email)
    }

    private func isValidPhone(_ phone: String) -> Bool {
        let numbers = phone.filter { $0.isNumber }
        // Aceita telefones com 10 dígitos (fixo) ou 11 dígitos (celular)
        return numbers.count == 10 || numbers.count == 11
    }

    private func isValidPassword(_ password: String) -> Bool {
        // Mínimo 8 caracteres
        guard password.count >= 8 else { return false }

        // Pelo menos uma letra maiúscula
        guard password.range(of: "[A-Z]", options: .regularExpression) != nil else { return false }

        // Pelo menos uma letra minúscula
        guard password.range(of: "[a-z]", options: .regularExpression) != nil else { return false }

        // Pelo menos um número
        guard password.range(of: "[0-9]", options: .regularExpression) != nil else { return false }

        // Pelo menos um caractere especial
        guard password.range(of: "[!@#$%^&*(),.?\":{}|<>]", options: .regularExpression) != nil else { return false }

        return true
    }

    // MARK: - Clear Form

    func clearForm() {
        email = ""
        password = ""
        confirmPassword = ""
        name = ""
        phone = ""
        errorMessage = nil
        showError = false
    }
}
