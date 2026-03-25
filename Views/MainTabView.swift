import SwiftUI

struct MainTabView: View {
    @State private var selectedTab = 0
    @State private var isPaywallPresented = false

    @EnvironmentObject var supabase: SupabaseManager
    @EnvironmentObject var subscriptionManager: SubscriptionManager


    init() {
        let tabBarAppearance = UITabBarAppearance()
        tabBarAppearance.configureWithOpaqueBackground()
        tabBarAppearance.backgroundColor = UIColor.systemBackground
        UITabBar.appearance().standardAppearance = tabBarAppearance
        UITabBar.appearance().scrollEdgeAppearance = tabBarAppearance
    }

    private var isBlocked: Bool {
        subscriptionManager.shouldShowPaywall
    }

    var body: some View {
        TabView(selection: $selectedTab) {
            NavigationStack { AgendaView() }
                .tabItem { Label("Agenda", systemImage: "calendar") }
                .tag(0)

            NavigationStack { PatientsListView() }
                .tabItem { Label("Pacientes", systemImage: "person.2.fill") }
                .tag(1)

            NavigationStack { SettingsView() }
                .tabItem { Label("Ajustes", systemImage: "gearshape.fill") }
                .tag(2)
        }
        .tint(.appPrimary)

        // MARK: - Overlay
        .overlay {
            if subscriptionManager.isLoading {
                ZStack {
                    Color.black.opacity(0.2).ignoresSafeArea()
                    VStack(spacing: 12) {
                        ProgressView()
                            .tint(.white)
                            .scaleEffect(1.2)

                        Text("Atualizando assinatura...")
                            .font(.caption)
                            .foregroundStyle(.white)
                    }
                    .padding(20)
                    .background(.ultraThinMaterial)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                }
                .allowsHitTesting(false)

            } else if isBlocked {
                ZStack {
                    Color.black.opacity(0.4).ignoresSafeArea()

                    VStack(spacing: 16) {
                        Image(systemName: "lock.fill")
                            .font(.system(size: 40))
                            .foregroundStyle(.white)

                        Text("Assinatura necessária")
                            .font(.headline)
                            .foregroundStyle(.white)

                        Button("Assinar agora") {
                            guard !subscriptionManager.isLoading else { return }
                            isPaywallPresented = true
                        }
                        .padding(.horizontal, 20)
                        .padding(.vertical, 10)
                        .background(Color.white)
                        .clipShape(Capsule())
                    }
                }
                .allowsHitTesting(true)
            }
        }

        // MARK: - Fonte única da verdade do Paywall
        .onChange(of: subscriptionManager.shouldShowPaywall) { _, _ in
            updatePaywallState()
        }
        .onChange(of: subscriptionManager.didFinishInitialAccessCheck) { _, _ in
            updatePaywallState()
        }
        .onChange(of: subscriptionManager.isLoading) { _, _ in
            updatePaywallState()
        }

        // Fecha sheet se deslogar
        .onChange(of: supabase.isAuthenticated) { _, isAuth in
            if !isAuth {
                isPaywallPresented = false
            }
        }

        // Estado inicial
        // Estado inicial
        // Estado inicial
        .onAppear {
            updatePaywallState()
        }


        // MARK: - Sheet
        .sheet(isPresented: $isPaywallPresented) {
            PaywallView(autoDismissWhenNoLongerRequired: true)
                .environmentObject(subscriptionManager)
                .environmentObject(supabase)
        }
    }

    // MARK: - Helpers
    private func updatePaywallState() {
        guard supabase.isAuthenticated else {
            isPaywallPresented = false
            return
        }

        // ✅ não abre/fecha sheet durante loading
        guard !subscriptionManager.isLoading else { return }

        // ✅ Regra única: se precisa mostrar paywall, abre. Se não, fecha.
        if subscriptionManager.shouldShowPaywall && !isPaywallPresented {
             AppLogger.log(SupabaseManager.shared.getAuthSnapshot(context: "Apresentando Paywall"), category: .auth)
        }
        isPaywallPresented = subscriptionManager.shouldShowPaywall
    }
}
