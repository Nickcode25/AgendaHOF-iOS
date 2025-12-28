import SwiftUI

// MARK: - Settings View (Refatorado)

/// View principal de configurações
/// Versão refatorada usando componentes modulares
/// Reduzida de 585 linhas (com sub-views) para ~80 linhas principais
struct SettingsView_Refactored: View {

    // MARK: - Environment & Dependencies

    @EnvironmentObject var supabase: SupabaseManager
    @StateObject private var authViewModel = AuthViewModel()

    // MARK: - State

    @State private var showLogoutConfirmation = false
    @State private var showProfile = false
    @State private var showNotifications = false
    @State private var showFinancialReport = false
    @State private var showInactivePatients = false

    // MARK: - Body

    var body: some View {
        List {
            // Perfil do usuário
            UserProfileSection(supabase: supabase) {
                showProfile = true
            }

            // Recursos
            ResourcesSection(
                supabase: supabase,
                onInactivePatientsTap: { showInactivePatients = true },
                onNotificationsTap: { showNotifications = true },
                onFinancialReportTap: { showFinancialReport = true }
            )

            // Sobre
            AboutSection()

            // Logout
            LogoutSection {
                showLogoutConfirmation = true
            }
        }
        .navigationTitle("Ajustes")
        .alert("Sair da Conta", isPresented: $showLogoutConfirmation) {
            Button("Cancelar", role: .cancel) {}
            Button("Sair", role: .destructive) {
                Task { await authViewModel.signOut() }
            }
        } message: {
            Text("Tem certeza que deseja sair da sua conta?")
        }
        .sheet(isPresented: $showProfile) {
            ProfileView()
        }
        .sheet(isPresented: $showNotifications) {
            NotificationsSettingsView()
        }
        .sheet(isPresented: $showFinancialReport) {
            FinancialReportView_Refactored()
                .environmentObject(supabase)
        }
        .sheet(isPresented: $showInactivePatients) {
            NavigationStack {
                InactivePatientsView()
                    .environmentObject(supabase)
            }
        }
    }
}

// MARK: - Preview

#Preview {
    NavigationStack {
        SettingsView_Refactored()
    }
    .environmentObject(SupabaseManager.shared)
}
