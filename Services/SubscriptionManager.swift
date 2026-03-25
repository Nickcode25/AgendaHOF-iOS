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

    private let saleProductIds: Set<String> = [
        "com.agendahof.premium"
    ]

    private let entitlementProductIds: Set<String> = [
        "com.agendahof.basic",
        "com.agendahof.pro",
        "com.agendahof.premium"
    ]

    private let receiptEndpoint = "https://zgdxszwjbbxepsvyjtrb.supabase.co/functions/v1/ios-receipt"

    private var transactionListener: Task<Void, Error>?
    private var purchaseWatchdogTask: Task<Void, Never>?
    private var lastAppleSyncAttemptAt: Date?
    private var lastAppleSyncedTransactionId: String?

    private let offlineGraceHours: Double = 24
    private let deterministicNoAccessProtectionHours: Double = 72
    private let requiredConsecutiveNoAccessChecks: Int = 4
    private let trustedLoadingFallbackHours: Double = 6
    private let appleSyncRetryInterval: TimeInterval = 120
    private let purchaseWatchdogTimeoutNanoseconds: UInt64 = 45_000_000_000

    // ✅ EVITA CONCORRÊNCIA / “BRIGA” DE ESTADOS
    private var accessCheckTask: Task<Void, Never>?
    private var lastRefreshStartedAt: Date?
    private var noAccessConfirmationPending = false
    private var noAccessConfirmationTask: Task<Void, Never>?
    private var consecutiveNoAccessChecks = 0
    private var accessCheckNonce: UUID = UUID()

    private init() {
        transactionListener = listenForTransactions()

        Task { await loadProducts() }

        restoreStateFromCache()
    }

    deinit {
        transactionListener?.cancel()
        accessCheckTask?.cancel()
        noAccessConfirmationTask?.cancel()
        purchaseWatchdogTask?.cancel()
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
        let checkStartedAt = Date()
        let nonce = UUID()
        accessCheckNonce = nonce

        if showLoader {
            isLoading = true
        }

        defer {
            if showLoader {
                isLoading = false
            }
            didFinishInitialAccessCheck = true
            
            let elapsedMs = Int(Date().timeIntervalSince(checkStartedAt) * 1000)
            AppLogger.log(
                "⏱️ [Access] checkAccessInternal concluído em \(elapsedMs)ms | status=\(self.accessStatus.rawValue) | hasAccess=\(self.accessState.hasAccess)",
                category: .business
            )
        }

        do {
            let token = try await supabase.validAccessToken()

            // 🔍 Log de diagnóstico obrigatório para rastrear race condition
            let hasSession = supabase.currentSession != nil
            AppLogger.log("🔍 [Access] hasSession=\(hasSession) | tokenLen=\(token.count) | calling /api/access", category: .business)

            let response = try await AccessAPI.fetchAccess(accessToken: token)

            if let appleOverride = await localAppleAccessOverrideStateIfNeeded(response: response) {
                guard accessCheckNonce == nonce else { return }
                clearPendingNoAccessConfirmation()
                AppLogger.log(
                    "🍎 [Access] Aplicando override local imediato por entitlement Apple ativo. plano=\(appleOverride.planType.rawValue)",
                    category: .business
                )
                finalizeAccess(appleOverride, status: .hasAccess)
                
                syncAppleEntitlementInBackgroundIfNeeded(response: response, accessToken: token)
                return
            }

            let didSyncAppleEntitlement = await reconcileAppleEntitlementWithBackendIfNeeded(
                response: response,
                accessToken: token
            )
            if didSyncAppleEntitlement {
                AppLogger.log("✅ [Access] Entitlement sincronizado. Disparando refreshAccess em background.", category: .business)
                refreshAccess(silent: true, force: true)
            }

            if response.hasAccess {
                guard accessCheckNonce == nonce else { return }
                clearPendingNoAccessConfirmation()
                let plan = parsePlanTypeForHasAccess(response.planType)
                
                let sourceEnum = mapSubscriptionSource(response.source)
                let stateReason = response.reason ?? "unknown"
                let stateStatus = response.status ?? "unknown"
                
                finalizeAccess(
                    .active(plan: plan,
                            expiresAt: response.expiresAtDate,
                            source: sourceEnum,
                            backendReason: stateReason,
                            backendStatus: stateStatus),
                    status: .hasAccess
                )
            } else {
                let plan = parsePlanTypeForNoAccess(response.planType)
                
                let sourceEnum = mapSubscriptionSource(response.source)
                let stateReason = response.reason ?? "unknown"
                let stateStatus = response.status ?? "unknown"
                
                let noAccessObj = AccessState(
                    hasActiveSubscription: false,
                    isInTrial: false,
                    isCourtesy: false,
                    planType: plan,
                    expirationDate: response.expiresAtDate,
                    source: sourceEnum,
                    backendReason: stateReason,
                    backendStatus: stateStatus
                )
                
                AppLogger.log("🔒 [Access] Backend negou acesso. Bloqueando imediatamente (sem fallback local). [Reason: \(stateReason)]", category: .business)
                guard accessCheckNonce == nonce else { return }
                clearPendingNoAccessConfirmation()
                finalizeAccess(noAccessObj, status: .noAccess)
            }

        } catch AccessHTTPError.unauthorized {
            // 🚨 401: NUNCA aplicar fallback/grace — é problema de autenticação, não de rede.
            AppLogger.warning("[Access] 401 em /api/access. Tentando refreshSession + retry 1x.")
            await handle401WithRetry(nonce: nonce)

        } catch {
            // ✅ Somente erros de REDE/timeout/offline chegam aqui.
            // Grace offline é legítima: o usuário estava autenticado e há falha de conectividade.
            if Task.isCancelled { return }
            AppLogger.warning("[Access] Erro de rede ao verificar acesso. Aplicando proteção offline. \(error)")

            let localResolution = await resolveLocalSupabaseAccess()
            switch localResolution {
            case .hasAccess(let fallbackState):
                guard accessCheckNonce == nonce else { return }
                clearPendingNoAccessConfirmation()
                AppLogger.log("✅ [Access] Fallback local confirmou acesso após erro de rede.", category: .business)
                finalizeAccess(fallbackState, status: .hasAccess)
            case .noAccess:
                applyDeterministicNoAccess(context: "Fallback local sem acesso após erro de rede", nonce: nonce)
            case .indeterminate:
                guard accessCheckNonce == nonce else { return }
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
    
    private func syncAppleEntitlementInBackgroundIfNeeded(response: AccessResponse, accessToken: String) {
        Task { [weak self] in
            guard let self else { return }
            let didSyncAppleEntitlement = await self.reconcileAppleEntitlementWithBackendIfNeeded(
                response: response,
                accessToken: accessToken
            )
            if didSyncAppleEntitlement {
                AppLogger.log("✅ [Access] Sync Apple em background concluído. Disparando refreshAccess.", category: .business)
                self.refreshAccess(silent: true, force: true)
            }
        }
    }

    private func reconcileAppleEntitlementWithBackendIfNeeded(
        response: AccessResponse,
        accessToken: String
    ) async -> Bool {
        let plan = parsePlanTypeForNoAccess(response.planType)
        let source = (response.source ?? "").lowercased()
        let status = (response.status ?? "").lowercased()
        let reason = (response.reason ?? "").lowercased()

        // Conta explicitamente sem assinatura ativa: não reconciliar automaticamente
        // para evitar que entitlement local de outro login "vaze" para esta conta.
        let backendExplicitNoSubscription =
            status == "no_subscription" ||
            reason == "trial_expired_no_subscription" ||
            reason == "no_subscription"
        if backendExplicitNoSubscription {
            AppLogger.warning("⚠️ [Access] Reconcile Apple ignorado: backend informou conta sem assinatura.")
            return false
        }

        // Reconciliar quando backend ainda está sem acesso ou preso em trial,
        // mas já existe entitlement ativo da Apple no dispositivo.
        let needsReconcile = (!response.hasAccess) || plan == .trial || source == "none"
        guard needsReconcile else { return false }

        guard let transaction = await bestActiveAppleEntitlement() else {
            AppLogger.warning("⚠️ [Access] Nenhum entitlement Apple ativo encontrado no dispositivo para reconciliar.")
            return false
        }

        let transactionId = String(transaction.id)
        if lastAppleSyncedTransactionId == transactionId {
            return false
        }

        if let lastAttempt = lastAppleSyncAttemptAt,
           Date().timeIntervalSince(lastAttempt) < appleSyncRetryInterval {
            return false
        }
        lastAppleSyncAttemptAt = Date()

        do {
            let planType = normalizedPlanTypeRawValue(for: transaction.productID)
            let expiration = transaction.expirationDate?.ISO8601Format()

            try await AccessAPI.notifyApplePurchase(
                accessToken: accessToken,
                planType: planType,
                planName: "Plano \(planType.capitalized)",
                planAmount: await resolvePlanAmount(for: transaction.productID),
                expirationDate: expiration,
                originalTransactionId: String(transaction.originalID),
                transactionId: transactionId
            )

            lastAppleSyncedTransactionId = transactionId
            AppLogger.log("🍎 [Access] Entitlement Apple reconciliado com backend com sucesso.", category: .business)
            return true
        } catch {
            AppLogger.warning("⚠️ [Access] Falha ao reconciliar entitlement Apple com backend: \(error.localizedDescription)")
            return false
        }
    }

    private func localAppleAccessOverrideStateIfNeeded(response: AccessResponse) async -> AccessState? {
        guard let transaction = await bestActiveAppleEntitlement() else { return nil }

        let applePlan = normalizeActivePlan(PlanType.fromAppleProductId(transaction.productID))
        guard applePlan != .none else { return nil }

        let backendPlan = response.hasAccess
            ? parsePlanTypeForHasAccess(response.planType)
            : parsePlanTypeForNoAccess(response.planType)
        let backendSource = (response.source ?? "").lowercased()
        let backendStatus = (response.status ?? "").lowercased()
        let backendReason = (response.reason ?? "").lowercased()

        if backendSource == SubscriptionSource.apple.rawValue, backendPlan == applePlan {
            return nil
        }

        // Se o backend afirmou explicitamente que a conta não tem assinatura,
        // não permitir override local para evitar "vazar" acesso entre contas.
        let backendExplicitNoSubscription =
            backendStatus == "no_subscription" ||
            backendReason == "trial_expired_no_subscription" ||
            backendReason == "no_subscription"
        if backendExplicitNoSubscription {
            AppLogger.warning("⚠️ [Access] Override local Apple ignorado: backend informou ausência de assinatura.")
            return nil
        }

        let backendLikelyStale =
            backendStatus == "cancelled" ||
            backendReason == "cancelled_subscription" ||
            backendPlan == .trial

        let shouldOverride =
            (!response.hasAccess && backendLikelyStale) ||
            backendPlan == .trial ||
            applePlan.tierLevel > backendPlan.tierLevel

        guard shouldOverride else { return nil }

        return .active(
            plan: applePlan,
            expiresAt: transaction.expirationDate,
            source: .apple,
            backendReason: response.reason ?? "apple_entitlement_override",
            backendStatus: response.status ?? "apple_verified_local"
        )
    }

    private func bestActiveAppleEntitlement() async -> Transaction? {
        var best: Transaction?
        var bestTier = -1
        var bestExpiration: Date = .distantPast

        for await result in Transaction.currentEntitlements {
            guard case .verified(let transaction) = result else { continue }
            guard entitlementProductIds.contains(transaction.productID) else { continue }
            guard transaction.revocationDate == nil else { continue }

            if let expirationDate = transaction.expirationDate, expirationDate < Date() {
                continue
            }

            let tier = normalizeActivePlan(PlanType.fromAppleProductId(transaction.productID)).tierLevel
            let expiration = transaction.expirationDate ?? .distantFuture

            if tier > bestTier || (tier == bestTier && expiration > bestExpiration) {
                best = transaction
                bestTier = tier
                bestExpiration = expiration
            }
        }

        return best
    }

    private func resolvePlanAmount(for productId: String) async -> Double? {
        if let cachedProduct = storeProducts.first(where: { $0.id == productId }) {
            return NSDecimalNumber(decimal: cachedProduct.price).doubleValue
        }

        do {
            let products = try await Product.products(for: [productId])
            if let product = products.first {
                if !storeProducts.contains(where: { $0.id == product.id }) {
                    storeProducts.append(product)
                    storeProducts.sort { $0.price < $1.price }
                }
                return NSDecimalNumber(decimal: product.price).doubleValue
            }
        } catch {
            AppLogger.warning("⚠️ [IAP] Não foi possível carregar preço do produto \(productId): \(error.localizedDescription)")
        }

        switch productId {
        case "com.agendahof.premium":
            return 129.90
        default:
            return nil
        }
    }

    private func mapSubscriptionSource(_ rawSource: String?) -> SubscriptionSource {
        switch rawSource?.lowercased() {
        case "apple":
            return .apple
        case "backend", "stripe", "grace":
            return .backend
        default:
            return .none
        }
    }

    private func normalizeActivePlan(_ plan: PlanType) -> PlanType {
        switch plan {
        case .basic, .pro:
            return .premium
        default:
            return plan
        }
    }

    private func parsePlanTypeForHasAccess(_ rawPlanType: String?) -> PlanType {
        let parsed = PlanType(rawValue: (rawPlanType ?? "premium")) ?? .premium
        return normalizeActivePlan(parsed)
    }

    private func parsePlanTypeForNoAccess(_ rawPlanType: String?) -> PlanType {
        let parsed = PlanType(rawValue: (rawPlanType ?? "none")) ?? .none
        switch parsed {
        case .basic, .pro, .premium:
            return .none
        default:
            return parsed
        }
    }

    private func normalizedPlanTypeRawValue(for productId: String) -> String {
        normalizeActivePlan(PlanType.fromAppleProductId(productId)).rawValue
    }

    // MARK: - 401 Handler: Retry com refreshSession, signOut se persistir

    private func handle401WithRetry(nonce: UUID) async {
        do {
            _ = try await supabase.client.auth.refreshSession()
            AppLogger.log("🔄 [Access] Sessão refrescada. Retentando /api/access...", category: .auth)

            // auth.session throws if no session; catch is handled in the outer do/catch
            let session = try await supabase.client.auth.session
            let token = session.accessToken
            AppLogger.log("🔍 [Access] Retry | tokenLen=\(token.count) | calling /api/access", category: .business)

            let response = try await AccessAPI.fetchAccess(accessToken: token)

            if response.hasAccess {
                guard accessCheckNonce == nonce else { return }
                clearPendingNoAccessConfirmation()
                let plan = parsePlanTypeForHasAccess(response.planType)
                let retrySource = mapSubscriptionSource(response.source)
                let retryReason = response.reason ?? "unknown"
                let retryStatus = response.status ?? "unknown"
                finalizeAccess(
                    .active(plan: plan,
                            expiresAt: response.expiresAtDate,
                            source: retrySource,
                            backendReason: retryReason,
                            backendStatus: retryStatus),
                    status: .hasAccess
                )
                AppLogger.log("✅ [Access] Retry bem-sucedido. Acesso liberado.", category: .business)
            } else {
                let plan = parsePlanTypeForNoAccess(response.planType)
                let retrySource = mapSubscriptionSource(response.source)
                let retryReason = response.reason ?? "unknown"
                let retryStatus = response.status ?? "unknown"
                let noAccessObj = AccessState(
                    hasActiveSubscription: false,
                    isInTrial: false,
                    isCourtesy: false,
                    planType: plan,
                    expirationDate: response.expiresAtDate,
                    source: retrySource,
                    backendReason: retryReason,
                    backendStatus: retryStatus
                )
                guard accessCheckNonce == nonce else { return }
                AppLogger.log("🔒 [Access] Retry: backend negou acesso. Bloqueando. [Reason: \(retryReason)]", category: .business)
                clearPendingNoAccessConfirmation()
                finalizeAccess(noAccessObj, status: .noAccess)
            }

        } catch {
            // ✅ erro transitório: NÃO desloga
            if isTransientNetworkError(error) {
                guard accessCheckNonce == nonce else { return }
                AppLogger.warning("⚠️ [Access] Refresh/Retry falhou por rede/timeout. NÃO deslogar. Entrando em unknown + grace e tentando novamente. \(error)")

                if let known = bestKnownAccessStateForUncertainCheck() {
                    finalizeAccess(known, status: .unknown)
                } else {
                    finalizeAccess(accessState, status: .unknown)
                }

                scheduleNoAccessConfirmationRefresh(delayNanoseconds: 2_000_000_000)
                return
            }

            // Verifica se sessão existe antes de deslogar
            let hasSessionNow = (try? await supabase.client.auth.session) != nil
            if hasSessionNow {
                guard accessCheckNonce == nonce else { return }
                AppLogger.warning("⚠️ [Access] Erro não-transitório, mas sessão ainda existe. Evitando signOut e tentando novamente em breve. \(error)")

                if let known = bestKnownAccessStateForUncertainCheck() {
                    finalizeAccess(known, status: .unknown)
                } else {
                    finalizeAccess(accessState, status: .unknown)
                }

                scheduleNoAccessConfirmationRefresh(delayNanoseconds: 2_000_000_000)
                return
            }

            // 🚨 só aqui: sessão realmente indisponível → dupla checagem final antes de deslogar
            AppLogger.warning("⚠️ [Access] getSession() retornou nil após 401. Agendando dupla checagem em 300ms...")
            try? await Task.sleep(nanoseconds: 300_000_000)
            let hasSessionAfterSleep = (try? await supabase.client.auth.session) != nil
            if hasSessionAfterSleep {
                guard accessCheckNonce == nonce else { return }
                AppLogger.warning("⚠️ [Access] Sessão se recuperou na dupla checagem! Salvando a vida da UI.")
                
                if let known = bestKnownAccessStateForUncertainCheck() {
                    finalizeAccess(known, status: .unknown)
                } else {
                    finalizeAccess(accessState, status: .unknown)
                }
                
                scheduleNoAccessConfirmationRefresh(delayNanoseconds: 2_000_000_000)
                return
            }

            // Última tentativa antes de expulsar o usuário:
            // recuperar sessão via credenciais "Lembrar-me" (quando disponível).
            let recoveredSession = await supabase.attemptSilentSessionRecoveryFromStoredCredentials(
                context: "SubscriptionManager.handle401WithRetry"
            )
            if recoveredSession {
                guard accessCheckNonce == nonce else { return }
                AppLogger.warning("♻️ [Access] Sessão recuperada silenciosamente após 401 persistente. Evitando signOut.")
                
                if let known = bestKnownAccessStateForUncertainCheck() {
                    finalizeAccess(known, status: .unknown)
                } else {
                    finalizeAccess(accessState, status: .unknown)
                }
                
                scheduleNoAccessConfirmationRefresh(delayNanoseconds: 1_000_000_000)
                return
            }

            guard accessCheckNonce == nonce else { return }
            AppLogger.error("❌ [Access] Sem sessão confirmada na dupla checagem. SignOut forçado. \(error)")
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
        if accessState.hasAccess { return normalizeActivePlan(accessState.planType) }
        if previousAccessState.hasAccess { return normalizeActivePlan(previousAccessState.planType) }
        if let cachedState = loadAccessStateFromCache(), cachedState.hasAccess {
            return normalizeActivePlan(cachedState.planType)
        }
        return .premium
    }

    private func applyDeterministicNoAccess(context: String, nonce: UUID) {
        if shouldConfirmNoAccessBeforeBlocking() {
            consecutiveNoAccessChecks = 0
            noAccessConfirmationPending = true
            AppLogger.warning("[Access] \(context). Confirmando novamente antes de abrir paywall.")

            if let knownAccessState = bestKnownAccessStateForUncertainCheck() {
                guard accessCheckNonce == nonce else { return }
                finalizeAccess(knownAccessState, status: .unknown)
            } else {
                guard accessCheckNonce == nonce else { return }
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
                guard accessCheckNonce == nonce else { return }
                finalizeAccess(knownAccessState, status: .unknown)
            } else {
                guard accessCheckNonce == nonce else { return }
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
                guard accessCheckNonce == nonce else { return }
                finalizeAccess(knownAccessState, status: .unknown)
            } else {
                guard accessCheckNonce == nonce else { return }
                finalizeAccess(accessState, status: .unknown)
            }
            
            scheduleNoAccessConfirmationRefresh(delayNanoseconds: 90_000_000_000)
            return
        }

        guard accessCheckNonce == nonce else { return }
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
                        plan: normalizeActivePlan(localState.planType),
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
                        plan: normalizeActivePlan(fallbackPlan),
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
                        plan: normalizeActivePlan(fallbackPlan),
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

        let ids = saleProductIds.sorted().joined(separator: ", ")
        AppLogger.log("🛍️ [StoreKit] Carregando produtos: \(ids)", category: .business)

        do {
            let products = try await Product.products(for: saleProductIds)
            storeProducts = products.sorted { $0.price < $1.price }

            if storeProducts.isEmpty {
                AppLogger.warning("⚠️ [StoreKit] Nenhum produto retornado para os IDs configurados.")
                errorMessage = "Produto Premium indisponível no momento. Verifique App Store Connect/TestFlight e tente novamente."
            } else {
                let productIds = storeProducts.map(\.id).joined(separator: ", ")
                AppLogger.log("✅ [StoreKit] Produtos carregados: \(productIds)", category: .business)
            }
        } catch {
            AppLogger.error("[StoreKit] Erro ao carregar produtos: \(error)")
            errorMessage = "Não foi possível carregar os planos. Tente novamente."
        }
    }

    // MARK: - Compra / Restore (mantive igual ao seu)
    // MARK: - Compra / Restore
    func purchase(_ product: Product) async {
        AppLogger.log("🧾 [StoreKit] Iniciando compra do produto: \(product.id) (\(product.displayPrice))", category: .business)

        guard product.id == "com.agendahof.premium" else {
            setPurchaseState(.failed("Produto inválido para compra."))
            errorMessage = "Somente o plano Premium está disponível."
            AppLogger.warning("⚠️ [StoreKit] Tentativa de compra bloqueada para produto não permitido: \(product.id)")
            return
        }

        setPurchaseState(.purchasing)
        errorMessage = nil

        do {
            let result = try await product.purchase()
            switch result {
            case .success(let verification):
                switch verification {
                case .verified(let transaction):
                    AppLogger.log("✅ [StoreKit] Compra verificada. transactionId=\(transaction.id), productId=\(transaction.productID)", category: .business)
                    do {
                        let token = try await supabase.validAccessToken()
                        let planType = normalizedPlanTypeRawValue(for: transaction.productID)
                        let expiration = transaction.expirationDate?.ISO8601Format()

                        try await AccessAPI.notifyApplePurchase(
                            accessToken: token,
                            planType: planType,
                            planName: "Plano \(planType.capitalized)",
                            planAmount: NSDecimalNumber(decimal: product.price).doubleValue,
                            expirationDate: expiration,
                            originalTransactionId: String(transaction.originalID),
                            transactionId: String(transaction.id)
                        )
                    } catch {
                        AppLogger.error("❌ [IAP] notifyApplePurchase falhou: \(error)")
                    }

                    await transaction.finish()
                    refreshAccess()
                    setPurchaseState(.success)

                case .unverified(_, let error):
                    AppLogger.error("[StoreKit] Compra não verificada: \(error)")
                    setPurchaseState(.failed("Não foi possível verificar a compra. Tente novamente."))
                    errorMessage = "Não foi possível verificar a compra."
                }

            case .userCancelled:
                AppLogger.warning("⚠️ [StoreKit] Compra retornou userCancelled. Isso também pode ocorrer quando o login sandbox é fechado/falha.")
                setPurchaseState(.cancelled)

            case .pending:
                AppLogger.warning("⏳ [StoreKit] Compra pendente de aprovação.")
                setPurchaseState(.failed("Compra pendente de aprovação (ex: Ask to Buy)."))
                errorMessage = "Compra pendente de aprovação."

            @unknown default:
                setPurchaseState(.failed("Erro desconhecido na compra."))
            }

        } catch {
            setPurchaseState(.failed(error.localizedDescription))
            errorMessage = "Erro ao processar compra: \(error.localizedDescription)"
        }
    }

    func restorePurchases() async {
        setPurchaseState(.restoring)
        errorMessage = nil

        do {
            try await AppStore.sync()

            // Achar melhor transação para notificar
            var best: Transaction?
            var bestTier = -1
            var bestExp: Date = .distantPast

            for await result in Transaction.currentEntitlements {
                guard case .verified(let t) = result else { continue }
                guard entitlementProductIds.contains(t.productID) else { continue }
                guard t.revocationDate == nil else { continue }

                let tier = normalizeActivePlan(PlanType.fromAppleProductId(t.productID)).tierLevel
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
                    let planType = normalizedPlanTypeRawValue(for: t.productID)
                    let expiration = t.expirationDate?.ISO8601Format()

                    try await AccessAPI.notifyApplePurchase(
                        accessToken: token,
                        planType: planType,
                        planName: "Plano \(planType.capitalized)",
                        planAmount: await resolvePlanAmount(for: t.productID),
                        expirationDate: expiration,
                        originalTransactionId: String(t.originalID),
                        transactionId: String(t.id)
                    )
                    
                    refreshAccess()
                    setPurchaseState(.success)
                    
                } catch {
                    setPurchaseState(.failed("Falha ao sincronizar restauração. Tente novamente."))
                    errorMessage = error.localizedDescription
                }
            } else {
                setPurchaseState(.failed("Nenhuma assinatura anterior encontrada."))
                errorMessage = "Nenhuma assinatura anterior encontrada."
            }

        } catch {
            setPurchaseState(.failed(error.localizedDescription))
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
                let planType = normalizedPlanTypeRawValue(for: transaction.productID)
                let expiration = transaction.expirationDate?.ISO8601Format()

                try await AccessAPI.notifyApplePurchase(
                    accessToken: token,
                    planType: planType,
                    planName: "Plano \(planType.capitalized)",
                    planAmount: await resolvePlanAmount(for: transaction.productID),
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

    private func isTransientNetworkError(_ error: Error) -> Bool {
        guard let e = error as? URLError else { return false }
        return [
            .timedOut,
            .networkConnectionLost,
            .notConnectedToInternet,
            .cannotFindHost,
            .cannotConnectToHost,
            .dnsLookupFailed
        ].contains(e.code)
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

    private func setPurchaseState(_ newState: PurchaseState) {
        purchaseState = newState
        switch newState {
        case .purchasing:
            armPurchaseWatchdog(expectedState: .purchasing)
        case .restoring:
            armPurchaseWatchdog(expectedState: .restoring)
        default:
            purchaseWatchdogTask?.cancel()
            purchaseWatchdogTask = nil
        }
    }

    private func armPurchaseWatchdog(expectedState: PurchaseState) {
        purchaseWatchdogTask?.cancel()
        let timeoutNanoseconds = self.purchaseWatchdogTimeoutNanoseconds
        purchaseWatchdogTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: timeoutNanoseconds)
            guard let self, !Task.isCancelled else { return }

            let stillPending: Bool
            switch (expectedState, self.purchaseState) {
            case (.purchasing, .purchasing), (.restoring, .restoring):
                stillPending = true
            default:
                stillPending = false
            }

            guard stillPending else { return }
            AppLogger.warning("⏱️ [StoreKit] Timeout de compra/restauração. Resetando estado para permitir nova tentativa.")
            self.errorMessage = "A operação demorou mais que o esperado. Tente novamente."
            self.purchaseState = .failed("A operação demorou mais que o esperado. Tente novamente.")
            self.purchaseWatchdogTask = nil
        }
    }

    func resetPurchaseState() {
        purchaseWatchdogTask?.cancel()
        purchaseWatchdogTask = nil
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
    
    /// Uso exclusivo de UX: permite sair do "Verificando assinatura..." após timeout
    /// somente quando houver evidência local forte de acesso recente.
    var canUseTrustedAccessForLoadingFallback: Bool {
        if accessStatus == .hasAccess {
            return true
        }
        
        guard accessStatus == .unknown else { return false }
        guard accessState.hasAccess else { return false }
        guard lastVerifiedHadAccess, let lastVerifiedAt else { return false }
        
        let maxAge = trustedLoadingFallbackHours * 3600
        let elapsed = Date().timeIntervalSince(lastVerifiedAt)
        return elapsed >= 0 && elapsed <= maxAge
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
