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

    // MARK: - Verificação Híbrida (Internal)
    private func checkAccessInternal() async {
        didFinishInitialAccessCheck = false
        isLoading = true
        errorMessage = nil

        // Se cancelou, sai silenciosamente
        if Task.isCancelled {
            isLoading = false
            return
        }

        guard let currentUser = supabase.currentUser else {
            finalizeAccess(.noAccess, status: .noAccess)
            AppLogger.log("⚠️ [Access] Sem usuário logado.", category: .auth)
            return
        }

        if supabase.userProfile == nil {
            await supabase.fetchUserProfile()
        }

        if Task.isCancelled {
            isLoading = false
            return
        }

        guard let profile = supabase.userProfile else {
            if let cached = loadAccessStateFromCache() {
                AppLogger.log("⚠️ [Access] Perfil ausente, usando cache de acesso: \(cached.planType.displayName)", category: .business)
                let status: AccessStatus = cached.hasAccess ? .unknown : .noAccess
                finalizeAccess(cached, status: status)
                return
            }

            finalizeAccess(.noAccess, status: .unknown)
            AppLogger.error("[Access] Falha ao carregar perfil e sem cache de acesso.")
            return
        }

        AppLogger.log("🔐 [Access] Iniciando verificação híbrida para: \(profile.nameForDisplay)", category: .business)

        // PASSO 1: Staff
        let staffCheck = SubscriptionLogic.checkStaffAccess(profile: profile)
        if let finalState = staffCheck.access {
            AppLogger.log("🚫 [Access] Decisão no passo Staff: \(finalState.planType)", category: .business)
            finalizeAccess(finalState, status: finalState.hasAccess ? .hasAccess : .noAccess)
            return
        }

        let targetUserId = staffCheck.targetUserId ?? currentUser.id.uuidString
        if staffCheck.isStaff {
            AppLogger.log("👨‍⚕️ [Access] Staff detectado. Verificando assinaturas do dono: \(targetUserId)", category: .business)
        }

        // PASSO 2: Stripe/Web no banco
        do {
            let subscriptions: [UserSubscription] = try await supabase.client
                .from("user_subscriptions")
                .select()
                .eq("user_id", value: targetUserId)
                .in("status", values: [SubscriptionStatus.active.rawValue, SubscriptionStatus.pendingCancellation.rawValue])
                .execute()
                .value

            AppLogger.log("📋 [Access] Assinaturas encontradas: \(subscriptions.count)", category: .business)

            if let activeState = SubscriptionLogic.evaluateSubscriptions(subscriptions) {
                AppLogger.log("✅ [Access] Assinatura VÁLIDA encontrada: \(activeState.planType.displayName)", category: .business)
                finalizeAccess(activeState, status: .hasAccess)
                return
            }

            AppLogger.log("⚠️ [Access] Nenhuma assinatura válida encontrada.", category: .business)

        } catch {
            AppLogger.error("[Access] Erro ao buscar assinaturas: \(error)")

            if previousAccessState.hasAccess {
                finalizeAccess(previousAccessState, status: .unknown)
                return
            }

            if let cached = loadAccessStateFromCache() {
                finalizeAccess(cached, status: .unknown)
                return
            }

            let isNetworkError =
                error.localizedDescription.lowercased().contains("network") ||
                error.localizedDescription.lowercased().contains("connection") ||
                error.localizedDescription.lowercased().contains("offline") ||
                error.localizedDescription.lowercased().contains("internet")

            if isNetworkError {
                finalizeAccess(.noAccess, status: .unknown)
                return
            }
        }

        if Task.isCancelled {
            isLoading = false
            return
        }

        // PASSO 3: Apple IAP
        if let appleState = await checkAppleSubscription() {
            AppLogger.log("✅ [Access] Assinatura Apple ativa: \(appleState.planType.displayName)", category: .business)
            finalizeAccess(appleState, status: .hasAccess)
            return
        }

        // PASSO 3.5: is_premium flag
        if profile.isPremium {
            AppLogger.log("✅ [Access] Usuário premium via Backend (is_premium flag)", category: .business)
            finalizeAccess(.active(plan: .premium, expiresAt: nil, isCourtesy: false, source: .backend), status: .hasAccess)
            return
        }

        // PASSO 4: Cortesia revogada
        do {
            let cancelledSubs: [UserSubscription] = try await supabase.client
                .from("user_subscriptions")
                .select()
                .eq("user_id", value: targetUserId)
                .eq("status", value: SubscriptionStatus.cancelled.rawValue)
                .eq("discount_percentage", value: 100)
                .limit(1)
                .execute()
                .value

            if SubscriptionLogic.checkRevokedCourtesy(cancelledSubs) {
                AppLogger.log("🚫 [Access] Cortesia revogada detectada. Trial bloqueado.", category: .business)
                finalizeAccess(.noAccess, status: .noAccess)
                return
            }
        } catch {
            AppLogger.error("[Access] Erro no check anti-abuso: \(error)")
        }

        // PASSO 5: Trial
        if staffCheck.isStaff {
            AppLogger.log("🚫 [Access] Staff sem assinatura ativa do dono. Trial não aplicável.", category: .business)
            finalizeAccess(.noAccess, status: .noAccess)
            return
        }

        var trialMeta: String?
        if let jsonValue = currentUser.userMetadata["trial_end_date"] {
            if case .string(let value) = jsonValue {
                trialMeta = value
            }
        }

        let trialState = SubscriptionLogic.checkTrial(createdAt: currentUser.createdAt, trialEndDateMetadata: trialMeta)

        if trialState.isInTrial {
            AppLogger.log("🎁 [Access] Período de Trial VÁLIDO.", category: .business)
            finalizeAccess(trialState, status: .hasAccess)
        } else {
            AppLogger.log("⏰ [Access] Trial expirado.", category: .business)
            finalizeAccess(.noAccess, status: .noAccess)
        }
    }

    // MARK: - StoreKit: Verificação Apple
    private func checkAppleSubscription() async -> AccessState? {
        var bestSubscription: (productID: String, planType: PlanType, expirationDate: Date?)?

        for await result in Transaction.currentEntitlements {
            switch result {
            case .verified(let transaction):
                if productIds.contains(transaction.productID) {
                    let planType = PlanType.fromAppleProductId(transaction.productID)
                    let expirationDate = transaction.expirationDate

                    if bestSubscription == nil || planType.tierLevel > bestSubscription!.planType.tierLevel {
                        bestSubscription = (transaction.productID, planType, expirationDate)
                    }
                }
            case .unverified(_, let error):
                AppLogger.error("[StoreKit] Transação não verificada: \(error)")
            }
        }

        if let best = bestSubscription {
            return .active(plan: best.planType, expiresAt: best.expirationDate, isCourtesy: false, source: .apple)
        }

        return nil
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
    func purchase(_ product: Product) async {
        purchaseState = .purchasing
        errorMessage = nil

        do {
            let result = try await product.purchase()
            switch result {
            case .success(let verification):
                switch verification {
                case .verified(let transaction):
                    let syncSuccess = await syncWithBackend(transaction: transaction)

                    if syncSuccess {
                        await transaction.finish()
                        await supabase.fetchUserProfile()
                    }

                    // ✅ use refreshAccess para evitar concorrência
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

            if let _ = await checkAppleSubscription() {
                for await result in Transaction.currentEntitlements {
                    if case .verified(let transaction) = result,
                       productIds.contains(transaction.productID) {
                        _ = await syncWithBackend(transaction: transaction)
                        break
                    }
                }

                refreshAccess()
                purchaseState = .success
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
    private func syncWithBackend(transaction: Transaction) async -> Bool {
        guard let userId = supabase.currentUser?.id.uuidString else { return false }

        let payload: [String: Any] = [
            "user_id": userId,
            "transaction_id": String(transaction.id),
            "original_transaction_id": String(transaction.originalID),
            "product_id": transaction.productID,
            "purchase_date": ISO8601DateFormatter().string(from: transaction.purchaseDate),
            "expiration_date": transaction.expirationDate.map { ISO8601DateFormatter().string(from: $0) } ?? "",
            "jws_token": transaction.jsonRepresentation.base64EncodedString(),
            "environment": transaction.environment.rawValue
        ]

        return await sendToBackend(payload: payload, retries: 3)
    }

    private func sendToBackend(payload: [String: Any], retries: Int) async -> Bool {
        guard retries > 0 else { return false }
        guard let url = URL(string: receiptEndpoint) else { return false }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        if let accessToken = supabase.currentSession?.accessToken {
            request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        }

        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: payload)
            let (_, response) = try await URLSession.shared.data(for: request)

            if let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) {
                return true
            }

            try await Task.sleep(nanoseconds: 2_000_000_000)
            return await sendToBackend(payload: payload, retries: retries - 1)
        } catch {
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            return await sendToBackend(payload: payload, retries: retries - 1)
        }
    }

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
            let syncSuccess = await syncWithBackend(transaction: transaction)
            if syncSuccess { await transaction.finish() }

            // ✅ usa refreshAccess para não “brigar” com checks em andamento
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

        if status == .hasAccess || status == .noAccess {
            self.lastVerifiedAt = Date()
            self.lastVerifiedHadAccess = (status == .hasAccess)
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

    var hasComputedAccess: Bool {
        if accessStatus == .hasAccess { return true }
        if accessStatus == .noAccess { return false }

        if accessStatus == .unknown {
            guard lastVerifiedHadAccess else { return false }

            if let lastVerified = lastVerifiedAt {
                let hoursSince = Date().timeIntervalSince(lastVerified) / 3600
                return hoursSince < offlineGraceHours
            }
            return false
        }

        return false
    }

    var shouldShowPaywall: Bool {
        didFinishInitialAccessCheck && !hasComputedAccess && !isLoading
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
