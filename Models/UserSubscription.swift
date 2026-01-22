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
    
    let planTypeString: String? // Campo 'plan_type' do banco
    let planName: String?       // Campo 'plan_name' do banco
    let planAmount: Double?     // Campo 'plan_amount' do banco
    
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
        case planTypeString = "plan_type"
        case planName = "plan_name"
        case planAmount = "plan_amount"
    }
}

// Extensão para lógica de validação
extension UserSubscription {
    /// Verifica se é uma cortesia (100% de desconto)
    var isCourtesy: Bool {
        return discountPercentage == 100
    }
    
    /// Determina o plano seguindo a lógica do Web (Prioridades 1, 2, 3)
    var planType: PlanType {
        // Checagem de Cortesia
        if isCourtesy { return .courtesy }
        
        // Prioridade 1: Pelo plan_type (com correção de valores)
        if let type = planTypeString?.lowercased() {
             let amount = planAmount ?? 0.0
             
             if type.contains("basic") {
                 if amount >= 99.00 { return .premium }
                 if amount >= 79.00 { return .pro }
             }
             
             if type.contains("premium") { return .premium }
             if type.contains("pro") { return .pro }
             if type.contains("basic") { return .basic }
        }
        
        // Prioridade 2: Pelo plan_name (Busca por texto)
        if let name = planName?.lowercased() {
            if name.contains("premium") || name.contains("completo") { return .premium }
            if name.contains("pro") || name.contains("profissional") { return .pro }
            if name.contains("basic") || name.contains("básico") || name.contains("basico") { return .basic }
        }
        
        // Prioridade 3: Pelo Preço (plan_amount)
        if let amount = planAmount {
            if amount >= 99.00 { return .premium }
            if amount >= 79.00 { return .pro }
            if amount > 0 { return .basic }
        }
        
        // Fallbacks Legados (se os campos novos não existirem)
        
        // Mapeamento exato dos IDs do Banco de Dados
        if let pid = planId {
            switch pid {
            case "357d1216-1796-40ed-9098-bb7f5cd1a907": return .premium
            case "10312af4-d757-4400-b7c0-f058ac9083d0": return .pro
            case "40864483-0418-4713-8df3-31a003b4d15b": return .basic
            default: break
            }
        }
        
        // Fallback final para Premium se Active mas sem dados (comportamento web legado)
        // CORREÇÃO CRÍTICA (21/01/2026):
        // Se o planId for nulo mas o status for active (vindo do Stripe via Web),
        // assumimos que é um plano Premium legado ou migrado.
        // A Web exibe como Premium, então o App deve espelhar isso.
        if status == .active {
            return .premium
        }
        
        return .basic
    }
}
