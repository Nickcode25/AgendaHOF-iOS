import Foundation
import SwiftUI

/// Gerenciador centralizado de Deep Links e navegação externa
/// Responsável por interpretar URLs e coordenar a navegação do app
@MainActor
class DeepLinkManager: ObservableObject {
    static let shared = DeepLinkManager()
    
    // MARK: - Published Properties
    
    @Published var showResetPassword = false
    @Published var resetToken: String?
    
    // MARK: - Initialization
    
    private init() {}
    
    // MARK: - Handlers
    
    /// Processa uma URL recebida via Custom Scheme ou Universal Link
    /// - Parameter url: A URL recebida pelo app
    func handle(_ url: URL) {
        // Logging centralizado (substituindo prints dispersos)
        logDeepLink(url)
        
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: true) else { return }
        
        // Rotas conhecidas
        let isResetPasswordPath = components.path.contains("reset-password") ||
                                  components.path.contains("auth/callback") ||
                                  components.host == "reset-password" ||
                                  url.host == "reset-password"
        
        if isResetPasswordPath {
            handleResetPassword(url: url, components: components)
        }
    }
    
    // MARK: - Specific Handlers
    
    private func handleResetPassword(url: URL, components: URLComponents) {
        // Supabase envia tokens no fragment (#) ou query (?)
        var accessToken: String?
        var tokenType: String?
        var error: String?
        var errorCode: String?
        
        // 1. Tentar extrair do fragment (Padrão Supabase)
        if let fragment = url.fragment {
            let fragmentComponents = URLComponents(string: "?\(fragment)")
            accessToken = fragmentComponents?.queryItems?.first(where: { $0.name == "access_token" })?.value
            tokenType = fragmentComponents?.queryItems?.first(where: { $0.name == "type" })?.value
            
            // Capturar erros
            error = fragmentComponents?.queryItems?.first(where: { $0.name == "error" })?.value
            errorCode = fragmentComponents?.queryItems?.first(where: { $0.name == "error_code" })?.value
        }
        
        // 2. Fallback: Query string
        if accessToken == nil {
            accessToken = components.queryItems?.first(where: { $0.name == "access_token" })?.value
            tokenType = components.queryItems?.first(where: { $0.name == "type" })?.value
        }
        
        // 3. Fallback Legacy
        if accessToken == nil {
            accessToken = components.queryItems?.first(where: { $0.name == "token" })?.value
        }
        
        // Tratamento de Erros
        if let errorCode = errorCode {
            print("❌ [Deep Link] Erro do Supabase: \(error ?? "unknown") (\(errorCode))")
            if errorCode == "otp_expired" {
                // Futuro: Usar um AlertManager para mostrar erro na UI
                print("⏰ Link expirado")
            }
            return
        }
        
        guard let token = accessToken else {
            print("❌ [Deep Link] Token não encontrado na URL")
            return
        }
        
        // Verificar tipo do token (apenas recovery)
        if tokenType == "recovery" || tokenType == nil {
            print("📋 [Deep Link] Iniciando fluxo de recuperação de senha...")
            
            // Fechar sheets existentes
            NotificationCenter.default.post(name: .dismissAllSheets, object: nil)
            
            // Pequeno delay para garantir UI limpa
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                guard let self = self else { return }
                self.resetToken = token
                self.showResetPassword = true
                print("✅ [Deep Link] Fluxo de reset iniciado")
            }
        }
    }
    
    // MARK: - Helpers
    
    private func logDeepLink(_ url: URL) {
        #if DEBUG
        print("🔗 [Deep Link] Recebido: \(url.absoluteString)")
        print("   - Scheme: \(url.scheme ?? "nil")")
        print("   - Host: \(url.host ?? "nil")")
        print("   - Components: \(url.pathComponents)")
        #endif
    }
}
