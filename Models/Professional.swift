import Foundation

struct Professional: Identifiable, Codable, Hashable {
    let id: String
    let createdAt: Date
    let userId: String
    var name: String
    var specialty: String?
    var cro: String?
    var phone: String?
    var email: String?
    var photoUrl: String?
    var isActive: Bool

    enum CodingKeys: String, CodingKey {
        case id
        case createdAt = "created_at"
        case userId = "user_id"
        case name, specialty, cro, phone, email
        case photoUrl = "photo_url"
        case isActive = "is_active"
    }

    // Para criar novo profissional
    struct Insert: Codable {
        let userId: String
        var name: String
        var specialty: String?
        var cro: String?
        var phone: String?
        var email: String?
        var photoUrl: String?
        var isActive: Bool = true

        enum CodingKeys: String, CodingKey {
            case userId = "user_id"
            case name, specialty, cro, phone, email
            case photoUrl = "photo_url"
            case isActive = "is_active"
        }
    }

    // Iniciais para avatar
    var initials: String {
        let parts = name.split(separator: " ")
        if parts.count >= 2 {
            return "\(parts[0].prefix(1))\(parts[1].prefix(1))".uppercased()
        }
        return String(name.prefix(2)).uppercased()
    }
}
