import SwiftUI

extension Color {
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
