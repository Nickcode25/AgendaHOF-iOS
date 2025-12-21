import SwiftUI

struct PatientDetailView: View {
    @Environment(\.dismiss) var dismiss
    let patient: Patient
    var onUpdate: () -> Void

    @State private var showEditSheet = false
    @State private var showDeleteConfirmation = false
    @State private var isDeleting = false
    @State private var patientAppointments: [Appointment] = []
    @State private var isLoadingAppointments = false
    @State private var currentPatient: Patient?  // ✅ Estado local para o paciente atualizado

    @StateObject private var patientService = PatientService()
    @StateObject private var appointmentService = AppointmentService()

    // ✅ Usar o paciente atualizado se disponível, senão usar o original
    private var displayPatient: Patient {
        currentPatient ?? patient
    }

    var body: some View {
        NavigationStack {
            List {
                // Header com avatar e nome
                Section {
                    HStack(spacing: 16) {
                        AvatarView(
                            name: displayPatient.name,
                            imageUrl: displayPatient.photoUrl,
                            size: 70
                        )

                        VStack(alignment: .leading, spacing: 4) {
                            Text(displayPatient.name)
                                .font(.title2)
                                .fontWeight(.bold)

                            if let age = displayPatient.age {
                                Text("\(age) anos")
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                            }

                            if let birthDate = displayPatient.birthDate {
                                Text(birthDate, style: .date)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                    .padding(.vertical, 8)
                }

                // Contato
                Section("Contato") {
                    if let phone = displayPatient.phone, !phone.isEmpty {
                        Link(destination: URL(string: "tel:\(phone.replacingOccurrences(of: " ", with: ""))")!) {
                            Label(phone, systemImage: "phone.fill")
                        }

                        Link(destination: URL(string: "https://wa.me/55\(phone.filter { $0.isNumber })")!) {
                            HStack {
                                Image("whatsapp")
                                    .resizable()
                                    .scaledToFit()
                                    .frame(width: 20, height: 20)
                                Text("WhatsApp")
                            }
                            .foregroundColor(.green)
                        }
                    }

                    if let email = displayPatient.email, !email.isEmpty {
                        Link(destination: URL(string: "mailto:\(email)")!) {
                            Label(email, systemImage: "envelope.fill")
                        }
                    }

                    if displayPatient.phone == nil && displayPatient.email == nil {
                        Text("Nenhum contato cadastrado")
                            .foregroundColor(.secondary)
                            .font(.subheadline)
                    }
                }

                // Histórico de Procedimentos
                Section("Últimos Procedimentos") {
                    if isLoadingAppointments {
                        HStack {
                            Spacer()
                            ProgressView()
                            Spacer()
                        }
                    } else if patientAppointments.isEmpty {
                        Text("Nenhum procedimento registrado")
                            .foregroundColor(.secondary)
                            .font(.subheadline)
                    } else {
                        ForEach(patientAppointments) { appointment in
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(appointment.procedure ?? "Procedimento")
                                        .font(.body)
                                        .fontWeight(.medium)

                                    Text(appointment.start.formatted(date: .abbreviated, time: .shortened))
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }

                                Spacer()

                                Text(appointment.professional)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            .padding(.vertical, 2)
                        }
                    }
                }

                // Documentos
                if let cpf = displayPatient.cpf, !cpf.isEmpty {
                    Section("Documentos") {
                        LabeledContent("CPF") {
                            Text(cpf)
                        }
                    }
                }

                // Endereço
                if let address = displayPatient.fullAddress {
                    Section("Endereço") {
                        Text(address)
                            .font(.subheadline)
                    }
                }

                // Informações Clínicas
                if let clinicalInfo = displayPatient.clinicalInfo, !clinicalInfo.isEmpty {
                    Section("Informações Clínicas") {
                        Text(clinicalInfo)
                            .font(.subheadline)
                    }
                }

                // Observações
                if let notes = displayPatient.notes, !notes.isEmpty {
                    Section("Observações") {
                        Text(notes)
                            .font(.subheadline)
                    }
                }

                // Ações
                Section {
                    Button(role: .destructive) {
                        showDeleteConfirmation = true
                    } label: {
                        Label("Excluir Paciente", systemImage: "trash")
                    }
                }
            }
            .navigationTitle("Paciente")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Fechar") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Editar") {
                        showEditSheet = true
                    }
                }
            }
            .loadingOverlay(isLoading: isDeleting, text: "Excluindo...")
            .alert("Excluir Paciente", isPresented: $showDeleteConfirmation) {
                Button("Cancelar", role: .cancel) {}
                Button("Excluir", role: .destructive) {
                    Task { await deletePatient() }
                }
            } message: {
                Text("Tem certeza que deseja excluir \(patient.name)? Esta ação não pode ser desfeita.")
            }
            .sheet(isPresented: $showEditSheet) {
                EditPatientView(patient: displayPatient) {
                    Task {
                        await reloadPatient()
                    }
                    onUpdate()
                }
            }
            .task {
                await loadPatientAppointments()
            }
        }
    }

    private func loadPatientAppointments() async {
        isLoadingAppointments = true
        patientAppointments = await appointmentService.fetchAppointmentsByPatient(patientId: patient.id)
        isLoadingAppointments = false
    }

    // ✅ Recarregar dados do paciente após edição
    private func reloadPatient() async {
        if let updated = await patientService.fetchPatient(id: patient.id) {
            currentPatient = updated
        }
    }

    private func deletePatient() async {
        isDeleting = true

        do {
            try await patientService.deletePatient(id: patient.id)
            onUpdate()
            dismiss()
        } catch {
            print("Erro ao excluir paciente: \(error)")
        }

        isDeleting = false
    }
}

// MARK: - Edit Patient View

struct EditPatientView: View {
    @Environment(\.dismiss) var dismiss
    let patient: Patient
    var onSave: () -> Void

    @State private var name: String
    @State private var phone: String
    @State private var birthDate: Date?  // ✅ Tornar opcional
    @State private var hasBirthDate: Bool  // ✅ Controlar se tem data de nascimento
    @State private var notes: String

    @State private var isLoading = false
    @State private var showError = false
    @State private var errorMessage = ""

    @StateObject private var patientService = PatientService()

    init(patient: Patient, onSave: @escaping () -> Void) {
        self.patient = patient
        self.onSave = onSave

        _name = State(initialValue: patient.name)
        _phone = State(initialValue: patient.phone ?? "")
        _birthDate = State(initialValue: patient.birthDate)  // ✅ Não usar Date() como fallback
        _hasBirthDate = State(initialValue: patient.birthDate != nil)  // ✅ Verificar se existe
        _notes = State(initialValue: patient.notes ?? "")
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Informações Básicas") {
                    TextField("Nome completo", text: $name)

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

                Section("Observações") {
                    TextEditor(text: $notes)
                        .frame(minHeight: 80)
                }
            }
            .navigationTitle("Editar Paciente")
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
        }
    }

    private func save() async {
        isLoading = true

        do {
            let updates: [String: AnyEncodable] = [
                "name": AnyEncodable(name),
                "phone": AnyEncodable(phone.isEmpty ? NSNull() : phone),
                "birth_date": AnyEncodable(hasBirthDate && birthDate != nil ? birthDate! : NSNull()),  // ✅ Salvar null se não informar
                "notes": AnyEncodable(notes.isEmpty ? NSNull() : notes)
            ]

            try await patientService.updatePatient(id: patient.id, updates: updates)
            onSave()
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
            showError = true
        }

        isLoading = false
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
}

#Preview {
    PatientDetailView(
        patient: Patient(
            id: "1",
            createdAt: Date(),
            updatedAt: Date(),
            userId: "user1",
            name: "João Silva",
            cpf: "123.456.789-00",
            birthDate: Calendar.current.date(byAdding: .year, value: -30, to: Date()),
            phone: "(11) 99999-9999",
            email: "joao@email.com",
            isActive: true
        )
    ) {}
}
