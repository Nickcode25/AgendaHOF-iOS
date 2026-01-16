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
        // Graceful handling: se URL inválida, não crashar o app
        // Em vez disso, criar client com URL placeholder que falhará nas requisições
        // mas permitirá que o app abra e mostre erro tratável ao usuário
        let url: URL
        if let validURL = URL(string: Constants.supabaseURL) {
            url = validURL
        } else {
            AppLogger.error("❌ CRITICAL: Invalid Supabase URL in Constants. Check your configuration.")
            // URL placeholder - requisições falharão com erro tratável, não crash
            url = URL(string: "https://invalid.supabase.co")!
        }
        
        client = SupabaseClient(
            supabaseURL: url,
            supabaseKey: Constants.supabaseAnonKey,
            options: SupabaseClientOptions(
                auth: .init(
                    flowType: .pkce,
                    autoRefreshToken: true,
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
        
        // Carregar perfil primeiro
        await loadUserProfile()
        
        // Verificar acesso via SubscriptionManager
        await SubscriptionManager.shared.checkAccess()
        
        // Permitir acesso apenas se tiver assinatura ou trial
        let accessState = SubscriptionManager.shared.accessState
        if accessState.hasActiveSubscription || accessState.isInTrial {
            self.isAuthenticated = true
            AppLogger.log("✅ [Auth] Login bem-sucedido. Plano: \(accessState.planType.displayName)", category: .auth)
        } else {
            // Fazer logout se não tiver acesso
            self.currentSession = nil
            self.currentUser = nil
            self.userProfile = nil
            self.isAuthenticated = false
            AppLogger.log("🚫 [Auth] Login negado. Sem plano ativo.", category: .auth)
            throw NSError(domain: "AgendaHOF", code: 403, userInfo: [
                NSLocalizedDescriptionKey: "Esta conta não possui uma assinatura vigente. Por favor, acesse o site agendahof.com para gerenciar seu plano e reativar suas funcionalidades."
            ])
        }
    }

    func signUp(email: String, password: String, name: String, professionalName: String?, phone: String, trialEndDate: String) async throws {
        isLoading = true
        defer { isLoading = false }

        // 1. Criar usuário no Supabase Auth com Metadados
        // O Trigger 'handle_new_user' no banco de dados irá ler estes metadados
        // e criar o registro na tabela user_profiles automaticamente.
        
        // Monta os metadados (professionalName é opcional)
        var metadata: [String: AnyJSON] = [
            "full_name": AnyJSON.string(name),
            "phone": AnyJSON.string(phone),
            "trial_end_date": AnyJSON.string(trialEndDate)
        ]
        
        // Adiciona professional_name apenas se foi preenchido
        if let profName = professionalName, !profName.isEmpty {
            metadata["professional_name"] = AnyJSON.string(profName)
        }
        
        let session = try await client.auth.signUp(
            email: email,
            password: password,
            data: metadata
        )

        self.currentSession = session.session
        self.currentUser = session.user
        self.isAuthenticated = session.session != nil

        // Aguardar um momento para o Trigger rodar e criar o perfil
        try? await Task.sleep(nanoseconds: 2 * 1_000_000_000) // Aumentado para 2 segundos
        
        // Tentar carregar o perfil criado pelo Trigger
        await loadUserProfile()
        
        // FALBACK: Se o trigger falhou ou demorou demais, criamos manualmente
        if self.userProfile == nil {
            AppLogger.log("⚠️ Aviso: Trigger demorou ou falhou. Criando perfil manualmente via App...", category: .auth)
            
            let userId = session.user.id
            
            // display_name: usa professional_name se existir, senão usa full_name
            let displayName = (professionalName != nil && !professionalName!.isEmpty) ? professionalName! : name
            
            do {
                var userProfile: [String: AnyJSON] = [
                    "id": AnyJSON.string(userId.uuidString),
                    "full_name": AnyJSON.string(name),
                    "display_name": AnyJSON.string(displayName),
                    "email": AnyJSON.string(email),
                    "phone": AnyJSON.string(phone),
                    "role": AnyJSON.string("owner"),
                    "clinic_id": AnyJSON.string(userId.uuidString),
                    "is_active": AnyJSON.bool(true)
                ]
                
                // Adiciona professional_name apenas se foi preenchido
                if let profName = professionalName, !profName.isEmpty {
                    userProfile["professional_name"] = AnyJSON.string(profName)
                }

                try await client
                    .from("user_profiles")
                    .insert(userProfile)
                    .execute()

                // Tentar carregar novamente
                await loadUserProfile()
                AppLogger.log("✅ Perfil criado manualmente com sucesso!", category: .auth)
            } catch {
                AppLogger.error("❌ Erro fatal ao criar perfil (Fallback): \(error)")
                // Se falhar o fallback, aí sim deslogamos
                try? await client.auth.signOut()
                self.currentSession = nil
                self.currentUser = nil
                self.isAuthenticated = false
                throw error
            }
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
            AppLogger.log("Nenhuma sessão ativa: \(error.localizedDescription)", category: .auth)
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
            AppLogger.error("Erro ao carregar perfil: \(error)")
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
