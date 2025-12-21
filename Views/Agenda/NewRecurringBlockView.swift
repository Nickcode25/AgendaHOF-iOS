import SwiftUI

struct NewRecurringBlockView: View {
    @Environment(\.dismiss) var dismiss
    @EnvironmentObject var supabase: SupabaseManager

    var onSave: () -> Void

    // Form state
    @State private var title = ""
    @State private var startTime = Calendar.current.date(bySettingHour: 12, minute: 0, second: 0, of: Date())!
    @State private var endTime = Calendar.current.date(bySettingHour: 13, minute: 30, second: 0, of: Date())!
    @State private var selectedDays: Set<Int> = [1, 2, 3, 4, 5] // Seg-Sex por padrão
    @State private var selectedProfessional: Professional?

    // UI state
    @State private var isLoading = false
    @State private var showError = false
    @State private var errorMessage = ""
    @State private var showProfessionalPicker = false

    // Services
    @StateObject private var professionalService = ProfessionalService()

    var body: some View {
        NavigationStack {
            Form {
                // Título do bloqueio
                Section("Título") {
                    TextField("Ex: Almoço, Reunião...", text: $title)
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
                    }
                    .padding(.vertical, 4)
                }
            }
            .navigationTitle("Novo Bloqueio")
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
                RecurringBlockProfessionalPicker(
                    professionals: professionalService.professionals,
                    selectedProfessional: $selectedProfessional
                )
            }
            .task {
                await professionalService.fetchProfessionals()
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
        guard let userId = supabase.effectiveUserId else {
            errorMessage = "Usuário não autenticado"
            showError = true
            return
        }

        isLoading = true

        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"

        let block = RecurringBlock.Insert(
            userId: userId,
            title: title,
            startTime: formatter.string(from: startTime),
            endTime: formatter.string(from: endTime),
            daysOfWeek: Array(selectedDays).sorted(),
            active: true,
            notes: nil,
            professional: selectedProfessional?.name,
            professionalId: selectedProfessional?.id
        )

        do {
            try await supabase.client
                .from("recurring_blocks")
                .insert(block)
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

// MARK: - Day Toggle Button

struct DayToggleButton: View {
    let day: DayOfWeek
    let isSelected: Bool
    var onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            Text(String(day.shortName.prefix(1)))
                .font(.subheadline)
                .fontWeight(.semibold)
                .frame(width: 36, height: 36)
                .background(isSelected ? Color.appPrimary : Color(.systemGray5))
                .foregroundColor(isSelected ? .white : .primary)
                .clipShape(Circle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Professional Picker for Recurring Block

struct RecurringBlockProfessionalPicker: View {
    @Environment(\.dismiss) var dismiss
    let professionals: [Professional]
    @Binding var selectedProfessional: Professional?

    var body: some View {
        NavigationStack {
            List {
                // Opção "Todos"
                Button {
                    selectedProfessional = nil
                    dismiss()
                } label: {
                    HStack {
                        Image(systemName: "person.2.fill")
                            .foregroundColor(.secondary)
                        Text("Todos os profissionais")
                            .foregroundColor(.primary)
                        Spacer()
                        if selectedProfessional == nil {
                            Image(systemName: "checkmark")
                                .foregroundColor(.appPrimary)
                        }
                    }
                }

                // Lista de profissionais
                ForEach(professionals) { professional in
                    Button {
                        selectedProfessional = professional
                        dismiss()
                    } label: {
                        HStack {
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
                            Spacer()
                            if selectedProfessional?.id == professional.id {
                                Image(systemName: "checkmark")
                                    .foregroundColor(.appPrimary)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Profissional")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Fechar") {
                        dismiss()
                    }
                }
            }
        }
        .presentationDetents([.medium])
    }
}

#Preview {
    NewRecurringBlockView {}
        .environmentObject(SupabaseManager.shared)
}
