import Foundation

// Protocolo para compatibilidade entre Appointment e WidgetAppointment
protocol AppointmentConvertible {
    var id: String { get }
    var patientName: String? { get }
    var procedure: String? { get }
    var start: Date { get }
    var end: Date { get }
    var isPersonal: Bool? { get }
    var title: String? { get }
}

/// Modelo simplificado de agendamento para widgets
/// Codable para serialização JSON e compartilhamento via App Group
struct WidgetAppointment: Codable, Identifiable {
    let id: String
    let patientName: String
    let procedure: String
    let start: Date
    let end: Date
    let status: String
    let isPersonal: Bool
    let title: String?

    var displayTitle: String {
        if isPersonal {
            return title ?? "Compromisso Pessoal"
        }
        return patientName
    }

    var timeRange: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        formatter.locale = Locale(identifier: "pt_BR")
        formatter.timeZone = TimeZone(identifier: "America/Sao_Paulo")
        return formatter.string(from: start)
    }

    var timeUntil: String {
        let now = Date()
        let interval = start.timeIntervalSince(now)

        if interval < 0 {
            return "Agora"
        }

        let hours = Int(interval / 3600)
        let minutes = Int((interval.truncatingRemainder(dividingBy: 3600)) / 60)

        if hours > 24 {
            let days = hours / 24
            return "Em \(days)d"
        } else if hours > 0 {
            return "Em \(hours)h"
        } else if minutes > 0 {
            return "Em \(minutes)min"
        } else {
            return "Agora"
        }
    }

    /// Duração formatada
    var duration: String {
        let interval = end.timeIntervalSince(start)
        let minutes = Int(interval / 60)

        if minutes >= 60 {
            let hours = minutes / 60
            let remainingMinutes = minutes % 60
            if remainingMinutes == 0 {
                return "\(hours)h"
            }
            return "\(hours)h \(remainingMinutes)min"
        }
        return "\(minutes)min"
    }

    /// Verifica se o agendamento já passou
    var isPast: Bool {
        return end < Date()
    }

    /// Verifica se o agendamento está acontecendo agora
    var isNow: Bool {
        let now = Date()
        return start <= now && end > now
    }

    /// Verifica se é hoje
    var isToday: Bool {
        let calendar = Calendar.current
        return calendar.isDateInToday(start)
    }
}

/// Dados completos para o widget
struct WidgetData: Codable {
    let appointments: [WidgetAppointment]
    let lastUpdate: Date

    /// Próximo agendamento futuro
    var nextAppointment: WidgetAppointment? {
        let now = Date()
        return appointments.first { $0.start >= now }
    }

    /// Agendamentos de hoje
    var todayAppointments: [WidgetAppointment] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: today)!

        return appointments.filter { appointment in
            appointment.start >= today && appointment.start < tomorrow
        }
    }

    /// Próximos 3 agendamentos
    var nextThree: [WidgetAppointment] {
        let now = Date()
        return appointments
            .filter { $0.start >= now }
            .prefix(3)
            .map { $0 }
    }
}
