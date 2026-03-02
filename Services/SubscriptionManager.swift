import Foundation
import StoreKit
import Supabase

@MainActor
class SubscriptionManager: ObservableObject {
    static let shared = SubscriptionManager()

    enum AccessStatus: String, Codable {
        case hasAccess
        case noAccess
        case unknown
    }
    
    private enum LocalAccessResolution {
        case hasAccess(AccessState)
        case noAccess
        case indeterminate
    }
    
    private struct PremiumFlagRow: Decodable {
        let isPremium: Bool
        
        enum CodingKeys: String, CodingKey {
            case isPremium = "is_premium"
        }
    }

    @Published var accessState: AccessState = .noAccess
    @Published var accessStatus: AccessStatus = .unknown
    @Published var lastVerifiedAt: Date?
    @Published var lastVerifiedHadAccess: Bool = false
    private var previousAccessState: AccessState = .noAccess

    @Published var storeProducts: [Product] = []
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var purchaseState: PurchaseState = .idle
    @Published var didFinishInitialAccessCheck: Bool = false

    private let supabase = SupabaseManager.shared

    private let productIds: Set<String> = [
        "com.agendahof.basic",
        "com.agendahof.pro",
        "com.agendahof.premium"
    ]

    private let receiptEndpoint = "https://zgdxszwjbbxepsvyjtrb.supabase.co/functions/v1/ios-receipt"

    private var transactionListener: Task<Void, Error>?

    private let offlineGraceHours: Double = 24
    private let deterministicNoAccessProtectionHours: Double = 72
    private let requiredConsecutiveNoAccessChecks: Int = 4

    // ✅ EVITA CONCORRÊNCIA / “BRIGA” DE ESTADOS
    private var accessCheckTask: Task<Void, Never>?
    private var lastRefreshStartedAt: Date?
    private var noAccessConfirmationPending = false
    private var noAccessConfirmationTask: Task<Void, Never>?
    private var consecutiveNoAccessChecks = 0

    private init() {
        transactionListener = listenForTransactions()

        Task { await loadProducts() }

        restoreStateFromCache()
    }

    deinit {
        transactionListener?.cancel()
        accessCheckTask?.cancel()
        noAccessConfirmationTask?.cancel()
    }

    // MARK: - Public API (use essa)
    /// Chame isso em vez de chamar `checkAccess()` diretamente em vários lugares.
    /// `silent = true` evita mostrar overlay de loading durante refresh em background/foreground.
    func refreshAccess(silent: Bool = true, force: Bool = false) {
        if !force, let last = lastRefreshStartedAt,
           Date().timeIntervalSince(last) < 10.0,
           accessCheckTask != nil { // Só bloqueia se já tiver task rodando ou range muito curto
            return
        }
        lastRefreshStartedAt = Date()

        // Cancela um check anterior (ex: onAppear + scenePhase.active)
        accessCheckTask?.cancel()

        accessCheckTask = Task { [weak self] in
            guard let self else { return }
            await self.checkAccessInternal(showLoader: !silent)
        }
    }
    
    // MARK: - Compatibilidade com código antigo
    /// Wrapper async para manter compatibilidade com chamadas antigas `await checkAccess()`
    func checkAccess(silent: Bool = false) async {
        // cancela qualquer check anterior
        accessCheckTask?.cancel()

        accessCheckTask = Task { [weak self] in
            guard let self else { return }
            await self.checkAccessInternal(showLoader: !silent)
        }

        // aguarda terminar (para fluxos que dependem do resultado)
        await accessCheckTask?.value
    }

    // MARK: - Verificação Backend-First (Internal)
    private func checkAccessInternal(showLoader: Bool) async {
        if showLoader {
            isLoading = true
        }

        defer {
            if showLoader {
                isLoading = false
            }
            didFinishInitialAccessCheck = true
        }

        do {
            let token = try await supabase.validAccessToken()

            // 🔍 Log de diagnóstico obrigatório para rastrear race condition
            let hasSession = supabase.currentSession != nil
            AppLogger.log("🔍 [Access] hasSession=\(hasSession) | tokenLen=\(token.count) | calling /api/access", category: .business)

            let response = try await AccessAPI.fetchAccess(accessToken: token)

            if response.hasAccess {
                clearPendingNoAccessConfirmation()
                let plan = PlanType(rawValue: (response.planType ?? "basic")) ?? .basic
                finalizeAccess(
                    .active(plan: plan,
                            expiresAt: response.expiresAtDate,
                            isCourtesy: false,
                            source: .backend),
                    status: .hasAccess
                )
            } else {
                // ✅ Backend respondeu com sucesso e negou o acesso.
                // Não aplicar fallback local — o backend é autoritativo aqui.
                // Grace de cobrança (3 dias) deve ser computada pelo BACKEND em /api/access.
                AppLogger.log("🔒 [Access] Backend negou acesso. Bloqueando imediatamente (sem fallback local).", category: .business)
                clearPendingNoAccessConfirmation()
                finalizeAccess(.noAccess, status: .noAccess)
            }

        } catch let urlError as URLError where urlError.code == .userAuthenticationRequired {
            // 🚨 401 / sessão ausente: NUNCA aplicar fallback/grace — é problema de autenticação, não de rede.
            AppLogger.warning("[Access] 401 em /api/access (sessão ausente/expirada). Tentando refreshSession + retry 1x.")
            await handle401WithRetry()

        } catch {
            // ✅ Somente erros de REDE/timeout/offline chegam aqui.
            // Grace offline é legítima: o usuário estava autenticado e há falha de conectividade.
            if Task.isCancelled { return }
            AppLogger.warning("[Access] Erro de rede ao verificar acesso. Aplicando proteção offline. \(error)")

            let localResolution = await resolveLocalSupabaseAccess()
            switch localResolution {
            case .hasAccess(let fallbackState):
                clearPendingNoAccessConfirmation()
                AppLogger.log("✅ [Access] Fallback local confirmou acesso após erro de rede.", category: .business)
                finalizeAccess(fallbackState, status: .hasAccess)
            case .noAccess:
                applyDeterministicNoAccess(context: "Fallback local sem acesso após erro de rede")
            case .indeterminate:
                if let knownAccessState = bestKnownAccessStateForUncertainCheck() {
                    finalizeAccess(knownAccessState, status: .unknown)
                } else if lastVerifiedHadAccess {
                    finalizeAccess(accessState, status: .unknown)
                } else {
                    finalizeAccess(accessState, status: .unknown)
                }
                clearPendingNoAccessConfirmation()
            }
        }
    }

    // MARK: - 401 Handler: Retry com refreshSession, signOut se persistir

    private func handle401WithRetry() async {
        do {
            // Tenta refrescar sessão (corrige race condition onde token ainda não estava disponível)
            _ = try await supabase.client.auth.refreshSession()
            AppLogger.log("🔄 [Access] Sessão refrescada. Retentando /api/access...", category: .auth)

            let session = try await supabase.client.auth.session
            let token = session.accessToken
            AppLogger.log("🔍 [Access] Retry | tokenLen=\(token.count) | calling /api/access", category: .business)

            let response = try await AccessAPI.fetchAccess(accessToken: token)

            if response.hasAccess {
                clearPendingNoAccessConfirmation()
                let plan = PlanType(rawValue: response.planType ?? "basic") ?? .basic
                finalizeAccess(
                    .active(plan: plan,
                            expiresAt: response.expiresAtDate,
                            isCourtesy: false,
                            source: .backend),
                    status: .hasAccess
                )
                AppLogger.log("✅ [Access] Retry bem-sucedido. Acesso liberado.", category: .business)
            } else {
                // Backend confirmou sem acesso após retry — bloquear imediatamente.
                AppLogger.log("🔒 [Access] Retry: backend negou acesso. Bloqueando.", category: .business)
                clearPendingNoAccessConfirmation()
                finalizeAccess(.noAccess, status: .noAccess)
            }
        } catch {
            // Refresh falhou ou segundo 401 — sessão definitivamente inválida.
            AppLogger.error("❌ [Access] 401 persistente após retry/refresh. Fazendo signOut forçado. \(error)")
            await supabase.performSignOutDueToInvalidSession()
            finalizeAccess(.noAccess, status: .noAccess)
        }
    }

    private func bestKnownAccessStateForUncertainCheck() -> AccessState? {
        if accessState.hasAccess { return accessState }
        if previousAccessState.hasAccess { return previousAccessState }
        if let cachedState = loadAccessStateFromCache(), cachedState.hasAccess { return cachedState }
        return nil
    }
    
    private func bestKnownPlanForFallback() -> PlanType {
        if accessState.hasAccess { return accessState.planType }
        if previousAccessState.hasAccess { return previousAccessState.planType }
        if let cachedState = loadAccessStateFromCache(), cachedState.hasAccess {
            return cachedState.planType
        }
        return .premium
    }

    private func applyDeterministicNoAccess(context: String) {
        if shouldConfirmNoAccessBeforeBlocking() {
            consecutiveNoAccessChecks = 0
            noAccessConfirmationPending = true
            AppLogger.warning("[Access] \(context). Confirmando novamente antes de abrir paywall.")

            if let knownAccessState = bestKnownAccessStateForUncertainCheck() {
                finalizeAccess(knownAccessState, status: .unknown)
            } else {
                finalizeAccess(accessState, status: .unknown)
            }

            scheduleNoAccessConfirmationRefresh()
            return
        }

        if shouldProtectKnownPaidUserFromUnexpectedNoAccess() {
            noAccessConfirmationPending = true
            consecutiveNoAccessChecks = 0
            AppLogger.warning("[Access] \(context). Mantendo acesso temporariamente (proteção anti falso negativo).")
            
            if let knownAccessState = bestKnownAccessStateForUncertainCheck() {
                finalizeAccess(knownAccessState, status: .unknown)
            } else {
                finalizeAccess(accessState, status: .unknown)
            }
            
            scheduleNoAccessConfirmationRefresh(delayNanoseconds: 300_000_000_000)
            return
        }
        
        consecutiveNoAccessChecks += 1
        
        if consecutiveNoAccessChecks < requiredConsecutiveNoAccessChecks {
            noAccessConfirmationPending = true
            AppLogger.warning("[Access] \(context). Sem acesso ainda não confirmado de forma determinística. Tentativa \(consecutiveNoAccessChecks)/\(requiredConsecutiveNoAccessChecks).")
            
            if let knownAccessState = bestKnownAccessStateForUncertainCheck() {
                finalizeAccess(knownAccessState, status: .unknown)
            } else {
                finalizeAccess(accessState, status: .unknown)
            }
            
            scheduleNoAccessConfirmationRefresh(delayNanoseconds: 90_000_000_000)
            return
        }

        clearPendingNoAccessConfirmation()
        finalizeAccess(.noAccess, status: .noAccess)
    }
    
    private func shouldProtectKnownPaidUserFromUnexpectedNoAccess() -> Bool {
        guard lastVerifiedHadAccess, let lastVerifiedAt else { return false }
        let protectionWindow = deterministicNoAccessProtectionHours * 3600
        return Date().timeIntervalSince(lastVerifiedAt) < protectionWindow
    }

    private func shouldConfirmNoAccessBeforeBlocking() -> Bool {
        if noAccessConfirmationPending {
            // Segunda confirmação já em andamento; pode aplicar noAccess.
            return false
        }
        
        // Em dispositivo novo (sem cache), evita bloqueio imediato por falso negativo no primeiro check.
        if !didFinishInitialAccessCheck { return true }

        // Se havia acesso conhecido recentemente, exige dupla confirmação.
        if accessState.hasAccess || previousAccessState.hasAccess { return true }
        if let cachedState = loadAccessStateFromCache(), cachedState.hasAccess { return true }

        if lastVerifiedHadAccess, let lastVerifiedAt {
            let withinOfflineGrace = Date().timeIntervalSince(lastVerifiedAt) < (offlineGraceHours * 3600)
            if withinOfflineGrace { return true }
        }

        return false
    }

    private func scheduleNoAccessConfirmationRefresh(delayNanoseconds: UInt64 = 1_200_000_000) {
        noAccessConfirmationTask?.cancel()
        noAccessConfirmationTask = Task { [weak self] in
            guard let self else { return }
            defer { self.noAccessConfirmationTask = nil }
            try? await Task.sleep(nanoseconds: delayNanoseconds)
            if Task.isCancelled { return }
            self.refreshAccess(silent: true, force: true)
        }
    }

    private func clearPendingNoAccessConfirmation() {
        noAccessConfirmationPending = false
        consecutiveNoAccessChecks = 0
        noAccessConfirmationTask?.cancel()
        noAccessConfirmationTask = nil
    }

    /// Fallback local: consulta `user_subscriptions` diretamente no Supabase
    /// para evitar falso negativo temporário da API `/api/access`.
    private func resolveLocalSupabaseAccess() async -> LocalAccessResolution {
        guard let currentUser = supabase.currentUser else { return .indeterminate }

        if supabase.userProfile == nil {
            await supabase.fetchUserProfile()
        }
        guard let profile = supabase.userProfile else { return .indeterminate }

        let staffCheck = SubscriptionLogic.checkStaffAccess(profile: profile)
        if let blockedState = staffCheck.access {
            return blockedState.hasAccess ? .hasAccess(blockedState) : .noAccess
        }

        let targetUserId = staffCheck.targetUserId ?? currentUser.id.uuidString

        do {
            let subscriptions: [UserSubscription] = try await supabase.client
                .from("user_subscriptions")
                .select()
                .eq("user_id", value: targetUserId)
                .in("status", values: [
                    SubscriptionStatus.active.rawValue,
                    SubscriptionStatus.trialing.rawValue,
                    SubscriptionStatus.pendingCancellation.rawValue
                ])
                .execute()
                .value

            if let localState = SubscriptionLogic.evaluateSubscriptions(subscriptions) {
                return .hasAccess(
                    .active(
                        plan: localState.planType,
                        expiresAt: localState.expirationDate,
                        isCourtesy: localState.isCourtesy,
                        source: .backend
                    )
                )
            }
            
            // Fallback de trial local para evitar falso bloqueio quando a API do backend diverge
            // ou está indisponível.
            var trialMeta: String?
            if let jsonValue = currentUser.userMetadata["trial_end_date"] {
                switch jsonValue {
                case .string(let value):
                    trialMeta = value
                default:
                    trialMeta = nil
                }
            }
            
            let trialState = SubscriptionLogic.checkTrial(
                createdAt: currentUser.createdAt,
                trialEndDateMetadata: trialMeta
            )
            
            if trialState.isInTrial {
                return .hasAccess(trialState)
            }
            
            // Fallback legado para contas Stripe/IAP híbridas:
            // alguns fluxos atualizam `is_premium` antes/de forma divergente de `user_subscriptions`.
            if profile.isPremium {
                let fallbackPlan = bestKnownPlanForFallback()
                AppLogger.log("✅ [Access] Fallback local via user_profiles.is_premium=true.", category: .business)
                return .hasAccess(
                    .active(
                        plan: fallbackPlan,
                        expiresAt: nil,
                        isCourtesy: false,
                        source: .backend
                    )
                )
            }
            
            // Fallback adicional para Staff:
            // quando o Staff herda acesso do Owner, valida `is_premium` no perfil do dono.
            if staffCheck.isStaff,
               let ownerUserId = staffCheck.targetUserId,
               ownerUserId != currentUser.id.uuidString,
               let ownerIsPremium = await fetchPremiumFlag(for: ownerUserId),
               ownerIsPremium {
                let fallbackPlan = bestKnownPlanForFallback()
                AppLogger.log("✅ [Access] Fallback Staff via owner user_profiles.is_premium=true.", category: .business)
                return .hasAccess(
                    .active(
                        plan: fallbackPlan,
                        expiresAt: nil,
                        isCourtesy: false,
                        source: .backend
                    )
                )
            }
            
            return .noAccess
        } catch {
            AppLogger.error("❌ [Access] Erro no fallback local: \(error)")
            return .indeterminate
        }
    }
    
    private func fetchPremiumFlag(for userId: String) async -> Bool? {
        do {
            let rows: [PremiumFlagRow] = try await supabase.client
                .from("user_profiles")
                .select("is_premium")
                .eq("id", value: userId)
                .limit(1)
                .execute()
                .value
            
            return rows.first?.isPremium
        } catch {
            AppLogger.warning("[Access] Não foi possível validar is_premium para userId \(userId): \(error.localizedDescription)")
            return nil
        }
    }



    // MARK: - StoreKit: Produtos
    func loadProducts() async {
        guard storeProducts.isEmpty else { return }

        do {
            let products = try await Product.products(for: productIds)
            storeProducts = products.sorted { $0.price < $1.price }
        } catch {
            AppLogger.error("[StoreKit] Erro ao carregar produtos: \(error)")
            errorMessage = "Não foi possível carregar os planos. Tente novamente."
        }
    }

    // MARK: - Compra / Restore (mantive igual ao seu)
    // MARK: - Compra / Restore
    func purchase(_ product: Product) async {
        purchaseState = .purchasing
        errorMessage = nil

        do {
            let result = try await product.purchase()
            switch result {
            case .success(let verification):
                switch verification {
                case .verified(let transaction):
                    do {
                        let token = try await supabase.validAccessToken()
                        let planType = PlanType.fromAppleProductId(transaction.productID).rawValue
                        let expiration = transaction.expirationDate?.ISO8601Format()

                        try await AccessAPI.notifyApplePurchase(
                            accessToken: token,
                            planType: planType,
                            planName: "Plano \(planType.capitalized)",
                            expirationDate: expiration,
                            originalTransactionId: String(transaction.originalID),
                            transactionId: String(transaction.id)
                        )
                    } catch {
                        AppLogger.error("❌ [IAP] notifyApplePurchase falhou: \(error)")
                    }

                    await transaction.finish()
                    refreshAccess()
                    purchaseState = .success

                case .unverified(_, let error):
                    AppLogger.error("[StoreKit] Compra não verificada: \(error)")
                    purchaseState = .failed("Não foi possível verificar a compra. Tente novamente.")
                    errorMessage = "Não foi possível verificar a compra."
                }

            case .userCancelled:
                purchaseState = .cancelled

            case .pending:
                purchaseState = .failed("Compra pendente de aprovação (ex: Ask to Buy).")
                errorMessage = "Compra pendente de aprovação."

            @unknown default:
                purchaseState = .failed("Erro desconhecido na compra.")
            }

        } catch {
            purchaseState = .failed(error.localizedDescription)
            errorMessage = "Erro ao processar compra: \(error.localizedDescription)"
        }
    }

    func restorePurchases() async {
        purchaseState = .restoring
        errorMessage = nil

        do {
            try await AppStore.sync()

            // Achar melhor transação para notificar
            var best: Transaction?
            var bestTier = -1
            var bestExp: Date = .distantPast

            for await result in Transaction.currentEntitlements {
                guard case .verified(let t) = result else { continue }
                guard productIds.contains(t.productID) else { continue }
                guard t.revocationDate == nil else { continue }

                let tier = PlanType.fromAppleProductId(t.productID).tierLevel
                let exp = t.expirationDate ?? .distantFuture

                if tier > bestTier || (tier == bestTier && exp > bestExp) {
                    best = t
                    bestTier = tier
                    bestExp = exp
                }
            }

            if let t = best {
                do {
                    let token = try await supabase.validAccessToken()
                    let planType = PlanType.fromAppleProductId(t.productID).rawValue
                    let expiration = t.expirationDate?.ISO8601Format()

                    try await AccessAPI.notifyApplePurchase(
                        accessToken: token,
                        planType: planType,
                        planName: "Plano \(planType.capitalized)",
                        expirationDate: expiration,
                        originalTransactionId: String(t.originalID),
                        transactionId: String(t.id)
                    )
                    
                    refreshAccess()
                    purchaseState = .success
                    
                } catch {
                    purchaseState = .failed("Falha ao sincronizar restauração. Tente novamente.")
                    errorMessage = error.localizedDescription
                }
            } else {
                purchaseState = .failed("Nenhuma assinatura anterior encontrada.")
                errorMessage = "Nenhuma assinatura anterior encontrada."
            }

        } catch {
            purchaseState = .failed(error.localizedDescription)
            errorMessage = "Erro ao restaurar compras: \(error.localizedDescription)"
        }
    }

    // MARK: - Sync backend (igual ao seu)


    // MARK: - Listener
    private func listenForTransactions() -> Task<Void, Error> {
        Task.detached {
            for await result in Transaction.updates {
                await self.handleTransactionUpdate(result)
            }
        }
    }

    private func handleTransactionUpdate(_ result: VerificationResult<Transaction>) async {
        switch result {
        case .verified(let transaction):
            do {
                let token = try await supabase.validAccessToken()
                let planType = PlanType.fromAppleProductId(transaction.productID).rawValue
                let expiration = transaction.expirationDate?.ISO8601Format()

                try await AccessAPI.notifyApplePurchase(
                    accessToken: token,
                    planType: planType,
                    planName: "Plano \(planType.capitalized)",
                    expirationDate: expiration,
                    originalTransactionId: String(transaction.originalID),
                    transactionId: String(transaction.id)
                )
            } catch {
                AppLogger.error("❌ [IAP] notify em Transaction.updates falhou: \(error)")
            }

            await transaction.finish()
            refreshAccess()

        case .unverified(_, let error):
            AppLogger.error("[StoreKit] Transação não verificada: \(error)")
        }
    }


    // MARK: - Helpers
    private func finalizeAccess(_ state: AccessState, status: AccessStatus) {
        if self.accessState.hasAccess {
            self.previousAccessState = self.accessState
        }

        self.accessState = state
        self.accessStatus = status
        
        // isLoading e didFinishInitialAccessCheck são controlados pelo defer no caller
        // Atualiza "última verificação" APENAS se o resultado for determinístico (veio do backend).
        // Se for .unknown (fallback), mantêm o timestamp original para não estender o grace period artificialmente.
        if status == .hasAccess || status == .noAccess {
            self.lastVerifiedAt = Date()
            self.lastVerifiedHadAccess = state.hasAccess
        }

        saveAccessStateToCache(state)
        saveAccessStatusToCache(status)
        if let date = lastVerifiedAt { saveLastVerifiedToCache(date) }
        saveLastVerifiedHadAccessToCache(lastVerifiedHadAccess)
    }

    func resetPurchaseState() {
        purchaseState = .idle
        errorMessage = nil
    }

    var effectiveHasAccess: Bool {
        // Se o estado atual diz que tem acesso, confie nisso.
        if accessState.hasAccess { return true }

        // Se o backend confirmou que NÃO tem, bloqueia.
        if accessStatus == .noAccess { return false }

        // Se está unknown, aplica grace (somente se já teve acesso recentemente)
        if accessStatus == .unknown {
            guard lastVerifiedHadAccess, let lastVerifiedAt else { return false }
            let hours = Date().timeIntervalSince(lastVerifiedAt) / 3600
            return hours < offlineGraceHours
        }

        return false
    }

    // Mantido para compatibilidade com MainTabView, mas usando a nova lógica corretiva
    var hasComputedAccess: Bool {
        effectiveHasAccess
    }

    var shouldShowPaywall: Bool {
        didFinishInitialAccessCheck && accessStatus == .noAccess && !isLoading
    }

    var recommendedProduct: Product? {
        storeProducts.first { $0.id == "com.agendahof.premium" }
    }

    // MARK: - Cache
    private func saveAccessStateToCache(_ state: AccessState) {
        if let encoded = try? JSONEncoder().encode(state) {
            UserDefaults.standard.set(encoded, forKey: "cached_access_state")
            UserDefaults.standard.set(Date(), forKey: "cached_access_state_date")
        }
    }

    private func saveAccessStatusToCache(_ status: AccessStatus) {
        if let encoded = try? JSONEncoder().encode(status) {
            UserDefaults.standard.set(encoded, forKey: "cached_access_status")
        }
    }

    private func saveLastVerifiedToCache(_ date: Date) {
        UserDefaults.standard.set(date, forKey: "cached_last_verified_at")
    }

    private func saveLastVerifiedHadAccessToCache(_ hadAccess: Bool) {
        UserDefaults.standard.set(hadAccess, forKey: "cached_last_verified_had_access")
    }

    private func loadAccessStateFromCache() -> AccessState? {
        guard let data = UserDefaults.standard.data(forKey: "cached_access_state"),
              let date = UserDefaults.standard.object(forKey: "cached_access_state_date") as? Date else {
            return nil
        }

        if Date().timeIntervalSince(date) > 7 * 24 * 3600 { return nil }
        return try? JSONDecoder().decode(AccessState.self, from: data)
    }

    func restoreStateFromCache() {
        if let cachedState = loadAccessStateFromCache() {
            self.accessState = cachedState
        }

        if let statusData = UserDefaults.standard.data(forKey: "cached_access_status"),
           let cachedStatus = try? JSONDecoder().decode(AccessStatus.self, from: statusData) {
            self.accessStatus = cachedStatus
        }

        if let date = UserDefaults.standard.object(forKey: "cached_last_verified_at") as? Date {
            self.lastVerifiedAt = date
        }

        self.lastVerifiedHadAccess = UserDefaults.standard.bool(forKey: "cached_last_verified_had_access")

        if accessStatus == .hasAccess { lastVerifiedHadAccess = true }
        if accessStatus == .noAccess { lastVerifiedHadAccess = false }

        // ✅ evita paywall “na largada” por cache
        self.didFinishInitialAccessCheck = false
    }
}
