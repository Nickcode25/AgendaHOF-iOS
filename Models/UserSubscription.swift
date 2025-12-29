import Foundation

enum SubscriptionStatus: String, Codable {
    case active = "active"
    case pendingCancellation = "pending_cancellation"
    case cancelled = "cancelled"
    case pastDue = "past_due"
    case expired = "expired"
    // Outros status do Stripe podem ser adicionados conforme necessário
}

/// Representa uma assinatura na tabela 'user_subscriptions' do Supabase
struct UserSubscription: Identifiable, Codable {
    let id: String
    let userId: String
    let planId: String? // Pode ser null no banco
    let status: SubscriptionStatus
    let discountPercentage: Int?
    let currentPeriodStart: Date? // Pode ser null no banco
    let currentPeriodEnd: Date? // Pode ser null no banco
    let nextBillingDate: Date? // Importante para validação
    let createdAt: Date
    let updatedAt: Date
    
    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case planId = "plan_id"
        case status
        case discountPercentage = "discount_percentage"
        case currentPeriodStart = "current_period_start"
        case currentPeriodEnd = "current_period_end"
        case nextBillingDate = "next_billing_date"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

// Extensão para lógica de validação
extension UserSubscription {
    /// Verifica se é uma cortesia (100% de desconto)
    var isCourtesy: Bool {
        return discountPercentage == 100
    }
    
    /// Tenta inferir o tipo de plano baseado no ID do plano (string)
    /// Ajuste conforme os IDs reais do seu Stripe/Supabase
    var planType: PlanType {
        guard let planId = planId else { 
            // Se não tem plan_id, mas tem desconto 100%, é cortesia
            if isCourtesy { return .courtesy }
            return .basic // Default seguro
        }
        
        let lowerPlanId = planId.lowercased()
        if lowerPlanId.contains("premium") { return .premium }
        if lowerPlanId.contains("pro") { return .pro }
        if lowerPlanId.contains("basic") { return .basic }
        
        // Se é cortesia mas tem plan_id, ainda retorna courtesy
        if isCourtesy { return .courtesy }
        
        return .basic // Default seguro
    }
}
