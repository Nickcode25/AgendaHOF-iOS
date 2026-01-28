import SwiftUI

// MARK: - Week Event Card View

/// Card de evento com posicionamento baseado em tempo para vista semanal
/// Altura proporcional à duração: 15min = 37.5pt, 30min = 75pt, 60min = 150pt
/// Suporta detecção de conflitos e posicionamento em colunas
struct WeekEventCardView: View {

    // MARK: - Properties

    let positioned: PositionedAppointment
    let availableWidth: CGFloat
    var isCompact: Bool = false
    var onTap: () -> Void

    // MARK: - Computed Properties

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

    // MARK: - Body

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
        .background(
            RoundedRectangle(cornerRadius: isCompact ? 2 : 4)
                .fill(Color(.systemGroupedBackground)) // Fundo sólido para esconder linhas
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

// MARK: - Preview

#Preview {
    // Criar appointment de exemplo
    let calendar = Calendar.current
    let now = Date()
    let start = calendar.date(bySettingHour: 10, minute: 0, second: 0, of: now)!
    let end = calendar.date(bySettingHour: 11, minute: 0, second: 0, of: now)!

    let appointment = Appointment(
        id: UUID().uuidString,
        createdAt: now,
        updatedAt: now,
        userId: UUID().uuidString,
        patientId: nil,
        patientName: "João Silva",
        procedure: "Consulta", // Note: param name is 'procedure', not 'procedureName' in init based on file view? Wait, let me double check Appointment.swift view again if needed. 
        // Checking Appointment.swift again from history: 
        // struct Appointment ... var procedure: String? ...
        // init(... procedure: String? = nil ...)
        // The old code had `procedureName: "Consulta"`.
        procedureId: nil,
        selectedProducts: nil,
        professional: "Dr. Teste",
        room: nil,
        start: start,
        end: end,
        notes: nil,
        status: .scheduled,
        isPersonal: false,
        title: nil
    )

    let positioned = PositionedAppointment(
        appointment: appointment,
        column: 0,
        totalColumns: 1
    )

    ZStack(alignment: .topLeading) {
        Color(.systemGroupedBackground)
            .ignoresSafeArea()

        VStack(spacing: 20) {
            Text("iPad (Regular)")
            WeekEventCardView(
                positioned: positioned,
                availableWidth: 100,
                isCompact: false,
                onTap: {}
            )

            Text("iPhone (Compact)")
            WeekEventCardView(
                positioned: positioned,
                availableWidth: 50,
                isCompact: true,
                onTap: {}
            )
        }
        .padding()
    }
}
