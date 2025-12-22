import Foundation
import UserNotifications

/// Gerenciador de notificações locais para resumo diário, semanal e aniversários
@MainActor
class NotificationManager: ObservableObject {
    static let shared = NotificationManager()

    @Published var isAuthorized = false

    private let center = UNUserNotificationCenter.current()
    private let supabase = SupabaseManager.shared

    // MARK: - Notification Identifiers

    private enum NotificationID {
        static let dailySummary = "daily_summary"
        static let weeklySummary = "weekly_summary"
        static let birthdayPrefix = "birthday_"
    }

    // MARK: - Initialization

    private init() {
        Task {
            await checkAuthorizationStatus()
        }
    }

    // MARK: - Authorization

    func requestAuthorization() async -> Bool {
        do {
            let granted = try await center.requestAuthorization(options: [.alert, .sound, .badge])
            isAuthorized = granted
            return granted
        } catch {
            print("Erro ao solicitar permissão de notificações: \(error)")
            return false
        }
    }

    func checkAuthorizationStatus() async {
        let settings = await center.notificationSettings()
        isAuthorized = settings.authorizationStatus == .authorized
    }

    // MARK: - Schedule All Notifications

    func scheduleAllNotifications() async {
        guard isAuthorized else {
            print("Notificações não autorizadas")
            return
        }

        // Cancelar notificações antigas
        await cancelAllScheduledNotifications()

        // Agendar novas notificações baseado nas preferências
        let defaults = UserDefaults.standard

        if defaults.bool(forKey: "daily_summary_enabled") {
            let hour = defaults.integer(forKey: "daily_summary_hour")
            let minute = defaults.integer(forKey: "daily_summary_minute")
            await scheduleDailySummary(hour: hour == 0 ? 8 : hour, minute: minute)
        }

        if defaults.bool(forKey: "weekly_summary_enabled") {
            // Domingo às 20:00 (horário de Brasília)
            await scheduleWeeklySummary(dayOfWeek: 1, hour: 20)
        }

        if defaults.bool(forKey: "birthday_notifications_enabled") {
            await scheduleBirthdayNotifications()
        }
    }

    // MARK: - Daily Summary

    /// Agenda notificação de resumo diário
    /// - Parameters:
    ///   - hour: Hora do dia (0-23)
    ///   - minute: Minuto (0-59)
    func scheduleDailySummary(hour: Int, minute: Int) async {
        let content = UNMutableNotificationContent()
        content.title = "📅 Resumo do Dia"
        content.sound = .default

        // Buscar agendamentos do dia
        let appointments = await fetchTodayAppointments()
        let count = appointments.count

        if count == 0 {
            content.body = "Você não tem agendamentos para hoje. Aproveite o dia!"
        } else if count == 1 {
            content.body = "Você tem 1 agendamento para hoje."
            if let first = appointments.first {
                content.body += " Primeiro: \(first.displayTitle) às \(first.start.hourMinuteString)"
            }
        } else {
            content.body = "Você tem \(count) agendamentos para hoje."
            if let first = appointments.first {
                content.body += " Primeiro: \(first.displayTitle) às \(first.start.hourMinuteString)"
            }
        }

        // Configurar trigger para repetir diariamente
        var dateComponents = DateComponents()
        dateComponents.hour = hour
        dateComponents.minute = minute

        let trigger = UNCalendarNotificationTrigger(dateMatching: dateComponents, repeats: true)

        let request = UNNotificationRequest(
            identifier: NotificationID.dailySummary,
            content: content,
            trigger: trigger
        )

        do {
            try await center.add(request)
            print("Resumo diário agendado para \(hour):\(String(format: "%02d", minute))")
        } catch {
            print("Erro ao agendar resumo diário: \(error)")
        }
    }

    // MARK: - Weekly Summary

    /// Agenda notificação de resumo semanal
    /// - Parameters:
    ///   - dayOfWeek: Dia da semana (1=Domingo, 2=Segunda, ..., 7=Sábado)
    ///   - hour: Hora do dia
    func scheduleWeeklySummary(dayOfWeek: Int, hour: Int) async {
        let content = UNMutableNotificationContent()
        content.title = "📊 Resumo da Semana"
        content.sound = .default

        // Buscar agendamentos da semana
        let appointments = await fetchWeekAppointments()
        let count = appointments.count

        if count == 0 {
            content.body = "Você não tem agendamentos esta semana."
        } else {
            content.body = "Você tem \(count) agendamento\(count == 1 ? "" : "s") esta semana."

            // Contar por dia e ordenar na ordem correta da semana
            var daysCounts: [Int: (name: String, count: Int)] = [:]  // [weekday: (name, count)]
            let calendar = Calendar.current

            for appointment in appointments {
                let weekday = calendar.component(.weekday, from: appointment.start)
                let dayName: String

                // Mapear weekday para nome do dia (2=Segunda...7=Sábado, 1=Domingo)
                switch weekday {
                case 2: dayName = "Segunda-Feira"
                case 3: dayName = "Terça-Feira"
                case 4: dayName = "Quarta-Feira"
                case 5: dayName = "Quinta-Feira"
                case 6: dayName = "Sexta-Feira"
                case 7: dayName = "Sábado"
                case 1: dayName = "Domingo"
                default: dayName = "Desconhecido"
                }

                if var existing = daysCounts[weekday] {
                    existing.count += 1
                    daysCounts[weekday] = existing
                } else {
                    daysCounts[weekday] = (name: dayName, count: 1)
                }
            }

            if !daysCounts.isEmpty {
                // Ordenar por weekday (Segunda=2, Terça=3... Domingo=1)
                let sortedDays = daysCounts.keys.sorted { first, second in
                    // Segunda a Sábado vêm antes de Domingo
                    if first == 1 { return false }  // Domingo por último
                    if second == 1 { return true }
                    return first < second
                }

                let summary = sortedDays.map { weekday in
                    let day = daysCounts[weekday]!
                    return "\(day.name): \(day.count)"
                }.joined(separator: ", ")

                content.body += " (\(summary))"
            }
        }

        // Configurar trigger para repetir semanalmente
        var dateComponents = DateComponents()
        dateComponents.weekday = dayOfWeek
        dateComponents.hour = hour
        dateComponents.minute = 0

        let trigger = UNCalendarNotificationTrigger(dateMatching: dateComponents, repeats: true)

        let request = UNNotificationRequest(
            identifier: NotificationID.weeklySummary,
            content: content,
            trigger: trigger
        )

        do {
            try await center.add(request)
            let dayNames = ["", "Domingo", "Segunda", "Terça", "Quarta", "Quinta", "Sexta", "Sábado"]
            print("Resumo semanal agendado para \(dayNames[dayOfWeek]) às \(hour):00")
        } catch {
            print("Erro ao agendar resumo semanal: \(error)")
        }
    }

    // MARK: - Birthday Notifications

    /// Agenda notificações de aniversário para os próximos 30 dias
    func scheduleBirthdayNotifications() async {
        let patients = await fetchPatientsWithBirthdays()
        let calendar = Calendar.current
        let now = Date()
        let today = calendar.startOfDay(for: now)  // ✅ Usar início do dia para comparação correta

        for patient in patients {
            guard let birthDate = patient.birthDate else { continue }

            // Calcular próximo aniversário
            var birthdayComponents = calendar.dateComponents([.month, .day], from: birthDate)
            birthdayComponents.year = calendar.component(.year, from: now)

            guard var nextBirthday = calendar.date(from: birthdayComponents) else { continue }

            // Se já passou este ano, pegar do próximo ano (comparar apenas datas)
            let nextBirthdayStart = calendar.startOfDay(for: nextBirthday)
            if nextBirthdayStart < today {
                birthdayComponents.year = (birthdayComponents.year ?? 0) + 1
                nextBirthday = calendar.date(from: birthdayComponents) ?? nextBirthday
            }

            // Só agendar se for nos próximos 30 dias (incluindo hoje)
            let daysUntilBirthday = calendar.dateComponents([.day], from: today, to: calendar.startOfDay(for: nextBirthday)).day ?? 0
            guard daysUntilBirthday <= 30 && daysUntilBirthday >= 0 else { continue }

            // Calcular idade
            let age = calendar.dateComponents([.year], from: birthDate, to: nextBirthday).year ?? 0

            let content = UNMutableNotificationContent()
            content.title = "🎂 Aniversário!"

            // ✅ Mensagem diferente se for hoje
            if daysUntilBirthday == 0 {
                content.body = "\(patient.name) faz \(age) anos HOJE! 🎉 Não esqueça de parabenizar."
            } else if daysUntilBirthday == 1 {
                content.body = "\(patient.name) faz \(age) anos amanhã! Prepare-se para parabenizar."
            } else {
                content.body = "\(patient.name) fará \(age) anos em \(daysUntilBirthday) dias!"
            }
            content.sound = .default

            // Agendar para 10h da manhã de domingo (para teste)
            var triggerComponents = calendar.dateComponents([.year, .month, .day], from: nextBirthday)
            triggerComponents.hour = 10
            triggerComponents.minute = 0

            let trigger = UNCalendarNotificationTrigger(dateMatching: triggerComponents, repeats: false)

            let request = UNNotificationRequest(
                identifier: "\(NotificationID.birthdayPrefix)\(patient.id)",
                content: content,
                trigger: trigger
            )

            do {
                try await center.add(request)
                #if DEBUG
                let dateFormatter = DateFormatter()
                dateFormatter.dateFormat = "dd/MM/yyyy HH:mm"
                print("🎂 [Birthday] Agendado: \(patient.name) - \(age) anos - em \(daysUntilBirthday) dias (\(dateFormatter.string(from: nextBirthday)))")
                #endif
            } catch {
                print("❌ [Birthday] Erro ao agendar \(patient.name): \(error)")
            }
        }

        #if DEBUG
        print("🎂 [Birthday] Total de notificações agendadas: \(patients.count)")
        #endif
    }

    // MARK: - Cancel Notifications

    func cancelAllScheduledNotifications() async {
        center.removeAllPendingNotificationRequests()
        print("Todas as notificações canceladas")
    }

    func cancelDailySummary() {
        center.removePendingNotificationRequests(withIdentifiers: [NotificationID.dailySummary])
    }

    func cancelWeeklySummary() {
        center.removePendingNotificationRequests(withIdentifiers: [NotificationID.weeklySummary])
    }

    func cancelBirthdayNotifications() async {
        let requests = await center.pendingNotificationRequests()
        let birthdayIds = requests
            .filter { $0.identifier.hasPrefix(NotificationID.birthdayPrefix) }
            .map { $0.identifier }
        center.removePendingNotificationRequests(withIdentifiers: birthdayIds)
    }

    // MARK: - Data Fetching

    private func fetchTodayAppointments() async -> [Appointment] {
        guard let userId = supabase.effectiveUserId else { return [] }

        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: today)!

        let formatter = ISO8601DateFormatter()

        do {
            let result: [Appointment] = try await supabase.client
                .from("appointments")
                .select()
                .eq("user_id", value: userId)
                .gte("start", value: formatter.string(from: today))
                .lt("start", value: formatter.string(from: tomorrow))
                .neq("status", value: "cancelled")
                .order("start", ascending: true)
                .execute()
                .value

            // ✅ Filtrar apenas agendamentos com pacientes (excluir compromissos pessoais e bloqueios)
            return result.filter { appointment in
                // Excluir apenas se for explicitamente marcado como compromisso pessoal
                if let isPersonal = appointment.isPersonal, isPersonal {
                    return false  // Excluir compromissos pessoais
                }
                return appointment.patientId != nil  // Incluir apenas com paciente
            }
        } catch {
            print("Erro ao buscar agendamentos do dia: \(error)")
            return []
        }
    }

    private func fetchWeekAppointments() async -> [Appointment] {
        guard let userId = supabase.effectiveUserId else { return [] }

        var calendar = Calendar.current
        calendar.timeZone = TimeZone(identifier: "America/Sao_Paulo")!
        calendar.firstWeekday = 1 // Domingo como primeiro dia da semana

        let now = Date()

        // Encontrar o próximo domingo (início da semana)
        let weekday = calendar.component(.weekday, from: now)
        let daysUntilSunday = weekday == 1 ? 0 : (8 - weekday) // Se já é domingo, conta essa semana

        let nextSunday = calendar.date(byAdding: .day, value: daysUntilSunday, to: calendar.startOfDay(for: now))!
        let nextSaturday = calendar.date(byAdding: .day, value: 7, to: nextSunday)! // Domingo até próximo domingo (7 dias completos)

        let formatter = ISO8601DateFormatter()

        do {
            let result: [Appointment] = try await supabase.client
                .from("appointments")
                .select()
                .eq("user_id", value: userId)
                .gte("start", value: formatter.string(from: nextSunday))
                .lt("start", value: formatter.string(from: nextSaturday))
                .neq("status", value: "cancelled")
                .order("start", ascending: true)
                .execute()
                .value

            // ✅ Filtrar apenas agendamentos com pacientes (excluir compromissos pessoais e bloqueios)
            return result.filter { appointment in
                // Excluir apenas se for explicitamente marcado como compromisso pessoal
                if let isPersonal = appointment.isPersonal, isPersonal {
                    return false  // Excluir compromissos pessoais
                }
                return appointment.patientId != nil  // Incluir apenas com paciente
            }
        } catch {
            print("Erro ao buscar agendamentos da semana: \(error)")
            return []
        }
    }

    private func fetchPatientsWithBirthdays() async -> [Patient] {
        guard let userId = supabase.effectiveUserId else { return [] }

        do {
            let result: [Patient] = try await supabase.client
                .from("patients")
                .select()
                .eq("user_id", value: userId)
                .eq("is_active", value: true)
                .not("birth_date", operator: .is, value: "null")
                .execute()
                .value

            return result
        } catch {
            print("Erro ao buscar pacientes com aniversário: \(error)")
            return []
        }
    }

    // MARK: - Debug

    func listPendingNotifications() async {
        let requests = await center.pendingNotificationRequests()
        print("=== Notificações Pendentes (\(requests.count)) ===")
        for request in requests {
            print("- \(request.identifier): \(request.content.title)")
        }
    }
}
