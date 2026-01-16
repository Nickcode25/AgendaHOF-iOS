import SwiftUI
import WidgetKit

struct SmallWidgetView: View {
    let entry: AgendaWidgetEntry

    var body: some View {
        if let appointment = entry.nextAppointment {
            // Widget com próximo paciente - Design Premium Clean
            VStack(alignment: .leading, spacing: 0) {
                // Horário em destaque - TAMANHO CORRIGIDO
                Text(appointment.timeRange)
                    .font(.system(size: 32, weight: .bold))
                    .foregroundColor(Color(hex: "ff6b00"))
                    .minimumScaleFactor(0.8)
                    .lineLimit(1)
                    .padding(.bottom, 6)

                // Badge de tempo restante
                HStack(spacing: 4) {
                    Image(systemName: "clock.fill")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundColor(Color(hex: "ff6b00"))

                    Text(appointment.timeUntil)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(Color(hex: "ff6b00"))
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color(hex: "ff6b00").opacity(0.12))
                .cornerRadius(6)
                .padding(.bottom, 12)

                Spacer()

                // Nome do paciente
                Text(appointment.displayTitle)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(.primary)
                    .lineLimit(2)
                    .minimumScaleFactor(0.85)

                // Procedimento
                Text(appointment.procedure)
                    .font(.system(size: 12, weight: .regular))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                    .padding(.top, 2)
            }
            .padding(16)
            .containerBackground(for: .widget) {
                Color.white
            }
        } else {
            // Estado vazio - Minimalista e positivo
            VStack(spacing: 10) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 40, weight: .light))
                    .foregroundColor(Color(hex: "ff6b00").opacity(0.3))

                VStack(spacing: 4) {
                    Text("Sem agendamentos")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.primary)

                    Text("Aproveite o dia!")
                        .font(.system(size: 11, weight: .regular))
                        .foregroundColor(.secondary)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .containerBackground(for: .widget) {
                Color.white
            }
        }
    }
}
