import Foundation

extension String {
    // MARK: - Validação

    /// Verifica se é um email válido
    var isValidEmail: Bool {
        let emailRegex = "[A-Z0-9a-z._%+-]+@[A-Za-z0-9.-]+\\.[A-Za-z]{2,64}"
        let emailPredicate = NSPredicate(format: "SELF MATCHES %@", emailRegex)
        return emailPredicate.evaluate(with: self)
    }

    /// Verifica se é um CPF válido
    var isValidCPF: Bool {
        let cpf = self.onlyNumbers
        guard cpf.count == 11 else { return false }

        // Verifica se todos os dígitos são iguais
        if cpf.allSatisfy({ $0 == cpf.first }) {
            return false
        }

        // Validação dos dígitos verificadores
        let digits = cpf.compactMap { Int(String($0)) }
        guard digits.count == 11 else { return false }

        // Primeiro dígito verificador
        var sum = 0
        for i in 0..<9 {
            sum += digits[i] * (10 - i)
        }
        var remainder = sum % 11
        let firstDigit = remainder < 2 ? 0 : 11 - remainder

        guard digits[9] == firstDigit else { return false }

        // Segundo dígito verificador
        sum = 0
        for i in 0..<10 {
            sum += digits[i] * (11 - i)
        }
        remainder = sum % 11
        let secondDigit = remainder < 2 ? 0 : 11 - remainder

        return digits[10] == secondDigit
    }

    /// Verifica se é um telefone válido
    var isValidPhone: Bool {
        let phone = self.onlyNumbers
        return phone.count >= 10 && phone.count <= 11
    }

    // MARK: - Formatação

    /// Retorna apenas números
    var onlyNumbers: String {
        self.filter { $0.isNumber }
    }

    /// Formata como CPF (xxx.xxx.xxx-xx)
    var formattedCPF: String {
        let numbers = self.onlyNumbers
        guard numbers.count == 11 else { return self }

        let part1 = numbers.prefix(3)
        let part2 = numbers.dropFirst(3).prefix(3)
        let part3 = numbers.dropFirst(6).prefix(3)
        let part4 = numbers.suffix(2)

        return "\(part1).\(part2).\(part3)-\(part4)"
    }

    /// Formata como telefone
    var formattedPhone: String {
        let numbers = self.onlyNumbers
        if numbers.count == 11 {
            let ddd = numbers.prefix(2)
            let part1 = numbers.dropFirst(2).prefix(5)
            let part2 = numbers.suffix(4)
            return "(\(ddd)) \(part1)-\(part2)"
        } else if numbers.count == 10 {
            let ddd = numbers.prefix(2)
            let part1 = numbers.dropFirst(2).prefix(4)
            let part2 = numbers.suffix(4)
            return "(\(ddd)) \(part1)-\(part2)"
        }
        return self
    }

    /// Formata como CEP (xxxxx-xxx)
    var formattedCEP: String {
        let numbers = self.onlyNumbers
        guard numbers.count == 8 else { return self }

        let part1 = numbers.prefix(5)
        let part2 = numbers.suffix(3)

        return "\(part1)-\(part2)"
    }

    // MARK: - Manipulação

    /// Capitaliza a primeira letra
    var capitalizedFirst: String {
        prefix(1).uppercased() + dropFirst()
    }

    /// Remove espaços extras
    var trimmed: String {
        trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Retorna as iniciais (até 2 caracteres)
    var initials: String {
        let parts = self.split(separator: " ")
        if parts.count >= 2 {
            return "\(parts[0].prefix(1))\(parts[1].prefix(1))".uppercased()
        }
        return String(prefix(2)).uppercased()
    }

    // MARK: - Conversão

    /// Converte para Date usando formato ISO8601
    var toDate: Date? {
        let formatter = ISO8601DateFormatter()
        return formatter.date(from: self)
    }

    /// Converte para Date usando formato específico
    func toDate(format: String) -> Date? {
        let formatter = DateFormatter()
        formatter.dateFormat = format
        formatter.locale = Locale(identifier: "pt_BR")
        return formatter.date(from: self)
    }
}
