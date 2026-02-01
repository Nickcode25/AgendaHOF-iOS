import SwiftUI

struct MainTabView: View {
    @State private var selectedTab = 0
    @EnvironmentObject var supabase: SupabaseManager
    @EnvironmentObject var subscriptionManager: SubscriptionManager

    init() {
        // Configurar aparência da Tab Bar para não ser transparente
        let tabBarAppearance = UITabBarAppearance()
        tabBarAppearance.configureWithOpaqueBackground()
        tabBarAppearance.backgroundColor = UIColor.systemBackground

        UITabBar.appearance().standardAppearance = tabBarAppearance
        UITabBar.appearance().scrollEdgeAppearance = tabBarAppearance
    }

    var body: some View {
        TabView(selection: $selectedTab) {
            // Agenda
            NavigationStack {
                AgendaView()
            }
            .tabItem {
                Label("Agenda", systemImage: "calendar")
            }
            .tag(0)

            // Pacientes
            NavigationStack {
                PatientsListView()
            }
            .tabItem {
                Label("Pacientes", systemImage: "person.2.fill")
            }
            .tag(1)

            // Ajustes
            NavigationStack {
                SettingsView()
            }
            .tabItem {
                Label("Ajustes", systemImage: "gearshape.fill")
            }
            .tag(2)
        }
        .tint(.appPrimary)
        // ✅ NOVO: Mostrar paywall automaticamente se não tiver acesso
        .sheet(isPresented: .constant(subscriptionManager.shouldShowPaywall)) {
            PaywallView()
                .environmentObject(subscriptionManager)
                .environmentObject(supabase)
        }
    }
}

#Preview {
    MainTabView()
        .environmentObject(SupabaseManager.shared)
}
