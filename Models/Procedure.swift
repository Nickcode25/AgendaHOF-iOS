import Foundation
import Supabase

struct Procedure: Identifiable, Codable, Hashable {
    let id: UUID
    let createdAt: Date
    let userId: UUID
    var name: String
    var description: String?
    var price: Double
    var cashValue: Double?
    var cardValue: Double?
    var durationMinutes: Int?
    var category: String?
    var isActive: Bool
    var stockCategories: [StockCategory]

    var enableReturnTracking: Bool?
    var returnIntervalValue: Int?
    var returnIntervalUnit: ProcedureReturnIntervalUnit?
    var returnAlertBeforeDays: Int?
    var returnMessageTemplate: String?

    enum CodingKeys: String, CodingKey {
        case id
        case createdAt = "created_at"
        case userId = "user_id"
        case name
        case description
        case price
        case cashValue = "cash_value"
        case cardValue = "card_value"
        case durationMinutes = "duration_minutes"
        case category
        case isActive = "is_active"
        case stockCategories = "stock_categories"
        case enableReturnTracking = "enable_return_tracking"
        case returnIntervalValue = "return_interval_value"
        case returnIntervalUnit = "return_interval_unit"
        case returnAlertBeforeDays = "return_alert_before_days"
        case returnMessageTemplate = "return_message_template"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        userId = try container.decode(UUID.self, forKey: .userId)
        name = try container.decode(String.self, forKey: .name)
        description = try container.decodeIfPresent(String.self, forKey: .description)
        price = try container.decode(Double.self, forKey: .price)
        cashValue = try container.decodeIfPresent(Double.self, forKey: .cashValue)
        cardValue = try container.decodeIfPresent(Double.self, forKey: .cardValue)
        durationMinutes = try container.decodeIfPresent(Int.self, forKey: .durationMinutes)
        category = try container.decodeIfPresent(String.self, forKey: .category)
        isActive = try container.decodeIfPresent(Bool.self, forKey: .isActive) ?? true
        stockCategories = (try? container.decode([StockCategory].self, forKey: .stockCategories)) ?? []
        enableReturnTracking = try container.decodeIfPresent(Bool.self, forKey: .enableReturnTracking)
        returnIntervalValue = try container.decodeIfPresent(Int.self, forKey: .returnIntervalValue)
        returnIntervalUnit = try container.decodeIfPresent(ProcedureReturnIntervalUnit.self, forKey: .returnIntervalUnit)
        returnAlertBeforeDays = try container.decodeIfPresent(Int.self, forKey: .returnAlertBeforeDays)
        returnMessageTemplate = try container.decodeIfPresent(String.self, forKey: .returnMessageTemplate)
    }

    var priceFormatted: String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.locale = Locale(identifier: "pt_BR")
        return formatter.string(from: NSNumber(value: price)) ?? "R$ 0,00"
    }

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

    var returnIntervalFormatted: String? {
        guard enableReturnTracking == true,
              let intervalValue = returnIntervalValue,
              intervalValue > 0,
              let intervalUnit = returnIntervalUnit else {
            return nil
        }

        let unitLabel: String
        switch intervalUnit {
        case .days:
            unitLabel = intervalValue == 1 ? "dia" : "dias"
        case .weeks:
            unitLabel = intervalValue == 1 ? "semana" : "semanas"
        case .months:
            unitLabel = intervalValue == 1 ? "mês" : "meses"
        }

        return "\(intervalValue) \(unitLabel)"
    }
}

struct StockCategory: Codable, Hashable, Sendable {
    var category: String
    var quantityUsed: Int
}

enum ProcedureReturnIntervalUnit: String, Codable, CaseIterable, Sendable {
    case days
    case weeks
    case months
}

struct ProcedureInsert: Codable, Hashable {
    var name: String
    var description: String?
    var price: Double
    var cashValue: Double?
    var cardValue: Double?
    var durationMinutes: Int?
    var category: String?
    var isActive: Bool = true
    var stockCategories: [StockCategory] = []
    var enableReturnTracking: Bool?
    var returnIntervalValue: Int?
    var returnIntervalUnit: ProcedureReturnIntervalUnit?
    var returnAlertBeforeDays: Int?
    var returnMessageTemplate: String?

    enum CodingKeys: String, CodingKey {
        case name
        case description
        case price
        case cashValue = "cash_value"
        case cardValue = "card_value"
        case durationMinutes = "duration_minutes"
        case category
        case isActive = "is_active"
        case stockCategories = "stock_categories"
        case enableReturnTracking = "enable_return_tracking"
        case returnIntervalValue = "return_interval_value"
        case returnIntervalUnit = "return_interval_unit"
        case returnAlertBeforeDays = "return_alert_before_days"
        case returnMessageTemplate = "return_message_template"
    }
}

struct ProcedureUpdate: Codable, Hashable {
    var name: String? = nil
    var description: String? = nil
    var price: Double? = nil
    var cashValue: Double? = nil
    var cardValue: Double? = nil
    var durationMinutes: Int? = nil
    var category: String? = nil
    var isActive: Bool? = nil
    var stockCategories: [StockCategory]? = nil
    var enableReturnTracking: Bool? = nil
    var returnIntervalValue: Int? = nil
    var returnIntervalUnit: ProcedureReturnIntervalUnit? = nil
    var returnAlertBeforeDays: Int? = nil
    var returnMessageTemplate: String? = nil

    enum CodingKeys: String, CodingKey {
        case name
        case description
        case price
        case cashValue = "cash_value"
        case cardValue = "card_value"
        case durationMinutes = "duration_minutes"
        case category
        case isActive = "is_active"
        case stockCategories = "stock_categories"
        case enableReturnTracking = "enable_return_tracking"
        case returnIntervalValue = "return_interval_value"
        case returnIntervalUnit = "return_interval_unit"
        case returnAlertBeforeDays = "return_alert_before_days"
        case returnMessageTemplate = "return_message_template"
    }

    var isEmpty: Bool {
        name == nil &&
        description == nil &&
        price == nil &&
        cashValue == nil &&
        cardValue == nil &&
        durationMinutes == nil &&
        category == nil &&
        isActive == nil &&
        stockCategories == nil &&
        enableReturnTracking == nil &&
        returnIntervalValue == nil &&
        returnIntervalUnit == nil &&
        returnAlertBeforeDays == nil &&
        returnMessageTemplate == nil
    }
}

extension Procedure {
    typealias Insert = ProcedureInsert
}

enum ProcedureServiceError: LocalizedError {
    case ownerIdNotInjected

    var errorDescription: String? {
        switch self {
        case .ownerIdNotInjected:
            return "Owner ID não foi injetado no ProcedureService."
        }
    }
}

@MainActor
final class ProcedureService {
    typealias OwnerIdProvider = () throws -> UUID

    private let supabase: SupabaseManager
    private let ownerIdProvider: OwnerIdProvider?

    init(
        supabase: SupabaseManager,
        ownerIdProvider: OwnerIdProvider? = nil
    ) {
        self.supabase = supabase
        self.ownerIdProvider = ownerIdProvider
    }

    func fetchProcedures(ownerId: UUID) async throws -> [Procedure] {
        try await supabase.client
            .from("procedures")
            .select()
            .eq("user_id", value: ownerId.uuidString)
            .eq("is_active", value: true)
            .order("name", ascending: true)
            .execute()
            .value
    }

    func fetchProcedures() async throws -> [Procedure] {
        try await fetchProcedures(ownerId: resolveOwnerId())
    }

    func createProcedure(procedure: ProcedureInsert) async throws -> Procedure {
        let ownerId = try resolveOwnerId()
        return try await createProcedure(procedure: procedure, ownerId: ownerId)
    }

    func createProcedure(procedure: ProcedureInsert, ownerId: UUID) async throws -> Procedure {
        let payload = ProcedureInsertPayload(ownerId: ownerId, procedure: procedure)

        return try await supabase.client
            .from("procedures")
            .insert(payload)
            .select()
            .single()
            .execute()
            .value
    }

    func updateProcedure(id: UUID, patch: ProcedureUpdate) async throws {
        guard !patch.isEmpty else { return }

        try await supabase.client
            .from("procedures")
            .update(patch)
            .eq("id", value: id.uuidString)
            .execute()
    }

    func deleteProcedure(id: UUID) async throws {
        try await supabase.client
            .from("procedures")
            .delete()
            .eq("id", value: id.uuidString)
            .execute()
    }

    func archiveProcedure(id: UUID) async throws {
        try await updateProcedure(id: id, patch: .init(isActive: false))
    }

    private func resolveOwnerId() throws -> UUID {
        guard let ownerIdProvider else {
            throw ProcedureServiceError.ownerIdNotInjected
        }
        return try ownerIdProvider()
    }

    private struct ProcedureInsertPayload: Codable {
        var userId: UUID
        var name: String
        var description: String?
        var price: Double
        var cashValue: Double?
        var cardValue: Double?
        var durationMinutes: Int?
        var category: String?
        var isActive: Bool
        var stockCategories: [StockCategory]
        var enableReturnTracking: Bool?
        var returnIntervalValue: Int?
        var returnIntervalUnit: ProcedureReturnIntervalUnit?
        var returnAlertBeforeDays: Int?
        var returnMessageTemplate: String?

        enum CodingKeys: String, CodingKey {
            case userId = "user_id"
            case name
            case description
            case price
            case cashValue = "cash_value"
            case cardValue = "card_value"
            case durationMinutes = "duration_minutes"
            case category
            case isActive = "is_active"
            case stockCategories = "stock_categories"
            case enableReturnTracking = "enable_return_tracking"
            case returnIntervalValue = "return_interval_value"
            case returnIntervalUnit = "return_interval_unit"
            case returnAlertBeforeDays = "return_alert_before_days"
            case returnMessageTemplate = "return_message_template"
        }

        init(ownerId: UUID, procedure: ProcedureInsert) {
            userId = ownerId
            name = procedure.name
            description = procedure.description
            price = procedure.price
            cashValue = procedure.cashValue
            cardValue = procedure.cardValue
            durationMinutes = procedure.durationMinutes
            category = procedure.category
            isActive = procedure.isActive
            stockCategories = procedure.stockCategories
            enableReturnTracking = procedure.enableReturnTracking
            returnIntervalValue = procedure.returnIntervalValue
            returnIntervalUnit = procedure.returnIntervalUnit
            returnAlertBeforeDays = procedure.returnAlertBeforeDays
            returnMessageTemplate = procedure.returnMessageTemplate
        }
    }
}
