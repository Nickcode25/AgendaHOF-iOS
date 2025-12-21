import Foundation

struct Patient: Identifiable, Codable, Hashable {
    let id: String
    let createdAt: Date
    var updatedAt: Date
    let userId: String
    var name: String
    var cpf: String?
    var birthDate: Date?
    var phone: String?
    var email: String?
    var address: String?
    var photoUrl: String?
    var notes: String?
    var isActive: Bool
    var plannedProcedures: [PlannedProcedure]?
    var cep: String?
    var street: String?
    var number: String?
    var complement: String?
    var neighborhood: String?
    var city: String?
    var state: String?
    var clinicalInfo: String?

    enum CodingKeys: String, CodingKey {
        case id
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case userId = "user_id"
        case name, cpf
        case birthDate = "birth_date"
        case phone, email, address
        case photoUrl = "photo_url"
        case notes
        case isActive = "is_active"
        case plannedProcedures = "planned_procedures"
        case cep, street, number, complement, neighborhood, city, state
        case clinicalInfo = "clinical_info"
    }

    // Inicializador para uso em código/previews
    init(
        id: String,
        createdAt: Date,
        updatedAt: Date,
        userId: String,
        name: String,
        cpf: String? = nil,
        birthDate: Date? = nil,
        phone: String? = nil,
        email: String? = nil,
        address: String? = nil,
        photoUrl: String? = nil,
        notes: String? = nil,
        isActive: Bool,
        plannedProcedures: [PlannedProcedure]? = nil,
        cep: String? = nil,
        street: String? = nil,
        number: String? = nil,
        complement: String? = nil,
        neighborhood: String? = nil,
        city: String? = nil,
        state: String? = nil,
        clinicalInfo: String? = nil
    ) {
        self.id = id
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.userId = userId
        self.name = name
        self.cpf = cpf
        self.birthDate = birthDate
        self.phone = phone
        self.email = email
        self.address = address
        self.photoUrl = photoUrl
        self.notes = notes
        self.isActive = isActive
        self.plannedProcedures = plannedProcedures
        self.cep = cep
        self.street = street
        self.number = number
        self.complement = complement
        self.neighborhood = neighborhood
        self.city = city
        self.state = state
        self.clinicalInfo = clinicalInfo
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        id = try container.decode(String.self, forKey: .id)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        updatedAt = try container.decode(Date.self, forKey: .updatedAt)
        userId = try container.decode(String.self, forKey: .userId)
        name = try container.decode(String.self, forKey: .name)
        cpf = try container.decodeIfPresent(String.self, forKey: .cpf)

        // birth_date pode vir como Date ISO8601 ou como String "yyyy-MM-dd"
        if let dateValue = try? container.decodeIfPresent(Date.self, forKey: .birthDate) {
            birthDate = dateValue
        } else if let dateString = try? container.decodeIfPresent(String.self, forKey: .birthDate) {
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM-dd"
            birthDate = formatter.date(from: dateString)
        } else {
            birthDate = nil
        }

        phone = try container.decodeIfPresent(String.self, forKey: .phone)
        email = try container.decodeIfPresent(String.self, forKey: .email)
        address = try container.decodeIfPresent(String.self, forKey: .address)
        photoUrl = try container.decodeIfPresent(String.self, forKey: .photoUrl)
        notes = try container.decodeIfPresent(String.self, forKey: .notes)
        isActive = try container.decode(Bool.self, forKey: .isActive)
        cep = try container.decodeIfPresent(String.self, forKey: .cep)
        street = try container.decodeIfPresent(String.self, forKey: .street)
        number = try container.decodeIfPresent(String.self, forKey: .number)
        complement = try container.decodeIfPresent(String.self, forKey: .complement)
        neighborhood = try container.decodeIfPresent(String.self, forKey: .neighborhood)
        city = try container.decodeIfPresent(String.self, forKey: .city)
        state = try container.decodeIfPresent(String.self, forKey: .state)
        clinicalInfo = try container.decodeIfPresent(String.self, forKey: .clinicalInfo)

        // planned_procedures pode ser array, string JSON, ou null
        if let procedures = try? container.decodeIfPresent([PlannedProcedure].self, forKey: .plannedProcedures) {
            plannedProcedures = procedures
        } else if let jsonString = try? container.decodeIfPresent(String.self, forKey: .plannedProcedures),
                  let data = jsonString.data(using: .utf8) {
            // Tentar parsear string JSON
            let decoder = JSONDecoder()
            decoder.keyDecodingStrategy = .convertFromSnakeCase
            plannedProcedures = try? decoder.decode([PlannedProcedure].self, from: data)
        } else {
            plannedProcedures = nil
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encode(updatedAt, forKey: .updatedAt)
        try container.encode(userId, forKey: .userId)
        try container.encode(name, forKey: .name)
        try container.encodeIfPresent(cpf, forKey: .cpf)
        try container.encodeIfPresent(birthDate, forKey: .birthDate)
        try container.encodeIfPresent(phone, forKey: .phone)
        try container.encodeIfPresent(email, forKey: .email)
        try container.encodeIfPresent(address, forKey: .address)
        try container.encodeIfPresent(photoUrl, forKey: .photoUrl)
        try container.encodeIfPresent(notes, forKey: .notes)
        try container.encode(isActive, forKey: .isActive)
        try container.encodeIfPresent(plannedProcedures, forKey: .plannedProcedures)
        try container.encodeIfPresent(cep, forKey: .cep)
        try container.encodeIfPresent(street, forKey: .street)
        try container.encodeIfPresent(number, forKey: .number)
        try container.encodeIfPresent(complement, forKey: .complement)
        try container.encodeIfPresent(neighborhood, forKey: .neighborhood)
        try container.encodeIfPresent(city, forKey: .city)
        try container.encodeIfPresent(state, forKey: .state)
        try container.encodeIfPresent(clinicalInfo, forKey: .clinicalInfo)
    }

    // Para criar novo paciente
    struct Insert: Codable {
        let userId: String
        var name: String
        var cpf: String?
        var birthDate: Date?
        var phone: String?
        var email: String?
        var address: String?
        var photoUrl: String?
        var notes: String?
        var isActive: Bool = true
        var cep: String?
        var street: String?
        var number: String?
        var complement: String?
        var neighborhood: String?
        var city: String?
        var state: String?
        var clinicalInfo: String?

        enum CodingKeys: String, CodingKey {
            case userId = "user_id"
            case name, cpf
            case birthDate = "birth_date"
            case phone, email, address
            case photoUrl = "photo_url"
            case notes
            case isActive = "is_active"
            case cep, street, number, complement, neighborhood, city, state
            case clinicalInfo = "clinical_info"
        }
    }

    // Iniciais do nome para avatar
    var initials: String {
        let parts = name.split(separator: " ")
        if parts.count >= 2 {
            return "\(parts[0].prefix(1))\(parts[1].prefix(1))".uppercased()
        }
        return String(name.prefix(2)).uppercased()
    }

    // Idade calculada
    var age: Int? {
        guard let birthDate = birthDate else { return nil }
        let calendar = Calendar.current
        let ageComponents = calendar.dateComponents([.year], from: birthDate, to: Date())
        return ageComponents.year
    }

    // Endereço completo formatado
    var fullAddress: String? {
        var parts: [String] = []
        if let street = street { parts.append(street) }
        if let number = number { parts.append(number) }
        if let complement = complement { parts.append(complement) }
        if let neighborhood = neighborhood { parts.append(neighborhood) }
        if let city = city, let state = state {
            parts.append("\(city) - \(state)")
        }
        if let cep = cep { parts.append("CEP: \(cep)") }
        return parts.isEmpty ? nil : parts.joined(separator: ", ")
    }
}

// PlannedProcedure com campos flexíveis para aceitar diferentes formatos do banco
struct PlannedProcedure: Identifiable, Codable, Hashable {
    let id: String
    var procedureName: String?
    var quantity: Int?
    var unitValue: Double?
    var totalValue: Double?
    var status: String?
    var notes: String?
    var createdAt: String? // String para evitar problemas de parsing
    var completedAt: String?
    var performedAt: String?  // ✅ NOVO: Data de realização
    var paymentType: String?
    var paymentMethod: String?
    var installments: Int?
    var usedProductId: String?
    var usedProductName: String?
    var professionalId: String?  // ✅ NOVO: ID do profissional
    var professionalName: String?  // ✅ NOVO: Nome do profissional
    var paymentSplits: [PaymentSplitData]?  // ✅ NOVO: Divisões de pagamento

    // Campos alternativos que podem vir do banco
    var name: String?
    var procedure: String?
    var value: Double?

    enum CodingKeys: String, CodingKey {
        case id
        case procedureName
        case quantity
        case unitValue
        case totalValue
        case status, notes
        case createdAt
        case completedAt
        case performedAt
        case paymentType
        case paymentMethod
        case installments
        case usedProductId
        case usedProductName
        case professionalId
        case professionalName
        case paymentSplits
        case name, procedure, value
    }

    // Nome do procedimento (aceita diferentes campos)
    var displayName: String {
        procedureName ?? name ?? procedure ?? "Procedimento"
    }

    // Valor para exibição
    var displayValue: Double {
        totalValue ?? value ?? unitValue ?? 0
    }
}

// ✅ NOVO: Estrutura para divisões de pagamento
struct PaymentSplitData: Codable, Hashable {
    var method: String?  // "cash", "pix", "credit_card", "debit_card", "transfer", "check"
    var amount: Double?

    enum CodingKeys: String, CodingKey {
        case method
        case amount
    }
}
