import SwiftUI
import UserNotifications

@main
struct AgendaHofApp: App {
    @StateObject private var supabase = SupabaseManager.shared
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(supabase)
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
