import SwiftUI

// MARK: - About Section

/// Seção "Sobre" no SettingsView
/// Exibe informações sobre o app (versão, etc.)
struct AboutSection: View {

    // MARK: - Properties

    let appVersion: String

    // MARK: - Body

    var body: some View {
        Section("Sobre") {
            LabeledContent("Versão") {
                Text(appVersion)
                    .foregroundColor(.secondary)
            }
        }
    }
}

// MARK: - Convenience Initializer

extension AboutSection {

    /// Inicializador conveniente usando Constants
    init() {
        self.appVersion = Constants.appVersion
    }
}

// MARK: - Preview

#Preview {
    List {
        AboutSection(appVersion: "1.0.0")

        AboutSection() // Usa Constants
    }
}
