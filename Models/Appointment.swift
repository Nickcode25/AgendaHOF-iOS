import Foundation

struct Appointment: Identifiable, Codable, Hashable {
    let id: String
    let createdAt: Date
    var updatedAt: Date
    let userId: String
    var patientId: String?  // Pode ser null para compromissos pessoais
    var patientName: String?  // Pode ser null
    var procedure: String?  // Pode ser null para compromissos pessoais
    var procedureId: String?
    var selectedProducts: String?
    var professional: String
    var room: String?
    var start: Date
    var end: Date
    var notes: String?
    var status: AppointmentStatus
    var isPersonal: Bool?
    var title: String?

    enum CodingKeys: String, CodingKey {
        case id
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case userId = "user_id"
        case patientId = "patient_id"
        case patientName = "patient_name"
        case procedure
        case procedureId = "procedure_id"
        case selectedProducts = "selected_products"
        case professional, room, start, end, notes, status
        case isPersonal = "is_personal"
        case title
    }

    enum AppointmentStatus: String, Codable, CaseIterable {
        case scheduled
        case confirmed
        case completed
        case cancelled
        case done

        var displayName: String {
            switch self {
            case .scheduled: return "Agendado"
            case .confirmed: return "Confirmado"
            case .completed: return "Concluído"
            case .cancelled: return "Cancelado"
            case .done: return "Realizado"
            }
        }

        var color: String {
            switch self {
            case .scheduled: return "orange"
            case .confirmed: return "green"
            case .completed: return "purple"
            case .cancelled: return "red"
            case .done: return "gray"
            }
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.singleValueContainer()
            let value = try container.decode(String.self)
            self = AppointmentStatus(rawValue: value) ?? .scheduled
        }
    }

    // Para criar novo agendamento
    struct Insert: Codable {
        let userId: String
        var patientId: String?
        var patientName: String?
        var procedure: String?
        var procedureId: String?
        var selectedProducts: String?
        var professional: String
        var room: String?
        var start: Date
        var end: Date
        var notes: String?
        var status: AppointmentStatus = .scheduled
        var isPersonal: Bool?
        var title: String?

        enum CodingKeys: String, CodingKey {
            case userId = "user_id"
            case patientId = "patient_id"
            case patientName = "patient_name"
            case procedure
            case procedureId = "procedure_id"
            case selectedProducts = "selected_products"
            case professional, room, start, end, notes, status
            case isPersonal = "is_personal"
            case title
        }
    }

    // Duração em minutos
    var durationMinutes: Int {
        let interval = end.timeIntervalSince(start)
        return Int(interval / 60)
    }

    // Horário formatado (apenas hora de início)
    var timeRange: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: start)
    }

    // É compromisso pessoal?
    var isPersonalAppointment: Bool {
        isPersonal ?? false
    }

    // Título para exibição
    var displayTitle: String {
        if isPersonalAppointment {
            return title ?? "Compromisso Pessoal"
        }
        return patientName ?? "Sem paciente"
    }
}
