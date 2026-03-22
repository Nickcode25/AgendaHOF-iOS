import SwiftUI
import UserNotifications
import BackgroundTasks

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

    static let financialRefreshTaskId = "com.agendahof.financialRefresh"

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
    ) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        UNUserNotificationCenter.current().setBadgeCount(0)

        registerBackgroundTasks()
        return true
    }

    // MARK: - Background Tasks

    private func registerBackgroundTasks() {
        BGTaskScheduler.shared.register(
            forTaskWithIdentifier: AppDelegate.financialRefreshTaskId,
            using: nil
        ) { task in
            self.handleFinancialRefresh(task: task as! BGAppRefreshTask)
        }

        scheduleFinancialRefresh()
        print("✅ [BGTask] Tarefa de atualização financeira registrada")
    }

    private func handleFinancialRefresh(task: BGAppRefreshTask) {
        print("🔄 [BGTask] DESATIVADO - Notificação financeira agora é enviada pelo Supabase")
        task.setTaskCompleted(success: true)
    }

    func scheduleFinancialRefresh() {
        let request = BGAppRefreshTaskRequest(identifier: AppDelegate.financialRefreshTaskId)

        var calendar = Calendar.current
        calendar.timeZone = TimeZone(identifier: "America/Sao_Paulo") ?? .current

        let now = Date()
        var components = calendar.dateComponents([.year, .month, .day], from: now)
        components.hour = 20
        components.minute = 50
        components.second = 0

        guard var targetDate = calendar.date(from: components) else {
            print("❌ [BGTask] Erro ao calcular data alvo")
            return
        }

        if targetDate <= now {
            targetDate = calendar.date(byAdding: .day, value: 1, to: targetDate) ?? targetDate
        }

        request.earliestBeginDate = targetDate

        do {
            try BGTaskScheduler.shared.submit(request)

            let formatter = DateFormatter()
            formatter.dateFormat = "dd/MM/yyyy HH:mm"
            formatter.timeZone = TimeZone(identifier: "America/Sao_Paulo")
            print("✅ [BGTask] Próxima atualização agendada para: \(formatter.string(from: targetDate))")
        } catch {
            print("❌ [BGTask] Erro ao agendar tarefa: \(error.localizedDescription)")
        }
    }

    // MARK: - Universal Links

    func application(
        _ application: UIApplication,
        continue userActivity: NSUserActivity,
        restorationHandler: @escaping ([UIUserActivityRestoring]?) -> Void
    ) -> Bool {
        guard userActivity.activityType == NSUserActivityTypeBrowsingWeb,
              userActivity.webpageURL != nil else {
            return false
        }
        return true
    }

    // MARK: - Push Notifications (APNs)

    func application(
        _ application: UIApplication,
        didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
    ) {
        Task {
            await PushNotificationManager.shared.didRegisterForRemoteNotifications(deviceToken: deviceToken)
        }
    }

    func application(
        _ application: UIApplication,
        didFailToRegisterForRemoteNotificationsWithError error: Error
    ) {
        Task {
            await PushNotificationManager.shared.didFailToRegisterForRemoteNotifications(error: error)
        }
    }

    // MARK: - Notificações

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        return [.banner, .sound, .badge]
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        let identifier = response.notification.request.identifier
        let userInfo = response.notification.request.content.userInfo

        if let type = userInfo["type"] as? String {
            switch type {
            case "financial_summary":
                AppLogger.log("Push financial summary recebida", category: .notification)
            case "daily_summary":
                AppLogger.log("Push daily summary recebida", category: .notification)
            case "weekly_summary":
                AppLogger.log("Push weekly summary recebida", category: .notification)
            case "week_preview":
                AppLogger.log("Push week preview recebida", category: .notification)
            case "course_reminder":
                AppLogger.log("Push course reminder recebida", category: .notification)
            default:
                AppLogger.log("Push recebida (tipo: \(type))", category: .notification)
            }
        } else {
            AppLogger.log("Notificacao local recebida: \(identifier)", category: .notification)
        }
    }
}

// MARK: - ContentView

struct ContentView: View {
    @EnvironmentObject var supabase: SupabaseManager
    @EnvironmentObject var deepLinkManager: DeepLinkManager
    @EnvironmentObject var subscriptionManager: SubscriptionManager
    @Environment(\.scenePhase) private var scenePhase

    @State private var isCheckingAuth = true
    @State private var lastForegroundValidation: Date = .distantPast
    @State private var accessGateFallbackArmed = false
    @State private var accessGateFallbackTask: Task<Void, Never>?
    
    private let accessGateFallbackDelayNanoseconds: UInt64 = 4_000_000_000
    
    private var canRenderAuthenticatedUI: Bool {
        if subscriptionManager.didFinishInitialAccessCheck { return true }
        return accessGateFallbackArmed && subscriptionManager.canUseTrustedAccessForLoadingFallback
    }

    var body: some View {
        Group {
            if isCheckingAuth {
                LoadingView(text: "Carregando...")
            } else if supabase.isAuthenticated {
                if canRenderAuthenticatedUI {
                    MainTabView()
                } else {
                    accessLoadingStateView
                }
            } else {
                WelcomeView()
            }
        }
        .animation(.easeInOut(duration: 0.3), value: supabase.isAuthenticated)

        .sheet(isPresented: $deepLinkManager.showResetPassword, onDismiss: {
            deepLinkManager.showResetPassword = false
            deepLinkManager.resetToken = nil
        }) {
            if let token = deepLinkManager.resetToken {
                ResetPasswordView(token: token)
            } else {
                Text("Erro: Token não encontrado")
            }
        }

        // 🔁 Foreground: revalida sessão e acesso
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active {
                let now = Date()
                
                // 1) Evita rodar se acabou de receber initialSession no boot (debounce de 2s)
                if let bootDate = supabase.lastInitialAuthDate, now.timeIntervalSince(bootDate) < 2 {
                    AppLogger.log("⏭️ [Lifecycle] Pulando checkSession no active (initialSession recente)", category: .auth)
                    return
                }

                // 2) Evita rajada de revalidações normais (ex: app voltando de permissões / sheets)
                guard now.timeIntervalSince(lastForegroundValidation) > 15 else { return }
                lastForegroundValidation = now

                Task {
                    let activeFlowStartedAt = Date()
                    AppLogger.log("🔄 [Lifecycle] App voltou para active. Revalidando sessão/acesso...", category: .auth)
                    AppLogger.log(SupabaseManager.shared.getAuthSnapshot(context: "ScenePhase Active (Pré-check)"), category: .auth)
                    
                    await supabase.checkSession()
                    let checkSessionElapsedMs = Int(Date().timeIntervalSince(activeFlowStartedAt) * 1000)
                    AppLogger.log("⏱️ [Lifecycle] checkSession(active) concluído em \(checkSessionElapsedMs)ms", category: .auth)

                    // ✅ Prioridade: dispara validação de assinatura imediatamente após checkSession
                    // para não atrasar a liberação da UI.
                    if supabase.isAuthenticated {
                        SubscriptionManager.shared.refreshAccess(silent: true, force: true)
                        let accessDispatchElapsedMs = Int(Date().timeIntervalSince(activeFlowStartedAt) * 1000)
                        AppLogger.log("⚡ [Lifecycle] refreshAccess(active) disparado em \(accessDispatchElapsedMs)ms", category: .auth)
                        restartAccessGateFallbackTimerIfNeeded()
                    }

                    // ✅ Sync da agenda roda em paralelo e não deve bloquear validação de assinatura.
                    if supabase.isAuthenticated {
                        Task {
                            let agendaSyncStartedAt = Date()
                            await AppointmentService.shared.refreshCurrentMonthIfNeeded(selectedDate: Date(), force: true)
                            let agendaSyncElapsedMs = Int(Date().timeIntervalSince(agendaSyncStartedAt) * 1000)
                            AppLogger.log("⏱️ [Lifecycle] refreshCurrentMonthIfNeeded(active) concluiu em \(agendaSyncElapsedMs)ms", category: .business)
                        }
                    }
                    
                    AppLogger.log(SupabaseManager.shared.getAuthSnapshot(context: "ScenePhase Active (Pós-check disparado)"), category: .auth)
                }
            }
        }

        // 🚀 Inicialização
        .task {
            let bootFlowStartedAt = Date()
            await supabase.checkSession()
            let bootCheckSessionElapsedMs = Int(Date().timeIntervalSince(bootFlowStartedAt) * 1000)
            AppLogger.log("⏱️ [Lifecycle] checkSession(boot) concluído em \(bootCheckSessionElapsedMs)ms", category: .auth)

            // ✅ Garante validação inicial de assinatura mesmo quando o check no `scenePhase.active`
            // é pulado pelo debounce de boot (initialSession recente).
            if supabase.isAuthenticated {
                SubscriptionManager.shared.refreshAccess(silent: true, force: true)
                let bootAccessDispatchElapsedMs = Int(Date().timeIntervalSince(bootFlowStartedAt) * 1000)
                AppLogger.log("⚡ [Lifecycle] refreshAccess(boot) disparado em \(bootAccessDispatchElapsedMs)ms", category: .auth)
                restartAccessGateFallbackTimerIfNeeded()
            }

            isCheckingAuth = false

            if supabase.isAuthenticated {
                await migrateAndScheduleNotifications()
            }
        }

        // 🔔 Setup notificações após login
        .onChange(of: supabase.isAuthenticated) { _, isAuthenticated in
            restartAccessGateFallbackTimerIfNeeded()
            
            if isAuthenticated {
                Task {
                    await setupNotificationsAfterLogin()
                }
            }
        }
        .onChange(of: subscriptionManager.didFinishInitialAccessCheck) { _, _ in
            restartAccessGateFallbackTimerIfNeeded()
        }
        .onAppear {
            restartAccessGateFallbackTimerIfNeeded()
        }
        .onDisappear {
            accessGateFallbackTask?.cancel()
            accessGateFallbackTask = nil
        }
    }

    // MARK: - Helpers
    
    @ViewBuilder
    private var accessLoadingStateView: some View {
        if accessGateFallbackArmed {
            ZStack {
                Color(.systemBackground).ignoresSafeArea()
                
                VStack(spacing: 14) {
                    ProgressView()
                        .scaleEffect(1.2)
                    
                    Text("Verificando assinatura...")
                        .font(.headline)
                    
                    Text("Conexão lenta detectada. Estamos tentando novamente.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 24)
                    
                    Button("Tentar novamente agora") {
                        AppLogger.warning("🔁 [Lifecycle] Retry manual da verificação de assinatura.")
                        SubscriptionManager.shared.refreshAccess(silent: true, force: true)
                        restartAccessGateFallbackTimerIfNeeded()
                    }
                    .buttonStyle(.borderedProminent)
                    .padding(.top, 4)
                }
            }
        } else {
            LoadingView(text: "Verificando assinatura...")
        }
    }
    
    private func restartAccessGateFallbackTimerIfNeeded() {
        accessGateFallbackTask?.cancel()
        accessGateFallbackTask = nil
        accessGateFallbackArmed = false
        
        guard supabase.isAuthenticated, !subscriptionManager.didFinishInitialAccessCheck else { return }
        
        accessGateFallbackTask = Task {
            try? await Task.sleep(nanoseconds: accessGateFallbackDelayNanoseconds)
            if Task.isCancelled { return }
            
            await MainActor.run {
                guard supabase.isAuthenticated, !subscriptionManager.didFinishInitialAccessCheck else { return }
                
                accessGateFallbackArmed = true
                let trustedFallback = subscriptionManager.canUseTrustedAccessForLoadingFallback
                AppLogger.warning("⏳ [Lifecycle] Timeout na verificação de assinatura. trustedFallback=\(trustedFallback)")
                
                if !trustedFallback {
                    // Mantém bloqueio para evitar brecha, mas força nova tentativa para sair do estado preso.
                    SubscriptionManager.shared.refreshAccess(silent: true, force: true)
                }
            }
        }
    }

    private func migrateAndScheduleNotifications() async {
        let defaults = UserDefaults.standard
        if defaults.bool(forKey: "daily_summary_enabled"),
           defaults.integer(forKey: "daily_summary_hour") == 7 {
            defaults.set(8, forKey: "daily_summary_hour")
        }
        await NotificationManager.shared.scheduleAllNotifications()
    }

    private func setupNotificationsAfterLogin() async {
        let granted = await NotificationManager.shared.requestAuthorization()
        if granted {
            let defaults = UserDefaults.standard
            if defaults.object(forKey: "daily_summary_enabled") == nil {
                defaults.set(true, forKey: "daily_summary_enabled")
                defaults.set(8, forKey: "daily_summary_hour")
                defaults.set(0, forKey: "daily_summary_minute")
                defaults.set(true, forKey: "weekly_summary_enabled")
                defaults.set(true, forKey: "birthday_notifications_enabled")

                defaults.set(true, forKey: "appointment_reminder_enabled")
                defaults.set(30, forKey: "appointment_reminder_minutes")
            }

            await NotificationManager.shared.scheduleAllNotifications()

            // ✅ Push
            await PushNotificationManager.shared.registerForPushNotifications()
        }
    }
}

#Preview {
    ContentView()
        .environmentObject(SupabaseManager.shared)
        .environmentObject(DeepLinkManager.shared)
        .environmentObject(SubscriptionManager.shared)
}

// MARK: - Notification Names

extension Notification.Name {
    static let dismissAllSheets = Notification.Name("dismissAllSheets")
}

// MARK: - WelcomeView

struct WelcomeView: View {
    @Environment(\.colorScheme) var colorScheme
    @State private var showSignUp = false

    var body: some View {
        NavigationStack {
            ZStack {
                LinearGradient(
                    gradient: Gradient(colors: [
                        Color(red: 0.04, green: 0.04, blue: 0.04),
                        Color(red: 0.12, green: 0.07, blue: 0.03),
                        Color(red: 0.98, green: 0.45, blue: 0.09)
                    ]),
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .ignoresSafeArea()
                .overlay(Color.black.opacity(0.1))

                VStack {
                    Spacer()
                    brandingSection
                    Spacer()

                    VStack(spacing: 20) {
                        NavigationLink(destination: LoginView()) {
                            Text("Entrar")
                                .font(.system(size: 17, weight: .semibold))
                                .foregroundColor(.black)
                                .frame(maxWidth: .infinity)
                                .frame(height: 56)
                                .background(Color.white)
                                .clipShape(Capsule())
                                .shadow(color: .black.opacity(0.1), radius: 10, x: 0, y: 5)
                        }

                        Button {
                            showSignUp = true
                        } label: {
                            Text("Criar conta")
                                .font(.system(size: 17, weight: .medium))
                                .foregroundColor(.white.opacity(0.9))
                        }
                    }
                    .padding(.horizontal, 24)
                    .padding(.bottom, 60)
                }
            }
        }
        .sheet(isPresented: $showSignUp) {
            SignUpView()
        }
    }

    private var brandingSection: some View {
        VStack(spacing: 16) {
            let logoURL = "https://AgendaHOF.b-cdn.net/logo-light.png"

            AsyncImage(url: URL(string: logoURL)) { phase in
                if let image = phase.image {
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                } else if phase.error != nil {
                    Image(systemName: "stethoscope")
                        .font(.system(size: 60, weight: .light))
                        .foregroundColor(.white)
                } else {
                    ProgressView().tint(.white)
                }
            }
            .frame(width: 280, height: 160)
            .shadow(color: .black.opacity(0.2), radius: 10, x: 0, y: 5)
        }
    }
}
