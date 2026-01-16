import Foundation
import Supabase

@MainActor
class SubscriptionManager: ObservableObject {
    static let shared = SubscriptionManager()
    
    @Published var accessState: AccessState = .noAccess
    @Published var isLoading = false
    @Published var errorMessage: String?
    
    private let supabase = SupabaseManager.shared
    
    // Configurações
    private let courtesyGracePeriodDays = 0 // Cortesias não tem grace period além do vencimento se não active
    private let paidGracePeriodDays = 5
    private let trialDurationDays = 7
    
    private init() {}
    
    /// Algoritmo Mestre de Verificação de Acesso (5 Passos)
    func checkAccess() async {
        isLoading = true
        errorMessage = nil
        
        // Garante que temos usuário logado e perfil carregado
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
        
        AppLogger.log("🔐 [Access] Iniciando verificação para: \(profile.nameForDisplay) (\(profile.role.rawValue))", category: .business)
        
        // ---------------------------------------------------------
        // PASSO 1: Verificar se é Staff (Funcionário)
        // ---------------------------------------------------------
        let staffCheck = SubscriptionLogic.checkStaffAccess(profile: profile)
        
        if let finalState = staffCheck.access {
            // Se já retornou um estado (ex: bloqueado), finaliza.
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
        // PASSO 2 & 3: Buscar e Validar Assinaturas
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
            
            // Log de cada assinatura para debug
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
            AppLogger.error("[Access] Erro ao buscar assinaturas: \(error)")
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
        
        // Se for staff e não achou assinatura, bloqueia (não herda trial, conforme decisão anterior)
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
    
    // MARK: - Helpers
    
    private func finalizeAccess(_ state: AccessState) {
        self.accessState = state
        self.isLoading = false
    }
}
