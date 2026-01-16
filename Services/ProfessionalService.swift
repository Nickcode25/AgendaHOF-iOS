import Foundation

@MainActor
class ProfessionalService: ObservableObject {
    private let supabase = SupabaseManager.shared

    @Published var professionals: [Professional] = []
    @Published var isLoading = false
    @Published var error: String?

    // MARK: - Fetch All

    func fetchProfessionals() async {
        guard let userId = supabase.effectiveUserId else {
            error = "Usuário não autenticado"
            return
        }

        isLoading = true
        error = nil

        do {
            let result: [Professional] = try await supabase.client
                .from("professionals")
                .select()
                .eq("user_id", value: userId)
                .eq("is_active", value: true)
                .order("name", ascending: true)
                .execute()
                .value

            professionals = result
        } catch {
            self.error = error.localizedDescription
            print("Erro ao buscar profissionais: \(error)")
        }

        isLoading = false
    }

    // MARK: - Create

    func createProfessional(_ professional: Professional.Insert) async throws -> Professional {
        let result: Professional = try await supabase.client
            .from("professionals")
            .insert(professional)
            .select()
            .single()
            .execute()
            .value

        await fetchProfessionals()
        return result
    }

    // MARK: - Update

    func updateProfessional(id: String, updates: [String: AnyEncodable]) async throws {
        try await supabase.client
            .from("professionals")
            .update(updates)
            .eq("id", value: id)
            .execute()

        await fetchProfessionals()
    }

    // MARK: - Delete (Soft)

    func deleteProfessional(id: String) async throws {
        try await supabase.client
            .from("professionals")
            .update(["is_active": AnyEncodable(false)])
            .eq("id", value: id)
            .execute()

        await fetchProfessionals()
    }
}
