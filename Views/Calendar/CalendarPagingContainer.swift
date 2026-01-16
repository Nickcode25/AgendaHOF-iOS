import SwiftUI

// MARK: - Paging Container para Calendário
/// Container principal que gerencia a paginação horizontal fluida entre dias/semanas
/// Utiliza APIs nativas do iOS 17+ para scroll suave e paging perfeito
///
/// Arquitetura:
/// CalendarPagingContainer
///  └── ScrollView (.horizontal, paging)
///      └── LazyHStack (spacing: 0)
///          ├── PageView (width = screen)
///          ├── PageView
///          └── PageView

struct CalendarPagingContainer<Content: View>: View {
    @ObservedObject var viewModel: AgendaViewModel

    /// Número de páginas para cada lado (passado/futuro)
    private let pagesPerSide = 50

    /// Gerador de conteúdo para cada página
    let pageContent: (Date) -> Content

    /// ID da página atual para scroll programático
    @State private var currentPageID: String?

    /// Largura da tela (calculada uma vez)
    @State private var screenWidth: CGFloat = UIScreen.main.bounds.width

    init(viewModel: AgendaViewModel, @ViewBuilder pageContent: @escaping (Date) -> Content) {
        self.viewModel = viewModel
        self.pageContent = pageContent
    }

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width

            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 0) {
                    ForEach(pageIndices, id: \.self) { index in
                        let date = dateForIndex(index)

                        pageContent(date)
                            .frame(width: width)
                            .id(pageIDFor(index))
                    }
                }
                .scrollTargetLayout()
            }
            .scrollTargetBehavior(.paging)
            .scrollPosition(id: $currentPageID)
            .scrollBounceBehavior(.basedOnSize)
            .onAppear {
                screenWidth = width
                currentPageID = pageIDFor(0)
            }
            .onChange(of: currentPageID) { _, newID in
                handlePageChange(newID: newID)
            }
            .onChange(of: viewModel.selectedDate) { _, _ in
                // Quando a data muda externamente, voltar para o centro
                withAnimation(.none) {
                    currentPageID = pageIDFor(0)
                }
            }
        }
    }

    // MARK: - Helpers

    /// Índices das páginas (-pagesPerSide ... 0 ... +pagesPerSide)
    private var pageIndices: [Int] {
        Array(-pagesPerSide...pagesPerSide)
    }

    /// Calcula a data para um índice de página
    private func dateForIndex(_ index: Int) -> Date {
        let calendar = Calendar.current

        switch viewModel.viewMode {
        case .day:
            return calendar.date(byAdding: .day, value: index, to: viewModel.selectedDate) ?? viewModel.selectedDate
        case .week:
            return calendar.date(byAdding: .weekOfYear, value: index, to: viewModel.selectedDate) ?? viewModel.selectedDate
        }
    }

    /// Gera um ID único para cada página
    private func pageIDFor(_ index: Int) -> String {
        "page_\(index)"
    }

    /// Trata a mudança de página
    private func handlePageChange(newID: String?) {
        guard let newID = newID,
              let index = indexFromPageID(newID),
              index != 0 else { return }

        // Atualiza a data selecionada baseado no índice
        let newDate = dateForIndex(index)

        // Atualiza o ViewModel e recarrega dados
        Task { @MainActor in
            viewModel.selectedDate = newDate
            await viewModel.loadData()

            // Reseta para o centro após carregar
            currentPageID = pageIDFor(0)
        }
    }

    /// Extrai o índice do ID da página
    private func indexFromPageID(_ id: String) -> Int? {
        let prefix = "page_"
        guard id.hasPrefix(prefix) else { return nil }
        return Int(id.dropFirst(prefix.count))
    }
}

// MARK: - Day Paging View
/// Vista paginada para modo diário

struct DayPagingView: View {
    @ObservedObject var viewModel: AgendaViewModel
    @State private var selectedAppointment: Appointment?
    @State private var selectedRecurringBlock: RecurringBlock?

    var body: some View {
        CalendarPagingContainer(viewModel: viewModel) { date in
            DayPageContent(
                viewModel: viewModel,
                date: date,
                selectedAppointment: $selectedAppointment,
                selectedRecurringBlock: $selectedRecurringBlock
            )
        }
        .sheet(item: $selectedAppointment) { appointment in
            AppointmentDetailSheet(appointment: appointment) {
                Task { await viewModel.loadData() }
            }
        }
        .sheet(item: $selectedRecurringBlock) { block in
            EditRecurringBlockView(block: block) {
                Task { await viewModel.loadData() }
            }
        }
    }
}

// MARK: - Day Page Content
/// Conteúdo de uma página de dia individual

struct DayPageContent: View {
    @ObservedObject var viewModel: AgendaViewModel
    let date: Date
    @Binding var selectedAppointment: Appointment?
    @Binding var selectedRecurringBlock: RecurringBlock?

    private var isToday: Bool {
        Calendar.current.isDateInToday(date)
    }

    /// Agendamentos filtrados para esta data específica
    private var dayAppointments: [Appointment] {
        let calendar = Calendar.current
        return viewModel.appointments.filter { calendar.isDate($0.start, inSameDayAs: date) }
    }

    /// Bloqueios para esta data
    private var dayBlocks: [RecurringBlock] {
        viewModel.blocksForDate(date)
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical, showsIndicators: true) {
                HStack(alignment: .top, spacing: 0) {
                    // Coluna de horas
                    CalendarTimeColumn()
                        .frame(width: CalendarConstants.timeColumnWidth)

                    // Grid principal
                    ZStack(alignment: .topLeading) {
                        // Linhas de hora
                        CalendarHourLines()

                        // Bloqueios recorrentes
                        ForEach(dayBlocks, id: \.id) { block in
                            DayRecurringBlockView(
                                block: block,
                                date: date,
                                availableWidth: UIScreen.main.bounds.width - CalendarConstants.timeColumnWidth - 16
                            ) {
                                selectedRecurringBlock = block
                            }
                        }

                        // Agendamentos
                        let positioned = OverlapLayoutEngine.calculateLayout(for: dayAppointments)
                        ForEach(positioned) { pos in
                            DayAppointmentBlock(
                                positioned: pos,
                                availableWidth: UIScreen.main.bounds.width - CalendarConstants.timeColumnWidth - 16
                            ) {
                                selectedAppointment = pos.appointment
                            }
                        }

                        // Indicador de hora atual
                        if isToday {
                            CurrentTimeIndicator(isToday: true)
                                .padding(.leading, -4)
                        }
                    }
                    .frame(height: CalendarConstants.totalGridHeight)
                }
                .padding(.top, 8)
                .id("dayTop")
            }
            .background(Color(.systemGroupedBackground))
            .onAppear {
                if isToday {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                        withAnimation(.easeInOut(duration: 0.3)) {
                            proxy.scrollTo("dayTop", anchor: .top)
                        }
                    }
                }
            }
        }
    }
}

// MARK: - Week Paging View
/// Vista paginada para modo semanal

struct WeekPagingView: View {
    @ObservedObject var viewModel: AgendaViewModel
    @State private var selectedAppointment: Appointment?

    var body: some View {
        CalendarPagingContainer(viewModel: viewModel) { date in
            WeekPageContent(
                viewModel: viewModel,
                weekStartDate: date,
                selectedAppointment: $selectedAppointment
            )
        }
        .sheet(item: $selectedAppointment) { appointment in
            AppointmentDetailSheet(appointment: appointment) {
                Task { await viewModel.loadData() }
            }
        }
    }
}

// MARK: - Week Page Content
/// Conteúdo de uma página de semana individual

struct WeekPageContent: View {
    @Environment(\.horizontalSizeClass) private var sizeClass
    @ObservedObject var viewModel: AgendaViewModel
    let weekStartDate: Date
    @Binding var selectedAppointment: Appointment?

    /// iPhone ou iPad?
    private var isCompact: Bool {
        sizeClass != .regular
    }

    /// Largura da coluna de tempo adaptativa
    private var timeColumnWidth: CGFloat {
        isCompact ? 35 : 50
    }

    /// Dias da semana
    private var weekDates: [Date] {
        var calendar = Calendar.current
        calendar.firstWeekday = 2 // Segunda-feira (1 = Domingo, 2 = Segunda)
        let startOfWeek = calendar.dateInterval(of: .weekOfYear, for: weekStartDate)?.start ?? weekStartDate

        return (0..<7).compactMap { dayOffset in
            calendar.date(byAdding: .day, value: dayOffset, to: startOfWeek)
        }
    }

    var body: some View {
        GeometryReader { geometry in
            let availableWidth = geometry.size.width
            let dayColumnWidth = calculateDayColumnWidth(for: availableWidth)

            VStack(spacing: 0) {
                // Header fixo
                weekHeader(dayColumnWidth: dayColumnWidth)

                // Grid com scroll vertical apenas
                weekGrid(dayColumnWidth: dayColumnWidth)
            }
        }
        .background(Color(.systemGroupedBackground))
    }

    // MARK: - Layout Calculations

    private func calculateDayColumnWidth(for availableWidth: CGFloat) -> CGFloat {
        let widthForDays = availableWidth - timeColumnWidth
        return widthForDays / 7
    }

    // MARK: - Week Header

    private func weekHeader(dayColumnWidth: CGFloat) -> some View {
        HStack(spacing: 0) {
            Color.clear
                .frame(width: timeColumnWidth)

            ForEach(weekDates, id: \.self) { date in
                WeekDayHeaderCell(
                    date: date,
                    isToday: Calendar.current.isDateInToday(date),
                    isSelected: Calendar.current.isDate(date, inSameDayAs: viewModel.selectedDate),
                    width: dayColumnWidth,
                    isCompact: isCompact
                ) {
                    viewModel.viewMode = .day
                    viewModel.selectDate(date)
                }
            }
        }
        .frame(height: isCompact ? 50 : CalendarConstants.dayHeaderHeight)
        .background(Color(.systemBackground))
        .overlay(
            Rectangle()
                .fill(Color(.systemGray4))
                .frame(height: 0.5),
            alignment: .bottom
        )
    }

    // MARK: - Week Grid

    private func weekGrid(dayColumnWidth: CGFloat) -> some View {
        ScrollView(.vertical, showsIndicators: true) {
            HStack(alignment: .top, spacing: 0) {
                WeekTimeColumnView(isCompact: isCompact)
                    .frame(width: timeColumnWidth)

                ForEach(weekDates, id: \.self) { date in
                    WeekDayColumnView(
                        date: date,
                        appointments: appointmentsFor(date),
                        recurringBlocks: blocksFor(date),
                        width: dayColumnWidth,
                        isCompact: isCompact,
                        onAppointmentTap: { appointment in
                            selectedAppointment = appointment
                        }
                    )
                }
            }
        }
        .id("week-paging-\(weekStartDate.timeIntervalSince1970)-\(viewModel.appointments.count)")
    }

    // MARK: - Helpers

    private func appointmentsFor(_ date: Date) -> [Appointment] {
        let calendar = Calendar.current
        return viewModel.appointments.filter { calendar.isDate($0.start, inSameDayAs: date) }
    }

    private func blocksFor(_ date: Date) -> [RecurringBlock] {
        return viewModel.blocksForDate(date)
    }
}

// MARK: - Preview

#Preview("Day Paging") {
    struct PreviewWrapper: View {
        @StateObject var viewModel = AgendaViewModel()

        var body: some View {
            NavigationStack {
                DayPagingView(viewModel: viewModel)
                    .navigationTitle("Agenda")
            }
            .environmentObject(SupabaseManager.shared)
        }
    }

    return PreviewWrapper()
}

#Preview("Week Paging") {
    struct PreviewWrapper: View {
        @StateObject var viewModel = AgendaViewModel()

        var body: some View {
            NavigationStack {
                WeekPagingView(viewModel: viewModel)
                    .navigationTitle("Semana")
            }
            .environmentObject(SupabaseManager.shared)
        }
    }

    return PreviewWrapper()
}
