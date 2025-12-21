import SwiftUI

struct NewAppointmentView: View {
    @Environment(\.dismiss) var dismiss
    @EnvironmentObject var supabase: SupabaseManager

    let selectedDate: Date
    let isPersonal: Bool
    var onSave: () -> Void

    // Form state
    @State private var title = ""
    @State private var selectedPatient: Patient?
    @State private var procedure = ""
    @State private var date: Date
    @State private var startTime: Date
    @State private var endTime: Date
    @State private var selectedProfessional: Professional?

    // UI state
    @State private var isLoading = false
    @State private var showPatientPicker = false
    @State private var showProfessionalPicker = false
    @State private var showError = false
    @State private var errorMessage = ""

    // Services
    @StateObject private var patientService = PatientService()
    @StateObject private var professionalService = ProfessionalService()
    @StateObject private var appointmentService = AppointmentService()

    init(selectedDate: Date, isPersonal: Bool = false, onSave: @escaping () -> Void) {
        self.selectedDate = selectedDate
        self.isPersonal = isPersonal
        self.onSave = onSave

        let calendar = Calendar.current
        let now = Date()
        let startOfDay = calendar.startOfDay(for: selectedDate)

        // Horário inicial: próxima hora cheia
        let currentHour = calendar.component(.hour, from: now)
        let defaultStartTime = calendar.date(bySettingHour: max(currentHour + 1, 8), minute: 0, second: 0, of: startOfDay)!
        let defaultEndTime = calendar.date(byAdding: .hour, value: 1, to: defaultStartTime)!

        _date = State(initialValue: selectedDate)
        _startTime = State(initialValue: defaultStartTime)
        _endTime = State(initialValue: defaultEndTime)
    }

    var body: some View {
        NavigationStack {
            Form {
                // Campos específicos por tipo
                if isPersonal {
                    personalFields
                } else {
                    appointmentFields
                }

                // Campos comuns
                commonFields
            }
            .navigationTitle(isPersonal ? "Novo Compromisso" : "Novo Agendamento")
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
            .sheet(isPresented: $showPatientPicker) {
                PatientPickerView(
                    patients: patientService.patients,
                    selectedPatient: $selectedPatient
                )
            }
            .sheet(isPresented: $showProfessionalPicker) {
                ProfessionalPickerSheet(
                    professionals: professionalService.professionals,
                    selectedProfessional: $selectedProfessional
                ) {}
            }
            .task {
                await patientService.fetchPatients()
                await professionalService.fetchProfessionals()

                // Se há apenas 1 profissional, seleciona automaticamente
                // Se há mais de 1, deixa nil (usuário escolhe)
                if selectedProfessional == nil && professionalService.professionals.count == 1 {
                    selectedProfessional = professionalService.professionals.first
                }
            }
        }
    }

    // MARK: - Personal Fields

    private var personalFields: some View {
        Section("Compromisso") {
            TextField("Título", text: $title)
        }
    }

    // MARK: - Appointment Fields

    private var appointmentFields: some View {
        Group {
            Section("Paciente") {
                Button {
                    showPatientPicker = true
                } label: {
                    HStack {
                        if let patient = selectedPatient {
                            AvatarView(name: patient.name, size: 36)
                            Text(patient.name)
                                .foregroundColor(.primary)
                        } else {
                            Image(systemName: "person.crop.circle.badge.plus")
                                .foregroundColor(.appPrimary)
                            Text("Selecionar Paciente")
                                .foregroundColor(.appPrimary)
                        }
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }

            Section("Procedimento") {
                TextField("Ex: Consulta, Limpeza...", text: $procedure)
            }
        }
    }

    // MARK: - Common Fields

    private var commonFields: some View {
        Group {
            Section("Data e Horário") {
                DatePicker("Data", selection: $date, displayedComponents: .date)

                DatePicker("Início", selection: $startTime, displayedComponents: .hourAndMinute)

                DatePicker("Término", selection: $endTime, displayedComponents: .hourAndMinute)
            }

            if !professionalService.professionals.isEmpty {
                Section("Profissional") {
                    Button {
                        showProfessionalPicker = true
                    } label: {
                        HStack {
                            if let professional = selectedProfessional {
                                AvatarView(name: professional.name, size: 36)
                                VStack(alignment: .leading) {
                                    Text(professional.name)
                                        .foregroundColor(.primary)
                                    if let specialty = professional.specialty {
                                        Text(specialty)
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    }
                                }
                            } else {
                                Image(systemName: "person.crop.circle")
                                    .foregroundColor(.appPrimary)
                                Text("Selecionar Profissional")
                                    .foregroundColor(.appPrimary)
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }
        }
    }

    // MARK: - Validation

    private var isFormValid: Bool {
        if isPersonal {
            return !title.isEmpty && selectedProfessional != nil
        } else {
            return selectedPatient != nil && !procedure.isEmpty && selectedProfessional != nil
        }
    }

    // MARK: - Save

    private func save() async {
        guard let userId = supabase.effectiveUserId,
              let professional = selectedProfessional else {
            errorMessage = "Dados incompletos"
            showError = true
            return
        }

        isLoading = true

        // Combinar data com horários
        let calendar = Calendar.current
        let startComponents = calendar.dateComponents([.hour, .minute], from: startTime)
        let endComponents = calendar.dateComponents([.hour, .minute], from: endTime)

        guard let start = calendar.date(bySettingHour: startComponents.hour ?? 0, minute: startComponents.minute ?? 0, second: 0, of: date),
              let end = calendar.date(bySettingHour: endComponents.hour ?? 0, minute: endComponents.minute ?? 0, second: 0, of: date) else {
            errorMessage = "Erro ao processar horários"
            showError = true
            isLoading = false
            return
        }

        // Verificar conflitos
        let hasConflict = await appointmentService.hasConflict(start: start, end: end, professional: professional.name)
        if hasConflict {
            errorMessage = "Já existe um agendamento neste horário para este profissional"
            showError = true
            isLoading = false
            return
        }

        do {
            let appointment = Appointment.Insert(
                userId: userId,
                patientId: isPersonal ? userId : selectedPatient!.id,
                patientName: isPersonal ? title : selectedPatient!.name,
                procedure: isPersonal ? "Compromisso Pessoal" : procedure,
                professional: professional.name,
                start: start,
                end: end,
                notes: nil,
                isPersonal: isPersonal,
                title: isPersonal ? title : nil
            )

            _ = try await appointmentService.createAppointment(appointment)
            onSave()
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
            showError = true
        }

        isLoading = false
    }
}

// MARK: - Patient Picker View

struct PatientPickerView: View {
    @Environment(\.dismiss) var dismiss
    let patients: [Patient]
    @Binding var selectedPatient: Patient?
    @State private var searchText = ""

    var filteredPatients: [Patient] {
        if searchText.isEmpty {
            return patients
        }
        return patients.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
    }

    var body: some View {
        NavigationStack {
            List(filteredPatients) { patient in
                Button {
                    selectedPatient = patient
                    dismiss()
                } label: {
                    HStack {
                        AvatarView(name: patient.name, size: 40)

                        VStack(alignment: .leading) {
                            Text(patient.name)
                                .foregroundColor(.primary)
                            if let phone = patient.phone {
                                Text(phone)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }

                        Spacer()

                        if selectedPatient?.id == patient.id {
                            Image(systemName: "checkmark")
                                .foregroundColor(.appPrimary)
                        }
                    }
                }
            }
            .searchable(text: $searchText, prompt: "Buscar paciente...")
            .navigationTitle("Selecionar Paciente")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Fechar") {
                        dismiss()
                    }
                }
            }
        }
    }
}

#Preview("Agendamento") {
    NewAppointmentView(selectedDate: Date(), isPersonal: false) {}
        .environmentObject(SupabaseManager.shared)
}

#Preview("Compromisso") {
    NewAppointmentView(selectedDate: Date(), isPersonal: true) {}
        .environmentObject(SupabaseManager.shared)
}
