import Foundation

extension String {
    // MARK: - Validação de Email

    /// Verifica se é um email válido usando regex RFC 5322 simplificado
    var isValidEmail: Bool {
        let emailRegex = "[A-Z0-9a-z._%+-]+@[A-Za-z0-9.-]+\\.[A-Za-z]{2,64}"
        let emailPredicate = NSPredicate(format: "SELF MATCHES %@", emailRegex)
        return emailPredicate.evaluate(with: self)
    }

    // MARK: - Validação de Senha

    /// Verifica se a senha atende aos requisitos mínimos de segurança
    /// - Mínimo 8 caracteres
    /// - Pelo menos 1 letra maiúscula
    /// - Pelo menos 1 letra minúscula
    /// - Pelo menos 1 número
    /// - Pelo menos 1 caractere especial
    var isValidPassword: Bool {
        guard count >= 8 else { return false }

        let uppercaseRegex = ".*[A-Z]+.*"
        let lowercaseRegex = ".*[a-z]+.*"
        let numberRegex = ".*[0-9]+.*"
        let specialCharRegex = ".*[!@#$%^&*()_+\\-=\\[\\]{};':\"\\\\|,.<>/?]+.*"

        let hasUppercase = NSPredicate(format: "SELF MATCHES %@", uppercaseRegex).evaluate(with: self)
        let hasLowercase = NSPredicate(format: "SELF MATCHES %@", lowercaseRegex).evaluate(with: self)
        let hasNumber = NSPredicate(format: "SELF MATCHES %@", numberRegex).evaluate(with: self)
        let hasSpecialChar = NSPredicate(format: "SELF MATCHES %@", specialCharRegex).evaluate(with: self)

        return hasUppercase && hasLowercase && hasNumber && hasSpecialChar
    }

    /// Retorna a força da senha (0.0 a 1.0)
    var passwordStrength: Double {
        var strength = 0.0

        // Comprimento
        if count >= 8 { strength += 0.2 }
        if count >= 12 { strength += 0.1 }

        // Maiúscula
        if contains(where: { $0.isUppercase }) { strength += 0.2 }

        // Minúscula
        if contains(where: { $0.isLowercase }) { strength += 0.2 }

        // Número
        if contains(where: { $0.isNumber }) { strength += 0.2 }

        // Caractere especial
        let specialChars = CharacterSet(charactersIn: "!@#$%^&*()_+-=[]{}';:\"\\|,.<>/?")
        if rangeOfCharacter(from: specialChars) != nil { strength += 0.1 }

        return min(strength, 1.0)
    }

    // MARK: - Validação de CPF

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

    // MARK: - Validação de Telefone

    /// Verifica se é um telefone brasileiro válido
    /// - Valida DDD (11-99)
    /// - Aceita 10 dígitos (fixo) ou 11 dígitos (celular)
    var isValidPhone: Bool {
        let numbers = self.onlyNumbers

        guard numbers.count == 10 || numbers.count == 11 else { return false }

        // Validar DDD (11-99)
        let ddd = Int(numbers.prefix(2)) ?? 0
        guard ddd >= 11 && ddd <= 99 else { return false }

        return true
    }

    /// Retorna mensagem de erro de validação de telefone, ou nil se válido
    var phoneValidationError: String? {
        let numbers = self.onlyNumbers

        if numbers.isEmpty {
            return nil // Campo vazio é permitido
        }

        if numbers.count < 10 {
            return "Telefone incompleto. Digite DDD + número"
        }

        if numbers.count > 11 {
            return "Telefone inválido. Máximo 11 dígitos"
        }

        let ddd = Int(numbers.prefix(2)) ?? 0
        if ddd < 11 || ddd > 99 {
            return "DDD inválido"
        }

        return nil
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

    // MARK: - Normalização

    /// Normaliza a string para comparação (remove acentos, espaços extras e converte para minúsculas)
    var normalized: String {
        self.folding(options: .diacriticInsensitive, locale: .current)
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
    }
    
    /// Remove prefixos comuns de títulos profissionais
    private var withoutProfessionalPrefix: String {
        let prefixes = ["dr.", "dra.", "dr ", "dra ", "prof.", "prof ", "doutor ", "doutora "]
        var result = self.normalized
        for prefix in prefixes {
            if result.hasPrefix(prefix) {
                result = String(result.dropFirst(prefix.count)).trimmingCharacters(in: .whitespaces)
            }
        }
        return result
    }
    
    /// Compara se duas strings são "iguais" ignorando case, diacríticos e prefixos profissionais (Dr./Dra.)
    func isRoughlyEqual(to other: String) -> Bool {
        let selfNormalized = self.normalized
        let otherNormalized = other.normalized
        
        // Comparação exata normalizada
        if selfNormalized == otherNormalized {
            return true
        }
        
        // Comparação sem prefixos profissionais (Dr./Dra.)
        let selfWithoutPrefix = self.withoutProfessionalPrefix
        let otherWithoutPrefix = other.withoutProfessionalPrefix
        
        if selfWithoutPrefix == otherWithoutPrefix {
            return true
        }
        
        // Uma contém a outra (para casos onde nome foi alterado)
        if selfNormalized.contains(otherNormalized) || otherNormalized.contains(selfNormalized) {
            return true
        }
        
        return false
    }
}
