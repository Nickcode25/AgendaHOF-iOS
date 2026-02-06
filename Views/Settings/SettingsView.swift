import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var supabase: SupabaseManager
    @EnvironmentObject var subscriptionManager: SubscriptionManager
    @StateObject private var authViewModel = AuthViewModel()

    @State private var showLogoutConfirmation = false
    @State private var showProfile = false
    @State private var showNotifications = false
    @State private var showFinancialReport = false
    @State private var showInactivePatients = false
    @State private var showSupport = false
    @State private var showPaywall = false

    var body: some View {
        List {
            // Perfil do usuário
            Section {
                Button {
                    showProfile = true
                } label: {
                    HStack(spacing: 12) {
                        AvatarView(
                            name: supabase.userProfile?.nameForDisplay ?? "Usuário",
                            imageUrl: supabase.userProfile?.profilePhoto,
                            size: 60
                        )

                        VStack(alignment: .leading, spacing: 4) {
                            Text(supabase.userProfile?.nameForDisplay ?? "Usuário")
                                .font(.headline)
                                .foregroundColor(.primary)

                            if let email = supabase.currentUser?.email {
                                Text(email)
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                            }

                            if let role = supabase.userProfile?.role {
                                Text(role.displayName)
                                    .font(.caption)
                                    .foregroundColor(.appPrimary)
                            }
                        }

                        Spacer()

                        Image(systemName: "chevron.right")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }

            // Gestão (Prioridade)
            Section("Gestão") {
                // Relatório Financeiro (apenas owner)
                if supabase.isOwner {
                    SettingsRow(
                        icon: "chart.bar.fill",
                        iconColor: .green,
                        title: "Relatório Financeiro"
                    ) {
                        showFinancialReport = true
                    }
                }
                
                // Pacientes Inativos (+6 meses)
                SettingsRow(
                    icon: "person.badge.clock.fill",
                    iconColor: Color(hex: "ff6b00"),
                    title: "Pacientes Inativos (+6 meses)"
                ) {
                    showInactivePatients = true
                }
            }

            // Configurações
            Section("Configurações") {
                // Notificações
                SettingsRow(
                    icon: "bell.fill",
                    iconColor: .red,
                    title: "Notificações"
                ) {
                    showNotifications = true
                }
            }
            
            // Assinatura / Plano (Apenas para Owners)
            if supabase.isOwner {
                Section("Plano") {
                    // Status do plano atual
                    HStack(spacing: 12) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 6)
                                .fill(planColor.gradient)
                                .frame(width: 29, height: 29)
                            
                            Image(systemName: planIcon)
                                .font(.system(size: 15))
                                .foregroundColor(.white)
                        }
                        
                        VStack(alignment: .leading, spacing: 2) {
                            Text(subscriptionManager.accessState.planType.displayName)
                                .font(.body)
                                .foregroundColor(.primary)
                            
                            if subscriptionManager.accessState.isInTrial {
                                if let expDate = subscriptionManager.accessState.expirationDate {
                                    Text("Expira em \(expDate.formatted(date: .abbreviated, time: .omitted))")
                                        .font(.caption)
                                        .foregroundColor(.orange)
                                }
                            } else if subscriptionManager.accessState.source != .none {
                                Text("Via \(subscriptionManager.accessState.source.displayName)")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                        
                        Spacer()
                    }
                    
                    // Botão para ver/alterar planos
                    Button {
                        showPaywall = true
                    } label: {
                        HStack {
                            Text(subscriptionManager.accessState.hasAccess ? "Gerenciar Plano" : "Ver Planos")
                                .foregroundColor(.blue)
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }
            
            // Ajuda & Sobre
            Section("Ajuda & Sobre") {
                // Suporte
                SettingsRow(
                    icon: "headphones.circle.fill",
                    iconColor: .blue,
                    title: "Suporte"
                ) {
                    showSupport = true
                }
                
                LabeledContent("Versão") {
                    Text(Constants.appVersion)
                        .foregroundColor(.secondary)
                }

                NavigationLink(destination: LegalInfoView()) {
                    HStack {
                        Image(systemName: "info.circle.fill") // Icone para combinar com os outros
                            .foregroundColor(.gray)
                        Text("Informações Legais")
                    }
                }
            }



            // Logout
            Section {
                Button(role: .destructive) {
                    showLogoutConfirmation = true
                } label: {
                    HStack {
                        Spacer()
                        Text("Sair da Conta")
                            .fontWeight(.medium)
                        Spacer()
                    }
                }
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
            FinancialReportView()
                .environmentObject(supabase)
        }
        .sheet(isPresented: $showInactivePatients) {
            NavigationStack {
                InactivePatientsView()
                    .environmentObject(supabase)
            }
        }
        .sheet(isPresented: $showSupport) {
            SupportView()
        }
        .sheet(isPresented: $showPaywall) {
            PaywallView()
                .environmentObject(subscriptionManager)
        }
    }
    
    // MARK: - Plan Display Helpers
    
    private var planColor: Color {
        switch subscriptionManager.accessState.planType {
        case .premium: return .purple
        case .pro: return .blue
        case .basic: return .green
        case .trial: return .orange
        case .courtesy: return .pink
        case .none: return .gray
        }
    }
    
    private var planIcon: String {
        switch subscriptionManager.accessState.planType {
        case .premium: return "crown.fill"
        case .pro: return "star.fill"
        case .basic: return "star"
        case .trial: return "clock.fill"
        case .courtesy: return "gift.fill"
        case .none: return "xmark.circle"
        }
    }


}

// MARK: - Settings Row

struct SettingsRow: View {
    let icon: String
    let iconColor: Color
    let title: String
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(iconColor.gradient)
                        .frame(width: 29, height: 29)

                    Image(systemName: icon)
                        .font(.system(size: 15))
                        .foregroundColor(.white)
                }

                Text(title)
                    .foregroundColor(.primary)

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }
}

// MARK: - Profile View

struct ProfileView: View {
    @Environment(\.dismiss) var dismiss
    @EnvironmentObject var supabase: SupabaseManager
    @StateObject private var authViewModel = AuthViewModel()
    @State private var showEditProfile = false
    @State private var showDeleteAccountConfirmation = false
    @State private var isDeletingAccount = false
    @State private var deleteAccountError: String?

    var body: some View {
        NavigationStack {
            List {
                // Avatar e nome
                Section {
                    HStack {
                        Spacer()
                        VStack(spacing: 12) {
                            AvatarView(
                                name: supabase.userProfile?.nameForDisplay ?? "Usuário",
                                imageUrl: supabase.userProfile?.profilePhoto,
                                size: 100
                            )

                            Text(supabase.userProfile?.nameForDisplay ?? "Usuário")
                                .font(.title2)
                                .fontWeight(.bold)

                            if let role = supabase.userProfile?.role {
                                Text(role.displayName)
                                    .font(.subheadline)
                                    .foregroundColor(.appPrimary)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 4)
                                    .background(Color.appPrimary.opacity(0.1))
                                    .cornerRadius(8)
                            }
                        }
                        Spacer()
                    }
                    .padding(.vertical, 20)
                }
                .listRowBackground(Color.clear)

                // Informações
                Section("Informações") {
                    if let email = supabase.currentUser?.email {
                        LabeledContent("Email") {
                            Text(email)
                                .foregroundColor(.secondary)
                        }
                    }

                    if let phone = supabase.userProfile?.phone, !phone.isEmpty {
                        LabeledContent("Telefone") {
                            Text(phone.formattedPhone)
                                .foregroundColor(.secondary)
                        }
                    } else {
                        LabeledContent("Telefone") {
                            Text("Não informado")
                                .foregroundColor(.secondary)
                        }
                    }

                    if let username = supabase.userProfile?.username {
                        LabeledContent("Usuário") {
                            Text("@\(username)")
                                .foregroundColor(.secondary)
                        }
                    }
                }

                // Editar perfil
                Section {
                    Button {
                        showEditProfile = true
                    } label: {
                        HStack {
                            Spacer()
                            Label("Editar Perfil", systemImage: "pencil")
                            Spacer()
                        }
                    }
                }
                
                // Excluir Conta
                Section {
                    Button(role: .destructive) {
                        showDeleteAccountConfirmation = true
                    } label: {
                        HStack {
                            Spacer()
                            Text("Excluir minha conta")
                                .fontWeight(.medium)
                            Spacer()
                        }
                    }
                }
            }
            .navigationTitle("Perfil")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Fechar") {
                        dismiss()
                    }
                }
            }
            .sheet(isPresented: $showEditProfile) {
                EditProfileView()
            }
            .alert("Excluir Conta?", isPresented: $showDeleteAccountConfirmation) {
                Button("Cancelar", role: .cancel) {}
                Button("Excluir", role: .destructive) {
                    Task { await deleteAccount() }
                }
            } message: {
                Text("Esta ação é irreversível. Todos os seus dados de pacientes e agendamentos serão apagados permanentemente. Tem certeza?")
            }
            .alert("Erro ao Excluir Conta", isPresented: Binding(
                get: { deleteAccountError != nil },
                set: { if !$0 { deleteAccountError = nil } }
            )) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(deleteAccountError ?? "")
            }
            .loadingOverlay(isLoading: isDeletingAccount, text: "Excluindo conta...")
        }
    }

    
    private func deleteAccount() async {
        isDeletingAccount = true

        do {
            try await authViewModel.deleteAccount()
            // Logout will happen automatically via deleteAccount()
        } catch {
            isDeletingAccount = false
            deleteAccountError = error.localizedDescription
        }
    }
}

// MARK: - Edit Profile View

struct EditProfileView: View {
    @Environment(\.dismiss) var dismiss
    @EnvironmentObject var supabase: SupabaseManager

    @State private var fullName: String = ""
    @State private var phone: String = ""
    @State private var username: String = ""

    @State private var isLoading = false
    @State private var showError = false
    @State private var errorMessage = ""
    @State private var phoneValidationError: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("Informações Pessoais") {
                    TextField("Nome completo", text: $fullName)
                        .textContentType(.name)
                        .autocapitalization(.words)

                    TextField("Nome de usuário", text: $username)
                        .textContentType(.username)
                        .autocapitalization(.none)
                        .autocorrectionDisabled()
                }

                Section {
                    TextField("Telefone", text: $phone)
                        .keyboardType(.phonePad)
                        .onChange(of: phone) { _, newValue in
                            phone = formatPhoneInput(newValue)
                            validatePhone()
                        }
                } header: {
                    Text("Telefone")
                } footer: {
                    if let error = phoneValidationError {
                        Text(error)
                            .foregroundColor(.red)
                    } else {
                        Text("Formato: (XX) XXXXX-XXXX ou (XX) XXXX-XXXX")
                    }
                }
            }
            .navigationTitle("Editar Perfil")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancelar") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Salvar") {
                        Task { await save() }
                    }
                    .disabled(!isFormValid)
                    .fontWeight(.semibold)
                }
            }
            .loadingOverlay(isLoading: isLoading, text: "Salvando...")
            .alert("Erro", isPresented: $showError) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(errorMessage)
            }
            .onAppear {
                loadCurrentProfile()
            }
        }
    }

    private var isFormValid: Bool {
        !fullName.trimmed.isEmpty && phoneValidationError == nil
    }

    private func loadCurrentProfile() {
        if let profile = supabase.userProfile {
            fullName = profile.fullName ?? ""
            phone = profile.phone?.formattedPhone ?? ""
            username = profile.username ?? ""
        }
    }

    private func validatePhone() {
        let numbers = phone.filter { $0.isNumber }

        if numbers.isEmpty {
            phoneValidationError = nil
            return
        }

        if numbers.count < 10 {
            phoneValidationError = "Telefone incompleto. Digite DDD + número"
        } else if numbers.count > 11 {
            phoneValidationError = "Telefone inválido. Máximo 11 dígitos"
        } else if numbers.count == 10 || numbers.count == 11 {
            // Validar DDD (11-99)
            let ddd = Int(numbers.prefix(2)) ?? 0
            if ddd < 11 || ddd > 99 {
                phoneValidationError = "DDD inválido"
            } else {
                phoneValidationError = nil
            }
        } else {
            phoneValidationError = "Telefone inválido"
        }
    }

    /// Formata telefone enquanto o usuário digita
    private func formatPhoneInput(_ value: String) -> String {
        let numbers = value.filter { $0.isNumber }
        var result = ""

        for (index, char) in numbers.prefix(11).enumerated() {
            if index == 0 {
                result += "("
            }
            if index == 2 {
                result += ") "
            }
            // Para 11 dígitos: (XX) XXXXX-XXXX
            // Para 10 dígitos: (XX) XXXX-XXXX
            if numbers.count <= 10 && index == 6 {
                result += "-"
            } else if numbers.count == 11 && index == 7 {
                result += "-"
            }
            result += String(char)
        }

        return result
    }

    private func save() async {
        // Validar telefone antes de salvar
        validatePhone()
        guard phoneValidationError == nil else {
            errorMessage = phoneValidationError ?? "Telefone inválido"
            showError = true
            return
        }

        isLoading = true

        do {
            let phoneNumbers = phone.filter { $0.isNumber }

            try await supabase.client
                .from("user_profiles")
                .update([
                    "full_name": fullName.trimmed,
                    "phone": phoneNumbers.isEmpty ? nil : phoneNumbers,
                    "username": username.trimmed.isEmpty ? nil : username.trimmed
                ] as [String: String?])
                .eq("id", value: supabase.currentUser?.id.uuidString ?? "")
                .execute()

            // Recarregar perfil
            await supabase.fetchUserProfile()

            dismiss()
        } catch {
            errorMessage = error.localizedDescription
            showError = true
        }

        isLoading = false
    }
}

// MARK: - Notifications Settings View

struct NotificationsSettingsView: View {
    @Environment(\.dismiss) var dismiss
    @EnvironmentObject var supabase: SupabaseManager
    @StateObject private var notificationManager = NotificationManager.shared

    // Apenas toggles de ativação (horários são fixos no backend)
    @AppStorage("daily_summary_enabled") private var dailySummaryEnabled = false
    @AppStorage("daily_financial_summary_enabled") private var dailyFinancialSummaryEnabled = false
    @AppStorage("weekly_summary_enabled") private var weeklySummaryEnabled = false
    @AppStorage("weekly_preview_enabled") private var weeklyPreviewEnabled = true

    @AppStorage("appointment_reminder_enabled") private var appointmentReminderEnabled = false
    @AppStorage("appointment_reminder_minutes") private var appointmentReminderMinutes = 30

    @State private var showPermissionAlert = false

    var body: some View {
        NavigationStack {
            List {
                // Status de permissão
                if !notificationManager.isAuthorized {
                    Section {
                        HStack {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundColor(.orange)
                            Text("Notificações desativadas no sistema")
                                .font(.subheadline)
                        }

                        Button("Ativar Notificações") {
                            Task {
                                let granted = await notificationManager.requestAuthorization()
                                if granted {
                                    // Ativar todas as notificações automaticamente
                                    dailySummaryEnabled = true
                                    weeklySummaryEnabled = true
                                    weeklyPreviewEnabled = true
                                    if supabase.isOwner {
                                        dailyFinancialSummaryEnabled = true
                                    }

                                    appointmentReminderEnabled = true
                                    
                                    // Agendar todas as notificações
                                    await notificationManager.scheduleAllNotifications()
                                } else {
                                    showPermissionAlert = true
                                }
                            }
                        }
                    } footer: {
                        Text("Você precisa permitir notificações para receber lembretes")
                    }
                }

                // Resumo Diário
                Section {
                    Toggle("Resumo Diário", isOn: $dailySummaryEnabled)
                        .onChange(of: dailySummaryEnabled) { _, _ in
                            scheduleNotifications()
                        }
                } header: {
                    Label("Resumo Diário", systemImage: "sun.max.fill")
                } footer: {
                    Text("Enviado diariamente às 08:00 da manhã.")
                }
                
                // Resumo Financeiro (Owner Only)
                if supabase.isOwner {
                    Section {
                        Toggle("Resumo Financeiro Diário", isOn: $dailyFinancialSummaryEnabled)
                            .onChange(of: dailyFinancialSummaryEnabled) { _, _ in
                                scheduleNotifications()
                            }
                    } header: {
                        Label("Faturamento do Dia", systemImage: "dollarsign.circle.fill")
                    } footer: {
                        Text("Enviado diariamente às 21:00 com faturamento e pacientes atendidos.")
                    }
                }

                // Resumo Semanal
                Section {
                    Toggle("Resumo Semanal", isOn: $weeklySummaryEnabled)
                        .onChange(of: weeklySummaryEnabled) { _, _ in
                            scheduleNotifications()
                        }
                } header: {
                    Label("Resumo Semanal", systemImage: "calendar.badge.clock")
                } footer: {
                    Text("Enviado todo sábado às 22:00 com o balanço da semana.")
                }
                
                // Prévia da Semana
                Section {
                    Toggle("Prévia da Semana", isOn: $weeklyPreviewEnabled)
                        .onChange(of: weeklyPreviewEnabled) { _, _ in
                            scheduleNotifications()
                        }
                } header: {
                    Label("Prévia da Semana", systemImage: "sparkles")
                } footer: {
                    Text("Enviado todo domingo às 20:00 com pacientes agendados para a próxima semana.")
                }


                // Lembretes de Agendamentos
                Section {
                    Toggle("Lembretes de Agendamentos", isOn: $appointmentReminderEnabled)
                        .onChange(of: appointmentReminderEnabled) { _, _ in
                            scheduleNotifications()
                        }

                    if appointmentReminderEnabled {
                        Picker("Tempo de Antecedência", selection: $appointmentReminderMinutes) {
                            Text("30 minutos antes").tag(30)
                            Text("1 hora antes").tag(60)
                        }
                        .onChange(of: appointmentReminderMinutes) { _, _ in
                            scheduleNotifications()
                        }
                    }
                } header: {
                    Label("Lembretes de Agendamentos", systemImage: "bell.badge.fill")
                } footer: {
                    if appointmentReminderEnabled {
                        Text("Notificação enviada \(appointmentReminderMinutes == 30 ? "30 minutos" : "1 hora") antes de cada agendamento.")
                    } else {
                        Text("Receba lembretes antes dos seus agendamentos.")
                    }
                }
            }
            .navigationTitle("Notificações")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Fechar") {
                        dismiss()
                    }
                }
            }
            .alert("Permissão Necessária", isPresented: $showPermissionAlert) {
                Button("Abrir Ajustes") {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                }
                Button("Cancelar", role: .cancel) {}
            } message: {
                Text("Para receber notificações, você precisa permitir nas configurações do seu iPhone.")
            }
            .task {
                await notificationManager.checkAuthorizationStatus()
            }
        }
    }

    private func scheduleNotifications() {
        Task {
            await notificationManager.scheduleAllNotifications()
        }
    }
}

#Preview {
    NavigationStack {
        SettingsView()
    }
    .environmentObject(SupabaseManager.shared)
}
