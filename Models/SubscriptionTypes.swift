import Foundation

/// Tipos de plano disponíveis no sistema
enum PlanType: String, Codable, CaseIterable {
    case basic = "basic"
    case pro = "pro"
    case premium = "premium"
    case courtesy = "courtesy" // Plano cortesia (100% OFF)
    case trial = "trial"       // Período de testes
    case none = "none"         // Sem plano ativo
    
    var displayName: String {
        switch self {
        case .basic: return "Básico"
        case .pro: return "Pro"
        case .premium: return "Premium"
        case .courtesy: return "Cortesia"
        case .trial: return "Período de Testes"
        case .none: return "Sem Plano"
        }
    }
}

/// Estado de acesso do usuário após verificação
struct AccessState {
    let hasActiveSubscription: Bool
    let isInTrial: Bool
    let isCourtesy: Bool
    let planType: PlanType
    let expirationDate: Date? // Data de expiração ou próxima cobrança
    
    /// Inicializador padrão para estado "sem acesso"
    static let noAccess = AccessState(
        hasActiveSubscription: false,
        isInTrial: false,
        isCourtesy: false,
        planType: .none,
        expirationDate: nil
    )
    
    /// Inicializador para Trial
    static func trial(until date: Date) -> AccessState {
        AccessState(
            hasActiveSubscription: true,
            isInTrial: true,
            isCourtesy: false,
            planType: .trial,
            expirationDate: date
        )
    }
    
    /// Inicializador para Assinatura Ativa
    static func active(plan: PlanType, expiresAt: Date?, isCourtesy: Bool = false) -> AccessState {
        AccessState(
            hasActiveSubscription: true,
            isInTrial: false,
            isCourtesy: isCourtesy,
            planType: plan,
            expirationDate: expiresAt
        )
    }
}
