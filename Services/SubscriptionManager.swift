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

    // ✅ EVITA CONCORRÊNCIA / “BRIGA” DE ESTADOS
    private var accessCheckTask: Task<Void, Never>?
    private var lastRefreshStartedAt: Date?

    private init() {
        transactionListener = listenForTransactions()

        Task { await loadProducts() }

        restoreStateFromCache()
    }

    deinit {
        transactionListener?.cancel()
        accessCheckTask?.cancel()
    }

    // MARK: - Public API (use essa)
    /// Chame isso em vez de chamar `checkAccess()` diretamente em vários lugares.
    func refreshAccess() {
        if let last = lastRefreshStartedAt,
           Date().timeIntervalSince(last) < 10.0,
           accessCheckTask != nil { // Só bloqueia se já tiver task rodando ou range muito curto
            return
        }
        lastRefreshStartedAt = Date()

        // Cancela um check anterior (ex: onAppear + scenePhase.active)
        accessCheckTask?.cancel()

        accessCheckTask = Task { [weak self] in
            guard let self else { return }
            await self.checkAccessInternal()
        }
    }
    
    // MARK: - Compatibilidade com código antigo
    /// Wrapper async para manter compatibilidade com chamadas antigas `await checkAccess()`
    func checkAccess() async {
        // cancela qualquer check anterior
        accessCheckTask?.cancel()

        accessCheckTask = Task { [weak self] in
            guard let self else { return }
            await self.checkAccessInternal()
        }

        // aguarda terminar (para fluxos que dependem do resultado)
        await accessCheckTask?.value
    }

    // MARK: - Verificação Backend-First (Internal)
    private func checkAccessInternal() async {
        didFinishInitialAccessCheck = false
        isLoading = true
        errorMessage = nil

        // cancelamento
        if Task.isCancelled {
            isLoading = false
            return
        }




        do {
            
            let token = try await supabase.validAccessToken()
            let accessResponse = try await AccessAPI.fetchAccess(accessToken: token)

            if accessResponse.hasAccess {
                let plan = PlanType(rawValue: (accessResponse.planType ?? "basic")) ?? .basic
                finalizeAccess(
                    .active(plan: plan,
                            expiresAt: accessResponse.expiresAtDate,
                            isCourtesy: false,
                            source: .backend),
                    status: .hasAccess
                )
            } else {
                finalizeAccess(.noAccess, status: .noAccess)
            }

        } catch {
            // Se for 401 vindo do backend (Sessão inválida/Revogada)
            // Se for 401 vindo do backend (Sessão inválida/Revogada)
            if let err = error as? URLError, err.code == .userAuthenticationRequired {
                AppLogger.error("[Access] 401 Unauthorized - Forçando logout.")
                do {
                    try await supabase.signOut() // Desloga
                } catch {
                    AppLogger.error("❌ [Auth] Falha ao fazer signOut após 401: \(error)")
                }
                finalizeAccess(.noAccess, status: .noAccess) // Bloqueia
                return
            }

            // Ignorar erro de cancelamento (ex: refreshAccess chamando cancel())
            if let err = error as? URLError, err.code == .cancelled {
                AppLogger.warning("[Access] Request cancelado. Ignorando.")
                return
            }

            AppLogger.error("[Access] Railway /api/access falhou: \(error)")

            // fallback: mantém acesso anterior por grace
            if previousAccessState.hasAccess {
                finalizeAccess(previousAccessState, status: .unknown)
                return
            }

            if let cached = loadAccessStateFromCache(), cached.hasAccess {
                finalizeAccess(cached, status: .unknown)
                return
            }

            finalizeAccess(.noAccess, status: .unknown)
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
        self.isLoading = false
        self.didFinishInitialAccessCheck = true

        // Atualiza "última verificação" sempre que o RESULTADO for determinístico
        // OU quando o state atual tiver acesso (pra suportar fallback em erro).
        if status == .hasAccess || status == .noAccess || state.hasAccess {
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
        didFinishInitialAccessCheck && !effectiveHasAccess && !isLoading
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
