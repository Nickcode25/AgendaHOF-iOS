import SwiftUI

// MARK: - Login Branding Section

/// Seção de branding do login com logo e tagline
/// Componente reutilizável que adapta ao modo claro/escuro
struct LoginBrandingSection: View {

    // MARK: - Properties

    @Environment(\.colorScheme) var colorScheme
    let isAppearing: Bool

    // MARK: - Body

    var body: some View {
        VStack(spacing: 12) {
            // Logo adaptativo (claro/escuro)
            logoImage

            // Tagline
            Text("A sua clínica a um toque de distância.")
                .font(.system(size: 15, weight: .regular))
                .foregroundStyle(.secondary.opacity(0.8))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
        }
        .opacity(isAppearing ? 1 : 0)
        .offset(y: isAppearing ? 0 : -10)
        .animation(.easeOut(duration: 0.5), value: isAppearing)
    }

    // MARK: - Logo Image

    private var logoImage: some View {
        let logoURL = colorScheme == .dark
            ? "https://AgendaHOF.b-cdn.net/logo-light.png"
            : "https://AgendaHOF.b-cdn.net/logo-dark.png"

        return AsyncImage(url: URL(string: logoURL)) { phase in
            if let image = phase.image {
                image
                    .resizable()
                    .aspectRatio(contentMode: .fit)
            } else if phase.error != nil {
                // Fallback caso erro no carregamento
                Image(systemName: "stethoscope")
                    .font(.system(size: 48, weight: .light))
                    .foregroundStyle(.primary.opacity(0.3))
            } else {
                ProgressView()
            }
        }
        .frame(height: 80)
    }
}

// MARK: - Preview

#Preview {
    VStack(spacing: 40) {
        LoginBrandingSection(isAppearing: true)
        LoginBrandingSection(isAppearing: false)
    }
    .padding()
}
