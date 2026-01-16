import SwiftUI
import UserNotifications

@main
struct AgendaHofApp: App {
    @StateObject private var supabase = SupabaseManager.shared
    @StateObject private var deepLinkManager = DeepLinkManager.shared
    @StateObject private var subscriptionManager = SubscriptionManager.shared
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(supabase)
                .environmentObject(deepLinkManager)
                .environmentObject(subscriptionManager)
                .onOpenURL { url in
                    deepLinkManager.handle(url)
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
    
    /// Chamado quando o app é aberto via Universal Link
    func application(_ application: UIApplication, continue userActivity: NSUserActivity, restorationHandler: @escaping ([UIUserActivityRestoring]?) -> Void) -> Bool {
        // Verificar se é um Universal Link
        guard userActivity.activityType == NSUserActivityTypeBrowsingWeb,
              let _ = userActivity.webpageURL else {
            return false
        }
        
        // O sistema irá chamar .onOpenURL() automaticamente no SwiftUI App Lifecycle
        // Não precisamos fazer nada aqui, apenas retornar true para indicar que trataremos o link
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
        print("🔔 Notificação recebida: \(identifier)")
    }
}

// MARK: - Content View

struct ContentView: View {
    @EnvironmentObject var supabase: SupabaseManager
    @EnvironmentObject var deepLinkManager: DeepLinkManager
    
    @State private var isCheckingAuth = true
    @State private var isReadyToShowSheet = false
    
    var body: some View {
        Group {
            if isCheckingAuth {
                LoadingView(text: "Carregando...")
            } else if supabase.isAuthenticated {
                MainTabView()
            } else {
                WelcomeView()
            }
        }
        .animation(.easeInOut(duration: 0.3), value: supabase.isAuthenticated)
        // O DeepLinkManager controla o estado da sheet de reset
        .sheet(isPresented: $deepLinkManager.showResetPassword) {
            ResetPasswordView(token: deepLinkManager.resetToken ?? "")
        }
        .onChange(of: isCheckingAuth) { _, newValue in
            if !newValue {
                isReadyToShowSheet = true
            }
        }
        .task {
            await supabase.checkSession()
            isCheckingAuth = false
            
            if supabase.isAuthenticated {
                await migrateAndScheduleNotifications()
            }
        }
        .onChange(of: supabase.isAuthenticated) { _, isAuthenticated in
            if isAuthenticated {
                Task {
                    await setupNotificationsAfterLogin()
                }
            }
        }
    }
    
    // MARK: - Setup Helpers
    
    /// Migra configurações legadas e agenda notificações na inicialização
    private func migrateAndScheduleNotifications() async {
        let defaults = UserDefaults.standard
        // Migração: 07:00 -> 08:00
        if defaults.bool(forKey: "daily_summary_enabled") && defaults.integer(forKey: "daily_summary_hour") == 7 {
            defaults.set(8, forKey: "daily_summary_hour")
        }
        await NotificationManager.shared.scheduleAllNotifications()
    }
    
    /// Configura notificações após login
    private func setupNotificationsAfterLogin() async {
        let granted = await NotificationManager.shared.requestAuthorization()
        if granted {
            // Definir padrões se não existirem
            let defaults = UserDefaults.standard
            if defaults.object(forKey: "daily_summary_enabled") == nil {
                defaults.set(true, forKey: "daily_summary_enabled")
                defaults.set(8, forKey: "daily_summary_hour")
                defaults.set(0, forKey: "daily_summary_minute")
                defaults.set(true, forKey: "weekly_summary_enabled")
                defaults.set(true, forKey: "birthday_notifications_enabled")
                
                // Ativar lembretes de agendamento por padrão
                defaults.set(true, forKey: "appointment_reminder_enabled")
                defaults.set(30, forKey: "appointment_reminder_minutes") // Padrão 30 min antes
            }
            await NotificationManager.shared.scheduleAllNotifications()
        }
    }
}

#Preview {
    ContentView()
        .environmentObject(SupabaseManager.shared)
        .environmentObject(DeepLinkManager.shared)
}

// MARK: - Notification Names

extension Notification.Name {
    static let dismissAllSheets = Notification.Name("dismissAllSheets")
}

// MARK: - Welcome View

struct WelcomeView: View {
    @Environment(\.colorScheme) var colorScheme
    @State private var animateGradient = false
    
    var body: some View {
        NavigationStack {
            ZStack {
                // Background Gradient
                // Gradiente Midnight Fire
                LinearGradient(
                    gradient: Gradient(colors: [
                        Color(red: 0.04, green: 0.04, blue: 0.04),  // #0a0a0a
                        Color(red: 0.12, green: 0.07, blue: 0.03),  // #1f1107
                        Color(red: 0.98, green: 0.45, blue: 0.09)   // #f97316
                    ]),
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .ignoresSafeArea()
                .overlay(
                    // Subtle noise or overlay for texture if needed
                    Color.black.opacity(0.1)
                )
                
                VStack {
                    Spacer()
                    
                    // Centralized Logo
                    brandingSection
                    
                    Spacer()
                    
                    // Bottom Actions
                    VStack(spacing: 20) {
                        // Login Button
                        NavigationLink(destination: LoginView()) {
                            Text("Entrar")
                                .font(.system(size: 17, weight: .semibold))
                                .foregroundColor(.black) // High contrast against white
                                .frame(maxWidth: .infinity)
                                .frame(height: 56)
                                .background(Color.white)
                                .clipShape(Capsule())
                                .shadow(color: .black.opacity(0.1), radius: 10, x: 0, y: 5)
                        }
                        
                        // Sign Up Button
                        NavigationLink(destination: SignUpView()) {
                            Text("Criar conta")
                                .font(.system(size: 17, weight: .medium))
                                .foregroundColor(.white.opacity(0.9))
                        }
                    }
                    .padding(.horizontal, 24)
                    .padding(.bottom, 60) // Safe area padding
                }
            }
        }
    }
    
    private var brandingSection: some View {
        VStack(spacing: 16) {
            // Logo Logic reusing current assets
            let logoURL = "https://AgendaHOF.b-cdn.net/logo-light.png"
            
            AsyncImage(url: URL(string: logoURL)) { phase in
                if let image = phase.image {
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                } else if phase.error != nil {
                    // Fallback
                    Image(systemName: "stethoscope")
                        .font(.system(size: 60, weight: .light))
                        .foregroundColor(.white)
                } else {
                    ProgressView()
                        .tint(.white)
                }
            }
            .frame(width: 280, height: 160)
            .shadow(color: .black.opacity(0.2), radius: 10, x: 0, y: 5)
        }
    }
}
