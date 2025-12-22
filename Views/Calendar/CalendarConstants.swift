import SwiftUI

/// Constantes e configurações do calendário
enum CalendarConstants {
    // MARK: - Horários
    static let startHour = 7   // 07:00
    static let endHour = 24    // 24:00 (meia-noite)
    static let totalHours = endHour - startHour  // 17 horas
    static let totalMinutes = totalHours * 60    // 1020 minutos

    // MARK: - Dimensões Base (Vista Diária)
    /// Altura por hora na vista DIÁRIA (mais compacta)
    static let hourHeight: CGFloat = 60

    // MARK: - Nova Arquitetura Semanal (baseada em minutos)
    /// 🧠 REGRA DE OURO: tempo manda no layout
    /// 2.5pt por minuto = escala proporcional real (base, sem zoom)
    /// 15min = 37.5pt | 30min = 75pt | 60min = 150pt | 90min = 225pt
    static let baseMinuteHeight: CGFloat = 2.5

    /// Altura por minuto (para compatibilidade, usa valor base)
    static let minuteHeight: CGFloat = 2.5

    /// Altura por hora na vista semanal (derivada de minuteHeight)
    static var weekHourHeight: CGFloat {
        minuteHeight * 60  // 150pt por hora
    }

    static let timeColumnWidth: CGFloat = 50
    static let dayHeaderHeight: CGFloat = 60  // Altura do header dos dias (aumentada para acomodar o círculo)
    static let weekDayColumnWidth: CGFloat = 120  // Largura fixa para cada coluna de dia

    // MARK: - Helpers de Escala Semanal (baseados em minutos)

    /// Converte horário para minutos desde o início do dia de trabalho
    static func minutesFromStart(for date: Date) -> Int {
        let calendar = Calendar.current
        let hour = calendar.component(.hour, from: date)
        let minute = calendar.component(.minute, from: date)
        return (hour - startHour) * 60 + minute
    }

    /// Calcula a posição Y para vista semanal (baseado em minutos)
    static func weekYPosition(for date: Date) -> CGFloat {
        CGFloat(minutesFromStart(for: date)) * minuteHeight
    }

    /// Calcula a altura para vista semanal baseado na duração em minutos
    static func weekHeight(from start: Date, to end: Date) -> CGFloat {
        let durationMinutes = end.timeIntervalSince(start) / 60.0
        return CGFloat(durationMinutes) * minuteHeight
    }

    /// Altura total do grid semanal
    static var totalWeekGridHeight: CGFloat {
        CGFloat(totalMinutes) * minuteHeight  // 14h * 60min * 2.5pt = 2100pt
    }

    // MARK: - Cores por tipo de agendamento
    static func appointmentColor(for appointment: Appointment) -> Color {
        // Compromissos pessoais = AZUL
        if appointment.isPersonalAppointment {
            return .blue
        }

        // Agendamentos de pacientes - cor por status
        switch appointment.status {
        case .confirmed:
            return .green
        case .cancelled:
            return .red
        case .scheduled, .completed, .done:
            return .orange
        }
    }

    static func appointmentBackgroundColor(for appointment: Appointment) -> Color {
        appointmentColor(for: appointment).opacity(0.15)
    }

    // MARK: - Helpers de posicionamento

    /// Calcula a posição Y baseado na hora
    static func yPosition(for date: Date) -> CGFloat {
        let calendar = Calendar.current
        let hour = calendar.component(.hour, from: date)
        let minute = calendar.component(.minute, from: date)

        let hoursFromStart = CGFloat(hour - startHour)
        let minuteFraction = CGFloat(minute) / 60.0

        return (hoursFromStart + minuteFraction) * hourHeight
    }

    /// Calcula a altura baseado na duração
    static func height(from start: Date, to end: Date) -> CGFloat {
        let duration = end.timeIntervalSince(start)
        let hours = duration / 3600.0
        return CGFloat(hours) * hourHeight
    }

    /// Altura total do grid
    static var totalGridHeight: CGFloat {
        CGFloat(totalHours) * hourHeight
    }
}

// MARK: - Extensões de Data

extension Date {
    /// Hora formatada (HH:mm)
    var hourMinuteString: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: self)
    }

    /// Apenas hora (ex: "09")
    var hourString: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH"
        return formatter.string(from: self)
    }

    /// Dia da semana abreviado (ex: "Seg")
    var shortWeekdayName: String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "pt_BR")
        formatter.dateFormat = "EEE"
        return formatter.string(from: self).capitalized
    }

    /// Número do dia (ex: "15")
    var dayNumber: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "d"
        return formatter.string(from: self)
    }
}
