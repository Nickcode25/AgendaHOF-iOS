import SwiftUI

/// Vista de calendário para um único dia com grid de tempo
/// Implementa layout similar ao Apple Calendar / Google Calendar
struct CalendarDayView: View {
    @ObservedObject var viewModel: AgendaViewModel
    
    private var isToday: Bool {


        Calendar.current.isDateInToday(viewModel.selectedDate)
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical, showsIndicators: true) {
                HStack(alignment: .top, spacing: 0) {
                    // Coluna de horas (fixa à esquerda)
                    CalendarTimeColumn()
                        .frame(width: CalendarConstants.timeColumnWidth)

                    // Grid principal com agendamentos
                    GeometryReader { geometry in
                        ZStack(alignment: .topLeading) {
                            // Linhas de hora (background)
                            CalendarHourLines()

                            // Bloqueios recorrentes (atrás dos agendamentos)
                            recurringBlocksLayer(width: geometry.size.width)

                            // Agendamentos posicionados com resolução de conflitos
                            appointmentsLayer(width: geometry.size.width)

                            // Indicador de hora atual (linha vermelha)
                            CurrentTimeIndicator(isToday: isToday)
                                .padding(.leading, -4)
                        }
                    }
                    .frame(height: CalendarConstants.totalGridHeight)
                }
                .padding(.top, 8)
                .id("calendarTop")
            }
            .background(Color(.systemGroupedBackground))
            .onAppear {
                if isToday {
                    scrollToCurrentTime(proxy: proxy)
                }
            }
        }
    }

    // MARK: - Recurring Blocks Layer

    @ViewBuilder
    private func recurringBlocksLayer(width: CGFloat) -> some View {
        let blocks = viewModel.blocksForDate(viewModel.selectedDate)
        let appointments = viewModel.appointmentsForSelectedDate

        // Para cada bloco, calcular os segmentos visíveis (não sobrepostos por agendamentos)
        ForEach(blocks, id: \.id) { block in
            let segments = calculateBlockSegments(block: block, appointments: appointments)

            ForEach(segments, id: \.id) { segment in
                DayRecurringBlockSegmentView(
                    segment: segment,
                    block: block,
                    availableWidth: width
                ) {
                    viewModel.activeSheet = .editRecurringBlock(block)
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
    private func appointmentsLayer(width: CGFloat) -> some View {
        let appointments = viewModel.appointmentsForSelectedDate
        let positionedAppointments = OverlapLayoutEngine.calculateLayout(for: appointments)

        ForEach(positionedAppointments) { positioned in
            DayAppointmentBlock(
                positioned: positioned,
                availableWidth: width
            ) {
                viewModel.activeSheet = .appointmentDetails(positioned.appointment)
            }
        }
    }

    // MARK: - Scroll to Current Time

    private func scrollToCurrentTime(proxy: ScrollViewProxy) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            withAnimation(.easeInOut(duration: 0.3)) {
                proxy.scrollTo("calendarTop", anchor: .top)
            }
        }
    }
}

// MARK: - Day Appointment Block

/// Bloco visual de agendamento para a vista diária
struct DayAppointmentBlock: View {
    @Environment(\.horizontalSizeClass) private var sizeClass

    let positioned: PositionedAppointment
    let availableWidth: CGFloat
    var onTap: () -> Void

    private var appointment: Appointment {
        positioned.appointment
    }

    private var blockColor: Color {
        CalendarConstants.appointmentColor(for: appointment)
    }

    private var blockWidth: CGFloat {
        positioned.width(for: availableWidth)
    }

    private var xOffset: CGFloat {
        positioned.xOffset(for: availableWidth)
    }

    private var blockHeight: CGFloat {
        positioned.height
    }

    /// Fonte fixa e compacta para todos os agendamentos
    /// Tamanho consistente independente da duração do agendamento
    private var textFont: Font {
        .system(size: 13, weight: .medium)
    }

    /// Largura da barra lateral adaptativa
    private var barWidth: CGFloat {
        sizeClass == .regular ? 6 : 4
    }

    var body: some View {
        HStack(spacing: 0) {
            // Barra lateral colorida
            RoundedRectangle(cornerRadius: 2)
                .fill(blockColor)
                .frame(width: barWidth)

            // Conteúdo centralizado: "09:30 - 10:00 Nome"
            Text("\(appointment.timeRange) \(appointment.displayTitle)")
                .font(textFont)
                .fontWeight(.medium)
                .foregroundColor(.primary)
                .lineLimit(1)
                .padding(.horizontal, sizeClass == .regular ? 8 : 6)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(width: blockWidth, height: blockHeight)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(CalendarConstants.appointmentBackgroundColor(for: appointment))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .strokeBorder(blockColor.opacity(0.3), lineWidth: 1)
        )
        .contentShape(Rectangle())
        .onTapGesture {
            onTap()
        }
        .offset(x: xOffset, y: positioned.yPosition)
    }
}

// MARK: - Block Segment Model

/// Representa um segmento de um bloqueio recorrente (parte visível não sobreposta por agendamentos)
struct BlockSegment: Identifiable {
    let id: String
    let startMinutes: Int  // Minutos do dia (0-1440)
    let endMinutes: Int    // Minutos do dia (0-1440)

    /// Horário de início formatado (ex: "12:00")
    var startTimeFormatted: String {
        let hour = startMinutes / 60
        let minute = startMinutes % 60
        return String(format: "%02d:%02d", hour, minute)
    }

    /// Horário de fim formatado (ex: "13:30")
    var endTimeFormatted: String {
        let hour = endMinutes / 60
        let minute = endMinutes % 60
        return String(format: "%02d:%02d", hour, minute)
    }

    /// Duração em minutos
    var durationMinutes: Int {
        endMinutes - startMinutes
    }
}

// MARK: - Day Recurring Block Segment View

/// Bloco visual de um segmento de bloqueio recorrente para a vista diária
struct DayRecurringBlockSegmentView: View {
    let segment: BlockSegment
    let block: RecurringBlock
    let availableWidth: CGFloat
    var onTap: (() -> Void)?

    /// Cor do bloqueio (cinza para bloqueios)
    private let blockColor = Color.gray

    /// Posição Y baseada no horário de início do segmento
    private var yPosition: CGFloat {
        let startHour = segment.startMinutes / 60
        let startMinute = segment.startMinutes % 60

        let hoursFromStart = CGFloat(startHour - CalendarConstants.startHour)
        let minuteFraction = CGFloat(startMinute) / 60.0

        let position = (hoursFromStart + minuteFraction) * CalendarConstants.hourHeight
        return max(0, position)
    }

    /// Altura baseada na duração do segmento
    private var blockHeight: CGFloat {
        let height = CGFloat(segment.durationMinutes) / 60.0 * CalendarConstants.hourHeight
        return max(height, 15)
    }

    var body: some View {
        HStack(spacing: 0) {
            // Barra lateral colorida
            RoundedRectangle(cornerRadius: 2)
                .fill(blockColor)
                .frame(width: 4)

            // Conteúdo centralizado: "12:00 Título"
            Text("\(segment.startTimeFormatted) \(block.title)")
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(.secondary)
                .lineLimit(1)
                .padding(.horizontal, 6)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(width: availableWidth - 8, height: blockHeight)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(blockColor.opacity(0.1))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .strokeBorder(blockColor.opacity(0.2), lineWidth: 1)
        )
        .contentShape(Rectangle())
        .onTapGesture {
            onTap?()
        }
        .offset(x: 4, y: yPosition)
    }
}

// MARK: - Day Recurring Block View (Legacy - mantido para compatibilidade)

/// Bloco visual de bloqueio recorrente para a vista diária
struct DayRecurringBlockView: View {
    let block: RecurringBlock
    let date: Date
    let availableWidth: CGFloat
    var onTap: (() -> Void)?

    /// Cor do bloqueio (cinza para bloqueios)
    private let blockColor = Color.gray

    /// Posição Y baseada no horário de início
    private var yPosition: CGFloat {
        let startHour = Int(block.startTime.prefix(2)) ?? CalendarConstants.startHour
        let startMinute = Int(block.startTime.dropFirst(3).prefix(2)) ?? 0

        let hoursFromStart = CGFloat(startHour - CalendarConstants.startHour)
        let minuteFraction = CGFloat(startMinute) / 60.0

        let position = (hoursFromStart + minuteFraction) * CalendarConstants.hourHeight
        return max(0, position)
    }

    /// Altura baseada na duração
    private var blockHeight: CGFloat {
        let startHour = Int(block.startTime.prefix(2)) ?? 0
        let startMinute = Int(block.startTime.dropFirst(3).prefix(2)) ?? 0
        let endHour = Int(block.endTime.prefix(2)) ?? 0
        let endMinute = Int(block.endTime.dropFirst(3).prefix(2)) ?? 0

        let startTotalMinutes = startHour * 60 + startMinute
        let endTotalMinutes = endHour * 60 + endMinute
        let durationMinutes = endTotalMinutes - startTotalMinutes

        let height = CGFloat(durationMinutes) / 60.0 * CalendarConstants.hourHeight
        return max(height, 15)
    }

    /// Horário formatado (apenas início, ex: "12:00")
    private var startTimeFormatted: String {
        String(block.startTime.prefix(5))
    }

    var body: some View {
        HStack(spacing: 0) {
            // Barra lateral colorida
            RoundedRectangle(cornerRadius: 2)
                .fill(blockColor)
                .frame(width: 4)

            // Conteúdo centralizado: "12:00 Título"
            Text("\(startTimeFormatted) \(block.title)")
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(.secondary)
                .lineLimit(1)
                .padding(.horizontal, 6)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(width: availableWidth - 8, height: blockHeight)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(blockColor.opacity(0.1))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .strokeBorder(blockColor.opacity(0.2), lineWidth: 1)
        )
        .contentShape(Rectangle())
        .onTapGesture {
            onTap?()
        }
        .offset(x: 4, y: yPosition)
    }
}

// MARK: - Preview

struct CalendarDayView_Previews: PreviewProvider {
    static var previews: some View {
        Group {
            // Preview 1: Day View with Overlaps
            PreviewWrapper()
                .previewDisplayName("Day View with Overlaps")

            // Preview 2: Sample Overlapping Appointments
            SampleAppointmentsPreview()
                .previewDisplayName("Sample Overlapping Appointments")
        }
    }

    struct PreviewWrapper: View {
        @StateObject var viewModel = AgendaViewModel()

        var body: some View {
            NavigationStack {
                CalendarDayView(viewModel: viewModel)
                    .navigationTitle("Agenda")
            }
            .environmentObject(SupabaseManager.shared)
        }
    }

    struct SampleAppointmentsPreview: View {
        var body: some View {
            ScrollView {
                HStack(alignment: .top, spacing: 0) {
                    CalendarTimeColumn()
                        .frame(width: 50)

                    GeometryReader { geo in
                        ZStack(alignment: .topLeading) {
                            CalendarHourLines()
                        }
                    }
                    .frame(height: CalendarConstants.totalGridHeight)
                }
            }
            .padding()
        }
    }
}
