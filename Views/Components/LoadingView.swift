import SwiftUI

struct LoadingView: View {
    var text: String = "Carregando..."
    var fullScreen: Bool = true

    var body: some View {
        Group {
            if fullScreen {
                ZStack {
                    Color(.systemBackground)
                        .ignoresSafeArea()

                    VStack(spacing: 16) {
                        ProgressView()
                            .scaleEffect(1.2)

                        Text(text)
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                }
            } else {
                VStack(spacing: 12) {
                    ProgressView()
                    Text(text)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding()
            }
        }
    }
}

// MARK: - Loading Overlay Modifier

struct LoadingOverlay: ViewModifier {
    let isLoading: Bool
    let text: String

    func body(content: Content) -> some View {
        ZStack {
            content
                .disabled(isLoading)
                .blur(radius: isLoading ? 2 : 0)

            if isLoading {
                Color.black.opacity(0.3)
                    .ignoresSafeArea()

                VStack(spacing: 16) {
                    ProgressView()
                        .scaleEffect(1.5)
                        .tint(.white)

                    Text(text)
                        .font(.subheadline)
                        .foregroundColor(.white)
                }
                .padding(24)
                .background(Color(.systemGray5).opacity(0.9))
                .cornerRadius(16)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: isLoading)
    }
}

extension View {
    func loadingOverlay(isLoading: Bool, text: String = "Carregando...") -> some View {
        modifier(LoadingOverlay(isLoading: isLoading, text: text))
    }
}

#Preview {
    LoadingView(text: "Carregando dados...")
}
