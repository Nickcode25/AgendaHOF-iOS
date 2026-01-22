import Foundation

struct UserProfile: Identifiable, Codable {
    let id: String
    var role: UserRole
    var clinicId: String?
    var parentUserId: String?
    var displayName: String?
    var fullName: String?
    var socialName: String?
    var username: String?
    var profilePhoto: String?
    var phone: String?
    var secondaryPhone: String?
    var isActive: Bool
    var isPremium: Bool  // Status de assinatura do backend (Stripe)
    let createdAt: Date
    var updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case id, role
        case clinicId = "clinic_id"
        case parentUserId = "parent_user_id"
        case displayName = "display_name"
        case fullName = "full_name"
        case socialName = "social_name"
        case username
        case profilePhoto = "profile_photo"
        case phone
        case secondaryPhone = "secondary_phone"
        case isActive = "is_active"
        case isPremium = "is_premium"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        id = try container.decode(String.self, forKey: .id)
        role = try container.decode(UserRole.self, forKey: .role)
        clinicId = try container.decodeIfPresent(String.self, forKey: .clinicId)
        parentUserId = try container.decodeIfPresent(String.self, forKey: .parentUserId)
        displayName = try container.decodeIfPresent(String.self, forKey: .displayName)
        fullName = try container.decodeIfPresent(String.self, forKey: .fullName)
        socialName = try container.decodeIfPresent(String.self, forKey: .socialName)
        username = try container.decodeIfPresent(String.self, forKey: .username)
        profilePhoto = try container.decodeIfPresent(String.self, forKey: .profilePhoto)
        secondaryPhone = try container.decodeIfPresent(String.self, forKey: .secondaryPhone)
        isActive = try container.decode(Bool.self, forKey: .isActive)
        isPremium = try container.decodeIfPresent(Bool.self, forKey: .isPremium) ?? false
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        updatedAt = try container.decode(Date.self, forKey: .updatedAt)

        // Phone pode ser string ou objeto JSON
        if let phoneString = try? container.decodeIfPresent(String.self, forKey: .phone) {
            phone = phoneString
        } else if let phoneDict = try? container.decodeIfPresent([String: String].self, forKey: .phone) {
            // Se for um dicionário, tentar extrair o número
            phone = phoneDict["number"] ?? phoneDict["phone"] ?? phoneDict.values.first
        } else {
            phone = nil
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(role, forKey: .role)
        try container.encodeIfPresent(clinicId, forKey: .clinicId)
        try container.encodeIfPresent(parentUserId, forKey: .parentUserId)
        try container.encodeIfPresent(displayName, forKey: .displayName)
        try container.encodeIfPresent(fullName, forKey: .fullName)
        try container.encodeIfPresent(socialName, forKey: .socialName)
        try container.encodeIfPresent(username, forKey: .username)
        try container.encodeIfPresent(profilePhoto, forKey: .profilePhoto)
        try container.encodeIfPresent(phone, forKey: .phone)
        try container.encodeIfPresent(secondaryPhone, forKey: .secondaryPhone)
        try container.encode(isActive, forKey: .isActive)
        try container.encode(isPremium, forKey: .isPremium)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encode(updatedAt, forKey: .updatedAt)
    }

    // Nome para exibição
    var nameForDisplay: String {
        displayName ?? fullName ?? socialName ?? username ?? "Usuário"
    }

    // Iniciais para avatar
    var initials: String {
        let name = nameForDisplay
        let parts = name.split(separator: " ")
        if parts.count >= 2 {
            return "\(parts[0].prefix(1))\(parts[1].prefix(1))".uppercased()
        }
        return String(name.prefix(2)).uppercased()
    }

    // É dono da clínica?
    var isOwner: Bool {
        role == .owner
    }

    // É funcionário?
    var isStaff: Bool {
        role == .staff
    }
}

enum UserRole: String, Codable {
    case owner
    case staff

    var displayName: String {
        switch self {
        case .owner: return "Proprietário"
        case .staff: return "Funcionário"
        }
    }
}
