import Foundation
import UserNotifications

/// Gerenciador de notificações locais para resumo diário, semanal e aniversários
@MainActor
class NotificationManager: ObservableObject {
    static let shared = NotificationManager()
    
    @Published var isAuthorized = false
    
    // Dependências
    private let center = UNUserNotificationCenter.current()
    private let supabase = SupabaseManager.shared
    
    // MARK: - Notification Identifiers
    
    private enum NotificationID {
        static let dailySummary = "daily_summary"
        static let weeklySummary = "weekly_summary"
        static let birthdayPrefix = "birthday_"
        static let appointmentReminderPrefix = "appointment_reminder_"
    }
    
    // MARK: - Initialization
    
    private init() {
        Task {
            await checkAuthorizationStatus()
        }
    }
    
    // MARK: - Authorization
    
    /// Solicita permissão paara enviar notificações
    func requestAuthorization() async -> Bool {
        do {
            let granted = try await center.requestAuthorization(options: [.alert, .sound, .badge])
            isAuthorized = granted
            return granted
        } catch {
            AppLogger.error("Erro ao solicitar permissão de notificações", error: error)
            return false
        }
    }
    
    /// Verifica o status atual de autorização
    func checkAuthorizationStatus() async {
        let settings = await center.notificationSettings()
        isAuthorized = settings.authorizationStatus == .authorized
    }
    
    // MARK: - Schedule All Notifications
    
    /// Reagenda todas as notificações com base nas configurações do usuário
    func scheduleAllNotifications() async {
        guard isAuthorized else {
            AppLogger.log("⚠️ Notificações não autorizadas. Ignorando agendamento.", category: .notification)
            return
        }
        
        // 1. Cancelar notificações antigas
        await cancelAllScheduledNotifications()
        
        // 2. Agendar novas notificações baseado nas preferências
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
        
        if defaults.bool(forKey: "appointment_reminder_enabled") {
            let reminderMinutes = defaults.integer(forKey: "appointment_reminder_minutes")
            await scheduleAppointmentReminders(minutesBefore: reminderMinutes == 0 ? 30 : reminderMinutes)
        }
    }
    
    // MARK: - Daily Summary
    
    /// Agenda notificação de resumo diário para os próximos 14 dias
    /// - Parameters:
    ///   - hour: Hora do dia (0-23)
    ///   - minute: Minuto (0-59)
    func scheduleDailySummary(hour: Int, minute: Int) async {
        // Remover notificação antiga (repetitiva) se existir
        center.removePendingNotificationRequests(withIdentifiers: [NotificationID.dailySummary])
        
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        
        // Agendar para os próximos 14 dias
        for dayOffset in 0..<14 {
            guard let date = calendar.date(byAdding: .day, value: dayOffset, to: today) else { continue }
            guard let nextDay = calendar.date(byAdding: .day, value: 1, to: date) else { continue }
            
            // Ignorar dias passados (se hora já passou hoje)
            let now = Date()
            let triggerDate = calendar.date(bySettingHour: hour, minute: minute, second: 0, of: date)!
            if triggerDate < now {
                // Se já passou o horário hoje, não agendar para hoje (ou agendar para amanhã? não, o loop já cobre amanhã)
                continue 
            }
            
            // Buscar agendamentos para este dia específico
            let appointments = await fetchAppointments(from: date, to: nextDay)
            let count = appointments.count
            
            // Criar conteúdo
            let content = UNMutableNotificationContent()
            content.title = "📅 Resumo do Dia"
            content.sound = .default
            
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
            
            // Configurar trigger
            let triggerComponents = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: triggerDate)
            let trigger = UNCalendarNotificationTrigger(dateMatching: triggerComponents, repeats: false)
            
            let identifier = "\(NotificationID.dailySummary)_\(date.formatted(.iso8601.year().month().day()))"
            let request = UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)
            
        addRequest(request, description: "Resumo diário para \(date.formatted(.dateTime.day().month()))")
        }
    }

    /// Reagendar todas as notificações dinâmicas (Resumo + Lembretes) para garantir dados atualizados
    func refreshNotifications() async {
        guard isAuthorized else { return }
        let defaults = UserDefaults.standard
        
        AppLogger.log("🔄 [Notification] Atualizando todas as notificações dinâmicas...", category: .notification)
        
        // 1. Atualizar Resumo Diário
        if defaults.bool(forKey: "daily_summary_enabled") {
            let hour = defaults.integer(forKey: "daily_summary_hour")
            let minute = defaults.integer(forKey: "daily_summary_minute")
            await scheduleDailySummary(hour: hour == 0 ? 8 : hour, minute: minute)
        }
        
        // 2. Atualizar Lembretes de Agendamentos
        if defaults.bool(forKey: "appointment_reminder_enabled") {
            let reminderMinutes = defaults.integer(forKey: "appointment_reminder_minutes")
            await scheduleAppointmentReminders(minutesBefore: reminderMinutes == 0 ? 30 : reminderMinutes)
        }
    }
    
    // MARK: - Weekly Summary
    
    /// Agenda notificação de resumo semanal
    /// - Parameters:
    ///   - dayOfWeek: Dia da semana (1=Domingo, 2=Segunda, ..., 7=Sábado)
    ///   - hour: Hora do dia
    func scheduleWeeklySummary(dayOfWeek: Int, hour: Int) async {
        // Remover anterior
        center.removePendingNotificationRequests(withIdentifiers: [NotificationID.weeklySummary])

        let content = UNMutableNotificationContent()
        content.title = "📊 Resumo da Semana"
        content.sound = .default
        
        // Calcular intervalo da próxima semana
        var calendar = Calendar.current
        calendar.timeZone = TimeZone(identifier: "America/Sao_Paulo") ?? .current
        calendar.firstWeekday = 1 // Domingo
        
        let now = Date()
        let weekday = calendar.component(.weekday, from: now)
        let daysUntilSunday = weekday == 1 ? 0 : (8 - weekday)
        
        guard let nextSunday = calendar.date(byAdding: .day, value: daysUntilSunday, to: calendar.startOfDay(for: now)),
              let nextSaturday = calendar.date(byAdding: .day, value: 7, to: nextSunday) else {
            return
        }
        
        // Buscar agendamentos
        let appointments = await fetchAppointments(from: nextSunday, to: nextSaturday)
        let count = appointments.count
        
        if count == 0 {
            content.body = "Você não tem agendamentos esta semana."
        } else {
            content.body = "Você tem \(count) agendamento\(count == 1 ? "" : "s") esta semana."
            
            // Resumo por dia
            let summary = generateWeeklySummaryText(appointments: appointments, calendar: calendar)
            if !summary.isEmpty {
                content.body += " (\(summary))"
            }
        }
        
        var dateComponents = DateComponents()
        if let nextSundayWithTime = calendar.date(bySettingHour: hour, minute: 0, second: 0, of: nextSunday) {
             dateComponents = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: nextSundayWithTime)
        }
        
        // Trigger único para o próximo domingo (será reagendado na próxima abertura do app)
        let trigger = UNCalendarNotificationTrigger(dateMatching: dateComponents, repeats: false)
        let request = UNNotificationRequest(identifier: NotificationID.weeklySummary, content: content, trigger: trigger)
        
        addRequest(request, description: "Resumo semanal")
    }
    
    private func generateWeeklySummaryText(appointments: [Appointment], calendar: Calendar) -> String {
        var daysCounts: [Int: (name: String, count: Int)] = [:]
        
        for appointment in appointments {
            let weekday = calendar.component(.weekday, from: appointment.start)
            let dayName: String
            
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
        
        let sortedDays = daysCounts.keys.sorted { first, second in
            if first == 1 { return false } // Domingo no fim
            if second == 1 { return true }
            return first < second
        }
        
        return sortedDays.map { weekday in
            let day = daysCounts[weekday]!
            return "\(day.name): \(day.count)"
        }.joined(separator: ", ")
    }
    
    // MARK: - Birthday Notifications
    
    func scheduleBirthdayNotifications() async {
        let patients = await fetchPatientsWithBirthdays()
        let calendar = Calendar.current
        let now = Date()
        let today = calendar.startOfDay(for: now)
        
        for patient in patients {
            guard let birthDate = patient.birthDate else { continue }
            
            // Calcular próximo aniversário
            var birthdayComponents = calendar.dateComponents([.month, .day], from: birthDate)
            birthdayComponents.year = calendar.component(.year, from: now)
            
            guard var nextBirthday = calendar.date(from: birthdayComponents) else { continue }
            
            // Ajustar para próximo ano se já passou
            let nextBirthdayStart = calendar.startOfDay(for: nextBirthday)
            if nextBirthdayStart < today {
                birthdayComponents.year = (birthdayComponents.year ?? 0) + 1
                nextBirthday = calendar.date(from: birthdayComponents) ?? nextBirthday
            }
            
            // Verificar intervalo (30 dias)
            guard let daysUntilBirthday = calendar.dateComponents([.day], from: today, to: calendar.startOfDay(for: nextBirthday)).day,
                  daysUntilBirthday >= 0 && daysUntilBirthday <= 30 else {
                continue
            }
            
            // Calcular idade
            let age = calendar.dateComponents([.year], from: birthDate, to: nextBirthday).year ?? 0
            
            let content = UNMutableNotificationContent()
            content.title = "🎂 Aniversário!"
            
            if daysUntilBirthday == 0 {
                content.body = "\(patient.name) faz \(age) anos HOJE! 🎉 Não esqueça de parabenizar."
            } else if daysUntilBirthday == 1 {
                content.body = "\(patient.name) faz \(age) anos amanhã! Prepare-se para parabenizar."
            } else {
                content.body = "\(patient.name) fará \(age) anos em \(daysUntilBirthday) dias!"
            }
            content.sound = .default
            
            var triggerComponents = calendar.dateComponents([.year, .month, .day], from: nextBirthday)
            triggerComponents.hour = 8 // Fixo às 08:00
            triggerComponents.minute = 0
            
            let trigger = UNCalendarNotificationTrigger(dateMatching: triggerComponents, repeats: false)
            let request = UNNotificationRequest(identifier: "\(NotificationID.birthdayPrefix)\(patient.id)", content: content, trigger: trigger)
            
            addRequest(request, description: "Aniversário \(patient.name)")
        }
    }
    
    // MARK: - Appointment Reminders
    
    func scheduleAppointmentReminders(minutesBefore: Int) async {
        let now = Date()
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: now)
        let tomorrow = calendar.date(byAdding: .day, value: 7, to: today)! // Buscar próximos 7 dias para garantir cobertura
        
        // Buscar agendamentos futuros
        let appointments = await fetchAppointments(from: now, to: tomorrow)
        
        for appointment in appointments {
            guard let reminderTime = calendar.date(byAdding: .minute, value: -minutesBefore, to: appointment.start) else { continue }
            
            guard reminderTime > now else { continue }
            
            let content = UNMutableNotificationContent()
            content.title = "Próximo Atendimento"
            content.body = "\(appointment.displayTitle) • \(appointment.start.hourMinuteString)"
            content.sound = .default
            content.categoryIdentifier = "APPOINTMENT_REMINDER"
            
            let triggerComponents = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: reminderTime)
            let trigger = UNCalendarNotificationTrigger(dateMatching: triggerComponents, repeats: false)
            
            let request = UNNotificationRequest(identifier: "\(NotificationID.appointmentReminderPrefix)\(appointment.id)", content: content, trigger: trigger)
            
            addRequest(request, description: "Lembrete para \(appointment.displayTitle)")
        }
    }
    
    // MARK: - Cancel Helpers
    
    func cancelAllScheduledNotifications() async {
        // Cancelar apenas as pendentes genéricas ou passadas. 
        // Na verdade, ao reagendar, já limpamos. Mas para "reset" geral pode ser útil.
        // O método scheduleAllNotifications já chama este primeiro.
        center.removeAllPendingNotificationRequests()
        // #if DEBUG block removed for cleanup
    }
    
    // MARK: - Data Fetching (Consolidated)
    
    /// Busca agendamentos em um intervalo de datas
    private func fetchAppointments(from start: Date, to end: Date) async -> [Appointment] {
        guard let userId = supabase.effectiveUserId else { return [] }
        
        let formatter = ISO8601DateFormatter()
        
        do {
            let result: [Appointment] = try await supabase.client
                .from("appointments")
                .select()
                .eq("user_id", value: userId)
                .gte("start", value: formatter.string(from: start))
                .lt("start", value: formatter.string(from: end))
                .neq("status", value: "cancelled")
                .order("start", ascending: true)
                .execute()
                .value
            
            // Filtro removido para incluir TODOS os agendamentos (pessoais ou sem paciente) na contagem
            return result
        } catch {
            print("❌ Erro ao buscar agendamentos (Notifications): \(error)")
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
            print("❌ Erro ao buscar aniversariantes: \(error)")
            return []
        }
    }
    
    // MARK: - Helper (Private)
    
    private func addRequest(_ request: UNNotificationRequest, description: String) {
        Task {
            do {
                try await center.add(request)
                // #if DEBUG block removed for cleanup
            } catch {
                print("❌ Erro ao agendar (\(description)): \(error)")
            }
        }
    }
}
