import Foundation

/// Modelo para pacientes inativos (sem procedimentos há +6 meses)
struct InactivePatient: Identifiable {
    let id: String
    let name: String
    let phone: String?
    let lastProcedureDate: Date?
    let photoUrl: String?

    /// Dias desde o último procedimento
    var daysSinceLastProcedure: Int {
        guard let lastDate = lastProcedureDate else {
            return Int.max // Nunca fez procedimento
        }

        let calendar = Calendar.current
        let days = calendar.dateComponents([.day], from: lastDate, to: Date()).day ?? 0
        return days
    }

    /// Status formatado: "Inativo há X dias"
    var inactiveStatus: String {
        let days = daysSinceLastProcedure

        if days == Int.max {
            return "Nunca realizou procedimento"
        }

        if days < 30 {
            return "Inativo há \(days) dias"
        } else if days < 365 {
            let months = days / 30
            return "Inativo há \(months) \(months == 1 ? "mês" : "meses")"
        } else {
            let years = days / 365
            return "Inativo há \(years) \(years == 1 ? "ano" : "anos")"
        }
    }

    /// Data formatada: "dd/MM/yyyy"
    var lastProcedureDateFormatted: String {
        guard let date = lastProcedureDate else {
            return "Sem registro"
        }

        let formatter = DateFormatter()
        formatter.dateFormat = "dd/MM/yyyy"
        formatter.locale = Locale(identifier: "pt_BR")
        return formatter.string(from: date)
    }

    /// Iniciais do nome para avatar
    var initials: String {
        let parts = name.split(separator: " ")
        if parts.count >= 2 {
            return "\(parts[0].prefix(1))\(parts[1].prefix(1))".uppercased()
        }
        return String(name.prefix(2)).uppercased()
    }

    /// Converte Patient + última data de procedimento em InactivePatient
    static func from(patient: Patient, lastProcedureDate: Date?) -> InactivePatient {
        InactivePatient(
            id: patient.id,
            name: patient.name,
            phone: patient.phone,
            lastProcedureDate: lastProcedureDate,
            photoUrl: patient.photoUrl
        )
    }
}
