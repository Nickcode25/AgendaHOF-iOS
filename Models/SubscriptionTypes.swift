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
    
    /// ID do produto no App Store Connect
    var appleProductId: String? {
        switch self {
        case .basic: return "com.agendahof.basic"
        case .pro: return "com.agendahof.pro"
        case .premium: return "com.agendahof.premium"
        default: return nil
        }
    }
    
    /// Nível hierárquico do plano (para comparação de prioridade)
    var tierLevel: Int {
        switch self {
        case .premium: return 3
        case .pro: return 2
        case .basic: return 1
        case .courtesy: return 0
        case .trial: return 0
        case .none: return 0
        }
    }
    
    /// Mapeia ID do produto Apple para PlanType
    static func fromAppleProductId(_ productId: String) -> PlanType {
        switch productId {
        case "com.agendahof.basic": return .basic
        case "com.agendahof.pro": return .pro
        case "com.agendahof.premium": return .premium
        default: return .none
        }
    }
}

/// Fonte da assinatura ativa
enum SubscriptionSource: String, Codable {
    case backend = "backend"  // Stripe via site
    case apple = "apple"      // IAP via StoreKit 2
    case none = "none"
    
    var displayName: String {
        switch self {
        case .backend: return "Site (Stripe)"
        case .apple: return "Apple"
        case .none: return "Nenhuma"
        }
    }
}

/// Estado da compra em andamento
enum PurchaseState: Equatable {
    case idle
    case purchasing
    case restoring
    case success
    case failed(String)
    case cancelled
}

/// Estado de acesso do usuário após verificação
struct AccessState {
    let hasActiveSubscription: Bool
    let isInTrial: Bool
    let isCourtesy: Bool
    let planType: PlanType
    let expirationDate: Date? // Data de expiração ou próxima cobrança
    let source: SubscriptionSource
    
    /// Inicializador padrão para estado "sem acesso"
    static let noAccess = AccessState(
        hasActiveSubscription: false,
        isInTrial: false,
        isCourtesy: false,
        planType: .none,
        expirationDate: nil,
        source: .none
    )
    
    /// Inicializador para Trial
    static func trial(until date: Date) -> AccessState {
        AccessState(
            hasActiveSubscription: true,
            isInTrial: true,
            isCourtesy: false,
            planType: .trial,
            expirationDate: date,
            source: .none
        )
    }
    
    /// Inicializador para Assinatura Ativa
    static func active(plan: PlanType, expiresAt: Date?, isCourtesy: Bool = false, source: SubscriptionSource = .backend) -> AccessState {
        AccessState(
            hasActiveSubscription: true,
            isInTrial: false,
            isCourtesy: isCourtesy,
            planType: plan,
            expirationDate: expiresAt,
            source: source
        )
    }
    
    /// Verifica se o usuário tem acesso ao app (qualquer tipo de assinatura válida)
    var hasAccess: Bool {
        hasActiveSubscription || isInTrial
    }
}

