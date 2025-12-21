import SwiftUI

struct ToastView: View {
    let message: String
    let type: ToastType

    enum ToastType {
        case success
        case error
        case warning
        case info

        var icon: String {
            switch self {
            case .success: return "checkmark.circle.fill"
            case .error: return "xmark.circle.fill"
            case .warning: return "exclamationmark.triangle.fill"
            case .info: return "info.circle.fill"
            }
        }

        var color: Color {
            switch self {
            case .success: return .green
            case .error: return .red
            case .warning: return .orange
            case .info: return .blue
            }
        }

        var backgroundColor: Color {
            switch self {
            case .success: return Color.green.opacity(0.1)
            case .error: return Color.red.opacity(0.1)
            case .warning: return Color.orange.opacity(0.1)
            case .info: return Color.blue.opacity(0.1)
            }
        }
    }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: type.icon)
                .font(.system(size: 20))
                .foregroundColor(type.color)

            Text(message)
                .font(.subheadline)
                .foregroundColor(.primary)
                .lineLimit(2)

            Spacer()
        }
        .padding()
        .background(type.backgroundColor)
        .background(.ultraThinMaterial)
        .cornerRadius(12)
        .shadow(color: .black.opacity(0.1), radius: 10, x: 0, y: 5)
        .padding(.horizontal)
    }
}

// MARK: - Toast Modifier

struct ToastModifier: ViewModifier {
    @Binding var isPresented: Bool
    let message: String
    let type: ToastView.ToastType
    var duration: Double = 3.0

    func body(content: Content) -> some View {
        ZStack {
            content

            VStack {
                if isPresented {
                    ToastView(message: message, type: type)
                        .transition(.move(edge: .top).combined(with: .opacity))
                        .onAppear {
                            DispatchQueue.main.asyncAfter(deadline: .now() + duration) {
                                withAnimation {
                                    isPresented = false
                                }
                            }
                        }
                }
                Spacer()
            }
            .padding(.top, 50)
        }
        .animation(.spring(), value: isPresented)
    }
}

extension View {
    func toast(isPresented: Binding<Bool>, message: String, type: ToastView.ToastType = .info, duration: Double = 3.0) -> some View {
        modifier(ToastModifier(isPresented: isPresented, message: message, type: type, duration: duration))
    }
}

// MARK: - Toast Manager

@MainActor
class ToastManager: ObservableObject {
    static let shared = ToastManager()

    @Published var isPresented = false
    @Published var message = ""
    @Published var type: ToastView.ToastType = .info

    func show(_ message: String, type: ToastView.ToastType = .info) {
        self.message = message
        self.type = type
        withAnimation {
            isPresented = true
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
            withAnimation {
                self.isPresented = false
            }
        }
    }

    func success(_ message: String) {
        show(message, type: .success)
    }

    func error(_ message: String) {
        show(message, type: .error)
    }

    func warning(_ message: String) {
        show(message, type: .warning)
    }

    func info(_ message: String) {
        show(message, type: .info)
    }
}

#Preview {
    VStack(spacing: 20) {
        ToastView(message: "Operação realizada com sucesso!", type: .success)
        ToastView(message: "Erro ao salvar dados", type: .error)
        ToastView(message: "Atenção: dados incompletos", type: .warning)
        ToastView(message: "Sincronizando...", type: .info)
    }
    .padding()
}
