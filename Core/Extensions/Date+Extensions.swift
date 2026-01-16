import Foundation

extension Date {
    // MARK: - Formatação

    /// Retorna a data formatada como "dd/MM/yyyy"
    var formattedDate: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "dd/MM/yyyy"
        formatter.locale = Locale(identifier: "pt_BR")
        return formatter.string(from: self)
    }

    /// Retorna a hora formatada como "HH:mm"
    var formattedTime: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: self)
    }

    /// Retorna a data completa formatada
    var formattedFull: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE, d 'de' MMMM 'de' yyyy"
        formatter.locale = Locale(identifier: "pt_BR")
        return formatter.string(from: self).capitalized
    }

    /// Retorna a data formatada para exibição curta
    var formattedShort: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "d MMM"
        formatter.locale = Locale(identifier: "pt_BR")
        return formatter.string(from: self)
    }

    // MARK: - Comparações

    /// Verifica se a data é hoje
    var isToday: Bool {
        Calendar.current.isDateInToday(self)
    }

    /// Verifica se a data é amanhã
    var isTomorrow: Bool {
        Calendar.current.isDateInTomorrow(self)
    }

    /// Verifica se a data é ontem
    var isYesterday: Bool {
        Calendar.current.isDateInYesterday(self)
    }

    /// Verifica se a data está no passado
    var isPast: Bool {
        self < Date()
    }

    /// Verifica se a data está no futuro
    var isFuture: Bool {
        self > Date()
    }

    // MARK: - Manipulação

    /// Retorna o início do dia
    var startOfDay: Date {
        Calendar.current.startOfDay(for: self)
    }

    /// Retorna o fim do dia (23:59:59)
    var endOfDay: Date {
        var components = DateComponents()
        components.day = 1
        components.second = -1
        return Calendar.current.date(byAdding: components, to: startOfDay) ?? self
    }

    /// Retorna o início da semana
    var startOfWeek: Date {
        var calendar = Calendar.current
        calendar.firstWeekday = 2 // Segunda-feira (1 = Domingo, 2 = Segunda)
        let components = calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: self)
        return calendar.date(from: components) ?? self
    }

    /// Retorna o fim da semana
    var endOfWeek: Date {
        Calendar.current.date(byAdding: .day, value: 6, to: startOfWeek) ?? self
    }

    /// Retorna o início do mês
    var startOfMonth: Date {
        let calendar = Calendar.current
        let components = calendar.dateComponents([.year, .month], from: self)
        return calendar.date(from: components) ?? self
    }

    /// Retorna o fim do mês
    var endOfMonth: Date {
        var components = DateComponents()
        components.month = 1
        components.day = -1
        return Calendar.current.date(byAdding: components, to: startOfMonth) ?? self
    }

    /// Adiciona dias à data
    func adding(days: Int) -> Date {
        Calendar.current.date(byAdding: .day, value: days, to: self) ?? self
    }

    /// Adiciona meses à data
    func adding(months: Int) -> Date {
        Calendar.current.date(byAdding: .month, value: months, to: self) ?? self
    }

    /// Adiciona anos à data
    func adding(years: Int) -> Date {
        Calendar.current.date(byAdding: .year, value: years, to: self) ?? self
    }

    // MARK: - Componentes

    /// Retorna o dia da semana (1 = Domingo, 7 = Sábado)
    var weekday: Int {
        Calendar.current.component(.weekday, from: self)
    }

    /// Retorna o dia do mês
    var day: Int {
        Calendar.current.component(.day, from: self)
    }

    /// Retorna o mês
    var month: Int {
        Calendar.current.component(.month, from: self)
    }

    /// Retorna o ano
    var year: Int {
        Calendar.current.component(.year, from: self)
    }

    /// Retorna a hora
    var hour: Int {
        Calendar.current.component(.hour, from: self)
    }

    /// Retorna os minutos
    var minute: Int {
        Calendar.current.component(.minute, from: self)
    }

    // MARK: - Idade

    /// Calcula a idade a partir desta data
    var age: Int {
        Calendar.current.dateComponents([.year], from: self, to: Date()).year ?? 0
    }

    // MARK: - Nomes

    /// Nome do dia da semana
    var weekdayName: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE"
        formatter.locale = Locale(identifier: "pt_BR")
        return formatter.string(from: self).capitalized
    }

    /// Nome abreviado do dia da semana
    var weekdayShortName: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE"
        formatter.locale = Locale(identifier: "pt_BR")
        return formatter.string(from: self)
    }

    /// Nome do mês
    var monthName: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMMM"
        formatter.locale = Locale(identifier: "pt_BR")
        return formatter.string(from: self).capitalized
    }
}
