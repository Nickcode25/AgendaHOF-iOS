import SwiftUI
import Combine

@MainActor
class ForgotPasswordViewModel: ObservableObject {
    @Published var email: String = ""
    @Published var isLoading: Bool = false
    @Published var success: Bool = false
    @Published var showError: Bool = false
    @Published var errorMessage: String = ""
    @Published var resendTimer: Int = 0
    @Published var isResending: Bool = false

    private var timerCancellable: AnyCancellable?

    // MARK: - Send Reset Email
    func sendResetEmail() async {
        guard !email.isEmpty else {
            errorMessage = "Digite seu email"
            showError = true
            return
        }

        isLoading = true

        do {
            // Chamar endpoint do backend usando constante centralizada
            guard let url = URL(string: Constants.forgotPasswordEndpoint) else {
                throw URLError(.badURL)
            }

            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")

            let body = ["email": email]
            request.httpBody = try JSONEncoder().encode(body)

            let (_, response) = try await URLSession.shared.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse else {
                throw URLError(.badServerResponse)
            }

            // SEGURANÇA: Sempre mostra sucesso para prevenir enumeração
            // O backend retorna success=true mesmo se o email não existir
            if httpResponse.statusCode == 200 || httpResponse.statusCode == 201 {
                success = true
                startResendTimer()
            } else {
                // Apenas erros de servidor são mostrados
                throw URLError(.badServerResponse)
            }

        } catch {
            // Apenas erro de rede é mostrado
            if let urlError = error as? URLError,
               urlError.code == .notConnectedToInternet || urlError.code == .timedOut {
                errorMessage = "Erro de conexão. Verifique sua internet e tente novamente."
                showError = true
            } else {
                // Para outros erros, ainda mostra sucesso (previne enumeração)
                success = true
                startResendTimer()
            }
        }

        isLoading = false
    }

    // MARK: - Resend Email
    func resendEmail() async {
        guard resendTimer == 0, !isResending else { return }

        isResending = true

        do {
            guard let url = URL(string: Constants.forgotPasswordEndpoint) else {
                throw URLError(.badURL)
            }

            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")

            let body = ["email": email]
            request.httpBody = try JSONEncoder().encode(body)

            let (_, _) = try await URLSession.shared.data(for: request)

            // Reinicia o timer
            startResendTimer()

        } catch {
            // Silencioso - não mostra erro para não revelar se email existe
            print("Erro ao reenviar email: \(error)")
        }

        isResending = false
    }

    // MARK: - Start Timer
    private func startResendTimer() {
        resendTimer = 60

        timerCancellable = Timer.publish(every: 1, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                guard let self = self else { return }
                if self.resendTimer > 0 {
                    self.resendTimer -= 1
                }
            }
    }

    deinit {
        timerCancellable?.cancel()
    }
}
