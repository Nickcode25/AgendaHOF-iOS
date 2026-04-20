import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var supabase: SupabaseManager
    @EnvironmentObject var subscriptionManager: SubscriptionManager
    @StateObject private var authViewModel = AuthViewModel()

    @State private var showLogoutConfirmation = false
    @State private var showProfile = false
    @State private var showNotifications = false
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
                NavigationLink {
                    ProceduresManagementView()
                } label: {
                    SettingsRowContent(
                        icon: "cross.case.fill",
                        iconColor: .teal,
                        title: "Procedimentos"
                    )
                }

                // Relatório Financeiro (apenas owner)
                if supabase.isOwner {
                    NavigationLink {
                        FinancialReportView()
                            .environmentObject(supabase)
                    } label: {
                        SettingsRowContent(
                            icon: "chart.bar.fill",
                            iconColor: .green,
                            title: "Relatório Financeiro"
                        )
                    }
                }
                // Retornos (Gestão de Procedimentos Periódicos)
                NavigationLink {
                    ReturnsView()
                } label: {
                    SettingsRowContent(
                        icon: "arrow.triangle.2.circlepath",
                        iconColor: .indigo,
                        title: "Retornos"
                    )
                }
                
                // Pacientes Inativos (+6 meses)
                NavigationLink {
                    InactivePatientsView()
                        .environmentObject(supabase)
                } label: {
                    SettingsRowContent(
                        icon: "person.badge.clock.fill",
                        iconColor: Color(hex: "ff6b00"),
                        title: "Pacientes Inativos (+6 meses)"
                    )
                }
            }

            // Configurações (apenas owner)
            if supabase.isOwner {
                Section("Configurações") {
                    SettingsRow(
                        icon: "bell.fill",
                        iconColor: .red,
                        title: "Notificações"
                    ) {
                        showNotifications = true
                    }
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

struct SettingsRowContent: View {
    let icon: String
    let iconColor: Color
    let title: String

    var body: some View {
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

struct SettingsRow: View {
    let icon: String
    let iconColor: Color
    let title: String
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            SettingsRowContent(icon: icon, iconColor: iconColor, title: title)
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
        if phone.isEmpty {
            phoneValidationError = nil
            return
        }
        
        if PhoneFormatter.normalizeBR(phone) != nil {
             phoneValidationError = nil
        } else {
             phoneValidationError = "Telefone inválido. Verifique o DDD e o número."
        }
    }

    /// Formata telefone enquanto o usuário digita
    private func formatPhoneInput(_ value: String) -> String {
        let numbers = value.filter { $0.isNumber }
        var result = ""

        // Remove DDI 55 se vier com ele (ex: 55319...)
        if numbers.hasPrefix("55") && numbers.count > 11 {
             let numbersWithoutDDI = String(numbers.dropFirst(2))
             // Apenas remover se o restante parecer um número válido com DDD
             return formatBR(numbersWithoutDDI)
        }
        
        return formatBR(numbers)
    }
    
    private func formatBR(_ numbers: String) -> String {
        var result = ""
        for (index, char) in numbers.prefix(11).enumerated() {
            if index == 0 { result += "(" }
            if index == 2 { result += ") " }
            if numbers.count <= 10 && index == 6 { result += "-" }
            else if numbers.count == 11 && index == 7 { result += "-" }
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
            // Normalizar telefone
            var phoneE164: String? = nil
            if !phone.isEmpty {
                phoneE164 = PhoneFormatter.normalizeBR(phone)
            }
            
            let phoneToSave = phone.isEmpty ? nil : phone

            try await supabase.client
                .from("user_profiles")
                .update([
                    "full_name": fullName.trimmed,
                    "phone": phoneToSave,
                    "phone_e164": phoneE164,
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

// MARK: - Procedures Management

@MainActor
final class ProceduresViewModel: ObservableObject {
    @Published private(set) var procedures: [Procedure] = []
    @Published var isLoading = false
    @Published var errorMessage: String?

    private let service: ProcedureService
    private var hasLoaded = false

    init(service: ProcedureService? = nil) {
        self.service = service ?? ProcedureService(supabase: SupabaseManager.shared)
    }

    func loadProceduresIfNeeded() async {
        guard !hasLoaded else { return }
        hasLoaded = true
        await refreshProcedures()
    }

    func refreshProcedures() async {
        isLoading = true
        defer { isLoading = false }

        do {
            let ownerId = try resolveOwnerId()
            procedures = try await service.fetchProcedures(ownerId: ownerId)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    fileprivate func createProcedure(from draft: ProcedureDraft) async throws {
        let ownerId = try resolveOwnerId()
        let payload = try draft.toInsert()
        _ = try await service.createProcedure(procedure: payload, ownerId: ownerId)
        procedures = try await service.fetchProcedures(ownerId: ownerId)
    }

    fileprivate func updateProcedure(_ procedure: Procedure, from draft: ProcedureDraft) async throws {
        let ownerId = try resolveOwnerId()
        let patch = try draft.toUpdate()
        try await service.updateProcedure(id: procedure.id, patch: patch)
        procedures = try await service.fetchProcedures(ownerId: ownerId)
    }

    func archiveProcedure(_ procedure: Procedure) async {
        do {
            try await service.archiveProcedure(id: procedure.id)
            procedures.removeAll { $0.id == procedure.id }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func deleteProcedure(_ procedure: Procedure) async {
        do {
            try await service.deleteProcedure(id: procedure.id)
            procedures.removeAll { $0.id == procedure.id }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func resolveOwnerId() throws -> UUID {
        guard let ownerIdString = SupabaseManager.shared.effectiveUserId,
              let ownerId = UUID(uuidString: ownerIdString) else {
            throw ProcedureServiceError.ownerIdNotInjected
        }
        return ownerId
    }
}

struct ProceduresManagementView: View {
    @StateObject private var viewModel = ProceduresViewModel()

    @State private var activeSheet: ProcedureSheet?
    @State private var procedurePendingArchive: Procedure?
    @State private var procedurePendingDelete: Procedure?

    var body: some View {
        List {
            if viewModel.procedures.isEmpty && !viewModel.isLoading {
                ContentUnavailableView(
                    "Nenhum procedimento cadastrado",
                    systemImage: "cross.case",
                    description: Text("Toque em + para adicionar o primeiro procedimento da clínica.")
                )
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
            } else {
                Section("Ativos") {
                    ForEach(viewModel.procedures) { procedure in
                        Button {
                            activeSheet = .edit(procedure)
                        } label: {
                            ProcedureRowView(procedure: procedure)
                        }
                        .buttonStyle(.plain)
                        .swipeActions(edge: .leading, allowsFullSwipe: false) {
                            Button {
                                activeSheet = .edit(procedure)
                            } label: {
                                Label("Editar", systemImage: "pencil")
                            }
                            .tint(.blue)
                        }
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button {
                                procedurePendingArchive = procedure
                            } label: {
                                Label("Arquivar", systemImage: "archivebox")
                            }
                            .tint(.orange)

                            Button(role: .destructive) {
                                procedurePendingDelete = procedure
                            } label: {
                                Label("Excluir", systemImage: "trash")
                            }
                        }
                    }
                }
            }
        }
        .overlay {
            if viewModel.isLoading && viewModel.procedures.isEmpty {
                ProgressView("Carregando procedimentos...")
            }
        }
        .navigationTitle("Procedimentos")
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    activeSheet = .create
                } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .refreshable {
            await viewModel.refreshProcedures()
        }
        .task {
            await viewModel.loadProceduresIfNeeded()
        }
        .sheet(item: $activeSheet) { sheet in
            switch sheet {
            case .create:
                NavigationStack {
                    ProcedureEditorView(
                        title: "Novo Procedimento",
                        submitButtonTitle: "Salvar",
                        draft: ProcedureDraft()
                    ) { draft in
                        try await viewModel.createProcedure(from: draft)
                    }
                }
            case .edit(let procedure):
                NavigationStack {
                    ProcedureEditorView(
                        title: "Editar Procedimento",
                        submitButtonTitle: "Salvar",
                        draft: ProcedureDraft(procedure: procedure)
                    ) { draft in
                        try await viewModel.updateProcedure(procedure, from: draft)
                    }
                }
            }
        }
        .alert(
            "Arquivar Procedimento?",
            isPresented: Binding(
                get: { procedurePendingArchive != nil },
                set: { newValue in
                    if !newValue { procedurePendingArchive = nil }
                }
            ),
            actions: {
                Button("Cancelar", role: .cancel) {
                    procedurePendingArchive = nil
                }
                Button("Arquivar") {
                    guard let procedure = procedurePendingArchive else { return }
                    Task { await viewModel.archiveProcedure(procedure) }
                    procedurePendingArchive = nil
                }
            },
            message: {
                Text("O procedimento ficará inativo e não aparecerá nas listas padrão.")
            }
        )
        .alert(
            "Excluir Procedimento?",
            isPresented: Binding(
                get: { procedurePendingDelete != nil },
                set: { newValue in
                    if !newValue { procedurePendingDelete = nil }
                }
            ),
            actions: {
                Button("Cancelar", role: .cancel) {
                    procedurePendingDelete = nil
                }
                Button("Excluir", role: .destructive) {
                    guard let procedure = procedurePendingDelete else { return }
                    Task { await viewModel.deleteProcedure(procedure) }
                    procedurePendingDelete = nil
                }
            },
            message: {
                Text("Essa ação remove o procedimento permanentemente.")
            }
        )
        .alert("Erro", isPresented: Binding(
            get: { viewModel.errorMessage != nil },
            set: { newValue in
                if !newValue { viewModel.errorMessage = nil }
            }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(viewModel.errorMessage ?? "Erro desconhecido.")
        }
    }
}

private struct ProcedureRowView: View {
    let procedure: Procedure

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(procedure.name)
                        .font(.headline)
                        .foregroundColor(.primary)

                    if let category = procedure.category, !category.trimmed.isEmpty {
                        Text(category)
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                }

                Spacer()

                Text(procedure.priceFormatted)
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(.green)
            }

            HStack(spacing: 8) {
                Label(procedure.durationFormatted, systemImage: "clock")
                    .font(.caption)
                    .foregroundColor(.secondary)

                if procedure.enableReturnTracking == true {
                    ProcedureTag(text: "Retorno")
                }

                if !procedure.stockCategories.isEmpty {
                    ProcedureTag(text: "Estoque")
                }
            }
        }
        .padding(.vertical, 4)
    }
}

private struct ProcedureTag: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.caption2.weight(.semibold))
            .foregroundColor(.indigo)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color.indigo.opacity(0.12))
            .clipShape(Capsule())
    }
}

private enum ProcedureSheet: Identifiable {
    case create
    case edit(Procedure)

    var id: String {
        switch self {
        case .create:
            return "create"
        case .edit(let procedure):
            return "edit-\(procedure.id.uuidString)"
        }
    }
}

private struct ProcedureEditorView: View {
    @Environment(\.dismiss) private var dismiss

    let title: String
    let submitButtonTitle: String
    let onSave: (ProcedureDraft) async throws -> Void

    @State private var draft: ProcedureDraft
    @State private var isSaving = false
    @State private var errorMessage: String?

    init(
        title: String,
        submitButtonTitle: String,
        draft: ProcedureDraft,
        onSave: @escaping (ProcedureDraft) async throws -> Void
    ) {
        self.title = title
        self.submitButtonTitle = submitButtonTitle
        self.onSave = onSave
        _draft = State(initialValue: draft)
    }

    var body: some View {
        Form {
            Section("Informações Básicas") {
                TextField("Nome *", text: $draft.name)
                    .textInputAutocapitalization(.words)

                TextField("Categoria", text: $draft.category)
                    .textInputAutocapitalization(.words)

                TextField("Descrição", text: $draft.description, axis: .vertical)
                    .lineLimit(2...4)
            }

            Section("Valores") {
                TextField("Preço *", text: $draft.price)
                    .keyboardType(.decimalPad)

                TextField("Valor à vista (opcional)", text: $draft.cashValue)
                    .keyboardType(.decimalPad)

                TextField("Valor no cartão (opcional)", text: $draft.cardValue)
                    .keyboardType(.decimalPad)
            }

            Section("Atendimento") {
                TextField("Duração em minutos (opcional)", text: $draft.durationMinutes)
                    .keyboardType(.numberPad)
            }

            Section("Baixa de Estoque") {
                if draft.stockCategories.isEmpty {
                    Text("Nenhuma categoria vinculada.")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }

                ForEach($draft.stockCategories) { $stock in
                    VStack(alignment: .leading, spacing: 8) {
                        TextField("Categoria", text: $stock.category)
                            .textInputAutocapitalization(.words)

                        HStack {
                            Stepper("Quantidade usada: \(stock.quantityUsed)", value: $stock.quantityUsed, in: 1...9999)

                            Spacer()

                            Button(role: .destructive) {
                                removeStockCategory(id: stock.id)
                            } label: {
                                Image(systemName: "trash")
                            }
                        }
                    }
                    .padding(.vertical, 4)
                }

                Button {
                    draft.stockCategories.append(.init())
                } label: {
                    Label("Adicionar Categoria de Estoque", systemImage: "plus.circle")
                }
            }

            Section("Retorno Inteligente") {
                Toggle("Ativar controle de retorno", isOn: $draft.enableReturnTracking)

                if draft.enableReturnTracking {
                    TextField("Intervalo", text: $draft.returnIntervalValue)
                        .keyboardType(.numberPad)

                    Picker("Unidade", selection: $draft.returnIntervalUnit) {
                        ForEach(ProcedureReturnIntervalUnit.allCases, id: \.self) { unit in
                            Text(unit.displayLabel).tag(unit)
                        }
                    }

                    TextField("Alertar antes (dias)", text: $draft.returnAlertBeforeDays)
                        .keyboardType(.numberPad)

                    TextField("Mensagem de retorno", text: $draft.returnMessageTemplate, axis: .vertical)
                        .lineLimit(2...5)
                }
            }
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button("Cancelar") {
                    dismiss()
                }
            }

            ToolbarItem(placement: .navigationBarTrailing) {
                Button(submitButtonTitle) {
                    save()
                }
                .disabled(isSaving || draft.name.trimmed.isEmpty || draft.price.trimmed.isEmpty)
                .fontWeight(.semibold)
            }
        }
        .loadingOverlay(isLoading: isSaving, text: "Salvando...")
        .alert("Erro ao salvar", isPresented: Binding(
            get: { errorMessage != nil },
            set: { newValue in
                if !newValue { errorMessage = nil }
            }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "Erro desconhecido.")
        }
    }

    private func removeStockCategory(id: UUID) {
        draft.stockCategories.removeAll { $0.id == id }
    }

    private func save() {
        Task {
            isSaving = true
            defer { isSaving = false }

            do {
                try await onSave(draft)
                dismiss()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}

private struct StockCategoryDraft: Identifiable, Hashable {
    let id: UUID
    var category: String
    var quantityUsed: Int

    init(id: UUID = UUID(), category: String = "", quantityUsed: Int = 1) {
        self.id = id
        self.category = category
        self.quantityUsed = quantityUsed
    }
}

private struct ProcedureDraft: Hashable {
    var name: String = ""
    var description: String = ""
    var price: String = ""
    var cashValue: String = ""
    var cardValue: String = ""
    var durationMinutes: String = ""
    var category: String = ""
    var stockCategories: [StockCategoryDraft] = []
    var enableReturnTracking: Bool = false
    var returnIntervalValue: String = "1"
    var returnIntervalUnit: ProcedureReturnIntervalUnit = .months
    var returnAlertBeforeDays: String = "15"
    var returnMessageTemplate: String = ""

    init() {}

    init(procedure: Procedure) {
        name = procedure.name
        description = procedure.description ?? ""
        price = Self.formatDecimal(procedure.price)
        cashValue = procedure.cashValue.map(Self.formatDecimal) ?? ""
        cardValue = procedure.cardValue.map(Self.formatDecimal) ?? ""
        durationMinutes = procedure.durationMinutes.map(String.init) ?? ""
        category = procedure.category ?? ""
        stockCategories = procedure.stockCategories.map {
            .init(category: $0.category, quantityUsed: max(1, $0.quantityUsed))
        }
        enableReturnTracking = procedure.enableReturnTracking ?? false
        returnIntervalValue = procedure.returnIntervalValue.map(String.init) ?? "1"
        returnIntervalUnit = procedure.returnIntervalUnit ?? .months
        returnAlertBeforeDays = procedure.returnAlertBeforeDays.map(String.init) ?? "15"
        returnMessageTemplate = procedure.returnMessageTemplate ?? ""
    }

    func toInsert() throws -> ProcedureInsert {
        let normalizedName = name.trimmed
        guard !normalizedName.isEmpty else { throw ProcedureDraftError.invalidName }

        guard let parsedPrice = Self.parseRequiredDouble(price) else {
            throw ProcedureDraftError.invalidPrice
        }

        let parsedCash = try Self.parseOptionalDouble(cashValue, error: .invalidCashValue)
        let parsedCard = try Self.parseOptionalDouble(cardValue, error: .invalidCardValue)
        let parsedDuration = try Self.parseOptionalInt(durationMinutes, error: .invalidDurationMinutes)

        let hasTracking = enableReturnTracking
        let parsedReturnInterval = hasTracking
            ? (try Self.parseOptionalInt(returnIntervalValue, error: .invalidReturnIntervalValue) ?? 1)
            : nil
        let parsedAlertDays = hasTracking
            ? (try Self.parseOptionalInt(returnAlertBeforeDays, error: .invalidReturnAlertDays))
            : nil

        return ProcedureInsert(
            name: normalizedName,
            description: description.trimmed.isEmpty ? nil : description.trimmed,
            price: parsedPrice,
            cashValue: parsedCash,
            cardValue: parsedCard,
            durationMinutes: parsedDuration,
            category: category.trimmed.isEmpty ? nil : category.trimmed,
            isActive: true,
            stockCategories: normalizedStockCategories,
            enableReturnTracking: hasTracking,
            returnIntervalValue: parsedReturnInterval,
            returnIntervalUnit: hasTracking ? returnIntervalUnit : nil,
            returnAlertBeforeDays: parsedAlertDays,
            returnMessageTemplate: hasTracking ? (returnMessageTemplate.trimmed.isEmpty ? nil : returnMessageTemplate.trimmed) : nil
        )
    }

    func toUpdate() throws -> ProcedureUpdate {
        let insert = try toInsert()
        return ProcedureUpdate(
            name: insert.name,
            description: insert.description,
            price: insert.price,
            cashValue: insert.cashValue,
            cardValue: insert.cardValue,
            durationMinutes: insert.durationMinutes,
            category: insert.category,
            isActive: insert.isActive,
            stockCategories: insert.stockCategories,
            enableReturnTracking: insert.enableReturnTracking,
            returnIntervalValue: insert.returnIntervalValue,
            returnIntervalUnit: insert.returnIntervalUnit,
            returnAlertBeforeDays: insert.returnAlertBeforeDays,
            returnMessageTemplate: insert.returnMessageTemplate
        )
    }

    private var normalizedStockCategories: [StockCategory] {
        stockCategories
            .map {
                StockCategory(
                    category: $0.category.trimmed,
                    quantityUsed: max(1, $0.quantityUsed)
                )
            }
            .filter { !$0.category.isEmpty }
    }

    private static func parseRequiredDouble(_ value: String) -> Double? {
        let trimmed = value.trimmed
        guard !trimmed.isEmpty else { return nil }
        return parseDouble(trimmed)
    }

    private static func parseOptionalDouble(
        _ value: String,
        error: ProcedureDraftError
    ) throws -> Double? {
        let trimmed = value.trimmed
        guard !trimmed.isEmpty else { return nil }

        guard let parsed = parseDouble(trimmed) else {
            throw error
        }
        return parsed
    }

    private static func parseOptionalInt(
        _ value: String,
        error: ProcedureDraftError
    ) throws -> Int? {
        let trimmed = value.trimmed
        guard !trimmed.isEmpty else { return nil }

        guard let parsed = Int(trimmed) else {
            throw error
        }
        return parsed
    }

    private static func parseDouble(_ value: String) -> Double? {
        if let number = brNumberFormatter.number(from: value) {
            return number.doubleValue
        }
        if let number = enNumberFormatter.number(from: value) {
            return number.doubleValue
        }

        let normalized = value.replacingOccurrences(of: ",", with: ".")
        return Double(normalized)
    }

    private static func formatDecimal(_ value: Double) -> String {
        brNumberFormatter.string(from: NSNumber(value: value)) ?? "\(value)"
    }

    private static let brNumberFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "pt_BR")
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 2
        formatter.minimumFractionDigits = 0
        return formatter
    }()

    private static let enNumberFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 2
        formatter.minimumFractionDigits = 0
        return formatter
    }()
}

private enum ProcedureDraftError: LocalizedError {
    case invalidName
    case invalidPrice
    case invalidCashValue
    case invalidCardValue
    case invalidDurationMinutes
    case invalidReturnIntervalValue
    case invalidReturnAlertDays

    var errorDescription: String? {
        switch self {
        case .invalidName:
            return "Informe o nome do procedimento."
        case .invalidPrice:
            return "Informe um preço válido."
        case .invalidCashValue:
            return "Valor à vista inválido."
        case .invalidCardValue:
            return "Valor no cartão inválido."
        case .invalidDurationMinutes:
            return "Duração inválida. Use apenas números inteiros."
        case .invalidReturnIntervalValue:
            return "Intervalo de retorno inválido. Use apenas números inteiros."
        case .invalidReturnAlertDays:
            return "Dias de alerta inválidos. Use apenas números inteiros."
        }
    }
}

private extension ProcedureReturnIntervalUnit {
    var displayLabel: String {
        switch self {
        case .days:
            return "Dias"
        case .weeks:
            return "Semanas"
        case .months:
            return "Meses"
        }
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
