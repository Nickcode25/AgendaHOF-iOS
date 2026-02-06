import SwiftUI
import StoreKit

struct LegalInfoView: View {
    @EnvironmentObject var subscriptionManager: SubscriptionManager

    var body: some View {
        List {
            // Seção 1: Documentos Legais
            Section(header: Text("Documentos Legais")) {
                Link(destination: URL(string: "https://agendahof.com/privacy")!) {
                    HStack {
                        Image(systemName: "hand.raised.fill")
                            .foregroundColor(.blue)
                        Text("Política de Privacidade")
                            .foregroundColor(.primary)
                        Spacer()
                        Image(systemName: "arrow.up.right")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                
                Link(destination: URL(string: "https://agendahof.com/terms")!) {
                    HStack {
                        Image(systemName: "doc.text.fill")
                            .foregroundColor(.blue)
                        Text("Termos de Uso")
                            .foregroundColor(.primary)
                        Spacer()
                        Image(systemName: "arrow.up.right")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
            
            // Seção 2: Sobre a Assinatura
            Section(header: Text("Sobre a Assinatura")) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Agenda HOF Professional (Plano Premium)")
                        .font(.headline)
                    
                    Text("Sistema de gestão de consultório para profissionais de Harmonização Orofacial")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    Divider()
                        .padding(.vertical, 4)
                    
                    HStack {
                        Text("Período:")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        Text("Assinatura Mensal")
                            .font(.subheadline)
                            .fontWeight(.medium)
                    }
                    
                    HStack {
                        Text("Preço:")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        
                        if let product = subscriptionManager.recommendedProduct {
                            Text("\(product.displayPrice)/mês")
                                .font(.subheadline)
                                .fontWeight(.medium)
                        } else {
                            Text("R$ 129,90/mês") // Fallback
                                .font(.subheadline)
                                .fontWeight(.medium)
                        }
                    }
                    
                    Text("Sua assinatura renova automaticamente todo mês.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding(.top, 2)
                }
                .padding(.vertical, 4)
            }
            
            // Seção 3: Informações do App
            Section(header: Text("Informações do App")) {
                HStack {
                    Text("Versão")
                    Spacer()
                    Text(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0")
                        .foregroundColor(.secondary)
                }
                
                Text("©️ 2026 Agenda HOF - Todos os direitos reservados")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .navigationTitle("Informações Legais")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            // Garantir que os produtos foram carregados
            if subscriptionManager.storeProducts.isEmpty {
                Task {
                    await subscriptionManager.loadProducts()
                }
            }
        }
    }
}

#Preview {
    NavigationStack {
        LegalInfoView()
            .environmentObject(SubscriptionManager.shared)
    }
}
