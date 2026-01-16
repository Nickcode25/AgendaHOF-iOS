import SwiftUI

struct PasswordStrengthIndicator: View {
    let password: String

    private var strength: PasswordStrength {
        calculateStrength(password)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Barra de Força
            HStack(spacing: 4) {
                ForEach(0..<4) { index in
                    RoundedRectangle(cornerRadius: 2)
                        .fill(index < strength.bars ? strength.color : Color.gray.opacity(0.3))
                        .frame(height: 4)
                }
            }

            // Texto
            Text(strength.text)
                .font(.system(size: 12))
                .foregroundColor(strength.color)

            // Requisitos
            VStack(alignment: .leading, spacing: 4) {
                RequirementRow(met: password.count >= 8, text: "Mínimo 8 caracteres")
                RequirementRow(met: password.range(of: ".*[A-Z]+.*", options: .regularExpression) != nil, text: "Uma letra maiúscula")
                RequirementRow(met: password.range(of: ".*[a-z]+.*", options: .regularExpression) != nil, text: "Uma letra minúscula")
                RequirementRow(met: password.range(of: ".*[0-9]+.*", options: .regularExpression) != nil, text: "Um número")
                RequirementRow(met: password.range(of: ".*[!@#$%^&*(),.?\":{}|<>]+.*", options: .regularExpression) != nil, text: "Um caractere especial")
            }
        }
    }

    private func calculateStrength(_ password: String) -> PasswordStrength {
        var score = 0

        if password.count >= 8 { score += 1 }
        if password.range(of: ".*[A-Z]+.*", options: .regularExpression) != nil { score += 1 }
        if password.range(of: ".*[a-z]+.*", options: .regularExpression) != nil { score += 1 }
        if password.range(of: ".*[0-9]+.*", options: .regularExpression) != nil { score += 1 }
        if password.range(of: ".*[!@#$%^&*(),.?\":{}|<>]+.*", options: .regularExpression) != nil { score += 1 }

        switch score {
        case 0...1:
            return PasswordStrength(bars: 1, color: .red, text: "Fraca")
        case 2:
            return PasswordStrength(bars: 2, color: Color(hex: "ff6b00"), text: "Média")
        case 3...4:
            return PasswordStrength(bars: 3, color: .yellow, text: "Boa")
        case 5:
            return PasswordStrength(bars: 4, color: .green, text: "Forte")
        default:
            return PasswordStrength(bars: 0, color: .gray, text: "")
        }
    }
}

struct RequirementRow: View {
    let met: Bool
    let text: String

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: met ? "checkmark.circle.fill" : "circle")
                .font(.system(size: 12))
                .foregroundColor(met ? .green : .gray)

            Text(text)
                .font(.system(size: 12))
                .foregroundColor(met ? .green : .gray)
        }
    }
}

struct PasswordStrength {
    let bars: Int
    let color: Color
    let text: String
}
