import SwiftUI

struct PatientsListView: View {
    @StateObject private var patientService = PatientService()
    @State private var searchText = ""
    @State private var showNewPatient = false
    @State private var showContactPicker = false
    @State private var selectedPatient: Patient?
    @State private var importedContact: ContactInfo?
    @State private var showMenu = false

    var filteredPatients: [Patient] {
        if searchText.isEmpty {
            return patientService.patients
        }

        // Normalizar texto de busca (remover acentos e converter para minúsculas)
        let normalizedSearch = searchText.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)

        return patientService.patients.filter { patient in
            // Normalizar nome do paciente
            let normalizedName = patient.name.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)

            // Normalizar email se existir
            let normalizedEmail = patient.email?.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)

            return normalizedName.contains(normalizedSearch) ||
                   (patient.phone?.contains(searchText) ?? false) ||
                   (normalizedEmail?.contains(normalizedSearch) ?? false)
        }
    }

    var body: some View {
        Group {
            if patientService.isLoading && patientService.patients.isEmpty {
                LoadingView(text: "Carregando pacientes...")
            } else if patientService.patients.isEmpty {
                EmptyStateView.noPatients {
                    showNewPatient = true
                }
            } else {
                patientsList
            }
        }
        .navigationTitle("Pacientes")
        .searchable(text: $searchText, prompt: "Buscar paciente pelo nome")
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    showMenu = true
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.primary)
                        .frame(width: 32, height: 32)
                        .background(Color(.systemGray5))
                        .clipShape(Circle())
                }
            }
        }
        .actionSheet(isPresented: $showMenu) {
            ActionSheet(
                title: Text("Opções"),
                buttons: [
                    .default(Text("Novo Paciente")) {
                        showNewPatient = true
                    },
                    .default(Text("Importar Contatos")) {
                        showContactPicker = true
                    },
                    .cancel(Text("Cancelar"))
                ]
            )
        }
        .sheet(isPresented: $showContactPicker) {
            ContactPicker { contact in
                importedContact = contact
                showContactPicker = false
                showNewPatient = true
            }
        }
        .sheet(isPresented: $showNewPatient) {
            NewPatientView(importedContact: importedContact) {
                Task { await patientService.fetchPatients() }
                importedContact = nil
            }
        }
        .sheet(item: $selectedPatient) { patient in
            PatientDetailView(patient: patient) {
                Task { await patientService.fetchPatients() }
            }
            .onAppear {
                // Limpar busca e remover foco do teclado ao abrir o sheet
                UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
            }
        }
        .task {
            await patientService.fetchPatients()
        }
        .refreshable {
            await patientService.fetchPatients()
        }
    }

    private var patientsList: some View {
        List {
            ForEach(filteredPatients) { patient in
                PatientRowClinical(patient: patient)
                    .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
                    .onTapGesture {
                        selectedPatient = patient
                    }
            }
        }
        .listStyle(.plain)
        .overlay {
            if !searchText.isEmpty && filteredPatients.isEmpty {
                EmptyStateView.noResults(query: searchText)
            }
        }
    }
}

// MARK: - Patient Row Clinical (Design Único)

struct PatientRowClinical: View {
    let patient: Patient

    // Formatar data do último procedimento REALIZADO
    private var lastProcedureDate: String? {
        guard let procedures = patient.plannedProcedures,
              !procedures.isEmpty else {
            return nil
        }

        // Filtrar apenas procedimentos REALIZADOS (com performedAt preenchido)
        let performedProcedures = procedures.filter { $0.performedAt != nil }

        guard !performedProcedures.isEmpty else {
            return nil
        }

        // Pegar o procedimento mais recente
        let sortedProcedures = performedProcedures.sorted { proc1, proc2 in
            let date1 = proc1.performedAt ?? ""
            let date2 = proc2.performedAt ?? ""
            return date1 > date2
        }

        if let mostRecent = sortedProcedures.first,
           let dateString = mostRecent.performedAt {
            return formatDateString(dateString)
        }

        return nil
    }

    // Converter data de múltiplos formatos para padrão brasileiro dd/MM/yyyy
    private func formatDateString(_ dateString: String) -> String? {
        let displayFormatter = DateFormatter()
        displayFormatter.dateFormat = "dd/MM/yyyy"
        displayFormatter.locale = Locale(identifier: "pt_BR")

        // Tentar ISO8601 com milissegundos primeiro (2025-12-08T15:00:00.000Z)
        let iso8601WithMillis = ISO8601DateFormatter()
        iso8601WithMillis.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = iso8601WithMillis.date(from: dateString) {
            return displayFormatter.string(from: date)
        }

        // Tentar ISO8601 padrão (2025-12-08T15:00:00Z)
        let iso8601Formatter = ISO8601DateFormatter()
        if let date = iso8601Formatter.date(from: dateString) {
            return displayFormatter.string(from: date)
        }

        // Tentar formato yyyy-MM-dd HH:mm:ss
        let inputFormatter = DateFormatter()
        inputFormatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        if let date = inputFormatter.date(from: dateString) {
            return displayFormatter.string(from: date)
        }

        // Tentar formato yyyy-MM-dd
        inputFormatter.dateFormat = "yyyy-MM-dd"
        if let date = inputFormatter.date(from: dateString) {
            return displayFormatter.string(from: date)
        }

        // Tentar formato yyyy/MM/dd
        inputFormatter.dateFormat = "yyyy/MM/dd"
        if let date = inputFormatter.date(from: dateString) {
            return displayFormatter.string(from: date)
        }

        return nil
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 14) {
                // Avatar clínico quadrado (SEM iniciais)
                ZStack {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color(hex: "ff6b00").opacity(0.15),
                                    Color(hex: "ff6b00").opacity(0.08)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 50, height: 50)

                    Image(systemName: "person.fill.viewfinder")
                        .font(.system(size: 22, weight: .regular))
                        .foregroundStyle(Color(hex: "ff6b00"))
                }

                // Informações do paciente
                VStack(alignment: .leading, spacing: 5) {
                    Text(patient.name)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.primary)

                    if let lastDate = lastProcedureDate {
                        Text("Último Procedimento - \(lastDate)")
                            .font(.system(size: 13))
                            .foregroundStyle(.secondary)
                    } else {
                        Text("Nenhum procedimento registrado")
                            .font(.system(size: 13))
                            .foregroundStyle(.tertiary)
                    }
                }

                Spacer()

                // Indicador visual
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.quaternary)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color(.secondarySystemGroupedBackground))
            )

            // Separador personalizado
            Rectangle()
                .fill(Color(.systemGray5))
                .frame(height: 1)
                .padding(.leading, 78)
                .padding(.top, 8)
        }
    }
}

// MARK: - New Patient View

struct NewPatientView: View {
    @Environment(\.dismiss) var dismiss
    @EnvironmentObject var supabase: SupabaseManager

    var importedContact: ContactInfo?
    var onSave: () -> Void

    @State private var name = ""
    @State private var phone = ""
    @State private var birthDate: Date?
    @State private var hasBirthDate: Bool
    @State private var showContactPicker = false

    @State private var isLoading = false
    @State private var showError = false
    @State private var errorMessage = ""

    @StateObject private var patientService = PatientService()

    init(importedContact: ContactInfo? = nil, onSave: @escaping () -> Void) {
        self.importedContact = importedContact
        self.onSave = onSave

        // Preencher campos com dados do contato importado
        if let contact = importedContact {
            _name = State(initialValue: contact.name)
            _phone = State(initialValue: contact.phone ?? "")
            if let birthday = contact.birthday {
                _birthDate = State(initialValue: birthday)
                _hasBirthDate = State(initialValue: true)
            } else {
                _birthDate = State(initialValue: nil)
                _hasBirthDate = State(initialValue: false)
            }
        } else {
            _birthDate = State(initialValue: nil)
            _hasBirthDate = State(initialValue: false)
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Informações Básicas") {
                    TextField("Nome completo *", text: $name)

                    TextField("Telefone", text: $phone)
                        .keyboardType(.phonePad)
                        .onChange(of: phone) { _, newValue in
                            phone = formatPhoneBrazil(newValue)
                        }

                    Toggle("Informar Data de Nascimento", isOn: $hasBirthDate)
                        .onChange(of: hasBirthDate) { _, newValue in
                            if newValue && birthDate == nil {
                                birthDate = Calendar.current.date(byAdding: .year, value: -30, to: Date())
                            }
                        }

                    if hasBirthDate {
                        DatePicker(
                            "Data de Nascimento",
                            selection: Binding(
                                get: { birthDate ?? Date() },
                                set: { birthDate = $0 }
                            ),
                            in: ...Date(),
                            displayedComponents: .date
                        )
                    }
                }

                // Botão para importar contato
                Section {
                    Button {
                        showContactPicker = true
                    } label: {
                        HStack {
                            Image(systemName: "person.crop.circle.badge.plus")
                            Text("Importar Contato")
                        }
                        .foregroundColor(.appPrimary)
                    }
                }
            }
            .navigationTitle("Novo Paciente")
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
                    .disabled(name.isEmpty)
                    .fontWeight(.semibold)
                }
            }
            .loadingOverlay(isLoading: isLoading, text: "Salvando...")
            .alert("Erro", isPresented: $showError) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(errorMessage)
            }
            .sheet(isPresented: $showContactPicker) {
                ContactPicker { contact in
                    name = contact.name
                    if let contactPhone = contact.phone {
                        phone = formatPhoneBrazil(contactPhone)
                    }
                    if let birthday = contact.birthday {
                        birthDate = birthday
                        hasBirthDate = true
                    }
                    showContactPicker = false
                }
            }
        }
    }

    // Formata telefone no padrão brasileiro (XX) XXXXX-XXXX
    private func formatPhoneBrazil(_ value: String) -> String {
        let numbers = value.filter { $0.isNumber }
        var result = ""

        for (index, char) in numbers.prefix(11).enumerated() {
            if index == 0 {
                result += "("
            }
            if index == 2 {
                result += ") "
            }
            if index == 7 {
                result += "-"
            }
            result += String(char)
        }

        return result
    }

    private func save() async {
        guard let userId = supabase.effectiveUserId else {
            errorMessage = "Usuário não autenticado"
            showError = true
            return
        }

        isLoading = true

        do {
            let patient = Patient.Insert(
                userId: userId,
                name: name.trimmingCharacters(in: .whitespaces),
                birthDate: hasBirthDate ? birthDate : nil,
                phone: phone.isEmpty ? nil : phone
            )

            _ = try await patientService.createPatient(patient)
            onSave()
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
            showError = true
        }

        isLoading = false
    }
}

#Preview {
    NavigationStack {
        PatientsListView()
    }
    .environmentObject(SupabaseManager.shared)
}
