import SwiftUI

/// View de exemplo mostrando como usar o SubscriptionManager
/// para bloquear/liberar funcionalidades baseado no plano do usuário
struct ExampleSubscriptionGatedView: View {
    @EnvironmentObject var subscriptionManager: SubscriptionManager
    
    var body: some View {
        VStack(spacing: 20) {
            // Badge do plano atual
            planBadge
            
            // Funcionalidade exemplo 1: Disponível para Premium
            if subscriptionManager.accessState.planType == .premium {
                Button("Relatórios Avançados (Premium)") {
                    // Acessa funcionalidade Premium
                }
                .buttonStyle(.borderedProminent)
            } else {
                Button("🔒 Relatórios Avançados") {
                    // Mostrar paywall
                }
                .disabled(true)
            }
            
            // Funcionalidade exemplo 2: Disponível apenas para Premium
            if subscriptionManager.accessState.planType == .premium {
                Button("Análise de IA (Premium)") {
                    // Acessa funcionalidade Premium
                }
                .buttonStyle(.borderedProminent)
            } else {
                Button("🔒 Análise de IA") {
                    // Mostrar paywall
                }
                .disabled(true)
            }
            
            // Info de expiração (se houver)
            if let expirationDate = subscriptionManager.accessState.expirationDate {
                Text("Expira em: \(expirationDate.formatted())")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
    }
    
    @ViewBuilder
    private var planBadge: some View {
        let state = subscriptionManager.accessState
        
        HStack {
            Image(systemName: state.isInTrial ? "clock" : "star.fill")
            Text(state.planType.displayName)
                .fontWeight(.semibold)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(badgeColor.opacity(0.2))
        .foregroundStyle(badgeColor)
        .clipShape(Capsule())
    }
    
    private var badgeColor: Color {
        let type = subscriptionManager.accessState.planType
        switch type {
        case .premium: return .purple
        case .pro, .basic: return .purple
        case .trial: return .orange
        case .courtesy: return .pink
        case .none: return .gray
        }
    }
}

#Preview {
    ExampleSubscriptionGatedView()
        .environmentObject(SubscriptionManager.shared)
}
