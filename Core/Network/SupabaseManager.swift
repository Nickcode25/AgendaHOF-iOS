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
    
    // MARK: - Auth Snapshot Helper
    func getAuthSnapshot(context: String = "") -> String {
        let hasSession = (currentSession != nil)
        let hasUser = (currentUser != nil)
        let isAuth = isAuthenticated
        let accessStatus = SubscriptionManager.shared.accessStatus.rawValue
        let hasEffectiveAccess = SubscriptionManager.shared.effectiveHasAccess
        
        let reason = SubscriptionManager.shared.accessState.backendReason ?? "nil"
        let status = SubscriptionManager.shared.accessState.backendStatus ?? "nil"
        let source = SubscriptionManager.shared.accessState.source.rawValue
        
        return "[Auth Snapshot] \(context) | hasSession:\(hasSession), hasUser:\(hasUser), isAuth:\(isAuth), access:\(accessStatus), effectiveAccess:\(hasEffectiveAccess) | reason:\(reason), status:\(status), source:\(source)"
    }
    
    private var userInitiatedSignOut = false
    private var isCheckingSessionNow = false
    
    // ✅ NOVO: Para evitar duplicidade com scenePhase.active no boot
    private(set) var lastInitialAuthDate: Date? = nil

    private init() {
        let url: URL
        if let validURL = URL(string: Constants.supabaseURL) {
            url = validURL
        } else {
            AppLogger.error("❌ CRITICAL: Invalid Supabase URL in Constants. Check your configuration.")
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

        // ✅ MUDANÇA CRÍTICA: Observer de auth apenas atualiza dados, NUNCA força logout
        Task {
            for await (event, session) in client.auth.authStateChanges {
                await handleAuthStateChange(event: event, session: session)
            }
        }
    }

    // ✅ NOVO: Método separado para tratar mudanças de autenticação
    private func handleAuthStateChange(event: AuthChangeEvent, session: Session?) async {
        AppLogger.log("🔔 [Auth] Auth state changed: \(event)", category: .auth)
        
        switch event {
        case .signedIn:
            // ✅ Atualizar sessão e usuário
            self.currentSession = session
            self.currentUser = session?.user
            
            // ✅ PERSISTÊNCIA: Cachear usuário para offline
            if let user = session?.user {
                saveUserToCache(user)
            }
            
            // ✅ Carregar perfil apenas se ainda não temos ou se mudou o usuário
            if self.userProfile == nil || self.userProfile?.id != session?.user.id.uuidString {
                await loadUserProfile()
            }
            
            // ✅ IMPORTANTE: Só marcar como autenticado se for login novo
            // Não sobrescrever se já estava autenticado (evita race condition)
            if !self.isAuthenticated {
                self.isAuthenticated = true
                AppLogger.log("✅ [Auth] Usuario autenticado via authStateChanges", category: .auth)
            }
            
        case .tokenRefreshed:
            // ✅ CRÍTICO: Apenas atualizar token, NUNCA alterar isAuthenticated
            self.currentSession = session
            AppLogger.log("🔄 [Auth] Token renovado automaticamente", category: .auth)
            // ❌ NÃO fazer logout ou alterar isAuthenticated aqui!
            
        case .signedOut:
            AppLogger.log("🚪 [Auth] SignedOut event recebido", category: .auth)
            AppLogger.log(getAuthSnapshot(context: "On SignedOut Event"), category: .auth)
            
            if userInitiatedSignOut {
                // logout explícito: limpa tudo
                self.currentSession = nil
                self.currentUser = nil
                self.userProfile = nil
                self.isAuthenticated = false
                return
            }
            
            // 🔥 Logout não iniciado pelo usuário:
            // tenta recuperar sessão silenciosamente para evitar "expulsão" por condição transitória.
            AppLogger.warning("⚠️ [Auth] SignedOut inesperado. Tentando recuperação silenciosa...")
            if await attemptSilentSessionRecoveryFromStoredCredentials(context: "authStateChanges.signedOut") {
                AppLogger.log("✅ [Auth] Sessão recuperada após signedOut inesperado.", category: .auth)
                return
            }
            
            AppLogger.error("❌ [Auth] Não foi possível recuperar sessão após signedOut inesperado. Finalizando logout.")
            await performSignOutDueToInvalidSession()
            
        case .initialSession:
            // ✅ Sessão inicial - apenas atualizar dados silenciosamente
            if let session = session {
                self.currentSession = session
                self.currentUser = session.user
                self.isAuthenticated = true
                self.lastInitialAuthDate = Date() // Marca o timestamp do boot
                await loadUserProfile()
                // AppLogger.log("🔵 [Auth] Sessão inicial carregada", category: .auth) // Removido por redundância
            }
            
        case .passwordRecovery, .userUpdated, .mfaChallengeVerified:
            // ✅ Eventos que não devem afetar autenticação
            if let session = session {
                self.currentSession = session
                self.currentUser = session.user
            }
            
        @unknown default:
            AppLogger.log("⚠️ [Auth] Evento desconhecido: \(event)", category: .auth)
        }
    }

    // MARK: - Auth Methods

    /// Sempre retorna um access token válido (refresca a sessão se precisar).
    /// Usa getSession() para evitar sessão stale após retornar do background.
    func validAccessToken() async throws -> String {
        let margin: TimeInterval = 60

        let session = try await safeSession(maxAttempts: 2)
        let expirationDate = Date(timeIntervalSince1970: session.expiresAt)

        if expirationDate.timeIntervalSinceNow < margin {
            AppLogger.log("🔄 [Auth] Token próximo de expirar. Renovando...", category: .auth)

            _ = try await client.auth.refreshSession()

            // pega a sessão novamente após refresh
            let refreshed = try await safeSession(maxAttempts: 2)
            return refreshed.accessToken
        }

        return session.accessToken
    }

    private func safeSession(maxAttempts: Int = 2) async throws -> Session {
        var lastError: Error?

        for attempt in 1...maxAttempts {
            do {
                // 1) tenta ler a sessão atual
                let session = try await client.auth.session
                return session
            } catch {
                lastError = error

                AppLogger.warning("⚠️ [Auth] Falha ao obter session (attempt \(attempt)/\(maxAttempts)): \(error.localizedDescription)")

                // 2) tenta refresh leve (se falhar por rede, vai cair no catch e tentar novamente)
                do {
                    _ = try await client.auth.refreshSession()
                } catch {
                    lastError = error
                }

                // 3) pequeno delay para evitar race pós-background
                try? await Task.sleep(nanoseconds: attempt == 1 ? 250_000_000 : 500_000_000)
                continue
            }
        }

        throw lastError ?? URLError(.userAuthenticationRequired)
    }

    func signIn(email: String, password: String) async throws {
        isLoading = true
        defer { isLoading = false }

        let startedAt = Date()
        let session = try await client.auth.signIn(
            email: email,
            password: password
        )

        self.currentSession = session
        self.currentUser = session.user
        saveUserToCache(session.user)
        
        // ✅ Login não deve ficar preso aguardando profile/acesso remoto
        self.isAuthenticated = true
        AppLogger.log("✅ [Auth] Sessão criada no signIn. Prosseguindo com carregamentos em background.", category: .auth)
        
        Task { [weak self] in
            guard let self else { return }
            await self.loadUserProfile()
        }
        
        SubscriptionManager.shared.refreshAccess(silent: true, force: true)

        let elapsedMs = Int(Date().timeIntervalSince(startedAt) * 1000)
        AppLogger.log("⏱️ [Auth] signIn concluído em \(elapsedMs)ms (sem bloquear por verificação de assinatura).", category: .auth)
    }

    func signUp(email: String, password: String, name: String, professionalName: String?, phone: String, phoneE164: String?, trialEndDate: String) async throws {
        isLoading = true
        defer { isLoading = false }

        var metadata: [String: AnyJSON] = [
            "full_name": AnyJSON.string(name),
            "phone": AnyJSON.string(phone),
            "trial_end_date": AnyJSON.string(trialEndDate)
        ]
        
        if let phoneE164 = phoneE164 {
            metadata["phone_e164"] = AnyJSON.string(phoneE164)
        }
        
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
        saveUserToCache(session.user)

        try? await Task.sleep(nanoseconds: 2 * 1_000_000_000)
        
        await loadUserProfile()
        
        // FALLBACK: Se o trigger falhou
        if self.userProfile == nil {
            AppLogger.log("⚠️ Aviso: Trigger demorou ou falhou. Criando perfil manualmente via App...", category: .auth)
            
                // Corrigido: session.user não é opcional
                let user = session.user
            
            let userId = user.id
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
                    "is_active": AnyJSON.bool(true),
                    "trial_end_date": AnyJSON.string(trialEndDate)
                ]
                
                if let profName = professionalName, !profName.isEmpty {
                    userProfile["professional_name"] = AnyJSON.string(profName)
                }
                
                if let phoneE164 = phoneE164 {
                    userProfile["phone_e164"] = AnyJSON.string(phoneE164)
                }

                try await client
                    .from("user_profiles")
                    .insert(userProfile)
                    .execute()

                await loadUserProfile()
                AppLogger.log("✅ Perfil criado manualmente com sucesso!", category: .auth)
            } catch {
                AppLogger.error("❌ Erro fatal ao criar perfil (Fallback): \(error)")
                // Evita revogar sessões de outros dispositivos em falhas locais de cadastro.
                try? await client.auth.signOut(scope: .local)
                self.currentSession = nil
                self.currentUser = nil
                self.isAuthenticated = false
                throw error
            }
        }
        
        // Criar Profissional Automaticamente
        let profName = (professionalName != nil && !professionalName!.isEmpty) ? professionalName! : name
        
        let newProfessional = Professional.Insert(
            userId: session.user.id.uuidString,
            name: profName,
            specialty: "Harmonização Orofacial",
            phone: phone,
            phoneE164: phoneE164,
            email: email,
            isActive: true
        )

        
        do {
            try await client
                .from("professionals")
                .insert(newProfessional)
                .execute()
            AppLogger.log("✅ [Auth] Profissional automático criado: \(profName)", category: .auth)
        } catch {
            AppLogger.error("❌ [Auth] Erro ao criar profissional automático: \(error)")
        }
        
        // ✅ Não bloquear conclusão do cadastro em checagem de assinatura
        SubscriptionManager.shared.refreshAccess(silent: true, force: true)
        AppLogger.log("✅ [Auth] Cadastro concluído. Verificação de assinatura disparada em background.", category: .auth)
        
        self.isAuthenticated = true
    }

    func signOut() async throws {
        // ✅ CRÍTICO: Só este método deve fazer logout de verdade
        AppLogger.log("🚪 [Auth] Usuario solicitou logout (EXPLICITO/LOCAL)", category: .auth)
        
        // Seta flag para permitir logout no handler
        userInitiatedSignOut = true
        defer { userInitiatedSignOut = false } // Reseta flag ao terminar
        
        // 1. Limpar tokens de push no servidor antes de invalidar a sessão
        await PushNotificationManager.shared.deactivateDeviceToken()
        
        // 2. Cancelar todas as notificações locais agendadas
        await NotificationManager.shared.cancelAllScheduledNotifications()
        
        // IMPORTANTE: logout local para não invalidar sessões em outros dispositivos da mesma conta.
        try await client.auth.signOut(scope: .local)
        
        // ✅ Limpar tudo após logout bem-sucedido
        self.currentSession = nil
        self.currentUser = nil
        self.userProfile = nil
        self.isAuthenticated = false
        
        // Limpar cache local
        UserDefaults.standard.removeObject(forKey: "cached_supabase_user")
        UserDefaults.standard.removeObject(forKey: "cached_access_state")
        AppointmentsCache.clearAll()
        
        AppLogger.log("✅ [Auth] Logout concluído", category: .auth)
    }

    /// SignOut forçado por sessão inválida detectada pelo SubscriptionManager (401 persistente).
    /// Não depende da flag userInitiatedSignOut — é um signOut de segurança.
    func performSignOutDueToInvalidSession() async {
        AppLogger.log("🔴 [Auth] SignOut forçado local: sessão inválida detectada pelo SubscriptionManager", category: .auth)
        
        userInitiatedSignOut = true
        defer { userInitiatedSignOut = false }
        
        // Best effort para manter push/local notifications consistentes com o estado de logout.
        await PushNotificationManager.shared.deactivateDeviceToken()
        await NotificationManager.shared.cancelAllScheduledNotifications()
        
        // Logout local defensivo: evita efeito cascata em múltiplos dispositivos.
        try? await client.auth.signOut(scope: .local)
        self.currentSession = nil
        self.currentUser = nil
        self.userProfile = nil
        self.isAuthenticated = false
        UserDefaults.standard.removeObject(forKey: "cached_supabase_user")
        UserDefaults.standard.removeObject(forKey: "cached_access_state")
        UserDefaults.standard.removeObject(forKey: "cached_access_state_date")
        UserDefaults.standard.removeObject(forKey: "cached_access_status")
        UserDefaults.standard.removeObject(forKey: "cached_last_verified_at")
        UserDefaults.standard.removeObject(forKey: "cached_last_verified_had_access")
        AppointmentsCache.clearAll()
        AppLogger.log("✅ [Auth] SignOut forçado concluído. Usuário será redirecionado para login.", category: .auth)
    }

    func checkSession() async {
        if isCheckingSessionNow { return }
        isCheckingSessionNow = true
        defer { isCheckingSessionNow = false }

        do {
            let session = try await safeSession(maxAttempts: 2)

            self.currentSession = session
            self.currentUser = session.user
            saveUserToCache(session.user)

            if self.userProfile == nil || self.userProfile?.id != session.user.id.uuidString {
                await loadUserProfile()
            }

            self.isAuthenticated = true
            AppLogger.log("✅ [Auth] Sessão restaurada via safeSession().", category: .auth)

        } catch {
            await handleSessionError(error)
        }
    }
    
    // ✅ NOVO: Método separado para tratar erros de sessão
    private func handleSessionError(_ error: Error) async {
        if let urlError = error as? URLError {
            let isNetworkError = [
                .timedOut,
                .networkConnectionLost,
                .notConnectedToInternet,
                .cannotConnectToHost,
                .cannotFindHost,
                .dnsLookupFailed
            ].contains(urlError.code)
            
            if isNetworkError {
                AppLogger.warning("⚠️ [Auth] Erro transitório de rede ao checar sessão. Mantendo estado atual. (\(urlError.localizedDescription))")
                // ✅ não eleva auth com base só em cache de User
                if self.currentSession != nil {
                     self.isAuthenticated = true
                }
                return
            }
        }
    
        let errorString = error.localizedDescription.lowercased()
        
        // ✅ Lista mais específica de erros que realmente significam "sessão inválida"
        let definiteAuthErrors = [
            "invalid grant",
            "invalid_grant",
            "refresh_token_not_found",
            "invalid token",
            "invalid_token",
            "session not found",
            "session_not_found"
            // "jwt expired" REMOVIDO: deve ser tratado como transitório/refreshable
        ]
        
        let isDefiniteAuthError = definiteAuthErrors.contains { errorString.contains($0) }
        
        if isDefiniteAuthError {
            AppLogger.log("🔴 [Auth] Erro de autenticação definitivo detectado: \(error.localizedDescription)", category: .auth)
            
            // ✅ TENTATIVA DE RE-AUTENTICAÇÃO SILENCIOSA
            if await attemptSilentSessionRecoveryFromStoredCredentials(context: "checkSession.definiteAuthError") {
                return // ✅ Sucesso - não fazer logout
            }
            
            // ✅ Só fazer logout se re-auth falhou E não temos sessão local
            // SE tivermos sessão local, TALVEZ valha a pena manter se for apenas token expired
            // mas invalid_grant geralmente é fatal.
            if self.currentSession == nil {
                AppLogger.log("🚫 [Auth] Fazendo logout por sessão inválida", category: .auth)
                self.currentUser = nil
                self.userProfile = nil
                self.isAuthenticated = false
            } else {
                AppLogger.log("⚠️ [Auth] Erro de sessão mas mantendo sessão local temporariamente (Hopeful strict)", category: .auth)
            }
            
        } else {
            // ✅ MUDANÇA CRÍTICA: Erros de rede E 401 genéricos NÃO causam logout
            // Assumimos que pode ser falha temporária do servidor ou rede
            AppLogger.log("⚠️ [Auth] Erro temporário ou 401 genérico ao verificar sessão: \(error.localizedDescription)", category: .auth)
            
            // ✅ MANTER sessão local
            if self.currentSession != nil {
                // ✅ Já temos sessão - considerar válida até prova em contrário
                self.isAuthenticated = true
                AppLogger.log("✅ [Auth] Mantendo sessão local (modo offline/tolerante)", category: .auth)
            } else {
                // ✅ TENTAR RESTAURAR USUÁRIO DO CACHE (Para suportar reiniciar app offline)
                if let cachedUser = loadUserFromCache() {
                    self.currentUser = cachedUser
                    // ✅ Não setamos isAuthenticated = true (o acesso é delegado ao SubscriptionManager)
                    AppLogger.log("✅ [Auth] Usuário restaurado do cache local para visualização offline", category: .auth)
                    
                    // Disparar verificação de acesso em background
                    SubscriptionManager.shared.refreshAccess(silent: true)
                    return
                }
                
                // ✅ Não temos sessão - tentar re-auth silenciosa antes de desistir
                if await attemptSilentSessionRecoveryFromStoredCredentials(context: "checkSession.noLocalSession") {
                    return
                }
                
                if UserDefaults.standard.bool(forKey: Constants.rememberMeKey) {
                    AppLogger.error("❌ [Auth] Re-login silencioso falhou sem sessão local.")
                    // Última chance: se falhar login e tiver user cacheado (caso raro onde signIn falha mas cache existe)
                    if let cachedUser = loadUserFromCache() {
                         self.currentUser = cachedUser
                         // ✅ Não setamos isAuthenticated = true
                         return
                    }
                    self.isAuthenticated = false
                } else {
                    AppLogger.log("🔵 [Auth] Sem sessão e sem credenciais salvas", category: .auth)
                    self.isAuthenticated = false
                }
            }
        }
    }
    
    /// Tenta recuperar sessão usando credenciais "Lembrar-me", sem chamar fluxo completo de signIn
    /// para evitar recursão com `SubscriptionManager.checkAccess()`.
    func attemptSilentSessionRecoveryFromStoredCredentials(context: String) async -> Bool {
        guard UserDefaults.standard.bool(forKey: Constants.rememberMeKey),
              let savedEmail = UserDefaults.standard.string(forKey: Constants.savedEmailKey),
              let savedPassword = KeychainManager.shared.getPassword(for: savedEmail) else {
            AppLogger.warning("⚠️ [Auth] Recuperação silenciosa indisponível (\(context)): sem credenciais salvas.")
            return false
        }

        let normalizedEmail = savedEmail.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        AppLogger.log("🔄 [Auth] Tentando recuperação silenciosa de sessão (\(context))...", category: .auth)
        
        do {
            let session = try await client.auth.signIn(
                email: normalizedEmail,
                password: savedPassword
            )
            
            self.currentSession = session
            self.currentUser = session.user
            saveUserToCache(session.user)
            
            if self.userProfile == nil || self.userProfile?.id != session.user.id.uuidString {
                await loadUserProfile()
            }
            
            self.isAuthenticated = true
            AppLogger.log("✅ [Auth] Recuperação silenciosa bem-sucedida (\(context)).", category: .auth)
            return true
        } catch {
            AppLogger.error("❌ [Auth] Recuperação silenciosa falhou (\(context)): \(error)")
            return false
        }
    }

    func resetPassword(email: String) async throws {
        if let redirectURL = URL(string: "agendahof://reset-password") {
            try await client.auth.resetPasswordForEmail(email, redirectTo: redirectURL)
        } else {
            try await client.auth.resetPasswordForEmail(email)
        }
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
            
            // ✅ PERSISTÊNCIA: Salvar perfil no cache local
            saveUserProfileToCache(profile)
            
        } catch {
            AppLogger.error("❌ [Auth] Erro ao carregar perfil: \(error)")
            // ✅ PERSISTÊNCIA: Tentar carregar do cache se falhar a rede
            if self.userProfile == nil {
                if let cachedProfile = loadUserProfileFromCache(userId: userId.uuidString) {
                    self.userProfile = cachedProfile
                    AppLogger.log("⚠️ [Auth] Perfil carregado do cache local (offline)", category: .auth)
                }
            }
        }
    }

    func fetchUserProfile() async {
        await loadUserProfile()
    }
    
    // MARK: - Persistence Helpers
    
    private func saveUserProfileToCache(_ profile: UserProfile) {
        if let encoded = try? JSONEncoder().encode(profile) {
            UserDefaults.standard.set(encoded, forKey: "cached_user_profile_\(profile.id)")
        }
    }
    
    private func loadUserProfileFromCache(userId: String) -> UserProfile? {
        guard let data = UserDefaults.standard.data(forKey: "cached_user_profile_\(userId)"),
              let profile = try? JSONDecoder().decode(UserProfile.self, from: data) else {
            return nil
        }
        return profile
    }
    
    // ✅ User object cache
    private func saveUserToCache(_ user: User) {
        if let encoded = try? JSONEncoder().encode(user) {
            UserDefaults.standard.set(encoded, forKey: "cached_supabase_user")
        }
    }
    
    private func loadUserFromCache() -> User? {
        guard let data = UserDefaults.standard.data(forKey: "cached_supabase_user"),
              let user = try? JSONDecoder().decode(User.self, from: data) else {
            return nil
        }
        return user
    }

    // MARK: - Effective User ID

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
