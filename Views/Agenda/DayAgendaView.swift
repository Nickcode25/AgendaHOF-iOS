import SwiftUI

struct DayAgendaView: View {
    @ObservedObject var viewModel: AgendaViewModel
    @State private var selectedAppointment: Appointment?

    private let workingHours = Array(7...20) // 7h às 20h

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(workingHours, id: \.self) { hour in
                    HourRow(
                        hour: hour,
                        appointments: viewModel.appointmentsByHour[hour] ?? [],
                        isBlocked: viewModel.isTimeBlocked(viewModel.selectedDate, hour: hour),
                        onAppointmentTap: { appointment in
                            selectedAppointment = appointment
                        }
                    )
                }
            }
            .padding(.vertical, 8)
        }
        .sheet(item: $selectedAppointment) { appointment in
            AppointmentDetailSheet(appointment: appointment) {
                Task { await viewModel.loadData() }
            }
        }
    }
}

// MARK: - Hour Row

struct HourRow: View {
    let hour: Int
    let appointments: [Appointment]
    let isBlocked: Bool
    var onAppointmentTap: (Appointment) -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            // Hora
            Text(String(format: "%02d:00", hour))
                .font(.caption)
                .foregroundColor(.secondary)
                .frame(width: 50, alignment: .trailing)

            // Linha divisória
            VStack {
                Rectangle()
                    .fill(Color(.systemGray4))
                    .frame(height: 1)
                Spacer()
            }
            .frame(width: 1)

            // Conteúdo
            VStack(alignment: .leading, spacing: 8) {
                if isBlocked {
                    BlockedTimeView()
                } else if appointments.isEmpty {
                    Color.clear
                        .frame(height: 60)
                } else {
                    ForEach(appointments) { appointment in
                        AppointmentCard(appointment: appointment)
                            .onTapGesture {
                                onAppointmentTap(appointment)
                            }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal)
        .padding(.vertical, 4)
    }
}

// MARK: - Blocked Time View

struct BlockedTimeView: View {
    var body: some View {
        HStack {
            Image(systemName: "slash.circle")
                .font(.subheadline)
                .foregroundColor(.gray)
            Text("Bloqueado")
                .font(.subheadline)
                .foregroundColor(.gray)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Color(.systemGray5).opacity(0.5))
        .cornerRadius(8)
    }
}

// MARK: - Appointment Card

struct AppointmentCard: View {
    let appointment: Appointment

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                // Indicador de cor por status
                Circle()
                    .fill(statusColor)
                    .frame(width: 8, height: 8)

                Text(appointment.displayTitle)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundColor(.primary)
                    .lineLimit(1)

                Spacer()

                Text(appointment.timeRange)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            if !appointment.isPersonalAppointment, let procedure = appointment.procedure {
                Text(procedure)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }

            HStack {
                Image(systemName: "person.fill")
                    .font(.caption2)
                Text(appointment.professional)
                    .font(.caption)
            }
            .foregroundColor(.appPrimary.opacity(0.8))
        }
        .padding(12)
        .background(cardBackground)
        .cornerRadius(10)
        .shadow(color: .black.opacity(0.05), radius: 2, x: 0, y: 1)
    }

    private var statusColor: Color {
        // Compromissos pessoais = AZUL
        if appointment.isPersonalAppointment {
            return .blue
        }

        // Agendamentos de pacientes - cor por status
        switch appointment.status {
        case .confirmed:
            return .green
        case .cancelled:
            return .red
        case .scheduled, .completed, .done:
            return .orange
        }
    }

    private var cardBackground: Color {
        return statusColor.opacity(0.1)
    }
}

// MARK: - Appointment Detail Sheet

struct AppointmentDetailSheet: View {
    @Environment(\.dismiss) var dismiss
    @Environment(\.horizontalSizeClass) private var sizeClass
    let appointment: Appointment
    var onUpdate: () -> Void

    @StateObject private var appointmentService = AppointmentService()
    @StateObject private var patientService = PatientService() // ✅ Service para buscar paciente
    @State private var fetchedPatient: Patient? // ✅ Estado para armazenar paciente com telefone
    
    @State private var showDeleteConfirmation = false
    @State private var showEditSheet = false
    @State private var isLoading = false

    /// Fontes adaptativas - boas em ambos dispositivos
    private var titleFont: Font {
        sizeClass == .regular ? .title2 : .title3
    }

    private var subtitleFont: Font {
        sizeClass == .regular ? .title3 : .headline
    }

    private var bodyFont: Font {
        .body
    }

    private var avatarSize: CGFloat {
        sizeClass == .regular ? 80 : 60
    }

    var body: some View {
        NavigationStack {
            List {
                // Info do paciente - Header maior para iPad
                Section {
                    HStack(spacing: 16) {
                        AvatarView(name: appointment.patientName ?? appointment.displayTitle, size: avatarSize)

                        VStack(alignment: .leading, spacing: 6) {
                            Text(appointment.displayTitle)
                                .font(titleFont)
                                .fontWeight(.semibold)

                            if !appointment.isPersonalAppointment, let procedure = appointment.procedure {
                                Text(procedure)
                                    .font(subtitleFont)
                                    .foregroundColor(.secondary)
                            }

                            // Status badge
                            HStack(spacing: 6) {
                                Circle()
                                    .fill(statusColor)
                                    .frame(width: 10, height: 10)
                                Text(appointment.status.displayName)
                                    .font(.subheadline)
                                    .foregroundColor(statusColor)
                                    .fontWeight(.medium)
                            }
                            .padding(.top, 4)
                        }
                    }
                    .padding(.vertical, 12)
                }

                // Detalhes com fontes maiores
                Section("Detalhes") {
                    LabeledContent("Data") {
                        Text(appointment.start, style: .date)
                            .font(bodyFont)
                    }

                    LabeledContent("Horário") {
                        Text(appointment.timeRange)
                            .font(bodyFont)
                            .fontWeight(.medium)
                    }

                    LabeledContent("Profissional") {
                        Text(appointment.professional)
                            .font(bodyFont)
                    }

                    if let room = appointment.room {
                        LabeledContent("Sala") {
                            Text(room)
                                .font(bodyFont)
                        }
                    }

                    if let notes = appointment.notes, !notes.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Observações")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                            Text(notes)
                                .font(bodyFont)
                        }
                        .padding(.vertical, 4)
                    }
                }

                // Ações Principais (Confirmar, Editar, Excluir)
                Section {
                    // 1. Confirmar Agendamento (se agendado)
                    if appointment.status == .scheduled {
                        Button {
                            Task {
                                await updateStatus(.confirmed)
                            }
                        } label: {
                            Label("Confirmar Agendamento", systemImage: "checkmark.circle")
                                .font(bodyFont)
                                .foregroundColor(.green)
                                .padding(.vertical, 4)
                        }
                    } else if appointment.status == .confirmed {
                         // Se já confirmado, opção de finalizar
                        Button {
                             Task {
                                 await updateStatus(.done)
                             }
                        } label: {
                            Label("Marcar como Realizado", systemImage: "checkmark.circle.fill")
                                .font(bodyFont)
                                .foregroundColor(.appPrimary)
                                .padding(.vertical, 4)
                        }
                    }

                     // 2. Editar Agendamento
                    Button {
                        showEditSheet = true
                    } label: {
                        Label("Editar Agendamento", systemImage: "pencil")
                            .font(bodyFont)
                            .foregroundColor(.appPrimary)
                            .padding(.vertical, 4)
                    }

                    // 3. Excluir Agendamento
                    Button(role: .destructive) {
                        showDeleteConfirmation = true
                    } label: {
                        Label("Excluir Agendamento", systemImage: "trash")
                            .font(bodyFont)
                            .padding(.vertical, 4)
                    }
                    
                    // Cancelar (mantendo como opção extra se não for excluir? O usuário pediu explicitamente Confirmar, Editar, Excluir. Vou manter Cancelar condicional ou removê-lo se redundante com Excluir? Geralmente cancelar mantém histórico, excluir remove. Vou manter Cancelar se o usuário não pediu para remover, mas ele pediu uma ORDEM específica. Vou colocar Cancelar junto ou abaixo se fizer sentido, mas vou priorizar a ordem pedida: Confirmar, Editar, Excluir.)
                    // Vou colocar Cancelar antes de Excluir se o status permitir, ou apenas seguir a ordem pedida estritamente.
                    // O usuário disse: "Confirmar agendamento, Editar agendamento, Excluir agendamento".
                    // Vou seguir essa ordem. O "Cancelar" existente no código original era uma opção. Vou movê-lo para baixo ou removê-lo se o usuário quiser simplificar. Pela imagem, tem "Cancelar Agendamento" (X) e "Excluir". Vou manter Cancelar logo após Confirmar (como ação negativa de status) ou junto com Excluir.
                    // Na dúvida, sigo a lista do usuário: Confirmar, Editar, Excluir. E deixo Cancelar como secundário ou removo se ele estiver substituindo.
                    // Mas a imagem mostra "Cancelar" e "Excluir". Vou assumir que ele quer a lista visual limpa nessa ordem.
                    // Vou adicionar "Cancelar" ao menu se status permitir, mas focar nos 3 pedidos.
                    

                }

                // 4. WhatsApp (Logo após a sequência)
                if let patient = fetchedPatient, let phone = patient.phone, !phone.isEmpty {
                    Section {
                        Button {
                            openWhatsApp(phone: phone)
                        } label: {
                            Label("Conversar no WhatsApp", systemImage: "message.circle.fill")
                                .font(bodyFont)
                                .fontWeight(.medium)
                                .foregroundColor(.green)
                                .frame(maxWidth: .infinity, alignment: .center)
                                .padding(.vertical, 4)
                        }
                    }
                }
            }
            .navigationTitle("Detalhes do Agendamento")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Fechar") {
                        dismiss()
                    }
                    .font(.body)
                    .fontWeight(.medium)
                }
            }
            .loadingOverlay(isLoading: isLoading)

            .alert("Excluir Agendamento", isPresented: $showDeleteConfirmation) {
                Button("Não", role: .cancel) {}
                Button("Sim, Excluir", role: .destructive) {
                    Task {
                        await deleteAppointment()
                    }
                }
            } message: {
                Text("Tem certeza que deseja excluir permanentemente este agendamento? Esta ação não pode ser desfeita.")
            }
            .sheet(isPresented: $showEditSheet) {
                EditAppointmentView(appointment: appointment) {
                    onUpdate()
                    dismiss()
                }
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .interactiveDismissDisabled(false)
        .task {
            // ✅ Buscar dados completos do paciente (incluindo telefone)
            if let patientId = appointment.patientId {
                fetchedPatient = await patientService.fetchPatient(id: patientId)
            }
        }
    }

    private var statusColor: Color {
        // Compromissos pessoais = AZUL
        if appointment.isPersonalAppointment {
            return .blue
        }

        // Agendamentos de pacientes - cor por status
        switch appointment.status {
        case .confirmed:
            return .green
        case .cancelled:
            return .red
        case .scheduled, .completed, .done:
            return .orange
        }
    }

    private func updateStatus(_ status: Appointment.AppointmentStatus) async {
        isLoading = true
        do {
            try await appointmentService.updateStatus(id: appointment.id, status: status)
            onUpdate()
            dismiss()
        } catch {
            print("Erro ao atualizar status: \(error)")
        }
        isLoading = false
    }

    private func deleteAppointment() async {
        isLoading = true
        do {
            try await appointmentService.deleteAppointment(id: appointment.id)
            onUpdate()
            dismiss()
        } catch {
            print("Erro ao excluir agendamento: \(error)")
        }
        isLoading = false
    }
    
    // ✅ Helper para abrir WhatsApp
    private func openWhatsApp(phone: String) {
        let cleanPhone = phone.components(separatedBy: CharacterSet.decimalDigits.inverted).joined()
        
        // Assumindo Brasil (55) se não tiver DDI. 
        // Lógica simples: se tem 10 ou 11 dígitos, adiciona 55.
        var finalPhone = cleanPhone
        if cleanPhone.count >= 10 && cleanPhone.count <= 11 {
            finalPhone = "55" + cleanPhone
        }
        
        if let url = URL(string: "https://wa.me/\(finalPhone)") {
            if UIApplication.shared.canOpenURL(url) {
                UIApplication.shared.open(url)
            } else {
                // Tenta abrir no navegador se o app não estiver instalado (o link wa.me redireciona)
                UIApplication.shared.open(url)
            }
        }
    }
}

// MARK: - Edit Appointment View

struct EditAppointmentView: View {
    @Environment(\.dismiss) var dismiss
    @EnvironmentObject var supabase: SupabaseManager

    let appointment: Appointment
    var onSave: () -> Void

    // Form state
    @State private var title: String
    @State private var procedure: String
    @State private var date: Date
    @State private var startTime: Date
    @State private var endTime: Date
    @State private var selectedProfessional: Professional?
    @State private var notes: String

    // UI state
    @State private var isLoading = false
    @State private var showError = false
    @State private var errorMessage = ""
    @State private var showProfessionalPicker = false

    // Services
    @StateObject private var professionalService = ProfessionalService()
    @StateObject private var appointmentService = AppointmentService()

    init(appointment: Appointment, onSave: @escaping () -> Void) {
        self.appointment = appointment
        self.onSave = onSave

        _title = State(initialValue: appointment.title ?? "")
        _procedure = State(initialValue: appointment.procedure ?? "")
        _date = State(initialValue: appointment.start)
        _startTime = State(initialValue: appointment.start)
        _endTime = State(initialValue: appointment.end)
        _notes = State(initialValue: appointment.notes ?? "")
    }

    var body: some View {
        NavigationStack {
            Form {
                // Campos específicos por tipo
                if appointment.isPersonalAppointment {
                    Section("Compromisso") {
                        TextField("Título", text: $title)
                    }
                } else {
                    Section("Paciente") {
                        HStack {
                            AvatarView(name: appointment.patientName ?? "?", size: 36)
                            Text(appointment.patientName ?? "Sem paciente")
                                .foregroundColor(.primary)
                        }
                    }

                    Section("Procedimento") {
                        TextField("Ex: Consulta, Limpeza...", text: $procedure)
                    }
                }

                // Data e Horário
                Section("Data e Horário") {
                    DatePicker("Data", selection: $date, displayedComponents: .date)
                    DatePicker("Início", selection: $startTime, displayedComponents: .hourAndMinute)
                    DatePicker("Término", selection: $endTime, displayedComponents: .hourAndMinute)
                }

                // Profissional
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
                                    Text(appointment.professional)
                                        .foregroundColor(.primary)
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
            .navigationTitle("Editar Agendamento")
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
            .sheet(isPresented: $showProfessionalPicker) {
                ProfessionalPickerSheet(
                    professionals: professionalService.professionals,
                    selectedProfessional: $selectedProfessional
                ) {}
            }
            .task {
                await professionalService.fetchProfessionals()

                // Encontrar profissional atual
                if let prof = professionalService.professionals.first(where: { $0.name == appointment.professional }) {
                    selectedProfessional = prof
                }
            }
        }
    }

    private var isFormValid: Bool {
        if appointment.isPersonalAppointment {
            return !title.isEmpty
        } else {
            return !procedure.isEmpty
        }
    }

    private func save() async {
        isLoading = true

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

        let professionalName = selectedProfessional?.name ?? appointment.professional

        // Verificar conflitos (excluindo o próprio agendamento)
        let hasConflict = await appointmentService.hasConflict(start: start, end: end, professional: professionalName, excludingId: appointment.id)
        if hasConflict {
            errorMessage = "Já existe um agendamento neste horário para este profissional"
            showError = true
            isLoading = false
            return
        }

        do {
            var updates: [String: AnyEncodable] = [
                "start": AnyEncodable(start),
                "end": AnyEncodable(end),
                "professional": AnyEncodable(professionalName)
            ]

            if appointment.isPersonalAppointment {
                updates["title"] = AnyEncodable(title)
            } else {
                updates["procedure"] = AnyEncodable(procedure)
            }

            try await appointmentService.updateAppointment(id: appointment.id, updates: updates)
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
    DayAgendaView(viewModel: AgendaViewModel())
}
