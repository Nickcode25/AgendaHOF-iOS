import SwiftUI

// MARK: - Week Day Column View

/// Coluna de um dia na vista semanal
/// Usa ZStack para posicionar eventos por offset baseado em tempo
/// A largura é dinâmica e calculada pelo parent baseado no espaço disponível
/// Implementa resolução de conflitos e segmentação de bloqueios recorrentes
struct WeekDayColumnView: View {

    // MARK: - Properties

    let date: Date
    let appointments: [Appointment]
    let recurringBlocks: [RecurringBlock]
    let width: CGFloat
    var isCompact: Bool = false
    var onAppointmentTap: (Appointment) -> Void
    var onRecurringBlockTap: ((RecurringBlock) -> Void)?

    // MARK: - Computed Properties

    private var isToday: Bool {
        Calendar.current.isDateInToday(date)
    }

    /// Padding interno para os cards (menor no iPhone)
    private var cardPadding: CGFloat {
        isCompact ? 1 : 4
    }

    // MARK: - Body

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
        .id(appointments.map(\.id).hashValue) // Força re-render quando a lista muda
    }

    // MARK: - Block Segmentation Logic

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
}

// MARK: - Preview

#Preview {
    let now = Date()
    let calendar = Calendar.current

    // Criar appointments de exemplo
    let appointment1Start = calendar.date(bySettingHour: 10, minute: 0, second: 0, of: now)!
    let appointment1End = calendar.date(bySettingHour: 11, minute: 0, second: 0, of: now)!

    let appointment1 = Appointment(
        id: UUID().uuidString,
        createdAt: now,
        updatedAt: now,
        userId: UUID().uuidString,
        patientId: nil,
        patientName: "João Silva",
        procedure: nil,
        procedureId: nil,
        selectedProducts: nil,
        professional: "Dr. Exemplo",
        room: nil,
        start: appointment1Start,
        end: appointment1End,
        notes: nil,
        status: .scheduled,
        isPersonal: false,
        title: nil
    )

    ScrollView {
        WeekDayColumnView(
            date: now,
            appointments: [appointment1],
            recurringBlocks: [],
            width: 100,
            isCompact: false,
            onAppointmentTap: { _ in },
            onRecurringBlockTap: { _ in }
        )
    }
    .frame(height: 400)
    .background(Color(.systemGroupedBackground))
}
