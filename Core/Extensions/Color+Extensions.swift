import SwiftUI

extension Color {
    /// Inicializador com string hexadecimal
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3: // RGB (12-bit)
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6: // RGB (24-bit)
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8: // ARGB (32-bit)
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (255, 0, 0, 0)
        }

        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue:  Double(b) / 255,
            opacity: Double(a) / 255
        )
    }

    /// Cor primária do app (laranja do AgendaHOF)
    static let appPrimary = Color(red: 1.0, green: 0.49, blue: 0.0) // #FF7D00

    /// Cor de background do app
    static let appBackground = Color(.systemBackground)

    /// Cor de background secundária
    static let appSecondaryBackground = Color(.secondarySystemBackground)

    /// Cor de texto primária
    static let appTextPrimary = Color(.label)

    /// Cor de texto secundária
    static let appTextSecondary = Color(.secondaryLabel)

    /// Cor de sucesso (verde)
    static let appSuccess = Color.green

    /// Cor de erro (vermelho)
    static let appError = Color.red

    /// Cor de aviso (amarelo)
    static let appWarning = Color.orange

    /// Cor de informação (azul)
    static let appInfo = Color.blue
}
