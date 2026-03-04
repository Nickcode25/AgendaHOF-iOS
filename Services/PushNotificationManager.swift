import Foundation
import UserNotifications
import UIKit

/// Gerenciador de notificações push remotas
@MainActor
class PushNotificationManager: NSObject, ObservableObject {
    static let shared = PushNotificationManager()
    
    @Published var deviceToken: String?
    @Published var isRegistered = false
    
    private let supabase = SupabaseManager.shared
    private let cachedDeviceTokenKey = "cached_push_device_token"
    
    private override init() {
        super.init()
        self.deviceToken = UserDefaults.standard.string(forKey: cachedDeviceTokenKey)
    }
    
    // MARK: - Registration
    
    /// Registra o app para receber notificações push
    func registerForPushNotifications() async {
        do {
            // Primeiro, solicitar autorização
            let granted = try await UNUserNotificationCenter.current()
                .requestAuthorization(options: [.alert, .sound, .badge])
            
            guard granted else {
                AppLogger.log("⚠️ Permissão de push notification negada pelo usuário", category: .notification)
                return
            }
            
            // Registrar para notificações remotas (deve ser na main thread)
            await MainActor.run {
                UIApplication.shared.registerForRemoteNotifications()
            }
            
            AppLogger.log("✅ Solicitação de registro de push notification enviada", category: .notification)
            
        } catch {
            AppLogger.error("Erro ao registrar para push notifications", error: error)
        }
    }
    
    // MARK: - Token Management
    
    /// Chamado quando o device token é recebido do APNs
    func didRegisterForRemoteNotifications(deviceToken: Data) async {
        let tokenString = deviceToken.map { String(format: "%02.2hhx", $0) }.joined()
        self.deviceToken = tokenString
        UserDefaults.standard.set(tokenString, forKey: cachedDeviceTokenKey)
        
        AppLogger.log("📱 Device token recebido: \(tokenString.prefix(20))...", category: .notification)
        
        // Armazenar no Supabase
        await storeDeviceToken(tokenString)
    }
    
    /// Armazena o device token no Supabase
    private func storeDeviceToken(_ token: String) async {
        guard let userId = supabase.currentUser?.id else {
            AppLogger.log("⚠️ Não foi possível armazenar token: usuário não autenticado", category: .notification)
            return
        }
        
        // Determinar ambiente (sandbox para Debug, production para Release)
        let environment: String
        #if DEBUG
        environment = "sandbox"
        #else
        environment = "production"
        #endif
        
        do {
            struct DeviceTokenData: Encodable {
                let user_id: String
                let device_token: String
                let platform: String
                let environment: String
                let is_active: Bool
                let updated_at: String
            }
            
            let deviceTokenData = DeviceTokenData(
                user_id: userId.uuidString,
                device_token: token,
                platform: "ios",
                environment: environment,
                is_active: true,
                updated_at: ISO8601DateFormatter().string(from: Date())
            )
            
            // ✅ Upsert: se o token já existe (mesmo em outra conta), ele é atualizado para a conta atual
            // A restrição única deve ser baseada no par (device_token, environment)
            try await supabase.client
                .from("device_tokens")
                .upsert(deviceTokenData, onConflict: "device_token,environment")
                .execute()
            
            isRegistered = true
            AppLogger.log("✅ Device token armazenado no Supabase (ambiente: \(environment))", category: .notification)
            
        } catch {
            AppLogger.error("Erro ao armazenar device token no Supabase", error: error)
        }
    }
    
    /// Desativa o device token ao fazer logout
    func deactivateDeviceToken() async {
        guard let token = resolvedDeviceToken() else {
            AppLogger.warning("⚠️ [Push] Nenhum device token disponível para desativar.")
            return
        }
        
        let environment: String
        #if DEBUG
        environment = "sandbox"
        #else
        environment = "production"
        #endif
        
        do {
            struct DeviceTokenDeactivate: Encodable {
                let is_active: Bool
                let updated_at: String
            }
            
            let updateData = DeviceTokenDeactivate(
                is_active: false,
                updated_at: ISO8601DateFormatter().string(from: Date())
            )
            
            try await supabase.client
                .from("device_tokens")
                .update(updateData)
                .eq("device_token", value: token)
                .eq("environment", value: environment)
                .execute()
            
            self.deviceToken = nil
            self.isRegistered = false
            UserDefaults.standard.removeObject(forKey: cachedDeviceTokenKey)
            AppLogger.log("📱 Device token desativado no Supabase (ambiente: \(environment))", category: .notification)
            
        } catch {
            AppLogger.error("Erro ao desativar device token", error: error)
        }
    }
    
    /// Chamado quando falha o registro de notificações push
    func didFailToRegisterForRemoteNotifications(error: Error) {
        AppLogger.error("❌ Falha ao registrar para push notifications", error: error)
    }
    
    private func resolvedDeviceToken() -> String? {
        if let inMemory = deviceToken, !inMemory.isEmpty { return inMemory }
        if let cached = UserDefaults.standard.string(forKey: cachedDeviceTokenKey), !cached.isEmpty {
            self.deviceToken = cached
            return cached
        }
        return nil
    }
}
