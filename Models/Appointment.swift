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
    var professionalId: String?  // ID do profissional para filtros precisos
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
        case professional
        case professionalId = "professional_id"
        case room, start, end, notes, status
        case isPersonal = "is_personal"
        case title
    }

    // Memberwise initializer
    init(
        id: String,
        createdAt: Date,
        updatedAt: Date,
        userId: String,
        patientId: String? = nil,
        patientName: String? = nil,
        procedure: String? = nil,
        procedureId: String? = nil,
        selectedProducts: String? = nil,
        professional: String,
        professionalId: String? = nil,
        room: String? = nil,
        start: Date,
        end: Date,
        notes: String? = nil,
        status: AppointmentStatus,
        isPersonal: Bool? = nil,
        title: String? = nil
    ) {
        self.id = id
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.userId = userId
        self.patientId = patientId
        self.patientName = patientName
        self.procedure = procedure
        self.procedureId = procedureId
        self.selectedProducts = selectedProducts
        self.professional = professional
        self.professionalId = professionalId
        self.room = room
        self.start = start
        self.end = end
        self.notes = notes
        self.status = status
        self.isPersonal = isPersonal
        self.title = title
    }

    // Custom decoder to handle selected_products as both String and Array
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        id = try container.decode(String.self, forKey: .id)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        updatedAt = try container.decode(Date.self, forKey: .updatedAt)
        userId = try container.decode(String.self, forKey: .userId)
        patientId = try container.decodeIfPresent(String.self, forKey: .patientId)
        patientName = try container.decodeIfPresent(String.self, forKey: .patientName)
        procedure = try container.decodeIfPresent(String.self, forKey: .procedure)
        procedureId = try container.decodeIfPresent(String.self, forKey: .procedureId)

        // Handle selected_products as String or Array
        if let productsString = try? container.decodeIfPresent(String.self, forKey: .selectedProducts) {
            selectedProducts = productsString
        } else if let productsArray = try? container.decodeIfPresent([String].self, forKey: .selectedProducts) {
            // Convert array to JSON string
            if let jsonData = try? JSONEncoder().encode(productsArray),
               let jsonString = String(data: jsonData, encoding: .utf8) {
                selectedProducts = jsonString
            } else {
                selectedProducts = nil
            }
        } else {
            selectedProducts = nil
        }

        professional = try container.decode(String.self, forKey: .professional)
        professionalId = try container.decodeIfPresent(String.self, forKey: .professionalId)
        room = try container.decodeIfPresent(String.self, forKey: .room)
        start = try container.decode(Date.self, forKey: .start)
        end = try container.decode(Date.self, forKey: .end)
        notes = try container.decodeIfPresent(String.self, forKey: .notes)
        status = try container.decode(AppointmentStatus.self, forKey: .status)
        isPersonal = try container.decodeIfPresent(Bool.self, forKey: .isPersonal)
        title = try container.decodeIfPresent(String.self, forKey: .title)
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
        var professionalId: String?  // ID do profissional
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
            case professional
            case professionalId = "professional_id"
            case room, start, end, notes, status
            case isPersonal = "is_personal"
            case title
        }
    }

    // Duração em minutos
    var durationMinutes: Int {
        let interval = end.timeIntervalSince(start)
        return Int(interval / 60)
    }

    // Horário formatado (início - fim)
    var timeRange: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return "\(formatter.string(from: start)) - \(formatter.string(from: end))"
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
