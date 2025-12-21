import SwiftUI

struct PatientsListView: View {
    @StateObject private var patientService = PatientService()
    @State private var searchText = ""
    @State private var showNewPatient = false
    @State private var showContactPicker = false
    @State private var selectedPatient: Patient?
    @State private var importedContact: ContactInfo?

    var filteredPatients: [Patient] {
        if searchText.isEmpty {
            return patientService.patients
        }
        return patientService.patients.filter {
            $0.name.localizedCaseInsensitiveContains(searchText) ||
            ($0.phone?.contains(searchText) ?? false) ||
            ($0.email?.localizedCaseInsensitiveContains(searchText) ?? false)
        }
    }

    // Agrupar por letra inicial
    var groupedPatients: [(String, [Patient])] {
        let grouped = Dictionary(grouping: filteredPatients) { patient in
            String(patient.name.prefix(1)).uppercased()
        }
        return grouped.sorted { $0.key < $1.key }
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
        .searchable(text: $searchText, prompt: "Buscar paciente...")
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                HStack(spacing: 16) {
                    // Botão importar contatos
                    Button {
                        showContactPicker = true
                    } label: {
                        Image(systemName: "person.crop.circle.badge.plus")
                    }

                    // Botão novo paciente
                    Button {
                        showNewPatient = true
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
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
            ForEach(groupedPatients, id: \.0) { letter, patients in
                Section(header: Text(letter)) {
                    ForEach(patients) { patient in
                        PatientRow(patient: patient)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                selectedPatient = patient
                            }
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .overlay {
            if !searchText.isEmpty && filteredPatients.isEmpty {
                EmptyStateView.noResults(query: searchText)
            }
        }
    }
}

// MARK: - Patient Row

struct PatientRow: View {
    let patient: Patient

    var body: some View {
        HStack(spacing: 12) {
            AvatarView(
                name: patient.name,
                imageUrl: patient.photoUrl,
                size: 44
            )

            VStack(alignment: .leading, spacing: 4) {
                Text(patient.name)
                    .font(.body)
                    .fontWeight(.medium)

                HStack(spacing: 8) {
                    if let phone = patient.phone, !phone.isEmpty {
                        Label(phone, systemImage: "phone")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    if let age = patient.age {
                        Text("\(age) anos")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding(.vertical, 4)
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
    @State private var birthDate: Date?  // ✅ Tornar opcional
    @State private var hasBirthDate: Bool  // ✅ Controlar se tem data de nascimento
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
                _hasBirthDate = State(initialValue: true)  // ✅ Ativar toggle se vier do contato
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
                        hasBirthDate = true  // ✅ Ativar toggle se importar data
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
                birthDate: hasBirthDate ? birthDate : nil,  // ✅ Salvar nil se toggle estiver desativado
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
