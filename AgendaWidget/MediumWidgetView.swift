import SwiftUI
import WidgetKit

struct MediumWidgetView: View {
    let entry: AgendaWidgetEntry

    var nextThreeAppointments: [WidgetAppointment] {
        let now = Date()
        return entry.appointments
            .filter { $0.start >= now }
            .prefix(3)
            .map { $0 }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header - Estilo clean e minimalista
            HStack(spacing: 8) {
                Image(systemName: "calendar")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(Color(hex: "ff6b00"))

                Text("Próximos Agendamentos")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(.primary)

                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.top, 14)
            .padding(.bottom, 12)

            // Divider sutil
            Rectangle()
                .fill(Color.gray.opacity(0.15))
                .frame(height: 0.5)
                .padding(.horizontal, 16)

            if !nextThreeAppointments.isEmpty {
                // Lista de agendamentos - estilo minimalista
                VStack(spacing: 0) {
                    ForEach(Array(nextThreeAppointments.enumerated()), id: \.element.id) { index, appointment in
                        HStack(alignment: .top, spacing: 12) {
                            // Horário em destaque - Laranja Vibrante
                            Text(appointment.timeRange)
                                .font(.system(size: 17, weight: .bold))
                                .foregroundColor(Color(hex: "ff6b00"))
                                .frame(width: 55, alignment: .leading)

                            VStack(alignment: .leading, spacing: 3) {
                                // Nome do paciente/título
                                Text(appointment.displayTitle)
                                    .font(.system(size: 14, weight: .regular))
                                    .foregroundColor(.primary)
                                    .lineLimit(1)

                                // Procedimento/categoria
                                Text(appointment.procedure)
                                    .font(.system(size: 13, weight: .regular))
                                    .foregroundColor(.secondary)
                                    .lineLimit(1)
                            }

                            Spacer()

                            // Tempo restante - badge discreto
                            Text(appointment.timeUntil)
                                .font(.system(size: 11, weight: .medium))
                                .foregroundColor(.secondary)
                                .padding(.top, 2)
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)

                        // Divider entre itens (exceto o último)
                        if index < nextThreeAppointments.count - 1 {
                            Rectangle()
                                .fill(Color.gray.opacity(0.1))
                                .frame(height: 0.5)
                                .padding(.leading, 83)
                        }
                    }
                }
                .padding(.top, 4)
            } else {
                // Estado vazio - minimalista
                Spacer()
                VStack(spacing: 8) {
                    Image(systemName: "calendar.badge.checkmark")
                        .font(.system(size: 32, weight: .light))
                        .foregroundColor(Color(hex: "ff6b00").opacity(0.4))

                    Text("Nenhum agendamento próximo")
                        .font(.system(size: 14, weight: .regular))
                        .foregroundColor(.secondary)
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
