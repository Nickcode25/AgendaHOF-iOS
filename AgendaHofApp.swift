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
            ContentView(
                showResetPassword: $showResetPassword,
                resetToken: $resetToken
            )
            .environmentObject(supabase)
            .onOpenURL { url in
                handleDeepLink(url)
            }
        }
    }

    // MARK: - Deep Link Handler
    private func handleDeepLink(_ url: URL) {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: true) else { return }

        #if DEBUG
        print("🔗 [Deep Link] Received URL: \(url.absoluteString)")
        print("🔗 [Deep Link] Scheme: \(url.scheme ?? "nil")")
        print("🔗 [Deep Link] Host: \(url.host ?? "nil")")
        print("🔗 [Deep Link] Path: \(components.path)")
        print("🔗 [Deep Link] Query Items: \(components.queryItems ?? [])")
        print("🔗 [Deep Link] Fragment: \(url.fragment ?? "nil")")
        #endif

        // Suporta múltiplos formatos:
        // 1. Custom URL Scheme: agendahof://reset-password?access_token=xxx&type=recovery
        // 2. Custom URL Scheme (fragment): agendahof://reset-password#access_token=xxx&type=recovery
        // 3. Universal Link: https://agendahof.com/reset-password#access_token=xxx&type=recovery
        // 4. Universal Link (callback): https://agendahof.com/auth/callback#access_token=xxx&type=recovery

        let isResetPasswordPath = components.path.contains("reset-password") ||
                                  components.path.contains("auth/callback") ||
                                  components.host == "reset-password" ||
                                  url.host == "reset-password"

        if isResetPasswordPath {
            // Supabase envia tokens no fragment (#) ou query (?)
            var accessToken: String?
            var tokenType: String?
            var error: String?
            var errorCode: String?
            var errorDescription: String?

            // 1. Tentar extrair do fragment (mais comum no Supabase)
            if let fragment = url.fragment {
                #if DEBUG
                print("🔍 [Deep Link] Tentando extrair do fragment: \(fragment)")
                #endif

                let fragmentComponents = URLComponents(string: "?\(fragment)")
                accessToken = fragmentComponents?.queryItems?.first(where: { $0.name == "access_token" })?.value
                tokenType = fragmentComponents?.queryItems?.first(where: { $0.name == "type" })?.value

                // Verificar se há erros
                error = fragmentComponents?.queryItems?.first(where: { $0.name == "error" })?.value
                errorCode = fragmentComponents?.queryItems?.first(where: { $0.name == "error_code" })?.value
                errorDescription = fragmentComponents?.queryItems?.first(where: { $0.name == "error_description" })?.value
            }

            // 2. Fallback: tentar extrair da query string
            if accessToken == nil {
                #if DEBUG
                print("🔍 [Deep Link] Fragment não encontrado, tentando query string")
                #endif

                accessToken = components.queryItems?.first(where: { $0.name == "access_token" })?.value
                tokenType = components.queryItems?.first(where: { $0.name == "type" })?.value
            }

            // 3. Fallback antigo: token simples (para compatibilidade)
            if accessToken == nil {
                #if DEBUG
                print("🔍 [Deep Link] access_token não encontrado, tentando 'token'")
                #endif

                accessToken = components.queryItems?.first(where: { $0.name == "token" })?.value
            }

            // Verificar se houve erro do Supabase
            if let errorCode = errorCode {
                #if DEBUG
                print("❌ [Deep Link] Erro do Supabase detectado!")
                print("   - Error: \(error ?? "unknown")")
                print("   - Error Code: \(errorCode)")
                print("   - Description: \(errorDescription?.replacingOccurrences(of: "+", with: " ") ?? "unknown")")
                #endif

                // Mostrar mensagem de erro para o usuário
                if errorCode == "otp_expired" {
                    // TODO: Mostrar alert dizendo que o link expirou
                    print("⏰ Link de recuperação expirou. Solicite um novo link.")
                }
                return
            }

            guard let token = accessToken else {
                #if DEBUG
                print("❌ [Deep Link] Token não encontrado na URL")
                print("💡 [Deep Link] Dica: O Supabase envia o token assim:")
                print("   - Fragment: https://agendahof.com/reset-password#access_token=XXX&type=recovery")
                print("   - Query: https://agendahof.com/reset-password?access_token=XXX&type=recovery")
                #endif
                return
            }

            #if DEBUG
            print("✅ [Deep Link] Token extraído com sucesso!")
            print("   - Token: \(token.prefix(20))...")
            print("   - Type: \(tokenType ?? "unknown")")
            #endif

            // Verificar se é um token de recuperação
            if tokenType == "recovery" || tokenType == nil {
                #if DEBUG
                print("📋 [Deep Link] Enviando notificação para fechar sheets...")
                #endif

                // Primeiro, notificar para fechar qualquer sheet aberta (ex: ForgotPasswordView)
                NotificationCenter.default.post(name: .dismissAllSheets, object: nil)

                // Aguardar um momento para garantir que sheets foram fechadas e ContentView carregou
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                    #if DEBUG
                    print("🎯 [Deep Link] Tentando abrir ResetPasswordView...")
                    print("   - Token: \(token.prefix(20))...")
                    print("   - showResetPassword antes: \(self.showResetPassword)")
                    print("   - resetToken antes: \(self.resetToken ?? "nil")")
                    #endif

                    // IMPORTANTE: Definir token ANTES de ativar a sheet
                    self.resetToken = token

                    // Aguardar um frame para garantir que resetToken foi atualizado
                    DispatchQueue.main.async {
                        self.showResetPassword = true

                        #if DEBUG
                        print("   - showResetPassword depois: \(self.showResetPassword)")
                        print("   - resetToken depois: \(self.resetToken?.prefix(20) ?? "nil")...")
                        #endif
                    }
                }
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
    @Binding var showResetPassword: Bool
    @Binding var resetToken: String?
    @State private var isReadyToShowSheet = false

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
        .sheet(isPresented: $showResetPassword) {
            // Usar um valor padrão vazio se resetToken for nil (não deveria acontecer)
            ResetPasswordView(token: resetToken ?? "")
                .onAppear {
                    #if DEBUG
                    print("🎬 [ContentView] Sheet ResetPasswordView apareceu!")
                    #endif
                }
        }
        .onChange(of: showResetPassword) { _, newValue in
            #if DEBUG
            print("🔄 [ContentView] showResetPassword mudou para: \(newValue)")
            if newValue {
                print("   - resetToken atual: \(resetToken?.prefix(20) ?? "nil")...")
            }
            #endif
        }
        .onChange(of: isCheckingAuth) { _, newValue in
            if !newValue {
                // ContentView terminou de carregar, agora é seguro mostrar sheets
                isReadyToShowSheet = true

                #if DEBUG
                print("✅ [ContentView] Pronto para mostrar sheets")
                #endif
            }
        }
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
    ContentView(
        showResetPassword: .constant(false),
        resetToken: .constant(nil)
    )
    .environmentObject(SupabaseManager.shared)
}

// MARK: - Notification Names

extension Notification.Name {
    static let dismissAllSheets = Notification.Name("dismissAllSheets")
}
