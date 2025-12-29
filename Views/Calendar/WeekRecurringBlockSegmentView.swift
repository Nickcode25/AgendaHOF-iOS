import SwiftUI

// MARK: - Week Recurring Block Segment View

/// Bloco visual de um segmento de bloqueio recorrente para a vista semanal
/// Exibe apenas os segmentos visíveis (não sobrepostos por agendamentos)
struct WeekRecurringBlockSegmentView: View {

    // MARK: - Properties

    let segment: BlockSegment
    let block: RecurringBlock
    let availableWidth: CGFloat
    var isCompact: Bool = false
    var onTap: (() -> Void)?

    // MARK: - Computed Properties

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

    // MARK: - Body

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

// MARK: - Preview

#Preview {
    let block = RecurringBlock(
        id: UUID().uuidString,
        createdAt: Date(),
        updatedAt: Date(),
        userId: UUID().uuidString,
        title: "Almoço",
        startTime: "12:00:00",
        endTime: "13:00:00",
        daysOfWeek: [1, 2, 3, 4, 5],
        active: true,
        notes: nil,
        professional: nil,
        professionalId: nil
    )

    let segment = BlockSegment(
        id: "\(block.id)-full",
        startMinutes: 720, // 12:00
        endMinutes: 780    // 13:00
    )

    ZStack(alignment: .topLeading) {
        Color(.systemGroupedBackground)
            .ignoresSafeArea()

        VStack(spacing: 20) {
            Text("iPad (Regular)")
            WeekRecurringBlockSegmentView(
                segment: segment,
                block: block,
                availableWidth: 100,
                isCompact: false,
                onTap: {}
            )

            Text("iPhone (Compact)")
            WeekRecurringBlockSegmentView(
                segment: segment,
                block: block,
                availableWidth: 50,
                isCompact: true,
                onTap: {}
            )
        }
        .padding()
    }
}
