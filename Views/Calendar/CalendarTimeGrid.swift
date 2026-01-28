import SwiftUI

/// Grid vertical de horas (coluna da esquerda com horários)
/// O texto da hora fica alinhado com a linha do grid (no topo de cada bloco)
struct CalendarTimeColumn: View {
    @Environment(\.horizontalSizeClass) private var sizeClass

    /// Fonte adaptativa: legível em ambos dispositivos
    private var timeFont: Font {
        sizeClass == .regular ? .caption : .caption
    }

    var body: some View {
        VStack(spacing: 0) {
            ForEach(CalendarConstants.startHour..<CalendarConstants.endHour, id: \.self) { hour in
                HStack {
                    Text(String(format: "%02d:00", hour))
                        .font(timeFont)
                        .fontWeight(.medium)
                        .foregroundColor(.secondary)
                        .frame(width: CalendarConstants.timeColumnWidth - 8, alignment: .trailing)

                    Spacer()
                }
                .frame(height: CalendarConstants.hourHeight, alignment: .top)
                .offset(y: -6) // Ajuste para alinhar texto com a linha
            }
        }
    }
}

/// Linhas horizontais do grid de horas
struct CalendarHourLines: View {
    var body: some View {
        VStack(spacing: 0) {
            ForEach(CalendarConstants.startHour..<CalendarConstants.endHour, id: \.self) { _ in
                VStack(spacing: 0) {
                    // Linha discreta para hora cheia
                    Rectangle()
                        .fill(Color.gray.opacity(0.3))
                        .frame(height: 0.5)
                    Spacer()
                }
                .frame(height: CalendarConstants.hourHeight)
            }
        }
    }
}

// MARK: - Nova Arquitetura Semanal (baseada em minutos)
// 🧠 REGRA DE OURO: tempo manda no layout, scroll é obrigatório, nada é comprimido

/// Coluna de tempo para vista semanal - mesmo scale do calendário
/// Horários crescem junto com o tempo, nunca ficam esmagados
struct WeekTimeColumnView: View {
    var isCompact: Bool = false

    /// Fonte adaptativa - menor no iPhone
    private var timeFont: Font {
        isCompact ? .system(size: 9, weight: .medium) : .caption
    }

    /// Largura da coluna adaptativa
    private var columnWidth: CGFloat {
        isCompact ? 35 : CalendarConstants.timeColumnWidth
    }

    var body: some View {
        VStack(spacing: 0) {
            ForEach(CalendarConstants.startHour..<CalendarConstants.endHour, id: \.self) { hour in
                Text(isCompact ? String(format: "%02d", hour) : String(format: "%02d:00", hour))
                    .font(timeFont)
                    .foregroundColor(.secondary)
                    .frame(width: columnWidth, alignment: .trailing)
                    .frame(height: CalendarConstants.weekHourHeight, alignment: .top)
                    .padding(.trailing, isCompact ? 2 : 4)
            }
        }
    }
}

/// Grid de fundo com linhas horizontais para vista semanal
/// Linhas a cada 30 minutos para referência visual
struct WeekTimeGridBackground: View {
    var body: some View {
        VStack(spacing: 0) {
            ForEach(0..<CalendarConstants.totalHours, id: \.self) { _ in
                VStack(spacing: 0) {
                    // Linha discreta para hora cheia
                    Rectangle()
                        .fill(Color.gray.opacity(0.3))
                        .frame(height: 0.5)
                    Spacer()
                }
                .frame(height: CalendarConstants.weekHourHeight)
            }
        }
    }
}

/// Indicador de hora atual para vista semanal
struct WeekCurrentTimeIndicator: View {
    @State private var currentTime = Date()
    let timer = Timer.publish(every: 60, on: .main, in: .common).autoconnect()

    var isToday: Bool

    var body: some View {
        if isToday && isWithinWorkingHours {
            HStack(spacing: 0) {
                Circle()
                    .fill(Color.red)
                    .frame(width: 10, height: 10)

                Rectangle()
                    .fill(Color.red)
                    .frame(height: 2)
            }
            .offset(y: yOffset - 5)
            .onReceive(timer) { _ in
                currentTime = Date()
            }
        }
    }

    private var isWithinWorkingHours: Bool {
        let hour = Calendar.current.component(.hour, from: currentTime)
        return hour >= CalendarConstants.startHour && hour < CalendarConstants.endHour
    }

    private var yOffset: CGFloat {
        CalendarConstants.weekYPosition(for: currentTime)
    }
}



/// Indicador de hora atual (linha vermelha)
struct CurrentTimeIndicator: View {
    @State private var currentTime = Date()
    let timer = Timer.publish(every: 60, on: .main, in: .common).autoconnect()

    var isToday: Bool

    var body: some View {
        if isToday && isWithinWorkingHours {
            GeometryReader { _ in
                HStack(spacing: 0) {
                    // Círculo vermelho
                    Circle()
                        .fill(Color.red)
                        .frame(width: 8, height: 8)

                    // Linha vermelha
                    Rectangle()
                        .fill(Color.red)
                        .frame(height: 1)
                }
                .offset(y: yOffset)
            }
            .onReceive(timer) { _ in
                currentTime = Date()
            }
        }
    }

    private var isWithinWorkingHours: Bool {
        let hour = Calendar.current.component(.hour, from: currentTime)
        return hour >= CalendarConstants.startHour && hour < CalendarConstants.endHour
    }

    private var yOffset: CGFloat {
        CalendarConstants.yPosition(for: currentTime) - 4 // -4 para centralizar o círculo
    }
}

#Preview {
    HStack(spacing: 0) {
        CalendarTimeColumn()
            .frame(width: CalendarConstants.timeColumnWidth)

        ZStack(alignment: .topLeading) {
            CalendarHourLines()
            CurrentTimeIndicator(isToday: true)
        }
    }
    .frame(height: CalendarConstants.totalGridHeight)
}
