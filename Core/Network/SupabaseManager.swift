import Foundation
import Supabase

@MainActor
class SupabaseManager: ObservableObject {
    static let shared = SupabaseManager()

    let client: SupabaseClient

    @Published var currentUser: User?
    @Published var currentSession: Session?
    @Published var userProfile: UserProfile?
    @Published var isAuthenticated = false
    @Published var isLoading = false

    private init() {
        client = SupabaseClient(
            supabaseURL: URL(string: Constants.supabaseURL)!,
            supabaseKey: Constants.supabaseAnonKey,
            options: SupabaseClientOptions(
                auth: .init(
                    flowType: .pkce,
                    emitLocalSessionAsInitialSession: true
                )
            )
        )

        // Observar mudanças de autenticação
        Task {
            for await (event, session) in client.auth.authStateChanges {
                switch event {
                case .signedIn:
                    self.currentSession = session
                    self.currentUser = session?.user
                    self.isAuthenticated = true
                    await loadUserProfile()
                case .signedOut:
                    self.currentSession = nil
                    self.currentUser = nil
                    self.userProfile = nil
                    self.isAuthenticated = false
                case .tokenRefreshed:
                    self.currentSession = session
                default:
                    break
                }
            }
        }
    }

    // MARK: - Auth Methods

    func signIn(email: String, password: String) async throws {
        isLoading = true
        defer { isLoading = false }

        let session = try await client.auth.signIn(
            email: email,
            password: password
        )

        self.currentSession = session
        self.currentUser = session.user
        self.isAuthenticated = true

        await loadUserProfile()
    }

    func signUp(email: String, password: String, name: String, phone: String) async throws {
        isLoading = true
        defer { isLoading = false }

        // 1. Criar usuário no Supabase Auth
        let session = try await client.auth.signUp(
            email: email,
            password: password,
            data: [
                "full_name": AnyJSON.string(name),
                "phone": AnyJSON.string(phone)
            ]
        )

        self.currentSession = session.session
        self.currentUser = session.user
        self.isAuthenticated = session.session != nil

        // 2. Criar perfil do usuário na tabela user_profiles
        let userId = session.user.id
        do {
            let userProfile: [String: AnyJSON] = [
                "id": AnyJSON.string(userId.uuidString),
                "full_name": AnyJSON.string(name),
                "phone": AnyJSON.string(phone),
                "role": AnyJSON.string("owner"),
                "is_active": AnyJSON.bool(true)
            ]

            try await client
                .from("user_profiles")
                .insert(userProfile)
                .execute()

            // Carregar o perfil criado
            await loadUserProfile()
        } catch {
            print("Erro ao criar perfil do usuário: \(error)")
            // Não falhar o signup se houver erro ao criar perfil
            // O perfil pode ser criado posteriormente
        }
    }

    func signOut() async throws {
        try await client.auth.signOut()
        self.currentSession = nil
        self.currentUser = nil
        self.userProfile = nil
        self.isAuthenticated = false
    }

    func checkSession() async {
        do {
            let session = try await client.auth.session
            self.currentSession = session
            self.currentUser = session.user
            self.isAuthenticated = true
            await loadUserProfile()
        } catch {
            self.isAuthenticated = false
            print("Nenhuma sessão ativa: \(error.localizedDescription)")
        }
    }

    func resetPassword(email: String) async throws {
        try await client.auth.resetPasswordForEmail(email)
    }

    // MARK: - User Profile

    private func loadUserProfile() async {
        guard let userId = currentUser?.id else { return }

        do {
            let profile: UserProfile = try await client
                .from("user_profiles")
                .select()
                .eq("id", value: userId.uuidString)
                .single()
                .execute()
                .value

            self.userProfile = profile
        } catch {
            print("Erro ao carregar perfil: \(error)")
        }
    }

    /// Recarrega o perfil do usuário (público para uso após edições)
    func fetchUserProfile() async {
        await loadUserProfile()
    }

    // MARK: - Effective User ID (para staff)

    var effectiveUserId: String? {
        if userProfile?.role == .staff {
            return userProfile?.parentUserId
        }
        return currentUser?.id.uuidString
    }

    var isOwner: Bool {
        userProfile?.role == .owner
    }

    var isStaff: Bool {
        userProfile?.role == .staff
    }
}

// MARK: - Auth Error Extension

extension Error {
    var authErrorMessage: String {
        let message = localizedDescription.lowercased()

        if message.contains("invalid login credentials") {
            return "Email ou senha incorretos"
        } else if message.contains("email not confirmed") {
            return "Email não confirmado. Verifique sua caixa de entrada."
        } else if message.contains("user already registered") {
            return "Este email já está cadastrado"
        } else if message.contains("network") || message.contains("connection") {
            return "Erro de conexão. Verifique sua internet."
        } else if message.contains("too many requests") {
            return "Muitas tentativas. Aguarde um momento."
        }

        return "Erro: \(localizedDescription)"
    }
}
