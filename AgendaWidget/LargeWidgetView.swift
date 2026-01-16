import SwiftUI
import WidgetKit

// Widget Grande - Design Minimalista Clean v8 - FUNDO BRANCO SEMPRE
struct LargeWidgetView: View {
    let entry: AgendaWidgetEntry

    var todayDate: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE, d 'de' MMMM"
        formatter.locale = Locale(identifier: "pt_BR")
        return formatter.string(from: Date()).capitalized
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header Premium - Agenda de Hoje
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 10) {
                    Image(systemName: "calendar")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(Color(hex: "ff6b00"))

                    Text("Agenda de Hoje")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundColor(.primary)

                    Spacer()

                    // Contador de eventos - Badge elegante
                    ZStack {
                        Circle()
                            .fill(Color(hex: "ff6b00"))
                            .frame(width: 32, height: 32)

                        Text("\(entry.todayAppointments.count)")
                            .font(.system(size: 15, weight: .bold))
                            .foregroundColor(.white)
                    }
                }

                Text(todayDate)
                    .font(.system(size: 13, weight: .regular))
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 18)
            .padding(.top, 16)
            .padding(.bottom, 14)

            // Divider principal
            Rectangle()
                .fill(Color.gray.opacity(0.15))
                .frame(height: 0.5)
                .padding(.horizontal, 18)

            if !entry.todayAppointments.isEmpty {
                // Lista de agendamentos do dia
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: 0) {
                        ForEach(Array(entry.todayAppointments.enumerated()), id: \.element.id) { index, event in
                            HStack(alignment: .top, spacing: 14) {
                                // Horário - Destaque laranja
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(event.timeRange)
                                        .font(.system(size: 18, weight: .bold))
                                        .foregroundColor(Color(hex: "ff6b00"))

                                    // Badge "Agora" se for o próximo
                                    if event.id == entry.nextAppointment?.id && event.start <= Date() {
                                        Text("Agora")
                                            .font(.system(size: 9, weight: .bold))
                                            .foregroundColor(.white)
                                            .padding(.horizontal, 6)
                                            .padding(.vertical, 3)
                                            .background(Color(hex: "ff6b00"))
                                            .cornerRadius(4)
                                    }
                                }
                                .frame(width: 60, alignment: .leading)

                                // Detalhes do evento - SEMPRE CLEAN
                                VStack(alignment: .leading, spacing: 4) {
                                    // Título (Paciente ou título do compromisso)
                                    Text(event.displayTitle)
                                        .font(.system(size: 14, weight: .semibold))
                                        .foregroundColor(.primary)
                                        .lineLimit(1)

                                    // Procedimento ou categoria
                                    Text(event.procedure)
                                        .font(.system(size: 13, weight: .regular))
                                        .foregroundColor(.secondary)
                                        .lineLimit(1)
                                }

                                Spacer()

                                // Indicador de tempo - apenas se for futuro
                                if event.start > Date() {
                                    Text(event.timeUntil)
                                        .font(.system(size: 11, weight: .medium))
                                        .foregroundColor(.secondary)
                                }
                            }
                            .padding(.horizontal, 18)
                            .padding(.vertical, 14)

                            // Divider entre itens
                            if index < entry.todayAppointments.count - 1 {
                                Rectangle()
                                    .fill(Color.gray.opacity(0.08))
                                    .frame(height: 0.5)
                                    .padding(.leading, 92)
                            }
                        }
                    }
                    .padding(.top, 6)
                }
            } else {
                // Estado vazio elegante
                Spacer()

                VStack(spacing: 14) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 44, weight: .light))
                        .foregroundColor(Color(hex: "ff6b00").opacity(0.3))

                    VStack(spacing: 6) {
                        Text("Nenhum agendamento hoje")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(.primary)

                        Text("Aproveite o dia livre!")
                            .font(.system(size: 13, weight: .regular))
                            .foregroundColor(.secondary)
                    }
                }
                .frame(maxWidth: .infinity)

                Spacer()
            }
        }
        .containerBackground(for: .widget) {
            Color.white
        }
    }
}
