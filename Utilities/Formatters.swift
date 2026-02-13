import Foundation

enum Formatters {
    // MARK: - Currency

    static let currency: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.locale = Locale(identifier: "pt_BR")
        return formatter
    }()

    static func formatCurrency(_ value: Double) -> String {
        currency.string(from: NSNumber(value: value)) ?? "R$ 0,00"
    }

    // MARK: - Percent

    static let percent: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .percent
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = 1
        return formatter
    }()

    static func formatPercent(_ value: Double) -> String {
        percent.string(from: NSNumber(value: value)) ?? "0%"
    }

    // MARK: - Number

    static let decimal: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.locale = Locale(identifier: "pt_BR")
        return formatter
    }()

    static func formatDecimal(_ value: Double) -> String {
        decimal.string(from: NSNumber(value: value)) ?? "0"
    }

    // MARK: - Date

    static let dateShort: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "dd/MM/yyyy"
        formatter.locale = Locale(identifier: "pt_BR")
        return formatter
    }()

    static let dateFull: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE, d 'de' MMMM 'de' yyyy"
        formatter.locale = Locale(identifier: "pt_BR")
        return formatter
    }()

    static let time: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter
    }()

    static let dateTime: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "dd/MM/yyyy 'às' HH:mm"
        formatter.locale = Locale(identifier: "pt_BR")
        return formatter
    }()

    static let iso8601: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        return formatter
    }()

    // MARK: - Relative Date

    static let relativeDate: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.locale = Locale(identifier: "pt_BR")
        formatter.unitsStyle = .full
        return formatter
    }()

    static func formatRelative(_ date: Date) -> String {
        relativeDate.localizedString(for: date, relativeTo: Date())
    }

    // MARK: - Duration

    static func formatDuration(minutes: Int) -> String {
        if minutes < 60 {
            return "\(minutes) min"
        }

        let hours = minutes / 60
        let remainingMinutes = minutes % 60

        if remainingMinutes == 0 {
            return "\(hours)h"
        }

        return "\(hours)h \(remainingMinutes)min"
    }

    // MARK: - Phone

    static func formatPhone(_ phone: String) -> String {
        let numbers = phone.filter { $0.isNumber }

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

        return phone
    }

    // MARK: - CPF

    static func formatCPF(_ cpf: String) -> String {
        let numbers = cpf.filter { $0.isNumber }
        guard numbers.count == 11 else { return cpf }

        let part1 = numbers.prefix(3)
        let part2 = numbers.dropFirst(3).prefix(3)
        let part3 = numbers.dropFirst(6).prefix(3)
        let part4 = numbers.suffix(2)

        return "\(part1).\(part2).\(part3)-\(part4)"
    }
}

// MARK: - Phone Formatter Helper

public struct PhoneFormatter {
    /// Normaliza um telefone brasileiro para o formato E.164
    /// - Parameter input: Telefone em qualquer formato (ex: (31) 98888-8888, 31988888888, +55 31...)
    /// - Returns: Telefone no formato +55XXXXXXXXXXX ou nil se inválido
    public static func normalizeBR(_ input: String) -> String? {
        let digits = input.onlyDigits
        
        // Regra 1: Vazio ou tamanho inválido
        if digits.isEmpty { return nil }
        
        // Regra 2: Já começa com 55 (DDI Brasil)
        if digits.hasPrefix("55") {
            // Pode ter 12 dígitos (55 + DDD + 8 números - fixo antigo/raro) ou 13 (55 + DDD + 9 números - celular)
            // Mas vamos focar nos celulares atuais (11 dígitos com DDD) -> total 13 com DDI
            // E fixos atuais (10 dígitos com DDD) -> total 12 com DDI
            if digits.count == 12 || digits.count == 13 {
                return "+" + digits
            }
        }
        
        // Regra 3: Sem DDI (apenas DDD + Número)
        // Celular: DDD (2) + 9 dígitos = 11
        // Fixo: DDD (2) + 8 dígitos = 10
        if digits.count == 10 || digits.count == 11 {
            return "+55" + digits
        }
        
        // Qualquer outro caso é considerado inválido para nossas regras estritas
        return nil
    }
}

extension String {
    var onlyDigits: String {
        return self.filter { $0.isNumber }
    }
}
