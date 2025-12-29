import SwiftUI

struct SupportView: View {
    @Environment(\.dismiss) var dismiss
    
    private let supportPhoneNumber = "5531989664015" // +55 31 98966-4015
    
    var body: some View {
        NavigationView {
            VStack(spacing: 24) {
                // Header Icon
                Image(systemName: "headphones.circle.fill")
                    .font(.system(size: 80))
                    .foregroundStyle(.blue)
                    .padding(.top, 40)
                
                // Title & Description
                VStack(spacing: 12) {
                    Text("Suporte Agenda HOF")
                        .font(.title2)
                        .fontWeight(.bold)
                    
                    Text("Estamos aqui para ajudar! Entre em contato conosco pelo WhatsApp.")
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                }
                
                Spacer()
                
                // WhatsApp Button
                Button {
                    openWhatsApp()
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "message.fill")
                            .font(.title3)
                        
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Falar com Suporte")
                                .font(.headline)
                            Text("WhatsApp: (31) 98966-4015")
                                .font(.caption)
                                .opacity(0.8)
                        }
                        
                        Spacer()
                        
                        Image(systemName: "chevron.right")
                            .font(.caption)
                            .opacity(0.5)
                    }
                    .foregroundColor(.white)
                    .padding()
                    .background(
                        LinearGradient(
                            colors: [Color.green, Color.green.opacity(0.8)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                    .shadow(color: .green.opacity(0.3), radius: 10, y: 5)
                }
                .padding(.horizontal, 24)
                
                // Info Cards
                VStack(spacing: 16) {
                    InfoCard(
                        icon: "clock.fill",
                        title: "Horário de Atendimento",
                        description: "Segunda a Sexta, 9h às 18h"
                    )
                    
                    InfoCard(
                        icon: "bubble.left.and.bubble.right.fill",
                        title: "Tempo de Resposta",
                        description: "Respondemos em até 24h úteis"
                    )
                }
                .padding(.horizontal, 24)
                
                Spacer()
            }
            .navigationTitle("Suporte")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Fechar") {
                        dismiss()
                    }
                }
            }
        }
    }
    
    private func openWhatsApp() {
        let message = "Olá! Preciso de ajuda com o Agenda HOF."
        let encodedMessage = message.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        let urlString = "https://wa.me/\(supportPhoneNumber)?text=\(encodedMessage)"
        
        if let url = URL(string: urlString) {
            UIApplication.shared.open(url)
        }
    }
}

// MARK: - Info Card Component

struct InfoCard: View {
    let icon: String
    let title: String
    let description: String
    
    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(.blue)
                .frame(width: 40)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                
                Text(description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            
            Spacer()
        }
        .padding()
        .background(Color(.systemGray6))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

#Preview {
    SupportView()
}
