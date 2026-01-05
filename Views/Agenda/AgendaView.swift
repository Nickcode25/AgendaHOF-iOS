import SwiftUI

struct AgendaView: View {
    @Environment(\.horizontalSizeClass) private var sizeClass
    @StateObject private var viewModel = AgendaViewModel()
    @StateObject private var professionalService = ProfessionalService()
    @State private var showNewAppointment = false
    @State private var showNewPersonalAppointment = false
    @State private var showNewRecurringBlock = false
    @State private var showDatePicker = false
    @State private var showProfessionalPicker = false

    /// Largura da tela em pontos
    private var screenWidth: CGFloat {
        UIScreen.main.bounds.width
    }

    /// Detecta tamanho da tela baseado na largura real
    /// - iPhone SE, mini, 8: ~375pt ou menos
    /// - iPhone 11, 12, 13, 14, 15, 16: ~390-414pt (414pt em zoom)
    /// - iPhone Plus/Pro Max: ~428-440pt
    /// - iPad: 768pt+
    private var screenSize: ScreenSize {
        if sizeClass == .regular {
            return .iPad
        }
        if screenWidth <= 375 {
            return .small      // iPhone SE, mini, 8
        } else if screenWidth <= 420 {
            return .medium     // iPhone 11, 12, 13, 14, 15, 16 (inclui zoom mode 414pt)
        } else {
            return .large      // iPhone Plus, Pro Max
        }
    }

    private enum ScreenSize {
        case small   // iPhone SE, mini, 8 (375pt)
        case medium  // iPhone padrão (390-393pt)
        case large   // iPhone Plus/Pro Max (428-440pt)
        case iPad    // iPad (768pt+)
    }

    /// Espaçamento entre itens da toolbar
    private var toolbarSpacing: CGFloat {
        switch screenSize {
        case .small: return 6
        case .medium: return 8
        case .large: return 10
        case .iPad: return 12
        }
    }

    /// Largura do segmented control
    private var segmentedWidth: CGFloat {
        switch screenSize {
        case .small: return 70
        case .medium: return 80
        case .large: return 90
        case .iPad: return 100
        }
    }

    var body: some View {
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
                // Vista direta sem paginação lateral
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
            }
        }
        .background(Color(.systemGroupedBackground))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            // LEADING: Navegação de data compacta
            ToolbarItem(placement: .navigationBarLeading) {
                HStack(spacing: screenSize == .small ? 2 : 4) {
                    // Botão anterior
                    Button {
                        if viewModel.viewMode == .day {
                            viewModel.goToPreviousDay()
                        } else {
                            viewModel.goToPreviousWeek()
                        }
                    } label: {
                        Image(systemName: "chevron.left")
                            .font(.caption)
                            .fontWeight(.semibold)
                    }

                    // Data - tap para abrir picker
                    Button {
                        showDatePicker = true
                    } label: {
                        Text(viewModel.compactDateTitle)
                            .font(screenSize == .small ? .caption : .subheadline)
                            .fontWeight(.semibold)
                            .foregroundColor(.primary)
                    }

                    // Botão próximo
                    Button {
                        if viewModel.viewMode == .day {
                            viewModel.goToNextDay()
                        } else {
                            viewModel.goToNextWeek()
                        }
                    } label: {
                        Image(systemName: "chevron.right")
                            .font(.caption)
                            .fontWeight(.semibold)
                    }


                }
            }

            // PRINCIPAL: Filtro do profissional (quando selecionado)
            ToolbarItem(placement: .principal) {
                if let professional = viewModel.selectedProfessional {
                    Button {
                        viewModel.selectedProfessional = nil
                        Task { await viewModel.loadData() }
                    } label: {
                        HStack(spacing: 4) {
                            Text(professional.name.components(separatedBy: " ").first ?? professional.name)
                                .font(.caption)
                            Image(systemName: "xmark.circle.fill")
                                .font(.caption2)
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.appPrimary.opacity(0.15))
                        .foregroundColor(.appPrimary)
                        .cornerRadius(12)
                    }
                } else if (screenSize == .large || screenSize == .iPad) && Calendar.current.isDateInToday(viewModel.selectedDate) && viewModel.viewMode == .day {
                    Text("Hoje")
                        .font(.headline)
                        .foregroundColor(.appPrimary)
                }
            }


            // TRAILING: Ações principais (sempre visíveis)
            ToolbarItem(placement: .navigationBarTrailing) {
                HStack(spacing: toolbarSpacing) {
                    // Hoje (apenas em telas grandes e iPad quando não for hoje)
                    if (screenSize == .large || screenSize == .iPad) && !Calendar.current.isDateInToday(viewModel.selectedDate) {
                        Button {
                            viewModel.goToToday()
                        } label: {
                            Text("Hoje")
                                .font(.caption)
                                .fontWeight(.medium)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Color.appPrimary.opacity(0.1))
                                .foregroundColor(.appPrimary)
                                .cornerRadius(8)
                        }
                    }

                    // Filtro de profissional (apenas ícone)
                    if !professionalService.professionals.isEmpty {
                        Button {
                            showProfessionalPicker = true
                        } label: {
                            Image(systemName: viewModel.selectedProfessional != nil ? "person.crop.circle.fill" : "person.crop.circle")
                                .foregroundColor(viewModel.selectedProfessional != nil ? .appPrimary : .primary)
                        }
                    }

                    // Toggle view mode - Segmented Control
                    Picker("", selection: $viewModel.viewMode) {
                        Text("Dia").tag(AgendaViewModel.ViewMode.day)
                        Text("Sem").tag(AgendaViewModel.ViewMode.week)
                    }
                    .pickerStyle(.segmented)
                    .frame(width: segmentedWidth)
                    .onChange(of: viewModel.viewMode) { _, _ in
                        Task { await viewModel.loadData() }
                    }

                    // Menu de adicionar (SEMPRE visível)
                    Menu {
                        Button {
                            showNewAppointment = true
                        } label: {
                            Label("Agendamento", systemImage: "calendar.badge.plus")
                        }

                        Button {
                            showNewPersonalAppointment = true
                        } label: {
                            Label("Compromisso Pessoal", systemImage: "person.fill.badge.plus")
                        }

                        Button {
                            showNewRecurringBlock = true
                        } label: {
                            Label("Bloqueio Recorrente", systemImage: "clock.badge.xmark")
                        }
                    } label: {
                        Image(systemName: "plus")
                            .fontWeight(.semibold)
                    }
                }
            }
        }
        .sheet(isPresented: $showNewAppointment) {
            NewAppointmentView(selectedDate: viewModel.selectedDate, isPersonal: false) {
                Task { await viewModel.loadData() }
            }
        }
        .sheet(isPresented: $showNewPersonalAppointment) {
            NewAppointmentView(selectedDate: viewModel.selectedDate, isPersonal: true) {
                Task { await viewModel.loadData() }
            }
        }
        .sheet(isPresented: $showNewRecurringBlock) {
            NewRecurringBlockView {
                Task { await viewModel.loadData() }
            }
        }
        .sheet(isPresented: $showDatePicker) {
            DatePickerSheet(selectedDate: $viewModel.selectedDate) {
                Task { await viewModel.loadData() }
            }
        }
        .sheet(isPresented: $showProfessionalPicker) {
            ProfessionalPickerSheet(
                professionals: professionalService.professionals,
                selectedProfessional: $viewModel.selectedProfessional
            ) {
                Task { await viewModel.loadData() }
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
