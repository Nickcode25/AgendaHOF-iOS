import SwiftUI

/// Constantes e configurações do calendário
enum CalendarConstants {
    // MARK: - Horários
    static let startHour = 7   // 07:00
    static let endHour = 24    // 24:00 (meia-noite)
    static let totalHours = endHour - startHour  // 17 horas
    static let totalMinutes = totalHours * 60    // 1020 minutos

    // MARK: - Dimensões Base (Vista Diária)
    /// Altura por hora na vista DIÁRIA (mais compacta)
    static let hourHeight: CGFloat = 60

    // MARK: - Nova Arquitetura Semanal (baseada em minutos)
    /// 🧠 REGRA DE OURO: tempo manda no layout
    /// 2.5pt por minuto = escala proporcional real (base, sem zoom)
    /// 15min = 37.5pt | 30min = 75pt | 60min = 150pt | 90min = 225pt
    static let baseMinuteHeight: CGFloat = 2.5

    /// Altura por minuto (para compatibilidade, usa valor base)
    static let minuteHeight: CGFloat = 2.5

    /// Altura por hora na vista semanal (derivada de minuteHeight)
    static var weekHourHeight: CGFloat {
        minuteHeight * 60  // 150pt por hora
    }

    static let timeColumnWidth: CGFloat = 50
    static let dayHeaderHeight: CGFloat = 60  // Altura do header dos dias (aumentada para acomodar o círculo)
    static let compactDayHeaderHeight: CGFloat = 68
    static let weekDayColumnWidth: CGFloat = 120  // Largura fixa para cada coluna de dia

    // MARK: - Helpers de Escala Semanal (baseados em minutos)

    /// Converte horário para minutos desde o início do dia de trabalho
    static func minutesFromStart(for date: Date) -> Int {
        let calendar = Calendar.current
        let hour = calendar.component(.hour, from: date)
        let minute = calendar.component(.minute, from: date)
        return (hour - startHour) * 60 + minute
    }

    /// Calcula a posição Y para vista semanal (baseado em minutos)
    static func weekYPosition(for date: Date) -> CGFloat {
        CGFloat(minutesFromStart(for: date)) * minuteHeight
    }

    /// Calcula a altura para vista semanal baseado na duração em minutos
    static func weekHeight(from start: Date, to end: Date) -> CGFloat {
        let durationMinutes = end.timeIntervalSince(start) / 60.0
        return CGFloat(durationMinutes) * minuteHeight
    }

    /// Altura total do grid semanal
    static var totalWeekGridHeight: CGFloat {
        CGFloat(totalMinutes) * minuteHeight  // 14h * 60min * 2.5pt = 2100pt
    }

    // MARK: - Cores por tipo de agendamento
    static func appointmentColor(for appointment: Appointment) -> Color {
        // Bloqueios recorrentes = CINZA (isPersonal + sem paciente + sem procedimento)
        // Compromissos pessoais reais têm procedimento/descrição
        if appointment.isPersonalAppointment && 
           appointment.patientId == nil && 
           appointment.procedure == nil {
            return .gray
        }
        
        // Compromissos pessoais = AZUL
        if appointment.isPersonalAppointment {
            return .blue
        }

        // Agendamentos de pacientes - cor por status
        switch appointment.status {
        case .confirmed:
            return .green
        case .cancelled:
            return .red
        case .scheduled, .completed, .done:
            return .orange
        }
    }

    static func appointmentBackgroundColor(for appointment: Appointment) -> Color {
        appointmentColor(for: appointment).opacity(0.15)
    }

    // MARK: - Helpers de posicionamento

    /// Calcula a posição Y baseado na hora
    static func yPosition(for date: Date) -> CGFloat {
        let calendar = Calendar.current
        let hour = calendar.component(.hour, from: date)
        let minute = calendar.component(.minute, from: date)

        let hoursFromStart = CGFloat(hour - startHour)
        let minuteFraction = CGFloat(minute) / 60.0

        return (hoursFromStart + minuteFraction) * hourHeight
    }

    /// Calcula a altura baseado na duração
    static func height(from start: Date, to end: Date) -> CGFloat {
        let duration = end.timeIntervalSince(start)
        let hours = duration / 3600.0
        return CGFloat(hours) * hourHeight
    }

    /// Altura total do grid
    static var totalGridHeight: CGFloat {
        CGFloat(totalHours) * hourHeight
    }

    // MARK: - Conversão Inversa (Y -> Data)

    /// Converte uma posição Y no grid para uma Data (horário)
    static func date(for yPosition: CGFloat, baseDate: Date) -> Date {
        // 1. Calcular horas totais baseadas na posição Y
        let totalHoursFromStart = yPosition / hourHeight

        // 2. Separar horas e minutos
        let hour = Int(totalHoursFromStart)
        let minutes = Int((totalHoursFromStart - CGFloat(hour)) * 60)

        // 3. Somar à hora inicial (7:00)
        let finalHour = startHour + hour
        let finalMinutes = (minutes / 15) * 15 // Arredondar para 15 min

        // 4. Criar data
        var calendar = Calendar.current
        calendar.timeZone = TimeZone.current

        return calendar.date(bySettingHour: finalHour, minute: finalMinutes, second: 0, of: baseDate) ?? baseDate
    }
}

// MARK: - Feriados Brasil (cálculo local, sem API externa)

struct BrazilianHoliday: Identifiable, Hashable {
    enum Kind: String, Hashable {
        case nacional
        case facultativo
        case comemorativo

        var displayName: String {
            switch self {
            case .nacional:
                return "Nacional"
            case .facultativo:
                return "Facultativo"
            case .comemorativo:
                return "Comemorativo"
            }
        }

        var color: Color {
            switch self {
            case .nacional:
                return .green
            case .facultativo:
                return .orange
            case .comemorativo:
                return .blue
            }
        }
    }

    let date: Date
    let name: String
    let kind: Kind

    var id: String {
        "\(BrazilianHolidayCalendar.dateKey(for: date))-\(name)"
    }
}

enum BrazilianHolidayCalendar {
    private static var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: "pt_BR")
        calendar.timeZone = TimeZone(identifier: "America/Sao_Paulo") ?? .current
        return calendar
    }

    static func holiday(on date: Date) -> BrazilianHoliday? {
        let year = calendar.component(.year, from: date)
        return holidaysByDate(for: year)[dateKey(for: date)]
    }

    static func holidays(in year: Int) -> [BrazilianHoliday] {
        holidaysByDate(for: year)
            .values
            .sorted { $0.date < $1.date }
    }

    fileprivate static func dateKey(for date: Date) -> String {
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        let year = components.year ?? 0
        let month = components.month ?? 0
        let day = components.day ?? 0
        return String(format: "%04d-%02d-%02d", year, month, day)
    }

    private static func holidaysByDate(for year: Int) -> [String: BrazilianHoliday] {
        var holidays: [BrazilianHoliday] = []

        let fixedHolidays: [(month: Int, day: Int, name: String, kind: BrazilianHoliday.Kind)] = [
            (1, 1, "Confraternização Universal", .nacional),
            (4, 21, "Tiradentes", .nacional),
            (5, 1, "Dia do Trabalho", .nacional),
            (9, 7, "Independência do Brasil", .nacional),
            (10, 12, "Nossa Senhora Aparecida", .nacional),
            (11, 2, "Finados", .nacional),
            (11, 15, "Proclamação da República", .nacional),
            (11, 20, "Consciência Negra", .nacional),
            (12, 25, "Natal", .nacional)
        ]

        for holiday in fixedHolidays {
            if let date = date(year: year, month: holiday.month, day: holiday.day) {
                holidays.append(
                    BrazilianHoliday(
                        date: date,
                        name: holiday.name,
                        kind: holiday.kind
                    )
                )
            }
        }

        if let easterDate = easterSunday(for: year) {
            let movableHolidays: [(offset: Int, name: String, kind: BrazilianHoliday.Kind)] = [
                (-47, "Carnaval", .facultativo),
                (-2, "Sexta-feira Santa", .nacional),
                (0, "Páscoa", .comemorativo),
                (60, "Corpus Christi", .facultativo)
            ]

            for holiday in movableHolidays {
                if let date = calendar.date(byAdding: .day, value: holiday.offset, to: easterDate) {
                    holidays.append(
                        BrazilianHoliday(
                            date: date,
                            name: holiday.name,
                            kind: holiday.kind
                        )
                    )
                }
            }
        }

        return holidays.reduce(into: [:]) { map, holiday in
            map[dateKey(for: holiday.date)] = holiday
        }
    }

    private static func date(year: Int, month: Int, day: Int) -> Date? {
        calendar.date(from: DateComponents(year: year, month: month, day: day))
    }

    /// Algoritmo de Meeus/Jones/Butcher para calcular a data da Páscoa.
    private static func easterSunday(for year: Int) -> Date? {
        let a = year % 19
        let b = year / 100
        let c = year % 100
        let d = b / 4
        let e = b % 4
        let f = (b + 8) / 25
        let g = (b - f + 1) / 3
        let h = (19 * a + b - d - g + 15) % 30
        let i = c / 4
        let k = c % 4
        let l = (32 + 2 * e + 2 * i - h - k) % 7
        let m = (a + 11 * h + 22 * l) / 451
        let month = (h + l - 7 * m + 114) / 31
        let day = ((h + l - 7 * m + 114) % 31) + 1

        return calendar.date(from: DateComponents(year: year, month: month, day: day))
    }
}

// MARK: - Extensões de Data

extension Date {
    /// Hora formatada (HH:mm)
    var hourMinuteString: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: self)
    }

    /// Apenas hora (ex: "09")
    var hourString: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH"
        return formatter.string(from: self)
    }

    /// Dia da semana abreviado (ex: "Seg")
    var shortWeekdayName: String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "pt_BR")
        formatter.dateFormat = "EEE"
        return formatter.string(from: self).capitalized
    }

    /// Número do dia (ex: "15")
    var dayNumber: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "d"
        return formatter.string(from: self)
    }
}
