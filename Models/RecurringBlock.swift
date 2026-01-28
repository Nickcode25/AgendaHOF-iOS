import Foundation

struct RecurringBlock: Identifiable, Codable, Hashable {
    let id: String
    let createdAt: Date
    var updatedAt: Date?
    let userId: String
    var title: String
    var startTime: String // HH:mm:ss
    var endTime: String   // HH:mm:ss
    var daysOfWeek: [Int] // 0=Dom, 1=Seg, ..., 6=Sáb
    var active: Bool
    var notes: String?
    var professional: String?
    var professionalId: String?

    enum CodingKeys: String, CodingKey {
        case id
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case userId = "user_id"
        case title
        case startTime = "start_time"
        case endTime = "end_time"
        case daysOfWeek = "days_of_week"
        case active, notes, professional
        case professionalId = "professional_id"
    }

    // Para criar novo bloqueio
    struct Insert: Codable {
        let userId: String
        var title: String
        var startTime: String
        var endTime: String
        var daysOfWeek: [Int]
        var active: Bool = true
        var notes: String?
        var professional: String?
        var professionalId: String?

        enum CodingKeys: String, CodingKey {
            case userId = "user_id"
            case title
            case startTime = "start_time"
            case endTime = "end_time"
            case daysOfWeek = "days_of_week"
            case active, notes, professional
            case professionalId = "professional_id"
        }
    }

    // Dias da semana formatados
    var daysFormatted: String {
        let dayNames = ["Dom", "Seg", "Ter", "Qua", "Qui", "Sex", "Sáb"]
        return daysOfWeek.sorted().map { dayNames[$0] }.joined(separator: ", ")
    }

    // Horário formatado (apenas hora de início)
    var timeRange: String {
        let start = String(startTime.prefix(5)) // Remove segundos
        return start
    }

    // Verifica se aplica a um dia específico
    func appliesTo(dayOfWeek: Int) -> Bool {
        daysOfWeek.contains(dayOfWeek)
    }

    // Verifica se aplica a uma data específica
    func appliesTo(date: Date) -> Bool {
        let calendar = Calendar.current
        let weekday = calendar.component(.weekday, from: date)
        // Calendar weekday: 1=Dom, 2=Seg, ..., 7=Sáb
        // Nossa convenção: 0=Dom, 1=Seg, ..., 6=Sáb
        let adjustedWeekday = weekday - 1
        return daysOfWeek.contains(adjustedWeekday)
    }
}

// Para atualizar bloqueio existente
struct RecurringBlockUpdate: Codable {
    var title: String
    var startTime: String
    var endTime: String
    var daysOfWeek: [Int]
    var active: Bool
    var professional: String?
    var professionalId: String?

    enum CodingKeys: String, CodingKey {
        case title
        case startTime = "start_time"
        case endTime = "end_time"
        case daysOfWeek = "days_of_week"
        case active, professional
        case professionalId = "professional_id"
    }
}

// MARK: - Use Case: Exceptions
struct RecurringBlockException: Identifiable, Codable, Hashable {
    let id: String
    let recurringBlockId: String
    let originalDate: String // YYYY-MM-DD
    let newStartTime: String?
    let newEndTime: String?
    let isExcluded: Bool

    enum CodingKeys: String, CodingKey {
        case id
        case recurringBlockId = "recurring_block_id"
        case originalDate = "original_date"
        case newStartTime = "new_start_time"
        case newEndTime = "new_end_time"
        case isExcluded = "is_excluded"
    }
}

// Enum para dias da semana
enum DayOfWeek: Int, CaseIterable {
    case sunday = 0
    case monday = 1
    case tuesday = 2
    case wednesday = 3
    case thursday = 4
    case friday = 5
    case saturday = 6

    var shortName: String {
        switch self {
        case .sunday: return "Dom"
        case .monday: return "Seg"
        case .tuesday: return "Ter"
        case .wednesday: return "Qua"
        case .thursday: return "Qui"
        case .friday: return "Sex"
        case .saturday: return "Sáb"
        }
    }

    var fullName: String {
        switch self {
        case .sunday: return "Domingo"
        case .monday: return "Segunda"
        case .tuesday: return "Terça"
        case .wednesday: return "Quarta"
        case .thursday: return "Quinta"
        case .friday: return "Sexta"
        case .saturday: return "Sábado"
        }
    }
}
