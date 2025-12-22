import SwiftUI
import UserNotifications

@main
struct AgendaHofApp: App {
    @StateObject private var supabase = SupabaseManager.shared
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @State private var showResetPassword = false
    @State private var resetToken: String?

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(supabase)
                .onOpenURL { url in
                    handleDeepLink(url)
                }
                .sheet(isPresented: $showResetPassword) {
                    if let token = resetToken {
                        ResetPasswordView(token: token)
                    }
                }
        }
    }

    // MARK: - Deep Link Handler
    private func handleDeepLink(_ url: URL) {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: true) else { return }

        #if DEBUG
        print("🔗 [Deep Link] Received URL: \(url.absoluteString)")
        print("🔗 [Deep Link] Path: \(components.path)")
        print("🔗 [Deep Link] Query Items: \(components.queryItems ?? [])")
        #endif

        // Suporta tanto Custom URL Scheme quanto Universal Links:
        // - agendahof://reset-password?access_token=xxxxx&type=recovery
        // - https://agendahof.com/reset-password#access_token=xxxxx&type=recovery
        // - https://agendahof.com/auth/callback#access_token=xxxxx&type=recovery

        let isResetPasswordPath = components.path.contains("reset-password") ||
                                  components.path.contains("auth/callback") ||
                                  components.host == "reset-password"

        if isResetPasswordPath {
            // Supabase envia tokens no fragment (#) ou query (?)
            var accessToken: String?
            var tokenType: String?

            // 1. Tentar extrair do fragment (mais comum no Supabase)
            if let fragment = url.fragment {
                let fragmentComponents = URLComponents(string: "?\(fragment)")
                accessToken = fragmentComponents?.queryItems?.first(where: { $0.name == "access_token" })?.value
                tokenType = fragmentComponents?.queryItems?.first(where: { $0.name == "type" })?.value
            }

            // 2. Fallback: tentar extrair da query string
            if accessToken == nil {
                accessToken = components.queryItems?.first(where: { $0.name == "access_token" })?.value
                tokenType = components.queryItems?.first(where: { $0.name == "type" })?.value
            }

            // 3. Fallback antigo: token simples
            if accessToken == nil {
                accessToken = components.queryItems?.first(where: { $0.name == "token" })?.value
            }

            guard let token = accessToken else {
                #if DEBUG
                print("❌ [Deep Link] Token não encontrado na URL")
                #endif
                return
            }

            #if DEBUG
            print("✅ [Deep Link] Token extraído com sucesso (type: \(tokenType ?? "unknown"))")
            #endif

            // Verificar se é um token de recuperação
            if tokenType == "recovery" || tokenType == nil {
                resetToken = token
                showResetPassword = true
            }
        }
    }
}

// MARK: - App Delegate

class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        // Configurar delegate de notificações
        UNUserNotificationCenter.current().delegate = self
        return true
    }

    // MARK: - Universal Links

    /// Chamado quando o app é aberto via Universal Link (https://agendahof.com/...)
    func application(_ application: UIApplication, continue userActivity: NSUserActivity, restorationHandler: @escaping ([UIUserActivityRestoring]?) -> Void) -> Bool {
        #if DEBUG
        print("🌐 [Universal Link] userActivity.activityType: \(userActivity.activityType)")
        #endif

        // Verificar se é um Universal Link
        guard userActivity.activityType == NSUserActivityTypeBrowsingWeb,
              let url = userActivity.webpageURL else {
            return false
        }

        #if DEBUG
        print("🌐 [Universal Link] URL recebida: \(url.absoluteString)")
        #endif

        // O sistema irá chamar .onOpenURL() automaticamente
        // Não precisamos fazer nada aqui, apenas retornar true
        return true
    }

    // MARK: - Notificações

    // Mostrar notificação mesmo quando o app está em foreground
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        return [.banner, .sound, .badge]
    }

    // Quando o usuário toca na notificação
    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        let identifier = response.notification.request.identifier
        print("Notificação recebida: \(identifier)")
    }
}

// MARK: - Content View

struct ContentView: View {
    @EnvironmentObject var supabase: SupabaseManager
    @State private var isCheckingAuth = true

    var body: some View {
        Group {
            if isCheckingAuth {
                LoadingView(text: "Carregando...")
            } else if supabase.isAuthenticated {
                MainTabView()
            } else {
                NavigationStack {
                    LoginView()
                }
            }
        }
        .animation(.easeInOut(duration: 0.3), value: supabase.isAuthenticated)
        .task {
            await supabase.checkSession()
            isCheckingAuth = false

            // Reagendar notificações quando o usuário estiver autenticado
            if supabase.isAuthenticated {
                // Atualizar horário padrão para usuários existentes (migração para 08:00)
                let defaults = UserDefaults.standard
                if defaults.bool(forKey: "daily_summary_enabled") && defaults.integer(forKey: "daily_summary_hour") == 7 {
                    defaults.set(8, forKey: "daily_summary_hour")  // Migrar de 07:00 para 08:00
                }

                await NotificationManager.shared.scheduleAllNotifications()
            }
        }
        .onChange(of: supabase.isAuthenticated) { _, isAuthenticated in
            if isAuthenticated {
                Task {
                    // Solicitar permissão de notificações primeiro
                    let granted = await NotificationManager.shared.requestAuthorization()
                    if granted {
                        // Ativar todas as notificações automaticamente
                        UserDefaults.standard.set(true, forKey: "daily_summary_enabled")
                        UserDefaults.standard.set(8, forKey: "daily_summary_hour")  // 08:00 horário de São Paulo
                        UserDefaults.standard.set(0, forKey: "daily_summary_minute")
                        UserDefaults.standard.set(true, forKey: "weekly_summary_enabled")
                        UserDefaults.standard.set(true, forKey: "birthday_notifications_enabled")

                        await NotificationManager.shared.scheduleAllNotifications()
                    }
                }
            }
        }
    }
}

#Preview {
    ContentView()
        .environmentObject(SupabaseManager.shared)
}
