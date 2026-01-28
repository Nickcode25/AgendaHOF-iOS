import SwiftUI

struct AgendaView: View {
    @Environment(\.horizontalSizeClass) private var sizeClass
    @StateObject private var viewModel = AgendaViewModel()
    @StateObject private var professionalService = ProfessionalService()









    var body: some View {
        VStack(spacing: 0) {
            // Header customizado com 2 linhas
            AgendaHeaderView(
                viewModel: viewModel,
                professionals: professionalService.professionals,
                onDatePickerTap: {
                    viewModel.activeSheet = .datePicker
                },
                onProfessionalPickerTap: {
                    viewModel.activeSheet = .professionalPicker
                }
            )
            
            // Conteúdo principal - calendário ocupa toda a tela
            Group {
                if let error = viewModel.error {
                    VStack {
                        Spacer()
                        EmptyStateView.error(message: error) {
                            Task { await viewModel.loadData() }
                        }
                        Spacer()
                    }
                } else {
                    // Vista direta sem paginação lateral (agora num ZStack principal)
                    ZStack(alignment: .bottomTrailing) { // Alinhamento para o FAB
                        
                        // Conteúdo (Calendário)
                        ZStack {
                            switch viewModel.viewMode {
                            case .day:
                                CalendarDayView(viewModel: viewModel)
                            case .week:
                                CalendarWeekView(viewModel: viewModel)
                            }

                            // Loading sutil durante transições (não bloqueia a tela)
                            if viewModel.isLoading {
                                VStack {
                                    Spacer()
                                    ProgressView()
                                        .controlSize(.regular)
                                        .tint(.gray)
                                    Spacer()
                                }
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                                .background(Color(.systemGroupedBackground).opacity(0.5))
                                .allowsHitTesting(false)
                            }
                        }

                        // Floating Action Button (FAB) - Menu
                        Menu {
                            Button {
                                viewModel.activeSheet = .newAppointment()
                            } label: {
                                Label("Agendamento", systemImage: "calendar.badge.plus")
                            }

                            Button {
                                viewModel.activeSheet = .newPersonalAppointment
                            } label: {
                                Label("Compromisso Pessoal", systemImage: "person.fill.badge.plus")
                            }

                            Button {
                                viewModel.activeSheet = .newRecurringBlock
                            } label: {
                                Label("Bloqueio Recorrente", systemImage: "clock.badge.xmark")
                            }
                        } label: {
                            Image(systemName: "plus")
                                .font(.system(size: 24, weight: .semibold))
                                .foregroundColor(.white)
                                .frame(width: 56, height: 56)
                                .background(
                                    Circle()
                                        .fill(Color.appPrimary)
                                        .shadow(color: .black.opacity(0.3), radius: 4, x: 0, y: 4)
                                )
                        }
                        .padding(.trailing, 24)
                        .padding(.bottom, 24)
                    }
                }
            }
        }
        .background(Color(.systemGroupedBackground))
        .navigationBarHidden(true)
        .sheet(item: $viewModel.activeSheet) { sheet in
            switch sheet {
            case .newAppointment(let start, let end):
                NewAppointmentView(
                    selectedDate: viewModel.selectedDate,
                    initialTime: start,
                    initialEndTime: end,
                    isPersonal: false
                ) {
                    Task { await viewModel.loadData() }
                }
            case .newPersonalAppointment:
                NewAppointmentView(selectedDate: viewModel.selectedDate, isPersonal: true) {
                    Task { await viewModel.loadData() }
                }
            case .newRecurringBlock:
                NewRecurringBlockView {
                    Task { await viewModel.loadData() }
                }
            case .datePicker:
                DatePickerSheet(selectedDate: $viewModel.selectedDate) {
                    Task { await viewModel.loadData() }
                }
            case .professionalPicker:
                ProfessionalPickerSheet(
                    professionals: professionalService.professionals,
                    selectedProfessional: $viewModel.selectedProfessional
                ) {
                    Task { await viewModel.loadData() }
                }
            case .appointmentDetails(let appointment):
                AppointmentDetailSheet(appointment: appointment) {
                    Task { await viewModel.loadData() }
                }
            case .editRecurringBlock(let block):
                EditRecurringBlockView(block: block) {
                    Task { await viewModel.loadData() }
                }
            }
        }
        .task {
            await professionalService.fetchProfessionals()
            await viewModel.loadData()
        }
        .refreshable {
            await viewModel.loadData()
        }
    }
}

// MARK: - Date Picker Sheet

struct DatePickerSheet: View {
    @Environment(\.dismiss) var dismiss
    @Binding var selectedDate: Date
    var onSelect: () -> Void

    var body: some View {
        NavigationStack {
            DatePicker(
                "Selecionar Data",
                selection: $selectedDate,
                displayedComponents: .date
            )
            .datePickerStyle(.graphical)
            .padding()
            .navigationTitle("Selecionar Data")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("OK") {
                        onSelect()
                        dismiss()
                    }
                }
            }
        }
        .presentationDetents([.medium])
    }
}

// MARK: - Professional Picker Sheet

struct ProfessionalPickerSheet: View {
    @Environment(\.dismiss) var dismiss
    let professionals: [Professional]
    @Binding var selectedProfessional: Professional?
    var onSelect: () -> Void

    var body: some View {
        NavigationStack {
            List {
                // Opção "Todos"
                Button {
                    selectedProfessional = nil
                    onSelect()
                    dismiss()
                } label: {
                    HStack {
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
                        onSelect()
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
            .navigationTitle("Filtrar Profissional")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Fechar") {
                        dismiss()
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}



#Preview {
    NavigationStack {
        AgendaView()
    }
    .environmentObject(SupabaseManager.shared)
}
