import Foundation
import StoreKit
import Supabase

/// Gerenciador de Assinaturas Híbridas
/// Suporta assinaturas via Backend (Stripe) e Apple IAP (StoreKit 2)
@MainActor
class SubscriptionManager: ObservableObject {
    static let shared = SubscriptionManager()
    
    // MARK: - Published Properties
    
    /// Estado atual de acesso do usuário
    @Published var accessState: AccessState = .noAccess
    
    /// Estado anterior (para preservar em caso de erro de rede)
    private var previousAccessState: AccessState = .noAccess
    
    /// Produtos disponíveis para compra via Apple
    @Published var storeProducts: [Product] = []
    
    /// Indica se está carregando informações
    @Published var isLoading = false
    
    /// Mensagem de erro, se houver
    @Published var errorMessage: String?
    
    /// Estado atual da compra
    @Published var purchaseState: PurchaseState = .idle
    
    // MARK: - Private Properties
    
    private let supabase = SupabaseManager.shared
    
    /// IDs dos produtos no App Store Connect
    private let productIds: Set<String> = [
        "com.agendahof.basic",
        "com.agendahof.pro",
        "com.agendahof.premium"
    ]
    
    /// Endpoint do backend para receber recibos Apple (Supabase Edge Function)
    private let receiptEndpoint = "https://zgdxszwjbbxepsvyjtrb.supabase.co/functions/v1/ios-receipt"
    
    /// Listener de transações
    private var transactionListener: Task<Void, Error>?
    
    // Configurações
    private let courtesyGracePeriodDays = 0
    private let paidGracePeriodDays = 5
    private let trialDurationDays = 7
    
    // MARK: - Initialization
    
    private init() {
        // Iniciar listener de transações (detached para não bloquear init)
        transactionListener = listenForTransactions()
        
        // Carregar produtos ao inicializar
        Task {
            await loadProducts()
        }
    }
    
    deinit {
        transactionListener?.cancel()
    }
    
    // MARK: - Verificação Híbrida de Acesso (Source of Truth)
    
    /// Algoritmo Mestre de Verificação de Acesso (Híbrido)
    /// 1. Verifica Backend primeiro (is_premium do Stripe)
    /// 2. Se não premium no backend, verifica StoreKit 2
    /// 3. Fallback para lógica existente (trial, etc.)
    func checkAccess() async {
        isLoading = true
        errorMessage = nil
        
        // Garante que temos usuário logado
        guard let currentUser = supabase.currentUser else {
            accessState = .noAccess
            isLoading = false
            AppLogger.log("⚠️ [Access] Sem usuário logado.", category: .auth)
            return
        }
        
        // Se o perfil ainda não carregou, tenta carregar
        if supabase.userProfile == nil {
            await supabase.fetchUserProfile()
        }
        
        guard let profile = supabase.userProfile else {
            accessState = .noAccess
            isLoading = false
            AppLogger.error("[Access] Falha ao carregar perfil para verificação.")
            return
        }
        
        AppLogger.log("🔐 [Access] Iniciando verificação híbrida para: \(profile.nameForDisplay)", category: .business)
        
        // ---------------------------------------------------------
        // PASSO 1: Verificar se é Staff (Funcionário)
        // ---------------------------------------------------------
        let staffCheck = SubscriptionLogic.checkStaffAccess(profile: profile)
        
        if let finalState = staffCheck.access {
            AppLogger.log("🚫 [Access] Decisão no passo Staff: \(finalState.planType)", category: .business)
            finalizeAccess(finalState)
            return
        }
        
        // Se isStaff é true e passou, staffCheck.targetUserId tem o ID do dono
        let targetUserId = staffCheck.targetUserId ?? currentUser.id.uuidString
        
        if staffCheck.isStaff {
            AppLogger.log("👨‍⚕️ [Access] Staff detectado. Verificando assinaturas do dono: \(targetUserId)", category: .business)
        }
        
        // ---------------------------------------------------------
        // PASSO 2: Buscar e Validar Assinaturas do Banco (Stripe/Web)
        // PRIORIDADE: Verifica assinaturas Stripe antes de Apple IAP
        // ---------------------------------------------------------
        do {
            let subscriptions: [UserSubscription] = try await supabase.client
                .from("user_subscriptions")
                .select()
                .eq("user_id", value: targetUserId)
                .in("status", values: [SubscriptionStatus.active.rawValue, SubscriptionStatus.pendingCancellation.rawValue])
                .execute()
                .value
            
            AppLogger.log("📋 [Access] Assinaturas encontradas: \(subscriptions.count)", category: .business)
            
            for (index, sub) in subscriptions.enumerated() {
                AppLogger.log("   [\(index)] ID: \(sub.id), Status: \(sub.status.rawValue), PlanID: \(sub.planId ?? "nil"), Desconto: \(sub.discountPercentage ?? 0)%", category: .business)
            }
            
            if let activeState = SubscriptionLogic.evaluateSubscriptions(subscriptions) {
                AppLogger.log("✅ [Access] Assinatura VÁLIDA encontrada: \(activeState.planType.displayName)", category: .business)
                finalizeAccess(activeState)
                return
            }
            
            AppLogger.log("⚠️ [Access] Nenhuma assinatura válida encontrada.", category: .business)
            
        } catch {
            // ✅ MELHORIA: Em caso de erro de rede, preservar estado anterior
            let isNetworkError = error.localizedDescription.lowercased().contains("network") ||
                                 error.localizedDescription.lowercased().contains("connection") ||
                                 error.localizedDescription.lowercased().contains("timeout") ||
                                 error.localizedDescription.lowercased().contains("offline")
            
            if isNetworkError && previousAccessState.hasAccess {
                AppLogger.log("⚠️ [Access] Erro de rede, mantendo estado anterior: \(previousAccessState.planType.displayName)", category: .business)
                finalizeAccess(previousAccessState)
                return
            }
            
            AppLogger.error("[Access] Erro ao buscar assinaturas: \(error)")
        }
        
        // ---------------------------------------------------------
        // PASSO 3: Verificar Apple IAP (Fallback - após Stripe)
        // Apple IAP tem prioridade MENOR que assinaturas Stripe do banco
        // ---------------------------------------------------------
        if let appleState = await checkAppleSubscription() {
            AppLogger.log("✅ [Access] Assinatura Apple ativa: \(appleState.planType.displayName)", category: .business)
            finalizeAccess(appleState)
            return
        }
        
        // ---------------------------------------------------------
        // PASSO 3.5: Verificar is_premium do Backend (Fallback genérico)
        // ---------------------------------------------------------
        if profile.isPremium {
            AppLogger.log("✅ [Access] Usuário premium via Backend (is_premium flag)", category: .business)
            finalizeAccess(.active(plan: .premium, expiresAt: nil, isCourtesy: false, source: .backend))
            return
        }
        
        // ---------------------------------------------------------
        // PASSO 4: Verificar Cortesia Revogada (Anti-Abuso)
        // ---------------------------------------------------------
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
                finalizeAccess(.noAccess)
                return
            }
        } catch {
            AppLogger.error("[Access] Erro no check anti-abuso: \(error)")
        }
        
        // ---------------------------------------------------------
        // PASSO 5: Verificar Período de Teste (Trial)
        // ---------------------------------------------------------
        
        // Se for staff e não achou assinatura, bloqueia
        if staffCheck.isStaff {
            AppLogger.log("🚫 [Access] Staff sem assinatura ativa do dono. Trial não aplicável.", category: .business)
            finalizeAccess(.noAccess)
            return
        }
        
        // Checa metadata trial_end_date
        var trialMeta: String?
        if let jsonValue = currentUser.userMetadata["trial_end_date"] {
            switch jsonValue {
            case .string(let value):
                trialMeta = value
            default:
                trialMeta = nil
            }
        }
        
        let trialState = SubscriptionLogic.checkTrial(createdAt: currentUser.createdAt, trialEndDateMetadata: trialMeta)
        
        if trialState.isInTrial {
            AppLogger.log("🎁 [Access] Período de Trial VÁLIDO.", category: .business)
            finalizeAccess(trialState)
        } else {
            AppLogger.log("⏰ [Access] Trial expirado.", category: .business)
            finalizeAccess(.noAccess)
        }
    }
    
    // MARK: - StoreKit 2 - Verificação de Assinatura Apple
    
    /// Verifica se existe assinatura ativa via StoreKit 2
    private func checkAppleSubscription() async -> AccessState? {
        var bestSubscription: (productID: String, planType: PlanType, expirationDate: Date?)? = nil
        
        // Itera sobre os entitlements ativos
        for await result in Transaction.currentEntitlements {
            switch result {
            case .verified(let transaction):
                // Verificar se é uma assinatura dos nossos produtos
                if productIds.contains(transaction.productID) {
                    let planType = PlanType.fromAppleProductId(transaction.productID)
                    let expirationDate = transaction.expirationDate
                    
                    AppLogger.log("🍎 [StoreKit] Encontrada assinatura Apple: \(transaction.productID)", category: .business)
                    
                    // Se ainda não temos nenhuma OU esta é de tier superior, guarda
                    if bestSubscription == nil || planType.tierLevel > bestSubscription!.planType.tierLevel {
                        bestSubscription = (transaction.productID, planType, expirationDate)
                    }
                }
            case .unverified(_, let error):
                AppLogger.error("[StoreKit] Transação não verificada: \(error)")
            }
        }
        
        // Retornar a melhor assinatura encontrada
        if let best = bestSubscription {
            AppLogger.log("🍎 [StoreKit] Assinatura Apple válida: \(best.productID) (\(best.planType.displayName))", category: .business)
            
            return .active(
                plan: best.planType,
                expiresAt: best.expirationDate,
                isCourtesy: false,
                source: .apple
            )
        }
        
        return nil
    }
    
    // MARK: - StoreKit 2 - Carregamento de Produtos
    
    /// Carrega os produtos disponíveis do App Store
    func loadProducts() async {
        guard storeProducts.isEmpty else { return }
        
        do {
            let products = try await Product.products(for: productIds)
            
            // Ordenar por preço (básico -> pro -> premium)
            storeProducts = products.sorted { $0.price < $1.price }
            
            AppLogger.log("🍎 [StoreKit] \(products.count) produtos carregados", category: .business)
            
            for product in storeProducts {
                AppLogger.log("   - \(product.id): \(product.displayPrice)", category: .business)
            }
            
        } catch {
            AppLogger.error("[StoreKit] Erro ao carregar produtos: \(error)")
            errorMessage = "Não foi possível carregar os planos. Tente novamente."
        }
    }
    
    // MARK: - StoreKit 2 - Compra
    
    /// Processa a compra de um produto
    /// - Parameter product: Produto a ser comprado
    func purchase(_ product: Product) async {
        purchaseState = .purchasing
        errorMessage = nil
        
        do {
            let result = try await product.purchase()
            
            switch result {
            case .success(let verification):
                switch verification {
                case .verified(let transaction):
                    AppLogger.log("✅ [StoreKit] Compra verificada: \(transaction.productID)", category: .business)
                    
                    // Sincronizar com backend (Tentar sync primeiro)
                    // Se falhar, NÃO finalizamos a transação para que o listener tente novamente depois
                    let syncSuccess = await syncWithBackend(transaction: transaction)
                    
                    if syncSuccess {
                        await transaction.finish()
                        AppLogger.log("✅ [StoreKit] Transação finalizada após sync com sucesso", category: .business)
                        
                        // ✅ CRÍTICO: Recarregar perfil para pegar is_premium atualizado
                        await supabase.fetchUserProfile()
                        AppLogger.log("🔄 [StoreKit] Perfil recarregado após compra", category: .business)
                    } else {
                        AppLogger.error("[StoreKit] Sync falhou. Transação mantida aberta para retentativa.")
                        // Não finalizamos a transação aqui. O listener pegará novamente.
                        // Mas para o usuário, podemos liberar o acesso TEMPORARIAMENTE se a validação local passar.
                    }
                    
                    // Atualizar estado de acesso
                    await checkAccess()
                    
                    purchaseState = .success
                    
                case .unverified(_, let error):
                    AppLogger.error("[StoreKit] Compra não verificada: \(error)")
                    purchaseState = .failed("Não foi possível verificar a compra. Tente novamente.")
                    errorMessage = "Não foi possível verificar a compra."
                }
                
            case .userCancelled:
                AppLogger.log("ℹ️ [StoreKit] Compra cancelada pelo usuário", category: .business)
                purchaseState = .cancelled
                
            case .pending:
                AppLogger.log("⏳ [StoreKit] Compra pendente de aprovação", category: .business)
                purchaseState = .failed("Compra pendente de aprovação (ex: Ask to Buy).")
                errorMessage = "Compra pendente de aprovação."
                
            @unknown default:
                purchaseState = .failed("Erro desconhecido na compra.")
            }
            
        } catch {
            AppLogger.error("[StoreKit] Erro na compra: \(error)")
            purchaseState = .failed(error.localizedDescription)
            errorMessage = "Erro ao processar compra: \(error.localizedDescription)"
        }
    }
    
    // MARK: - StoreKit 2 - Restaurar Compras
    
    /// Restaura compras anteriores
    func restorePurchases() async {
        purchaseState = .restoring
        errorMessage = nil
        
        do {
            // Sincroniza com a App Store
            try await AppStore.sync()
            
            AppLogger.log("🔄 [StoreKit] Sincronização com App Store concluída", category: .business)
            
            // Verificar se há assinaturas agora
            if let appleState = await checkAppleSubscription() {
                AppLogger.log("✅ [StoreKit] Assinatura restaurada: \(appleState.planType.displayName)", category: .business)
                
                // Sincronizar com backend
                for await result in Transaction.currentEntitlements {
                    if case .verified(let transaction) = result {
                        if productIds.contains(transaction.productID) {
                            await syncWithBackend(transaction: transaction)
                            break
                        }
                    }
                }
                
                await checkAccess()
                purchaseState = .success
            } else {
                AppLogger.log("ℹ️ [StoreKit] Nenhuma assinatura encontrada para restaurar", category: .business)
                purchaseState = .failed("Nenhuma assinatura anterior encontrada.")
                errorMessage = "Nenhuma assinatura anterior encontrada."
            }
            
        } catch {
            AppLogger.error("[StoreKit] Erro ao restaurar compras: \(error)")
            purchaseState = .failed(error.localizedDescription)
            errorMessage = "Erro ao restaurar compras: \(error.localizedDescription)"
        }
    }
    
    // MARK: - Sincronização com Backend
    
    /// Envia o recibo/token da transação Apple para o backend
    /// Isso permite que o backend atualize is_premium e libere acesso na web
    /// - Returns: `true` se sincronizou com sucesso, `false` caso contrário
    private func syncWithBackend(transaction: Transaction) async -> Bool {
        guard let userId = supabase.currentUser?.id.uuidString else {
            AppLogger.error("[Sync] Sem usuário logado para sincronizar")
            return false
        }
        
        AppLogger.log("📤 [Sync] Enviando transação Apple para backend...", category: .business)
        
        // Obter o JWS Token (JSON Web Signature) da transação
        // Note: transaction.jsonRepresentation.base64EncodedString() já faz a conversão direta
        
        // Preparar payload
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
        
        // Enviar para o backend com retry
        return await sendToBackend(payload: payload, retries: 3)
    }
    
    /// Envia payload para o backend com retry
    /// - Returns: `true` se sucesso, `false` se falha
    private func sendToBackend(payload: [String: Any], retries: Int) async -> Bool {
        guard retries > 0 else {
            AppLogger.error("[Sync] Falha após todas as tentativas de sincronização")
            return false
        }
        
        guard let url = URL(string: receiptEndpoint) else {
            AppLogger.error("[Sync] URL inválida: \(receiptEndpoint)")
            return false
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        // Adicionar token de autenticação se disponível
        if let accessToken = supabase.currentSession?.accessToken {
            request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        }
        
        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: payload)
            
            let (_, response) = try await URLSession.shared.data(for: request)
            
            if let httpResponse = response as? HTTPURLResponse {
                if (200...299).contains(httpResponse.statusCode) {
                    AppLogger.log("✅ [Sync] Transação sincronizada com backend (status: \(httpResponse.statusCode))", category: .business)
                    return true
                } else {
                    AppLogger.error("[Sync] Backend retornou status \(httpResponse.statusCode). Tentando novamente...")
                    try await Task.sleep(nanoseconds: 2_000_000_000) // 2 segundos
                    return await sendToBackend(payload: payload, retries: retries - 1)
                }
            }
            
            return false // Fallback se não for HTTPURLResponse (raro)
            
        } catch {
            AppLogger.error("[Sync] Erro ao enviar para backend: \(error). Tentando novamente...")
            try? await Task.sleep(nanoseconds: 2_000_000_000) // 2 segundos
            return await sendToBackend(payload: payload, retries: retries - 1)
        }
    }
    
    // MARK: - Transaction Listener
    
    /// Escuta transações em background (renovações automáticas, etc.)
    private func listenForTransactions() -> Task<Void, Error> {
        return Task.detached {
            for await result in Transaction.updates {
                await self.handleTransactionUpdate(result)
            }
        }
    }
    
    /// Processa atualizações de transações
    private func handleTransactionUpdate(_ result: VerificationResult<Transaction>) async {
        switch result {
        case .verified(let transaction):
            AppLogger.log("🔔 [StoreKit] Atualização de transação: \(transaction.productID)", category: .business)
            
            // Sincronizar com backend (Tentar sync primeiro)
            let syncSuccess = await syncWithBackend(transaction: transaction)
            
            // Só finaliza se sincronizou com sucesso
            if syncSuccess {
                await transaction.finish()
                AppLogger.log("✅ [StoreKit] Transação finalizada e sincronizada via Listener", category: .business)
            } else {
                AppLogger.error("[StoreKit] Sync falhou no Listener. Transação mantida na fila.")
            }
            
            // Atualizar estado
            await checkAccess()
            
        case .unverified(_, let error):
            AppLogger.error("[StoreKit] Transação não verificada: \(error)")
        }
    }
    
    // MARK: - Helpers
    
    private func finalizeAccess(_ state: AccessState) {
        // Salvar estado anterior antes de atualizar (para preservar em erros de rede)
        if self.accessState.hasAccess {
            self.previousAccessState = self.accessState
        }
        self.accessState = state
        self.isLoading = false
    }
    
    /// Reseta o estado de compra para idle
    func resetPurchaseState() {
        purchaseState = .idle
        errorMessage = nil
    }
    
    /// Verifica se o usuário precisa ver o paywall
    var shouldShowPaywall: Bool {
        !accessState.hasAccess && !isLoading
    }
    
    /// Retorna o produto recomendado (Premium - melhor custo-benefício)
    var recommendedProduct: Product? {
        storeProducts.first { $0.id == "com.agendahof.premium" }
    }
}
