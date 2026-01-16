import SwiftUI

struct MainTabView: View {
    @State private var selectedTab = 0
    @EnvironmentObject var supabase: SupabaseManager

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
    }
}

#Preview {
    MainTabView()
        .environmentObject(SupabaseManager.shared)
}
