import SwiftUI

/// Vista de calendário semanal com arquitetura baseada em minutos
/// 🧠 REGRA DE OURO: tempo manda no layout, scroll é obrigatório, nada é comprimido
///
/// Arquitetura de Layout Responsivo:
/// - Em landscape/iPad: usa 100% da largura disponível, sem scroll horizontal
/// - Em portrait/iPhone: permite scroll horizontal se necessário
/// - A coluna de tempo mantém largura fixa
/// - Os dias dividem igualmente o espaço restante
///
/// WeeklyCalendarView
///  └─ GeometryReader (detecta largura disponível)
///     └─ Vertical Scroll (tempo)
///        └─ Horizontal Scroll (condicional)
///           └─ HStack
///              ├─ TimeColumnView (largura fixa)
///              ├─ DayColumnView (largura dinâmica)
///              └─ ...
struct CalendarWeekView: View {
    @Environment(\.horizontalSizeClass) private var sizeClass
    @ObservedObject var viewModel: AgendaViewModel
    @State private var refreshID = UUID() // Trigger para forçar re-render

    /// Número de dias visíveis na semana
    private let numberOfDays: CGFloat = 7

    /// Dias da semana atual
    private var weekDates: [Date] {
        var calendar = Calendar.current
        calendar.firstWeekday = 2 // Segunda-feira (1 = Domingo, 2 = Segunda)
        let startOfWeek = calendar.dateInterval(of: .weekOfYear, for: viewModel.selectedDate)?.start ?? viewModel.selectedDate

        return (0..<7).compactMap { dayOffset in
            calendar.date(byAdding: .day, value: dayOffset, to: startOfWeek)
        }
    }

    /// Largura da coluna de tempo adaptativa
    private var timeColumnWidth: CGFloat {
        sizeClass == .regular ? 50 : 35
    }

    var body: some View {
        // GeometryReader para obter a largura disponível da tela
        GeometryReader { geometry in
            let availableWidth = geometry.size.width
            let dayColumnWidth = calculateDayColumnWidth(for: availableWidth)

            VStack(spacing: 0) {
                // Header fixo com dias da semana
                weekHeaderView(dayColumnWidth: dayColumnWidth)

                // Grid de calendário com scroll vertical apenas
                calendarGridView(dayColumnWidth: dayColumnWidth)
            }
        }
        .background(Color(.systemGroupedBackground))
    }

    // MARK: - Layout Calculations

    /// Calcula a largura de cada coluna de dia baseado na largura disponível
    /// No iPhone: divide igualmente para caber todos os 7 dias sem scroll horizontal
    private func calculateDayColumnWidth(for availableWidth: CGFloat) -> CGFloat {
        // Largura disponível para os dias = largura total - coluna de tempo
        let widthForDays = availableWidth - timeColumnWidth

        // Largura de cada dia = espaço disponível / número de dias
        return widthForDays / numberOfDays
    }

    // MARK: - Week Header (fixo no topo)

    private func weekHeaderView(dayColumnWidth: CGFloat) -> some View {
        HStack(spacing: 0) {
            // Espaço para coluna de horas
            Color.clear
                .frame(width: timeColumnWidth)

            // Headers dos dias
            ForEach(weekDates, id: \.self) { date in
                WeekDayHeaderCell(
                    date: date,
                    isToday: Calendar.current.isDateInToday(date),
                    isSelected: Calendar.current.isDate(date, inSameDayAs: viewModel.selectedDate),
                    width: dayColumnWidth,
                    isCompact: sizeClass != .regular
                ) {
                    viewModel.viewMode = .day
                    viewModel.selectDate(date)
                }
            }
        }
        .frame(height: sizeClass == .regular ? CalendarConstants.dayHeaderHeight : 50)
        .background(Color(.systemBackground))
        .overlay(
            Rectangle()
                .fill(Color(.systemGray4))
                .frame(height: 0.5),
            alignment: .bottom
        )
    }

    // MARK: - Calendar Grid (scrollable)

    private func calendarGridView(dayColumnWidth: CGFloat) -> some View {
        // Scroll vertical apenas (sem scroll horizontal no iPhone)
        ScrollView(.vertical, showsIndicators: true) {
            HStack(alignment: .top, spacing: 0) {
                // Coluna de horas compacta
                WeekTimeColumnView(isCompact: sizeClass != .regular)
                    .frame(width: timeColumnWidth)

                // Colunas dos dias (largura calculada para caber na tela)
                ForEach(weekDates, id: \.self) { date in
                    WeekDayColumnView(
                        date: date,
                        appointments: appointmentsFor(date),
                        recurringBlocks: blocksFor(date),
                        width: dayColumnWidth,
                        isCompact: sizeClass != .regular,
                        onAppointmentTap: { appointment in
                            viewModel.activeSheet = .appointmentDetails(appointment)
                        },
                        onRecurringBlockTap: { block in
                            viewModel.activeSheet = .editRecurringBlock(block)
                        }
                    )
                }
            }
        }
        .id(viewModel.appointments.map(\.id).hashValue)
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

#Preview("Week View") {
    struct PreviewWrapper: View {
        @StateObject var viewModel = AgendaViewModel()

        var body: some View {
            NavigationStack {
                CalendarWeekView(viewModel: viewModel)
                    .navigationTitle("Semana")
            }
            .environmentObject(SupabaseManager.shared)
        }
    }

    return PreviewWrapper()
}


