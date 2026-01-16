import SwiftUI

struct AvatarView: View {
    let name: String
    var imageUrl: String?
    var size: CGFloat = 40
    var backgroundColor: Color = .appPrimary.opacity(0.15)
    var textColor: Color = .appPrimary

    var body: some View {
        Group {
            if let imageUrl = imageUrl, let url = URL(string: imageUrl) {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFill()
                    case .failure(_):
                        initialsView
                    case .empty:
                        ProgressView()
                            .frame(width: size, height: size)
                    @unknown default:
                        initialsView
                    }
                }
            } else {
                initialsView
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
    }

    private var initialsView: some View {
        ZStack {
            Circle()
                .fill(backgroundColor)

            Text(initials)
                .font(.system(size: size * 0.4, weight: .semibold))
                .foregroundColor(textColor)
        }
    }

    private var initials: String {
        let parts = name.split(separator: " ")
        if parts.count >= 2 {
            return "\(parts[0].prefix(1))\(parts[1].prefix(1))".uppercased()
        }
        return String(name.prefix(2)).uppercased()
    }
}

// MARK: - Avatar com Badge

struct AvatarWithBadge: View {
    let name: String
    var imageUrl: String?
    var size: CGFloat = 40
    var badgeColor: Color = .green
    var showBadge: Bool = true

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            AvatarView(name: name, imageUrl: imageUrl, size: size)

            if showBadge {
                Circle()
                    .fill(badgeColor)
                    .frame(width: size * 0.3, height: size * 0.3)
                    .overlay(
                        Circle()
                            .stroke(Color(.systemBackground), lineWidth: 2)
                    )
                    .offset(x: 2, y: 2)
            }
        }
    }
}

#Preview {
    VStack(spacing: 20) {
        AvatarView(name: "João Silva", size: 60)
        AvatarView(name: "Maria", size: 40)
        AvatarWithBadge(name: "Pedro Santos", size: 50, badgeColor: .green)
    }
}
