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

    init(selectedDate: Date, initialTime: Date? = nil, initialEndTime: Date? = nil, isPersonal: Bool = false, onSave: @escaping () -> Void) {
        self.selectedDate = selectedDate
        self.isPersonal = isPersonal
        self.onSave = onSave

        let calendar = Calendar.current
        
        // Se fornecido horário inicial (drag-to-create), usa ele
        if let start = initialTime {
            _date = State(initialValue: start)
            _startTime = State(initialValue: start)
            
            // Se tiver fim específico (arraste), usa. Senão +1h
            if let end = initialEndTime {
                _endTime = State(initialValue: end)
            } else {
                _endTime = State(initialValue: calendar.date(byAdding: .hour, value: 1, to: start) ?? start)
            }
        } else {
            // Lógica padrão: próxima hora cheia
            let now = Date()
            let startOfDay = calendar.startOfDay(for: selectedDate)
            let currentHour = calendar.component(.hour, from: now)
            
            // Se a data selecionada for hoje, sugere próxima hora. Se for futuro, sugere 08:00
            let isToday = calendar.isDateInToday(selectedDate)
            let defaultHour = isToday ? max(currentHour + 1, 8) : 8
            
            let defaultStartTime = calendar.date(bySettingHour: defaultHour, minute: 0, second: 0, of: startOfDay)!
            let defaultEndTime = calendar.date(byAdding: .hour, value: 1, to: defaultStartTime)!

            _date = State(initialValue: selectedDate)
            _startTime = State(initialValue: defaultStartTime)
            _endTime = State(initialValue: defaultEndTime)
        }
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
            .sheet(isPresented: $showNewProfessionalSheet) {
                NewProfessionalView(existingProfessionals: professionalService.professionals, onSave: { newProfessional in
                    // Reload list and select the new one
                    Task {
                        await professionalService.fetchProfessionals()
                        selectedProfessional = newProfessional
                    }
                })
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

    @State private var showNewProfessionalSheet = false

    // MARK: - Common Fields

    private var commonFields: some View {
        Group {
            Section("Data e Horário") {
                DatePicker("Data", selection: $date, displayedComponents: .date)

                DatePicker("Início", selection: $startTime, displayedComponents: .hourAndMinute)

                DatePicker("Término", selection: $endTime, displayedComponents: .hourAndMinute)
            }

            Section("Profissional") {
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
                
                Button {
                    showNewProfessionalSheet = true
                } label: {
                    HStack {
                        Image(systemName: "plus.circle")
                            .foregroundColor(.appPrimary)
                        Text("Cadastrar Novo Profissional")
                            .foregroundColor(.appPrimary)
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
import SwiftUI

struct NewProfessionalView: View {
    @Environment(\.dismiss) var dismiss
    @EnvironmentObject var supabase: SupabaseManager
    
    // Callbacks
    var onSave: ((Professional) -> Void)?
    
    // Services
    @StateObject private var service = ProfessionalService()
    
    // Form States
    @State private var name = ""
    @State private var specialty = ""
    @State private var cro = ""
    @State private var cpf = ""
    @State private var phone = ""
    @State private var email = ""
    
    // Address
    @State private var cep = ""
    @State private var street = ""
    @State private var number = ""
    @State private var complement = ""
    @State private var neighborhood = ""
    @State private var city = ""
    @State private var state = ""
    
    // Other
    @State private var notes = ""
    
    // UI
    @State private var isLoading = false
    @State private var errorMessage = ""
    @State private var showError = false
    
    // Existing list for validation
    var existingProfessionals: [Professional] = []

    init(existingProfessionals: [Professional] = [], onSave: ((Professional) -> Void)? = nil) {
        self.existingProfessionals = existingProfessionals
        self.onSave = onSave
    }
    
    var body: some View {
        NavigationStack {
            Form {
                Section("Dados Pessoais") {
                    TextField("Nome Completo *", text: $name)
                        .textInputAutocapitalization(.words)
                    
                    TextField("Especialidade (ex: Dentista)", text: $specialty)
                        .textInputAutocapitalization(.sentences)
                    
                    TextField("CRO / Registro", text: $cro)
                        .textInputAutocapitalization(.characters)
                    
                    TextField("CPF", text: $cpf)
                        .keyboardType(.numberPad)
                        .onChange(of: cpf) { newValue in
                             cpf = formatCPF(newValue)
                        }
                }
                
                Section("Contato") {
                    TextField("Telefone / Celular", text: $phone)
                        .keyboardType(.phonePad)
                        .onChange(of: phone) { newValue in
                             phone = formatPhone(newValue)
                        }
                    
                    TextField("Email", text: $email)
                        .keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never)
                }
                
                Section("Endereço") {
                    TextField("CEP", text: $cep)
                        .keyboardType(.numberPad)
                        .onChange(of: cep) { newValue in
                            cep = formatCEP(newValue)
                            if newValue.count >= 9 { // 12345-678
                                fetchAddress()
                            }
                        }
                    
                    if !street.isEmpty || !city.isEmpty {
                        TextField("Rua", text: $street)
                        HStack {
                            TextField("Número", text: $number)
                                .keyboardType(.numberPad)
                            Divider()
                            TextField("Comp.", text: $complement)
                        }
                        TextField("Bairro", text: $neighborhood)
                        HStack {
                            TextField("Cidade", text: $city)
                            Divider()
                            TextField("UF", text: $state)
                                .frame(width: 50)
                        }
                    } else if isLoading {
                        ProgressView()
                    }
                }
                
                Section("Observações") {
                    TextEditor(text: $notes)
                        .frame(height: 80)
                }
            }
            .navigationTitle("Novo Profissional")
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
                    .disabled(name.isEmpty || isLoading)
                    .fontWeight(.bold)
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
    
    // MARK: - Actions
    
    private func save() async {
        guard let userId = supabase.effectiveUserId else { return }
        
        // 1. Validar Campos Obrigatórios
        guard !name.trimmingCharacters(in: .whitespaces).isEmpty else {
            errorMessage = "O nome é obrigatório."
            showError = true
            return
        }
        
        // 2. Validar Duplicidade Local
        let cleanName = name.trimmingCharacters(in: .whitespaces).lowercased()
        if existingProfessionals.contains(where: { $0.name.trimmingCharacters(in: .whitespaces).lowercased() == cleanName }) {
            errorMessage = "Já existe um profissional com este nome."
            showError = true
            return
        }
        
        // (Opcional) Validar CPF/CRO duplicado se preenchido
        // ...
        
        isLoading = true
        
        let newProfessional = Professional.Insert(
            userId: userId,
            name: name,
            specialty: specialty.isEmpty ? nil : specialty,
            cro: cro.isEmpty ? nil : cro,
            phone: phone.isEmpty ? nil : phone,
            email: email.isEmpty ? nil : email,
            cpf: cpf.isEmpty ? nil : cpf,
            zipCode: cep.isEmpty ? nil : cep,
            street: street.isEmpty ? nil : street,
            number: number.isEmpty ? nil : number,
            complement: complement.isEmpty ? nil : complement,
            neighborhood: neighborhood.isEmpty ? nil : neighborhood,
            city: city.isEmpty ? nil : city,
            state: state.isEmpty ? nil : state,
            notes: notes.isEmpty ? nil : notes,
            photoUrl: nil, // Upload not implemented here yet
            isActive: true
        )
        
        do {
            let created = try await service.createProfessional(newProfessional)
            onSave?(created)
            dismiss()
        } catch {
            errorMessage = "Erro ao salvar: \(error.localizedDescription)"
            showError = true
        }
        
        isLoading = false
    }
    
    private func fetchAddress() {
        // Mocked or simple implementation for now, user guideline said logic is optional/integration.
        // For keeping it simple in this step, I'm just leaving the hook. 
        // If the user wants ViaCEP integrated, I can add it, but for now I focus on saving flow.
    }
    
    // MARK: - Formatters
    
    private func formatCPF(_ cpf: String) -> String {
        let numbers = cpf.components(separatedBy: CharacterSet.decimalDigits.inverted).joined()
        if numbers.count > 11 { return String(numbers.prefix(11)) }
        // Simple masking XXX.XXX.XXX-XX could apply here
        return numbers
    }
    
    private func formatPhone(_ phone: String) -> String {
        let numbers = phone.components(separatedBy: CharacterSet.decimalDigits.inverted).joined()
        if numbers.count > 11 { return String(numbers.prefix(11)) }
        return numbers
    }
    
    private func formatCEP(_ cep: String) -> String {
         let numbers = cep.components(separatedBy: CharacterSet.decimalDigits.inverted).joined()
         if numbers.count > 8 { return String(numbers.prefix(8)) }
         return numbers
    }
}
