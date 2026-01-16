import SwiftUI

struct EditRecurringBlockView: View {
    @Environment(\.dismiss) var dismiss
    @EnvironmentObject var supabase: SupabaseManager

    let block: RecurringBlock
    var onSave: () -> Void

    // Form state
    @State private var title: String
    @State private var startTime: Date
    @State private var endTime: Date
    @State private var selectedDays: Set<Int>
    @State private var selectedProfessional: Professional?
    @State private var isActive: Bool

    // UI state
    @State private var isLoading = false
    @State private var showError = false
    @State private var errorMessage = ""
    @State private var showProfessionalPicker = false
    @State private var showDeleteConfirmation = false

    // Services
    @StateObject private var professionalService = ProfessionalService()

    init(block: RecurringBlock, onSave: @escaping () -> Void) {
        self.block = block
        self.onSave = onSave

        // Initialize state from block
        _title = State(initialValue: block.title)
        _selectedDays = State(initialValue: Set(block.daysOfWeek))
        _isActive = State(initialValue: block.active)

        // Parse times
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"

        let startDate = formatter.date(from: block.startTime) ?? Date()
        let endDate = formatter.date(from: block.endTime) ?? Date()

        _startTime = State(initialValue: startDate)
        _endTime = State(initialValue: endDate)
    }

    var body: some View {
        NavigationStack {
            Form {
                // Título do bloqueio
                Section("Título") {
                    TextField("Ex: Almoço, Reunião...", text: $title)
                }

                // Status ativo/inativo
                Section {
                    Toggle("Ativo", isOn: $isActive)
                }

                // Dias da semana
                Section("Dias da Semana") {
                    daysOfWeekPicker
                }

                // Horário
                Section("Horário") {
                    DatePicker("Início", selection: $startTime, displayedComponents: .hourAndMinute)

                    DatePicker("Término", selection: $endTime, displayedComponents: .hourAndMinute)
                }

                // Profissional (opcional)
                if !professionalService.professionals.isEmpty {
                    Section("Profissional (opcional)") {
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
                                        .foregroundColor(.secondary)
                                    Text("Todos os profissionais")
                                        .foregroundColor(.secondary)
                                }
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                }

                // Preview
                Section("Resumo") {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Image(systemName: "clock.fill")
                                .foregroundColor(.appPrimary)
                            Text(timeRangeFormatted)
                                .fontWeight(.medium)
                        }

                        HStack {
                            Image(systemName: "calendar")
                                .foregroundColor(.appPrimary)
                            Text(selectedDaysFormatted)
                                .font(.subheadline)
                        }

                        if let professional = selectedProfessional {
                            HStack {
                                Image(systemName: "person.fill")
                                    .foregroundColor(.appPrimary)
                                Text(professional.name)
                                    .font(.subheadline)
                            }
                        }

                        HStack {
                            Image(systemName: isActive ? "checkmark.circle.fill" : "xmark.circle.fill")
                                .foregroundColor(isActive ? .green : .red)
                            Text(isActive ? "Ativo" : "Inativo")
                                .font(.subheadline)
                        }
                    }
                    .padding(.vertical, 4)
                }

                // Botão de deletar
                Section {
                    Button(role: .destructive) {
                        showDeleteConfirmation = true
                    } label: {
                        HStack {
                            Spacer()
                            Label("Excluir Bloqueio", systemImage: "trash")
                            Spacer()
                        }
                    }
                }
            }
            .navigationTitle("Editar Bloqueio")
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
            .confirmationDialog(
                "Excluir Bloqueio",
                isPresented: $showDeleteConfirmation,
                titleVisibility: .visible
            ) {
                Button("Excluir", role: .destructive) {
                    Task { await delete() }
                }
                Button("Cancelar", role: .cancel) {}
            } message: {
                Text("Tem certeza que deseja excluir este bloqueio recorrente? Esta ação não pode ser desfeita.")
            }
            .sheet(isPresented: $showProfessionalPicker) {
                RecurringBlockProfessionalPicker(
                    professionals: professionalService.professionals,
                    selectedProfessional: $selectedProfessional
                )
            }
            .task {
                await professionalService.fetchProfessionals()
                // Set selected professional from block
                if let profId = block.professionalId {
                    selectedProfessional = professionalService.professionals.first { $0.id == profId }
                }
            }
        }
    }

    // MARK: - Days of Week Picker

    private var daysOfWeekPicker: some View {
        HStack(spacing: 8) {
            ForEach(DayOfWeek.allCases, id: \.rawValue) { day in
                DayToggleButton(
                    day: day,
                    isSelected: selectedDays.contains(day.rawValue)
                ) {
                    if selectedDays.contains(day.rawValue) {
                        selectedDays.remove(day.rawValue)
                    } else {
                        selectedDays.insert(day.rawValue)
                    }
                }
            }
        }
        .padding(.vertical, 8)
    }

    // MARK: - Computed Properties

    private var isFormValid: Bool {
        !title.isEmpty && !selectedDays.isEmpty && startTime < endTime
    }

    private var timeRangeFormatted: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return "\(formatter.string(from: startTime)) - \(formatter.string(from: endTime))"
    }

    private var selectedDaysFormatted: String {
        let dayNames = ["Dom", "Seg", "Ter", "Qua", "Qui", "Sex", "Sáb"]
        return selectedDays.sorted().map { dayNames[$0] }.joined(separator: ", ")
    }

    // MARK: - Save

    private func save() async {
        isLoading = true

        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"

        let update = RecurringBlockUpdate(
            title: title,
            startTime: formatter.string(from: startTime),
            endTime: formatter.string(from: endTime),
            daysOfWeek: Array(selectedDays).sorted(),
            active: isActive,
            professional: selectedProfessional?.name,
            professionalId: selectedProfessional?.id
        )

        do {
            try await supabase.client
                .from("recurring_blocks")
                .update(update)
                .eq("id", value: block.id)
                .execute()

            onSave()
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
            showError = true
        }

        isLoading = false
    }

    // MARK: - Delete

    private func delete() async {
        isLoading = true

        do {
            try await supabase.client
                .from("recurring_blocks")
                .delete()
                .eq("id", value: block.id)
                .execute()

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
    let sampleBlock = RecurringBlock(
        id: "preview",
        createdAt: Date(),
        updatedAt: nil,
        userId: "user123",
        title: "Almoço",
        startTime: "12:00:00",
        endTime: "13:30:00",
        daysOfWeek: [1, 2, 3, 4, 5],
        active: true,
        notes: nil,
        professional: nil,
        professionalId: nil
    )

    EditRecurringBlockView(block: sampleBlock) {}
        .environmentObject(SupabaseManager.shared)
}
