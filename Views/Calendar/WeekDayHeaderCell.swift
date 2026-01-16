import SwiftUI

// MARK: - Week Day Header Cell

/// Célula de cabeçalho para cada dia na vista semanal
/// Exibe dia da semana abreviado e número do dia
/// Adapta tamanho e fonte para iPhone (compact) vs iPad (regular)
struct WeekDayHeaderCell: View {

    // MARK: - Properties

    let date: Date
    let isToday: Bool
    let isSelected: Bool
    let width: CGFloat
    var isCompact: Bool = false
    var onTap: () -> Void

    // MARK: - Computed Properties

    /// Abreviação do dia da semana (uma letra no iPhone, três no iPad)
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

    // MARK: - Body

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

// MARK: - Preview

#Preview {
    HStack(spacing: 0) {
        // Hoje (selecionado)
        WeekDayHeaderCell(
            date: Date(),
            isToday: true,
            isSelected: true,
            width: 50,
            isCompact: false,
            onTap: {}
        )

        // Dia normal
        WeekDayHeaderCell(
            date: Calendar.current.date(byAdding: .day, value: 1, to: Date())!,
            isToday: false,
            isSelected: false,
            width: 50,
            isCompact: false,
            onTap: {}
        )

        // iPhone (compact)
        WeekDayHeaderCell(
            date: Date(),
            isToday: true,
            isSelected: true,
            width: 40,
            isCompact: true,
            onTap: {}
        )
    }
    .previewLayout(.sizeThatFits)
    .padding()
}
