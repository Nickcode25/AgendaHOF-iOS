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
                    await loadUserProfile()
                    
                    // Não definir isAuthenticated = true aqui imediatamente.
                    // Deixar que signIn() ou checkSession() façam a verificação de acesso.
                    // Se definirmos true aqui, a UI pode transicionar antes da verificação de plano.
                    
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
        
        // ✅ MUDANÇA: Sempre permitir login, independentemente do plano
        // O paywall será exibido automaticamente dentro do app
        self.isAuthenticated = true
        
        // Verificar acesso via SubscriptionManager (para exibir paywall, não bloquear)
        await SubscriptionManager.shared.checkAccess()
        
        let accessState = SubscriptionManager.shared.accessState
        if accessState.hasAccess {
            AppLogger.log("✅ [Auth] Login bem-sucedido. Plano: \(accessState.planType.displayName) via \(accessState.source.displayName)", category: .auth)
        } else {
            AppLogger.log("✅ [Auth] Login bem-sucedido sem plano ativo. Paywall será exibido.", category: .auth)
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
            await loadUserProfile()
            
            // ✅ IMPORTANTE: Separar autenticação de acesso
            // A sessão do Supabase é válida = usuário está autenticado
            // A verificação de subscription é separada (feita no checkAccess)
            self.isAuthenticated = true
            
            // Verificar acesso via SubscriptionManager (para paywall, não logout)
            await SubscriptionManager.shared.checkAccess()
            
            let accessState = SubscriptionManager.shared.accessState
            if accessState.hasAccess {
                AppLogger.log("✅ [Auth] Sessão restaurada. Plano: \(accessState.planType.displayName) via \(accessState.source.displayName)", category: .auth)
            } else {
                // ✅ MUDANÇA: Não fazer logout, apenas logar
                // O app vai mostrar paywall em vez de deslogar
                AppLogger.log("⚠️ [Auth] Sessão válida mas sem subscription ativa. Paywall será exibido.", category: .auth)
            }
        } catch {
            // Verificar se é erro de autenticação real (401) ou apenas erro de rede
            let nsError = error as NSError
            let isAuthError = nsError.code == 401 || 
                              error.localizedDescription.lowercased().contains("unauthorized") ||
                              error.localizedDescription.lowercased().contains("jwt expired") ||
                              error.localizedDescription.lowercased().contains("invalid token")
            
            if isAuthError {
                // Erro de autenticação real - sessão inválida
                AppLogger.log("🚫 [Auth] Sessão inválida ou expirada: \(error.localizedDescription)", category: .auth)
                self.currentSession = nil
                self.currentUser = nil
                self.userProfile = nil
                self.isAuthenticated = false
            } else {
                // Erro de rede ou outro - manter sessão local
                AppLogger.log("⚠️ [Auth] Erro de rede ao verificar sessão (mantendo estado): \(error.localizedDescription)", category: .auth)
                
                // Se já temos uma sessão local, assumimos que ainda é válida
                if self.currentSession != nil {
                    self.isAuthenticated = true
                    AppLogger.log("✅ [Auth] Sessão local mantida (modo offline)", category: .auth)
                } else {
                    self.isAuthenticated = false
                }
            }
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
