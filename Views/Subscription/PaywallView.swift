import SwiftUI
import StoreKit

/// View de Paywall para exibir os planos de assinatura
/// Aparece apenas quando o usuário não tem acesso ativo
struct PaywallView: View {
    @EnvironmentObject var subscriptionManager: SubscriptionManager
    @EnvironmentObject var supabase: SupabaseManager
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    
    @State private var selectedProduct: Product?
    @State private var showingAlert = false
    @State private var alertTitle = ""
    @State private var alertMessage = ""
    
    var body: some View {
        NavigationStack {
            ZStack {
                // Background gradient
                backgroundGradient
                
                ScrollView {
                    VStack(spacing: 24) {
                        // Header
                        headerSection
                        
                        // Planos
                        if subscriptionManager.storeProducts.isEmpty {
                            loadingPlansView
                        } else {
                            plansSection
                        }
                        
                        // Botão de Compra
                        purchaseButton
                        
                        // Termos e Políticas
                        legalSection
                        
                        Spacer(minLength: 40)
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 20)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        // Se o usuário já tem acesso, apenas fecha a view
                        // Se não tem acesso, faz logout
                        if subscriptionManager.accessState.hasAccess {
                            dismiss()
                        } else {
                            Task {
                                try? await supabase.signOut()
                            }
                        }
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title2)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .alert(alertTitle, isPresented: $showingAlert) {
                Button("OK", role: .cancel) {
                    if subscriptionManager.purchaseState == .success {
                        dismiss()
                    }
                    subscriptionManager.resetPurchaseState()
                }
            } message: {
                Text(alertMessage)
            }
            .onChange(of: subscriptionManager.purchaseState) { _, newState in
                handlePurchaseStateChange(newState)
            }
            .onAppear {
                Task {
                    await subscriptionManager.loadProducts()
                    // Selecionar produto recomendado por padrão
                    if selectedProduct == nil {
                        selectedProduct = subscriptionManager.recommendedProduct
                    }
                }
            }
            .onDisappear {
                // Recarregar verificação de acesso ao fechar paywall
                // Isso garante que mudanças de plano sejam refletidas na UI
                Task {
                    await subscriptionManager.checkAccess()
                }
            }
        }
    }
    
    // MARK: - Background
    
    private var backgroundGradient: some View {
        LinearGradient(
            gradient: Gradient(colors: [
                colorScheme == .dark ? Color(hex: "1a1a2e") : Color(hex: "f8f9fa"),
                colorScheme == .dark ? Color(hex: "16213e") : Color(hex: "e9ecef")
            ]),
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .ignoresSafeArea()
    }
    
    // MARK: - Header
    
    private var headerSection: some View {
        VStack(spacing: 16) {
            // Ícone
            Image(systemName: "crown.fill")
                .font(.system(size: 60))
                .foregroundStyle(
                    LinearGradient(
                        colors: [.yellow, .orange],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .shadow(color: .orange.opacity(0.3), radius: 10, x: 0, y: 5)
            
            // Título
            Text("Desbloqueie o Acesso Completo")
                .font(.title2)
                .fontWeight(.bold)
                .multilineTextAlignment(.center)
            
            // Subtítulo
            Text("Gerencie sua agenda, pacientes e finanças sem limites")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(.bottom, 8)
    }
    
    // MARK: - Loading Plans
    
    private var loadingPlansView: some View {
        VStack(spacing: 16) {
            ProgressView()
                .scaleEffect(1.2)
            Text("Carregando planos...")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(height: 200)
    }
    
    // MARK: - Plans Section
    
    private var plansSection: some View {
        VStack(spacing: 12) {
            // Ordenar: Premium primeiro (recomendado), depois Pro, depois Básico
            let sortedProducts = subscriptionManager.storeProducts.sorted { p1, p2 in
                let order = ["com.agendahof.premium": 0, "com.agendahof.pro": 1, "com.agendahof.basic": 2]
                return (order[p1.id] ?? 3) < (order[p2.id] ?? 3)
            }
            
            ForEach(sortedProducts, id: \.id) { product in
                PlanCard(
                    product: product,
                    isSelected: selectedProduct?.id == product.id,
                    isRecommended: product.id == "com.agendahof.premium"  // Premium é o recomendado
                ) {
                    withAnimation(.spring(response: 0.3)) {
                        selectedProduct = product
                    }
                }
            }
        }
    }
    
    // MARK: - Purchase Button
    
    private var purchaseButton: some View {
        Button {
            guard let product = selectedProduct else { return }
            Task {
                await subscriptionManager.purchase(product)
            }
        } label: {
            Group {
                if subscriptionManager.purchaseState == .purchasing {
                    HStack(spacing: 12) {
                        ProgressView()
                            .tint(.white)
                        Text("Processando...")
                    }
                } else {
                    Text("Assinar Agora")
                        .fontWeight(.semibold)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 56)
            .background(
                LinearGradient(
                    colors: selectedProduct != nil ? [Color(hex: "ff6b00"), Color(hex: "ff8c00")] : [.gray],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
            .foregroundColor(.white)
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .shadow(color: Color(hex: "ff6b00").opacity(0.4), radius: 10, x: 0, y: 5)
        }
        .disabled(selectedProduct == nil || subscriptionManager.purchaseState == .purchasing)
        .padding(.top, 8)
    }

    
    // MARK: - Legal Section
    
    private var legalSection: some View {
        VStack(spacing: 8) {
            Button("Restaurar Compras") {
                Task {
                    await subscriptionManager.restorePurchases()
                }
            }
            .font(.subheadline)
            .fontWeight(.medium)
            .foregroundStyle(.primary)
            .padding(.bottom, 8)
            
            Text("Ao assinar, você concorda com os")
                .font(.caption)
                .foregroundStyle(.secondary)
            
            HStack(spacing: 4) {
                Link("Termos de Uso", destination: URL(string: "https://agendahof.com/terms")!)
                Text("e")
                Link("Política de Privacidade", destination: URL(string: "https://agendahof.com/privacy")!)
            }
            .font(.caption)
            
            Text("Assinatura com renovação automática mensal ou anual. Cancele a qualquer momento em Ajustes > Assinaturas.")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.top, 4)
        }
        .padding(.top, 16)
    }
    
    // MARK: - Handle Purchase State
    
    private func handlePurchaseStateChange(_ state: PurchaseState) {
        switch state {
        case .success:
            alertTitle = "Parabéns! 🎉"
            alertMessage = "Sua assinatura foi ativada com sucesso!\n\nAgora você tem acesso completo ao Agenda HOF. Aproveite todas as funcionalidades premium!"
            showingAlert = true
            
        case .failed(let message):
            alertTitle = "Ops! Algo deu errado"
            alertMessage = "Não foi possível completar sua assinatura.\n\n\(message)\n\nTente novamente ou entre em contato com o suporte."
            showingAlert = true
            
        case .cancelled:
            // Não mostrar alerta para cancelamento
            subscriptionManager.resetPurchaseState()
            
        default:
            break
        }
    }
}

// MARK: - Plan Card Component

struct PlanCard: View {
    let product: Product
    let isSelected: Bool
    let isRecommended: Bool
    let onTap: () -> Void
    
    @Environment(\.colorScheme) private var colorScheme
    
    private var planType: PlanType {
        PlanType.fromAppleProductId(product.id)
    }
    
    private var planColor: Color {
        switch planType {
        case .basic: return Color(hex: "6c757d")  // Cinza
        case .pro: return Color(hex: "0d6efd")    // Azul
        case .premium: return Color(hex: "ff6b00") // Laranja (destaque)
        default: return .gray
        }
    }
    
    private var planIcon: String {
        switch planType {
        case .basic: return "star"
        case .pro: return "star.fill"
        case .premium: return "crown.fill"
        default: return "questionmark"
        }
    }
    
    private var features: [String] {
        switch planType {
        case .basic:
            return [
                "Até 25 agendamentos/mês",
                "Agenda inteligente",
                "Cadastro de até 25 pacientes"
            ]
        case .pro:
            return [
                "Agendamentos ilimitados",
                "Agenda inteligente",
                "Pacientes ilimitados",
                "Histórico de atendimentos",
                "Gestão de Profissionais",
                "Gestão de Procedimentos"
            ]
        case .premium:
            return [
                "Tudo do Plano Pro",
                "WhatsApp integrado",
                "Registro de vendas",
                "Controle de despesas",
                "Relatórios financeiros",
                "Controle de Estoque",
                "Gestão de Alunos",
                "Gestão de Cursos",
                "Gestão de Funcionários"
            ]
        default:
            return []
        }
    }
    
    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    // Ícone e Nome
                    HStack(spacing: 10) {
                        Image(systemName: planIcon)
                            .font(.title2)
                            .foregroundStyle(planColor)
                        
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 6) {
                                Text(planType.displayName)
                                    .font(.headline)
                                    .foregroundStyle(.primary)
                                
                                if isRecommended {
                                    Text("RECOMENDADO")
                                        .font(.system(size: 9, weight: .bold))
                                        .foregroundStyle(.white)
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(planColor)
                                        .clipShape(Capsule())
                                }
                            }
                            
                            Text(product.description)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                    
                    Spacer()
                    
                    // Preço
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(product.displayPrice)
                            .font(.title3)
                            .fontWeight(.bold)
                            .foregroundStyle(.primary)
                        
                        if let subscription = product.subscription {
                            Text("/\(subscription.subscriptionPeriod.unit.localizedDescription)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                
                // Features (expandidas quando selecionado)
                if isSelected {
                    Divider()
                        .padding(.vertical, 4)
                    
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(features, id: \.self) { feature in
                            HStack(spacing: 8) {
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.caption)
                                    .foregroundStyle(planColor)
                                
                                Text(feature)
                                    .font(.caption)
                                    .foregroundStyle(.primary)
                            }
                        }
                    }
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(colorScheme == .dark ? Color(hex: "2a2a3e") : .white)
                    .shadow(
                        color: isSelected ? planColor.opacity(0.3) : .black.opacity(0.05),
                        radius: isSelected ? 10 : 5,
                        x: 0,
                        y: isSelected ? 5 : 2
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(isSelected ? planColor : .clear, lineWidth: 2)
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Subscription Period Extension

extension Product.SubscriptionPeriod.Unit {
    var localizedDescription: String {
        switch self {
        case .day: return "dia"
        case .week: return "semana"
        case .month: return "mês"
        case .year: return "ano"
        @unknown default: return ""
        }
    }
}

// MARK: - Preview

#Preview {
    PaywallView()
        .environmentObject(SubscriptionManager.shared)
}
