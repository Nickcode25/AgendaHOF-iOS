import Foundation

struct Procedure: Identifiable, Codable, Hashable {
    let id: String
    let createdAt: Date
    let userId: String
    var name: String
    var price: Double
    var durationMinutes: Int?  // Pode ser null no banco
    var description: String?
    var isActive: Bool

    enum CodingKeys: String, CodingKey {
        case id
        case createdAt = "created_at"
        case userId = "user_id"
        case name, price
        case durationMinutes = "duration_minutes"
        case description
        case isActive = "is_active"
    }

    // Para criar novo procedimento
    struct Insert: Codable {
        let userId: String
        var name: String
        var price: Double
        var durationMinutes: Int
        var description: String?
        var isActive: Bool = true

        enum CodingKeys: String, CodingKey {
            case userId = "user_id"
            case name, price
            case durationMinutes = "duration_minutes"
            case description
            case isActive = "is_active"
        }
    }

    // Preço formatado
    var priceFormatted: String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.locale = Locale(identifier: "pt_BR")
        return formatter.string(from: NSNumber(value: price)) ?? "R$ 0,00"
    }

    // Duração formatada
    var durationFormatted: String {
        guard let duration = durationMinutes else {
            return "Não definido"
        }
        if duration >= 60 {
            let hours = duration / 60
            let minutes = duration % 60
            if minutes == 0 {
                return "\(hours)h"
            }
            return "\(hours)h \(minutes)min"
        }
        return "\(duration) min"
    }
}
