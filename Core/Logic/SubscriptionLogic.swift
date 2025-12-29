import Foundation

/// Encapsula a lógica pura de verificação de acesso, facilitando testes unitários
struct SubscriptionLogic {
    
    // Configurações
    static let paidGracePeriodDays = 5
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
        // Se status for past_due, geralmente bloqueamos ou damos grace period? 
        // A regra diz: active com grace period.
        
        if sub.status == .pendingCancellation {
             guard let nextBilling = sub.nextBillingDate else { return false }
             return referenceDate <= nextBilling
        }
        
        if sub.status == .active {
            guard let nextBilling = sub.nextBillingDate else { return true } // Se active e sem data, assume valido
            
            let gracePeriod = Calendar.current.date(byAdding: .day, value: paidGracePeriodDays, to: nextBilling) ?? nextBilling
            return referenceDate <= gracePeriod
        }
        
        return false
    }
    
    /// Avalia a lista de assinaturas para encontrar a melhor válida
    static func evaluateSubscriptions(_ subscriptions: [UserSubscription], referenceDate: Date = Date()) -> AccessState? {
        // A filtragem e ordenação (Passo 2) idealmente já vem do banco, mas podemos garantir aqui
        // Ordem: discount ASC, created DESC
        let sorted = subscriptions.sorted {
            if ($0.discountPercentage ?? 0) != ($1.discountPercentage ?? 0) {
                return ($0.discountPercentage ?? 0) < ($1.discountPercentage ?? 0)
            }
            return $0.createdAt > $1.createdAt
        }
        
        for sub in sorted {
            if validateSubscription(sub, referenceDate: referenceDate) {
                return .active(plan: sub.planType, expiresAt: sub.nextBillingDate, isCourtesy: sub.isCourtesy)
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
