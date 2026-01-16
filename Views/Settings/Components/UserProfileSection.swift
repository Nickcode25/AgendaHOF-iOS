import SwiftUI

// MARK: - User Profile Section

/// Seção de perfil do usuário no SettingsView
/// Exibe avatar, nome, email e cargo com navegação para ProfileView
struct UserProfileSection: View {

    // MARK: - Properties

    let userName: String
    let userEmail: String?
    let userRole: String?
    let profilePhotoURL: String?
    let onTap: () -> Void

    // MARK: - Body

    var body: some View {
        Section {
            Button(action: onTap) {
                HStack(spacing: 12) {
                    // Avatar
                    AvatarView(
                        name: userName,
                        imageUrl: profilePhotoURL,
                        size: 60
                    )

                    // Informações do usuário
                    VStack(alignment: .leading, spacing: 4) {
                        Text(userName)
                            .font(.headline)
                            .foregroundColor(.primary)

                        if let email = userEmail {
                            Text(email)
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }

                        if let role = userRole {
                            Text(role)
                                .font(.caption)
                                .foregroundColor(.appPrimary)
                        }
                    }

                    Spacer()

                    // Chevron
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
    }
}

// MARK: - Convenience Initializer

extension UserProfileSection {

    /// Inicializador conveniente usando SupabaseManager
    init(supabase: SupabaseManager, onTap: @escaping () -> Void) {
        self.userName = supabase.userProfile?.nameForDisplay ?? "Usuário"
        self.userEmail = supabase.currentUser?.email
        self.userRole = supabase.userProfile?.role.displayName
        self.profilePhotoURL = supabase.userProfile?.profilePhoto
        self.onTap = onTap
    }
}

// MARK: - Preview

#Preview {
    List {
        UserProfileSection(
            userName: "Dr. João Silva",
            userEmail: "joao.silva@example.com",
            userRole: "Proprietário",
            profilePhotoURL: nil,
            onTap: {}
        )
    }
}
