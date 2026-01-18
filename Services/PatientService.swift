import Foundation

@MainActor
class PatientService: ObservableObject {
    private let supabase = SupabaseManager.shared

    @Published var patients: [Patient] = []
    @Published var isLoading = false
    @Published var error: String?

    // MARK: - Fetch All

    func fetchPatients() async {
        guard let userId = supabase.effectiveUserId else {
            error = "Usuário não autenticado"
            return
        }

        isLoading = true
        error = nil

        do {
            let result: [Patient] = try await supabase.client
                .from("patients")
                .select("*, planned_procedures")
                .eq("user_id", value: userId)
                .eq("is_active", value: true)
                .order("name", ascending: true)
                .execute()
                .value

            patients = result
        } catch {
            self.error = error.localizedDescription
            print("Erro ao buscar pacientes: \(error)")
        }

        isLoading = false
    }

    // MARK: - Fetch One

    func fetchPatient(id: String) async -> Patient? {
        do {
            let patient: Patient = try await supabase.client
                .from("patients")
                .select("*, planned_procedures")
                .eq("id", value: id)
                .single()
                .execute()
                .value

            return patient
        } catch {
            print("Erro ao buscar paciente: \(error)")
            return nil
        }
    }

    // MARK: - Search

    func searchPatients(query: String) async -> [Patient] {
        guard let userId = supabase.effectiveUserId else { return [] }

        do {
            let result: [Patient] = try await supabase.client
                .from("patients")
                .select("*, planned_procedures")
                .eq("user_id", value: userId)
                .eq("is_active", value: true)
                .ilike("name", pattern: "%\(query)%")
                .order("name", ascending: true)
                .limit(20)
                .execute()
                .value

            return result
        } catch {
            print("Erro na busca: \(error)")
            return []
        }
    }

    // MARK: - Create

    func createPatient(_ patient: Patient.Insert) async throws -> Patient {
        let result: Patient = try await supabase.client
            .from("patients")
            .insert(patient)
            .select()
            .single()
            .execute()
            .value

        // Atualizar lista local
        await fetchPatients()

        return result
    }

    // MARK: - Update

    func updatePatient(id: String, updates: [String: AnyEncodable]) async throws {
        try await supabase.client
            .from("patients")
            .update(updates)
            .eq("id", value: id)
            .execute()

        // Atualizar lista local
        await fetchPatients()
        
        // ✅ Reagendar notificação financeira para refletir procedimentos concluídos
        Task { await NotificationManager.shared.scheduleDailyFinancialSummary() }
    }

    // MARK: - Delete (Soft)

    func deletePatient(id: String) async throws {
        try await supabase.client
            .from("patients")
            .update(["is_active": AnyEncodable(false)])
            .eq("id", value: id)
            .execute()

        // Atualizar lista local
        await fetchPatients()
    }
}

// Helper para codificar valores dinâmicos
struct AnyEncodable: Encodable {
    let value: Any

    init(_ value: Any) {
        self.value = value
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()

        switch value {
        case let bool as Bool:
            try container.encode(bool)
        case let int as Int:
            try container.encode(int)
        case let double as Double:
            try container.encode(double)
        case let string as String:
            try container.encode(string)
        case let date as Date:
            try container.encode(date)
        case let array as [Any]:
            let encodableArray = array.map { AnyEncodable($0) }
            try container.encode(encodableArray)
        case let dict as [String: Any]:
            let encodableDict = dict.mapValues { AnyEncodable($0) }
            try container.encode(encodableDict)
        case is NSNull:
            try container.encodeNil()
        default:
            try container.encodeNil()
        }
    }
}
