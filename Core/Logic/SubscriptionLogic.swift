import Foundation

/// Encapsula a lógica pura de verificação de acesso, facilitando testes unitários
struct SubscriptionLogic {
    
    // Configurações
    static let paidGracePeriodDays = 3 // Atualizado para 3 dias conforme Web
    static let trialDurationDays = 7
    
    // MARK: - Passos de Verificação
    
    /// Passo 1: Verifica se é Staff
    static func checkStaffAccess(profile: UserProfile?) -> (isStaff: Bool, targetUserId: String?, access: AccessState?) {
        guard let profile = profile else { return (false, nil, .noAccess) }
        
        if profile.role == .staff {
            if !profile.isActive {
                return (true, nil, .noAccess) // Staff inativo = Bloqueado
            }
            if let clinicId = profile.clinicId {
                return (true, clinicId, nil) // Staff ativo com clínica = Verificar dono
            } else {
                return (true, nil, .noAccess) // Staff sem clínica = Bloqueado
            }
        }
        
        // Não é staff, target é ele mesmo (nil indica usar current user)
        return (false, nil, nil)
    }
    
    /// Passo 3: Valida Assinatura
    static func validateSubscription(_ sub: UserSubscription, referenceDate: Date = Date()) -> Bool {
        // Cortesia (100% OFF)
        if sub.isCourtesy {
            return sub.status == .active
        }
        
        // Assinatura Paga
        // Se status for pending_cancellation, usuário tem acesso até a data final
        if sub.status == .pendingCancellation {
             guard let nextBilling = sub.nextBillingDate else { return false }
             // Acesso vai até o fim do período (next_billing_date) EXATO
             return referenceDate <= nextBilling
        }
        
        // Se status active, CONFIAMOS no status do Stripe/Supabase
        // O Webhook do Stripe se encarrega de mudar para past_due ou unpaid se falhar
        if sub.status == .active {
            return true
        }
        
        return false
    }
    
    /// Avalia a lista de assinaturas para encontrar a melhor válida
    static func evaluateSubscriptions(_ subscriptions: [UserSubscription], referenceDate: Date = Date()) -> AccessState? {
        // Ordenação conforme Regra Web:
        // 1. discount_percentage ASC (nulls first) - Paga (0 ou null) < Cortesia (100)
        // 2. created_at DESC - Mais recente primeiro
        let sorted = subscriptions.sorted { sub1, sub2 in
            let d1 = sub1.discountPercentage ?? 0 // Tratando null como 0 (pago total)
            let d2 = sub2.discountPercentage ?? 0
            
            if d1 != d2 {
                return d1 < d2 // ASC
            }
            
            return sub1.createdAt > sub2.createdAt // DESC
        }
        
        for sub in sorted {
            if validateSubscription(sub, referenceDate: referenceDate) {
                // A struct UserSubscription agora calcula o planType baseado na lógica da Web
                return .active(plan: sub.planType, expiresAt: sub.nextBillingDate, isCourtesy: sub.isCourtesy, source: .backend)
            }
        }
        
        return nil
    }
    
    /// Passo 4: Verifica Anti-Abuso (Cortesia Revogada)
    static func checkRevokedCourtesy(_ cancelledSubscriptions: [UserSubscription]) -> Bool {
        // Procura alguma que foi 100% off e está cancelled
        return cancelledSubscriptions.contains { $0.discountPercentage == 100 && $0.status == .cancelled }
    }
    
    /// Passo 5: Verifica Trial
    static func checkTrial(createdAt: Date, trialEndDateMetadata: String?, referenceDate: Date = Date()) -> AccessState {
        var trialEndDate: Date
        
        if let dateStr = trialEndDateMetadata {
            // Tenta parse
             let formatter = ISO8601DateFormatter()
             formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let date = formatter.date(from: dateStr) {
                trialEndDate = date
            } else {
                 formatter.formatOptions = [.withInternetDateTime]
                 if let date = formatter.date(from: dateStr) {
                     trialEndDate = date
                 } else {
                     // Metadata inválido, fallback para created_at rules
                     trialEndDate = Calendar.current.date(byAdding: .day, value: trialDurationDays, to: createdAt) ?? createdAt
                 }
            }
        } else {
            // Sem metadata, usa regra padrão: Created + 7 dias
            trialEndDate = Calendar.current.date(byAdding: .day, value: trialDurationDays, to: createdAt) ?? createdAt
        }
        
        if referenceDate <= trialEndDate {
            return .trial(until: trialEndDate)
        } else {
            return .noAccess
        }
    }
}
