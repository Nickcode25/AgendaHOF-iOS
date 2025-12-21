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
    @State private var selectedAppointment: Appointment?
    @State private var selectedRecurringBlock: RecurringBlock?

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
                            selectedAppointment = appointment
                        },
                        onRecurringBlockTap: { block in
                            selectedRecurringBlock = block
                        }
                    )
                }
            }
        }
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

// MARK: - Week Day Header Cell

struct WeekDayHeaderCell: View {
    let date: Date
    let isToday: Bool
    let isSelected: Bool
    let width: CGFloat
    var isCompact: Bool = false
    var onTap: () -> Void

    /// Abreviação do dia da semana (uma letra no iPhone)
    private var weekdayText: String {
        if isCompact {
            // Uma letra apenas: D, S, T, Q, Q, S, S
            return String(date.shortWeekdayName.prefix(1))
        }
        return date.shortWeekdayName
    }

    private var weekdayFont: Font {
        isCompact ? .system(size: 10, weight: .medium) : .caption
    }

    private var dayFont: Font {
        isCompact ? .system(size: 14, weight: .semibold) : .title3
    }

    private var circleSize: CGFloat {
        isCompact ? 24 : 36
    }

    var body: some View {
        VStack(spacing: isCompact ? 2 : 4) {
            // Dia da semana abreviado
            Text(weekdayText)
                .font(weekdayFont)
                .foregroundColor(isToday ? .appPrimary : .secondary)

            // Número do dia
            Text(date.dayNumber)
                .font(dayFont)
                .foregroundColor(isToday ? .white : (isSelected ? .appPrimary : .primary))
                .frame(width: circleSize, height: circleSize)
                .background(
                    Circle()
                        .fill(isToday ? Color.appPrimary : Color.clear)
                )
        }
        .frame(width: width)
        .contentShape(Rectangle())
        .onTapGesture(perform: onTap)
    }
}

// MARK: - Week Day Column View

/// Coluna de um dia - usa ZStack para posicionar eventos por offset
/// A largura é dinâmica e calculada pelo parent baseado no espaço disponível
struct WeekDayColumnView: View {
    let date: Date
    let appointments: [Appointment]
    let recurringBlocks: [RecurringBlock]
    let width: CGFloat
    var isCompact: Bool = false
    var onAppointmentTap: (Appointment) -> Void
    var onRecurringBlockTap: ((RecurringBlock) -> Void)?

    private var isToday: Bool {
        Calendar.current.isDateInToday(date)
    }

    /// Padding interno para os cards (menor no iPhone)
    private var cardPadding: CGFloat {
        isCompact ? 1 : 4
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            // Background para hoje
            if isToday {
                Rectangle()
                    .fill(Color.appPrimary.opacity(0.05))
            }

            // Separador vertical entre dias
            HStack {
                Spacer()
                Rectangle()
                    .fill(Color(.systemGray5))
                    .frame(width: 0.5)
            }

            // Grid de fundo com linhas de hora
            WeekTimeGridBackground()

            // Camada de bloqueios recorrentes (atrás dos agendamentos)
            recurringBlocksLayer

            // Camada de agendamentos com resolução de conflitos
            appointmentsLayer

            // Indicador de hora atual (apenas para hoje)
            if isToday {
                WeekCurrentTimeIndicator(isToday: true)
                    .padding(.leading, -2)
            }
        }
        .frame(width: width, height: CalendarConstants.totalWeekGridHeight)
    }

    // MARK: - Recurring Blocks Layer

    @ViewBuilder
    private var recurringBlocksLayer: some View {
        // Para cada bloco, calcular os segmentos visíveis (não sobrepostos por agendamentos)
        ForEach(recurringBlocks, id: \.id) { block in
            let segments = calculateBlockSegments(block: block, appointments: appointments)

            ForEach(segments, id: \.id) { segment in
                WeekRecurringBlockSegmentView(
                    segment: segment,
                    block: block,
                    availableWidth: width - cardPadding * 2,
                    isCompact: isCompact
                ) {
                    onRecurringBlockTap?(block)
                }
            }
        }
    }

    /// Calcula os segmentos visíveis de um bloqueio, removendo as partes sobrepostas por agendamentos
    private func calculateBlockSegments(block: RecurringBlock, appointments: [Appointment]) -> [BlockSegment] {
        // Converter horários do bloco para minutos do dia
        let blockStartMinutes = timeToMinutes(block.startTime)
        let blockEndMinutes = timeToMinutes(block.endTime)

        // Coletar intervalos ocupados por agendamentos
        var occupiedRanges: [(start: Int, end: Int)] = []

        for appointment in appointments {
            let calendar = Calendar.current
            let appointmentStartMinutes = calendar.component(.hour, from: appointment.start) * 60 +
                                          calendar.component(.minute, from: appointment.start)
            let appointmentEndMinutes = calendar.component(.hour, from: appointment.end) * 60 +
                                        calendar.component(.minute, from: appointment.end)

            // Verificar se há sobreposição com o bloco
            if appointmentStartMinutes < blockEndMinutes && appointmentEndMinutes > blockStartMinutes {
                occupiedRanges.append((start: appointmentStartMinutes, end: appointmentEndMinutes))
            }
        }

        // Se não há sobreposições, retornar o bloco inteiro
        if occupiedRanges.isEmpty {
            return [BlockSegment(
                id: "\(block.id)-full",
                startMinutes: blockStartMinutes,
                endMinutes: blockEndMinutes
            )]
        }

        // Ordenar intervalos ocupados por início
        let sortedRanges = occupiedRanges.sorted { $0.start < $1.start }

        // Calcular segmentos livres
        var segments: [BlockSegment] = []
        var currentStart = blockStartMinutes

        for range in sortedRanges {
            // Se há espaço antes do próximo agendamento
            if currentStart < range.start {
                let segmentEnd = min(range.start, blockEndMinutes)
                if segmentEnd > currentStart {
                    segments.append(BlockSegment(
                        id: "\(block.id)-\(currentStart)-\(segmentEnd)",
                        startMinutes: currentStart,
                        endMinutes: segmentEnd
                    ))
                }
            }
            // Avançar para depois do agendamento
            currentStart = max(currentStart, range.end)
        }

        // Se sobrou espaço após o último agendamento
        if currentStart < blockEndMinutes {
            segments.append(BlockSegment(
                id: "\(block.id)-\(currentStart)-\(blockEndMinutes)",
                startMinutes: currentStart,
                endMinutes: blockEndMinutes
            ))
        }

        return segments
    }

    /// Converte string de horário "HH:mm:ss" para minutos do dia
    private func timeToMinutes(_ time: String) -> Int {
        let hour = Int(time.prefix(2)) ?? 0
        let minute = Int(time.dropFirst(3).prefix(2)) ?? 0
        return hour * 60 + minute
    }

    // MARK: - Appointments Layer

    @ViewBuilder
    private var appointmentsLayer: some View {
        let positionedAppointments = OverlapLayoutEngine.calculateLayout(for: appointments)

        ForEach(positionedAppointments) { positioned in
            WeekEventCardView(
                positioned: positioned,
                availableWidth: width - cardPadding * 2,
                isCompact: isCompact
            ) {
                onAppointmentTap(positioned.appointment)
            }
        }
    }
}

// MARK: - Week Event Card View

/// Card de evento com posicionamento baseado em tempo
/// Altura proporcional à duração: 15min = 37.5pt, 30min = 75pt, 60min = 150pt
struct WeekEventCardView: View {
    let positioned: PositionedAppointment
    let availableWidth: CGFloat
    var isCompact: Bool = false
    var onTap: () -> Void

    private var appointment: Appointment {
        positioned.appointment
    }

    private var blockColor: Color {
        CalendarConstants.appointmentColor(for: appointment)
    }

    /// Largura baseada em colunas (para conflitos)
    private var blockWidth: CGFloat {
        positioned.width(for: availableWidth, padding: isCompact ? 1 : 2)
    }

    /// Offset X baseado na coluna
    private var xOffset: CGFloat {
        positioned.xOffset(for: availableWidth, padding: isCompact ? 1 : 2)
    }

    /// Altura baseada na duração real (minutos × minuteHeight)
    private var blockHeight: CGFloat {
        max(positioned.weekHeight, CalendarConstants.minuteHeight * 15) // Mínimo 15min
    }

    /// Posição Y baseada no horário de início
    private var yPosition: CGFloat {
        positioned.weekYPosition
    }

    /// Fonte para o horário - menor no iPhone
    private var timeFont: Font {
        isCompact ? .system(size: 8, weight: .semibold) : .system(size: 9, weight: .semibold)
    }

    /// Fonte para o nome - menor no iPhone
    private var nameFont: Font {
        isCompact ? .system(size: 7, weight: .medium) : .system(size: 9, weight: .medium)
    }

    /// Largura da barra lateral
    private var barWidth: CGFloat {
        isCompact ? 2 : 3
    }

    /// Primeiro nome do paciente/título (abreviado no iPhone)
    private var displayName: String {
        let fullName = appointment.displayTitle
        let firstName = fullName.components(separatedBy: " ").first ?? fullName
        if isCompact && firstName.count > 6 {
            return String(firstName.prefix(5)) + "."
        }
        return firstName
    }

    var body: some View {
        HStack(spacing: 0) {
            // Barra lateral colorida
            RoundedRectangle(cornerRadius: 1)
                .fill(blockColor)
                .frame(width: barWidth)

            // Conteúdo: horário em cima, nome embaixo (tanto iPhone quanto iPad)
            VStack(spacing: isCompact ? 0 : 1) {
                // Horário
                Text(appointment.start.hourMinuteString)
                    .font(timeFont)
                    .foregroundColor(blockColor)

                // Primeiro nome
                Text(displayName)
                    .font(nameFont)
                    .foregroundColor(.primary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            .padding(.horizontal, isCompact ? 1 : 2)
            .padding(.vertical, isCompact ? 1 : 2)
        }
        .frame(width: blockWidth, height: blockHeight)
        .background(
            RoundedRectangle(cornerRadius: isCompact ? 2 : 4)
                .fill(CalendarConstants.appointmentBackgroundColor(for: appointment))
        )
        .overlay(
            RoundedRectangle(cornerRadius: isCompact ? 2 : 4)
                .strokeBorder(blockColor.opacity(0.3), lineWidth: 0.5)
        )
        .contentShape(Rectangle())
        .onTapGesture {
            onTap()
        }
        .offset(x: xOffset, y: yPosition)
    }
}

// MARK: - Week Recurring Block Segment View

/// Bloco visual de um segmento de bloqueio recorrente para a vista semanal
struct WeekRecurringBlockSegmentView: View {
    let segment: BlockSegment
    let block: RecurringBlock
    let availableWidth: CGFloat
    var isCompact: Bool = false
    var onTap: (() -> Void)?

    /// Cor do bloqueio (cinza para bloqueios)
    private let blockColor = Color.gray

    /// Posição Y baseada no horário de início do segmento (usando escala semanal)
    private var yPosition: CGFloat {
        let startHour = segment.startMinutes / 60
        let startMinute = segment.startMinutes % 60

        let minutesFromStart = (startHour - CalendarConstants.startHour) * 60 + startMinute
        let position = CGFloat(minutesFromStart) * CalendarConstants.minuteHeight
        return max(0, position)
    }

    /// Altura baseada na duração do segmento (usando escala semanal)
    private var blockHeight: CGFloat {
        let height = CGFloat(segment.durationMinutes) * CalendarConstants.minuteHeight
        return max(height, CalendarConstants.minuteHeight * 15) // Mínimo 15min
    }

    /// Primeiro nome do título (abreviado no iPhone)
    private var displayTitle: String {
        let title = block.title
        if isCompact && title.count > 5 {
            return String(title.prefix(4)) + "."
        }
        return title
    }

    var body: some View {
        HStack(spacing: 0) {
            // Barra lateral colorida
            RoundedRectangle(cornerRadius: 1)
                .fill(blockColor)
                .frame(width: isCompact ? 2 : 3)

            // Conteúdo: horário em cima, título embaixo (tanto iPhone quanto iPad)
            VStack(spacing: isCompact ? 0 : 1) {
                Text(segment.startTimeFormatted)
                    .font(.system(size: isCompact ? 8 : 9, weight: .semibold))
                    .foregroundColor(blockColor)

                Text(displayTitle)
                    .font(.system(size: isCompact ? 7 : 9, weight: .medium))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            .padding(.horizontal, isCompact ? 1 : 2)
            .padding(.vertical, isCompact ? 1 : 2)
        }
        .frame(width: availableWidth, height: blockHeight)
        .background(
            RoundedRectangle(cornerRadius: isCompact ? 2 : 4)
                .fill(blockColor.opacity(0.1))
        )
        .overlay(
            RoundedRectangle(cornerRadius: isCompact ? 2 : 4)
                .strokeBorder(blockColor.opacity(0.2), lineWidth: 0.5)
        )
        .contentShape(Rectangle())
        .onTapGesture {
            onTap?()
        }
        .offset(x: isCompact ? 1 : 2, y: yPosition)
    }
}

// MARK: - Week Recurring Block View (Legacy - mantido para compatibilidade)

/// Bloco visual de bloqueio recorrente para a vista semanal
struct WeekRecurringBlockView: View {
    let block: RecurringBlock
    let availableWidth: CGFloat
    var isCompact: Bool = false
    var onTap: (() -> Void)?

    /// Cor do bloqueio (cinza para bloqueios)
    private let blockColor = Color.gray

    /// Posição Y baseada no horário de início (usando escala semanal)
    private var yPosition: CGFloat {
        let startHour = Int(block.startTime.prefix(2)) ?? CalendarConstants.startHour
        let startMinute = Int(block.startTime.dropFirst(3).prefix(2)) ?? 0

        let minutesFromStart = (startHour - CalendarConstants.startHour) * 60 + startMinute
        let position = CGFloat(minutesFromStart) * CalendarConstants.minuteHeight
        return max(0, position)
    }

    /// Altura baseada na duração (usando escala semanal)
    private var blockHeight: CGFloat {
        let startHour = Int(block.startTime.prefix(2)) ?? 0
        let startMinute = Int(block.startTime.dropFirst(3).prefix(2)) ?? 0
        let endHour = Int(block.endTime.prefix(2)) ?? 0
        let endMinute = Int(block.endTime.dropFirst(3).prefix(2)) ?? 0

        let startTotalMinutes = startHour * 60 + startMinute
        let endTotalMinutes = endHour * 60 + endMinute
        let durationMinutes = endTotalMinutes - startTotalMinutes

        let height = CGFloat(durationMinutes) * CalendarConstants.minuteHeight
        return max(height, CalendarConstants.minuteHeight * 15) // Mínimo 15min
    }

    /// Horário formatado (apenas início, ex: "12:00")
    private var startTimeFormatted: String {
        String(block.startTime.prefix(5))
    }

    /// Primeiro nome do título (abreviado no iPhone)
    private var displayTitle: String {
        let title = block.title
        if isCompact && title.count > 5 {
            return String(title.prefix(4)) + "."
        }
        return title
    }

    var body: some View {
        HStack(spacing: 0) {
            // Barra lateral colorida
            RoundedRectangle(cornerRadius: 1)
                .fill(blockColor)
                .frame(width: isCompact ? 2 : 3)

            // Conteúdo: horário em cima, título embaixo (tanto iPhone quanto iPad)
            VStack(spacing: isCompact ? 0 : 1) {
                Text(startTimeFormatted)
                    .font(.system(size: isCompact ? 8 : 9, weight: .semibold))
                    .foregroundColor(blockColor)

                Text(displayTitle)
                    .font(.system(size: isCompact ? 7 : 9, weight: .medium))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            .padding(.horizontal, isCompact ? 1 : 2)
            .padding(.vertical, isCompact ? 1 : 2)
        }
        .frame(width: availableWidth, height: blockHeight)
        .background(
            RoundedRectangle(cornerRadius: isCompact ? 2 : 4)
                .fill(blockColor.opacity(0.1))
        )
        .overlay(
            RoundedRectangle(cornerRadius: isCompact ? 2 : 4)
                .strokeBorder(blockColor.opacity(0.2), lineWidth: 0.5)
        )
        .contentShape(Rectangle())
        .onTapGesture {
            onTap?()
        }
        .offset(x: isCompact ? 1 : 2, y: yPosition)
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
