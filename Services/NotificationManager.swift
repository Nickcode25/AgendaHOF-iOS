import Foundation
import UserNotifications
import SwiftUI

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
        static let weeklyPreview = "weekly_preview"
        static let dailyFinancialSummary = "daily_financial_summary"
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
    /// Solicita permissão paara enviar notificações
    func requestAuthorization() async -> Bool {
        do {
            let granted = try await center.requestAuthorization(options: [.alert, .sound, .badge])
            isAuthorized = granted
            
            if granted {
                await enableDefaultNotifications()
                await scheduleAllNotifications()
            }
            
            return granted
        } catch {
            AppLogger.error("Erro ao solicitar permissão de notificações", error: error)
            return false
        }
    }
    
    /// Habilita todas as notificações por padrão se ainda não foram configuradas
    private func enableDefaultNotifications() async {
        let defaults = UserDefaults.standard
        
        // Helper para definir true apenas se a chave não existir
        func setTrueIfNotSet(_ key: String) {
            if defaults.object(forKey: key) == nil {
                defaults.set(true, forKey: key)
            }
        }
        
        // 1. Resumo Diário
        setTrueIfNotSet("daily_summary_enabled")
        if defaults.object(forKey: "daily_summary_hour") == nil {
            defaults.set(8, forKey: "daily_summary_hour")
            defaults.set(0, forKey: "daily_summary_minute")
        }
        
        // 2. Resumo Financeiro
        setTrueIfNotSet("daily_financial_summary_enabled")
        
        // 3. Resumo Semanal
        setTrueIfNotSet("weekly_summary_enabled")
        

        // 5. Lembretes
        setTrueIfNotSet("appointment_reminder_enabled")
        if defaults.object(forKey: "appointment_reminder_minutes") == nil {
            defaults.set(30, forKey: "appointment_reminder_minutes")
        }
        
        AppLogger.log("✅ Todas as notificações habilitadas por padrão (Setup Inicial)", category: .notification)
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
        
        // DESATIVADO: Resumo diário agora é enviado via Push pelo servidor
        /*
        if defaults.bool(forKey: "daily_summary_enabled") {
            let hour = defaults.integer(forKey: "daily_summary_hour")
            let minute = defaults.integer(forKey: "daily_summary_minute")
            await scheduleDailySummary(hour: hour == 0 ? 8 : hour, minute: minute)
        }
        */
        
        // DESATIVADO: Notificação financeira agora é enviada pelo Supabase
        // A notificação local calculava R$ 0,00 (incorreto)
        // if defaults.bool(forKey: "daily_financial_summary_enabled") && supabase.isOwner {
        //      // Agendar para 21:00
        //      await scheduleDailyFinancialSummary()
        // }
        
        // DESATIVADO: Notificação de resumo semanal agora é enviada pelo Supabase
        // A notificação local estava sendo enviada 3 vezes
        // if defaults.bool(forKey: "weekly_summary_enabled") {
        //     // Sábado às 22:00 (horário de São Paulo)
        //     await scheduleWeeklySummary(dayOfWeek: 7, hour: 22)
        // }
        
        if defaults.bool(forKey: "weekly_preview_enabled") {
            // Domingo às 20:00 (horário de São Paulo)
            await scheduleWeeklyPreview()
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
            guard let triggerDate = calendar.date(bySettingHour: hour, minute: minute, second: 0, of: date) else { continue }
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
    
    // MARK: - Daily Financial Summary (Owner Only)
    
    /// Agenda notificação de resumo financeiro diário às 21:00
    /// Exibe número de pacientes atendidos e faturamento do dia
    /// - Parameter forceUpdate: Se true, força atualização mesmo se já foi agendada hoje
    func scheduleDailyFinancialSummary(forceUpdate: Bool = false) async {
        AppLogger.log("💰 Agendando Resumo Financeiro Diário... (force: \(forceUpdate))", category: .notification)
        
        guard supabase.isOwner else {
            AppLogger.log("💰 Usuário não é Owner. Cancelando.", category: .notification)
            center.removePendingNotificationRequests(withIdentifiers: [NotificationID.dailyFinancialSummary])
            return
        }
        
        var calendar = Calendar.current
        calendar.timeZone = TimeZone(identifier: "America/Sao_Paulo") ?? .current
        
        let now = Date()
        let today = calendar.startOfDay(for: now)
        
        // Verificar se JÁ foi enviada hoje (proteção contra duplicatas)
        if !forceUpdate && hasSentFinancialSummary(for: today) {
            AppLogger.log("💰 Resumo financeiro já foi enviado hoje. Ignorando.", category: .notification)
            return
        }
        
        // Verificar se já existe uma notificação agendada para hoje
        let pendingNotifications = await center.pendingNotificationRequests()
        let hasScheduledForToday = pendingNotifications.contains { request in
            guard request.identifier == NotificationID.dailyFinancialSummary,
                  let trigger = request.trigger as? UNCalendarNotificationTrigger,
                  let triggerDate = trigger.nextTriggerDate() else {
                return false
            }
            return calendar.isDate(triggerDate, inSameDayAs: today)
        }
        
        if !forceUpdate && hasScheduledForToday {
            AppLogger.log("💰 Já existe notificação agendada para hoje. Ignorando duplicata.", category: .notification)
            return
        }
        
        // Calcular horário de entrega (21:00)
        guard let triggerDate = calendar.date(bySettingHour: 21, minute: 0, second: 0, of: today) else {
            AppLogger.error("Erro ao calcular horário de notificação financeira", error: nil)
            return
        }
        
        var finalTriggerDate = triggerDate
        var shouldSendImmediately = false
        
        #if DEBUG
        // Em modo debug, agendar para 10 segundos no futuro para teste
        if let debugTrigger = calendar.date(byAdding: .second, value: 10, to: now) {
            finalTriggerDate = debugTrigger
            AppLogger.log("🐛 [DEBUG] Agendando notificação para 10 segundos (teste)", category: .notification)
        } else {
            return
        }
        #else
        // Se já passou das 21:00 hoje, verificar se ainda faz sentido enviar
        if triggerDate < now {
            let minutesLate = Int(now.timeIntervalSince(triggerDate) / 60)
            
            // Se atrasou menos de 2 horas, enviar imediatamente
            if minutesLate < 120 {
                AppLogger.log("💰 Passou das 21:00 (\(minutesLate)min atrás). Enviando imediatamente.", category: .notification)
                finalTriggerDate = calendar.date(byAdding: .second, value: 3, to: now) ?? now
                shouldSendImmediately = true
            } else {
                // Já é muito tarde (depois das 23:00), agendar para amanhã
                AppLogger.log("💰 Muito tarde para enviar hoje (\(minutesLate)min). Agendando para amanhã.", category: .notification)
                guard let tomorrow = calendar.date(byAdding: .day, value: 1, to: today),
                      let tomorrowTrigger = calendar.date(bySettingHour: 21, minute: 0, second: 0, of: tomorrow) else {
                    return
                }
                finalTriggerDate = tomorrowTrigger
            }
        }
        #endif
        
        // ⭐ PASSO 1: CALCULAR os dados ANTES de remover a notificação antiga
        let startOfDay = calendar.startOfDay(for: now)
        guard let endOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay) else { return }
        
        let totalRevenue = await calculateRevenue(from: startOfDay, to: endOfDay)
        let patientCount = await countAttendedPatients(from: startOfDay, to: endOfDay)
        
        AppLogger.log("💰 Faturamento: R$ \(totalRevenue) | Pacientes: \(patientCount)", category: .notification)
        
        // ⭐ PASSO 2: Se não houver pacientes, RETORNAR sem remover a antiga
        // Isso mantém uma notificação válida de ontem, se existir
        if patientCount == 0 {
            AppLogger.log("💰 Sem pacientes atendidos. Notificação não enviada.", category: .notification)
            // Marcar como enviada para evitar reagendamentos desnecessários
            markFinancialSummaryAsSent(for: today)
            return // ⚠️ CRITICAL: Return ANTES de remover - mantém notificação antiga
        }
        
        // ⭐ PASSO 3: AGORA SIM remover a antiga (só chegamos aqui com dados válidos)
        center.removePendingNotificationRequests(withIdentifiers: [NotificationID.dailyFinancialSummary])
        
        // ⭐ PASSO 4: Criar nova notificação com dados frescos
        // Formatar valor em Real Brasileiro
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.locale = Locale(identifier: "pt_BR")
        let revenueDouble = NSDecimalNumber(decimal: totalRevenue).doubleValue
        let revenueString = formatter.string(from: NSNumber(value: revenueDouble)) ?? "R$ 0,00"
        
        // Criar conteúdo da notificação
        let content = UNMutableNotificationContent()
        content.title = "📊 Resumo do Dia"
        content.body = getFinancialMotivationalMessage(revenue: totalRevenue, patientCount: patientCount, formattedRevenue: revenueString)
        content.sound = .default
        
        let triggerComponents = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: finalTriggerDate)
        let trigger = UNCalendarNotificationTrigger(dateMatching: triggerComponents, repeats: false)
        
        let request = UNNotificationRequest(
            identifier: NotificationID.dailyFinancialSummary,
            content: content,
            trigger: trigger
        )
        
        addRequest(request, description: "Resumo Financeiro Diário")
        
        // Se for envio imediato, marcar como enviado para evitar duplicidade
        if shouldSendImmediately {
            // Aguardar 5 segundos antes de marcar como enviado (garantir que a notificação foi entregue)
            Task {
                try? await Task.sleep(nanoseconds: 5_000_000_000)
                markFinancialSummaryAsSent(for: today)
            }
        }
        
        #if DEBUG
        AppLogger.log("✅ Resumo Financeiro agendado para \(finalTriggerDate.formatted(.dateTime.hour().minute().second()))", category: .notification)
        #else
        AppLogger.log("✅ Resumo Financeiro agendado para \(finalTriggerDate.formatted(.dateTime.hour().minute()))", category: .notification)
        #endif
    }
    
    // MARK: - Helpers: Sent Status
    
    private func financialSummaryKey(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return "financial_summary_sent_\(formatter.string(from: date))"
    }
    
    /// Verifica se o resumo financeiro já foi enviado para uma data específica
    func hasSentFinancialSummary(for date: Date) -> Bool {
        return UserDefaults.standard.bool(forKey: financialSummaryKey(for: date))
    }
    
    /// Marca o resumo financeiro como enviado para uma data
    func markFinancialSummaryAsSent(for date: Date) {
        UserDefaults.standard.set(true, forKey: financialSummaryKey(for: date))
    }
    
    /// Retorna mensagem motivacional baseada no faturamento do dia
    private func getFinancialMotivationalMessage(revenue: Decimal, patientCount: Int, formattedRevenue: String) -> String {
        let revenueDouble = NSDecimalNumber(decimal: revenue).doubleValue
        let patientText = "Você atendeu \(patientCount) paciente\(patientCount == 1 ? "" : "s") e faturou"
        
        switch revenueDouble {
        case 0...1000:
            return "\(patientText) \(formattedRevenue) hoje. Cada passo conta! 💪"
        case 1001...5000:
            return "Ótimo! \(patientText) \(formattedRevenue) no dia. Continue firme! 🚀"
        case 5001...10000:
            return "Excelente! \(patientText) \(formattedRevenue) hoje. Você está arrasando! 🔥"
        case 10001...15000:
            return "Espetacular! \(patientText) \(formattedRevenue) em um dia. Você é incrível! ⭐️"
        case 15001...20000:
            return "Fantástico! \(patientText) \(formattedRevenue) hoje. Seu sucesso inspira! 🌟"
        case 20001...25000:
            return "Extraordinário! \(patientText) \(formattedRevenue) em um dia. Você é referência! 👑"
        default:
            return "Simplesmente INCRÍVEL! \(patientText) \(formattedRevenue) hoje. Parabéns pelo sucesso absoluto! 🏆✨"
        }
    }
    
    /// Retorna mensagem motivacional para o resumo semanal (incrementos de 10k)
    private func getWeeklyMotivationalMessage(revenue: Decimal, patientCount: Int, formattedRevenue: String) -> String {
        let revenueDouble = NSDecimalNumber(decimal: revenue).doubleValue
        let patientText = "Você atendeu \(patientCount) paciente\(patientCount == 1 ? "" : "s") e faturou"
        
        switch revenueDouble {
        case 0...10000:
            return "\(patientText) \(formattedRevenue) esta semana. Bom trabalho, mantenha o foco! 💪"
        case 10001...20000:
            return "Parabéns! \(patientText) \(formattedRevenue) esta semana. Você está crescendo! 🚀"
        case 20001...30000:
            return "Excelente! \(patientText) \(formattedRevenue) esta semana. Resultado incrível! 🔥"
        case 30001...40000:
            return "Uau! \(patientText) \(formattedRevenue) esta semana. Você é uma máquina! ⭐️"
        case 40001...50000:
            return "Espetacular! \(patientText) \(formattedRevenue) esta semana. Seu esforço vale ouro! 🌟"
        case 50001...60000:
            return "Extraordinário! \(patientText) \(formattedRevenue) esta semana. Rumo ao topo! 👑"
        default:
            return "Fenomenal! \(patientText) \(formattedRevenue) esta semana. Uma semana lendária! 🏆✨"
        }
    }
    
    // MARK: - Count Attended Patients
    
    /// Conta pacientes atendidos no período (agendamentos não cancelados e não pessoais)
    private func countAttendedPatients(from start: Date, to end: Date) async -> Int {
        let appointments = await fetchAppointments(from: start, to: end)
        
        // Filtrar apenas agendamentos não cancelados de pacientes (excluir pessoais)
        let patientAppointments = appointments.filter { appointment in
            appointment.status != .cancelled && appointment.isPersonal != true
        }
        
        return patientAppointments.count
    }
    
    // MARK: - Weekly Preview (Sunday Evening)
    
    /// Agenda notificação de prévia da semana (domingo às 20:00)
    /// Exibe quantos pacientes estão agendados para a próxima semana com mensagem motivacional
    func scheduleWeeklyPreview() async {
        AppLogger.log("🔮 Agendando Prévia Semanal...", category: .notification)
        
        center.removePendingNotificationRequests(withIdentifiers: [NotificationID.weeklyPreview])
        
        var calendar = Calendar.current
        calendar.timeZone = TimeZone(identifier: "America/Sao_Paulo") ?? .current
        calendar.firstWeekday = 2 // Segunda-feira
        
        let now = Date()
        let currentWeekday = calendar.component(.weekday, from: now)
        let currentHour = calendar.component(.hour, from: now)
        
        // Calcular próximo domingo às 20:00
        let daysUntilSunday: Int
        if currentWeekday == 1 { // Domingo
            daysUntilSunday = currentHour >= 20 ? 7 : 0
        } else { // Segunda a Sábado
            daysUntilSunday = (8 - currentWeekday) % 7
        }
        
        guard let notificationSunday = calendar.date(byAdding: .day, value: daysUntilSunday, to: calendar.startOfDay(for: now)) else {
            AppLogger.error("Erro ao calcular próximo domingo para prévia semanal", error: nil)
            return
        }
        
        // Calcular a semana que está começando (segunda após o domingo até domingo seguinte)
        guard let upcomingMonday = calendar.date(byAdding: .day, value: 1, to: notificationSunday),
              let upcomingWeekEnd = calendar.date(byAdding: .day, value: 7, to: upcomingMonday) else {
            AppLogger.error("Erro ao calcular semana futura", error: nil)
            return
        }
        
        // Buscar agendamentos da próxima semana
        let appointments = await fetchAppointments(from: upcomingMonday, to: upcomingWeekEnd)
        
        // Filtrar apenas pacientes (excluir pessoais e cancelados)
        let patientAppointments = appointments.filter { appointment in
            appointment.status != .cancelled && appointment.isPersonal != true
        }
        
        let patientCount = patientAppointments.count
        
        AppLogger.log("🔮 Próxima semana: \(patientCount) pacientes agendados", category: .notification)
        
        // Criar conteúdo da notificação
        let content = UNMutableNotificationContent()
        content.title = "🌟 Prévia da Semana"
        content.body = getMotivationalMessage(patientCount: patientCount)
        content.sound = .default
        
        // Configurar horário do trigger (domingo às 20:00)
        #if DEBUG
        // Em modo debug, agendar para 10 segundos no futuro para teste
        guard let notificationTime = calendar.date(byAdding: .second, value: 10, to: now) else { return }
        AppLogger.log("🐛 [DEBUG] Agendando prévia semanal para 10 segundos (teste)", category: .notification)
        #else
        guard let notificationTime = calendar.date(bySettingHour: 20, minute: 0, second: 0, of: notificationSunday) else {
            AppLogger.error("Erro ao configurar horário da prévia semanal", error: nil)
            return
        }
        #endif
        
        let dateComponents = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: notificationTime)
        let trigger = UNCalendarNotificationTrigger(dateMatching: dateComponents, repeats: false)
        let request = UNNotificationRequest(identifier: NotificationID.weeklyPreview, content: content, trigger: trigger)
        
        addRequest(request, description: "Prévia semanal para \(notificationSunday.formatted(.dateTime.day().month()))")
        
        AppLogger.log("✅ Prévia semanal agendada para \(notificationTime.formatted(.dateTime.day().month().hour().minute())) com \(patientCount) pacientes", category: .notification)
    }
    
    /// Retorna mensagem motivacional baseada no número de pacientes
    private func getMotivationalMessage(patientCount: Int) -> String {
        switch patientCount {
        case 0:
            return "Sua semana está livre! Aproveite para planejar e relaxar. 🌟"
        case 1...10:
            return "Você tem \(patientCount) paciente\(patientCount == 1 ? "" : "s") esta semana. Vamos começar com energia! 💪"
        case 11...20:
            return "Semana movimentada! \(patientCount) pacientes te aguardam. Você vai arrasar! 🚀"
        default:
            return "Wow! \(patientCount) pacientes agendados. Prepare-se para uma semana incrível! 🔥"
        }
    }

    /// Reagendar todas as notificações dinâmicas (Resumo + Lembretes) para garantir dados atualizados
    func refreshNotifications() async {
        guard isAuthorized else { return }
        let defaults = UserDefaults.standard
        
        AppLogger.log("🔄 [Notification] Atualizando todas as notificações dinâmicas...", category: .notification)
        
        // 1. LIMPEZA: Remover notificações antigas agendadas localmente
        // Isso é necessário para cancelar agendamentos futuros feitos antes da migração para o Supabase
        center.removePendingNotificationRequests(withIdentifiers: [NotificationID.dailySummary, NotificationID.weeklyPreview])
        
        // Remover também IDs gerados dinamicamente (para os próximos 30 dias por segurança)
        let calendar = Calendar.current
        let today = Date()
        var identifiersToRemove: [String] = []
        
        for i in 0..<30 {
            if let date = calendar.date(byAdding: .day, value: i, to: today) {
                let dateStr = date.formatted(.iso8601.year().month().day())
                identifiersToRemove.append("\(NotificationID.dailySummary)_\(dateStr)")
            }
        }
        center.removePendingNotificationRequests(withIdentifiers: identifiersToRemove)
        AppLogger.log("🧹 [Notification] Limpeza de notificações locais antigas realizada", category: .notification)
        
        // 1. DESATIVADO: Resumo Diário agora é enviado pelo Supabase
        // A notificação local agend ava 14 dias no futuro com dados estáticos
        // Com o Supabase, a notificação é enviada diariamente às 08:00 com dados atualizados
        // if defaults.bool(forKey: "daily_summary_enabled") {
        //     let hour = defaults.integer(forKey: "daily_summary_hour")
        //     let minute = defaults.integer(forKey: "daily_summary_minute")
        //     await scheduleDailySummary(hour: hour == 0 ? 8 : hour, minute: minute)
        // }
        
        // 2. Atualizar Lembretes de Agendamentos
        if defaults.bool(forKey: "appointment_reminder_enabled") {
            let reminderMinutes = defaults.integer(forKey: "appointment_reminder_minutes")
            await scheduleAppointmentReminders(minutesBefore: reminderMinutes == 0 ? 30 : reminderMinutes)
        }
        
        // 3. DESATIVADO: Resumo Financeiro agora é enviado pelo Supabase
        // A notificação local calculava valores incorretos
        // if defaults.bool(forKey: "daily_financial_summary_enabled") && supabase.isOwner {
        //      await scheduleDailyFinancialSummary(forceUpdate: true)
        // }
        
        // 4. DESATIVADO: Resumo Semanal agora é enviado pelo Supabase
        // A notificação local estava sendo enviada múltiplas vezes
        // if defaults.bool(forKey: "weekly_summary_enabled") {
        //     await scheduleWeeklySummary(dayOfWeek: 7, hour: 22) // Sábado 22:00
        // }
        
        // 5. DESATIVADO: Prévia da Semana agora é enviada pelo Supabase
        // A notificação local só funcionava se o app fosse aberto antes de domingo 20:00
        // Com o Supabase, a notificação é enviada automaticamente via push notification
        // if defaults.bool(forKey: "weekly_preview_enabled") {
        //     await scheduleWeeklyPreview()
        // }
        
        AppLogger.log("✅ [Notification] Todas as notificações atualizadas", category: .notification)
    }
    
    // MARK: - Weekly Summary
    
    /// Agenda notificação de resumo semanal
    /// - Parameters:
    ///   - dayOfWeek: Dia da semana (1=Domingo, 2=Segunda, ..., 7=Sábado)
    ///   - hour: Hora do dia
    func scheduleWeeklySummary(dayOfWeek: Int, hour: Int) async {
        // Remover anterior
        center.removePendingNotificationRequests(withIdentifiers: [NotificationID.weeklySummary])

        var calendar = Calendar.current
        calendar.timeZone = TimeZone(identifier: "America/Sao_Paulo") ?? .current
        calendar.firstWeekday = 2 // Segunda-feira
        
        let now = Date()
        let currentWeekday = calendar.component(.weekday, from: now)
        
        // ✅ Calcular o próximo sábado às 22:00 para agendar a notificação
        let daysUntilSaturday: Int
        if currentWeekday == 7 { // Se hoje é sábado
            let currentHour = calendar.component(.hour, from: now)
            if currentHour >= hour { // Se já passou das 22:00, agendar para próximo sábado
                daysUntilSaturday = 7
            } else { // Agendar para hoje às 22:00
                daysUntilSaturday = 0
            }
        } else if currentWeekday == 1 { // Domingo
            daysUntilSaturday = 6
        } else { // Segunda (2) a Sexta (6)
            daysUntilSaturday = 7 - currentWeekday
        }
        
        guard let notificationSaturday = calendar.date(byAdding: .day, value: daysUntilSaturday, to: calendar.startOfDay(for: now)) else {
            AppLogger.error("Erro ao calcular próximo sábado para notificação semanal", error: nil)
            return
        }
        
        // ✅ Calcular a semana a ser resumida (segunda-feira até sábado da semana que termina no notificationSaturday)
        // Exemplo: Se notificationSaturday é 2026-01-31 (sábado), a semana é de 2026-01-26 (segunda) até 2026-01-31 (sábado)
        guard let weekStartMonday = calendar.date(byAdding: .day, value: -5, to: notificationSaturday) else {
            AppLogger.error("Erro ao calcular segunda-feira da semana", error: nil)
            return
        }
        
        // Para o fetch, precisamos do início da segunda até o final do sábado (início do domingo seguinte)
        guard let weekEndSunday = calendar.date(byAdding: .day, value: 1, to: notificationSaturday) else {
            AppLogger.error("Erro ao calcular fim da semana", error: nil)
            return
        }
        
        // Buscar agendamentos da semana (segunda a sábado)
        let appointments = await fetchAppointments(from: weekStartMonday, to: weekEndSunday)
        let count = appointments.count
        
        // ✅ Calcular resumo financeiro semanal
        let weeklyRevenue = await calculateRevenue(from: weekStartMonday, to: weekEndSunday)
        let attendedPatients = await countAttendedPatientsInRange(from: weekStartMonday, to: weekEndSunday)
        
        // Criar conteúdo da notificação
        let content = UNMutableNotificationContent()
        content.title = "📊 Resumo da Semana"
        content.sound = .default
        
        // Formatar valor monetário
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.locale = Locale(identifier: "pt_BR")
        let revenueDouble = NSDecimalNumber(decimal: weeklyRevenue).doubleValue
        let revenueString = formatter.string(from: NSNumber(value: revenueDouble)) ?? "R$ 0,00"
        
        if count == 0 {
            content.body = "Você não teve agendamentos esta semana."
        } else {
            // Mensagem motivacional semanal
            content.body = getWeeklyMotivationalMessage(revenue: weeklyRevenue, patientCount: attendedPatients, formattedRevenue: revenueString)
            

        }
        
        // Configurar o horário do trigger (sábado às 22:00)
        #if DEBUG
        // Em modo debug, agendar para 10 segundos no futuro para teste
        guard let notificationTime = calendar.date(byAdding: .second, value: 10, to: now) else { return }
        AppLogger.log("🐛 [DEBUG] Agendando resumo semanal para 10 segundos (teste)", category: .notification)
        #else
        guard let notificationTime = calendar.date(bySettingHour: hour, minute: 0, second: 0, of: notificationSaturday) else {
            AppLogger.error("Erro ao configurar horário da notificação semanal", error: nil)
            return
        }
        #endif
        
        let dateComponents = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: notificationTime)
        
        // Trigger único para o próximo sábado às 22:00 (será reagendado na próxima abertura do app)
        let trigger = UNCalendarNotificationTrigger(dateMatching: dateComponents, repeats: false)
        let request = UNNotificationRequest(identifier: NotificationID.weeklySummary, content: content, trigger: trigger)
        
        addRequest(request, description: "Resumo semanal para \(notificationSaturday.formatted(.dateTime.day().month()))")
        
        AppLogger.log("✅ Resumo semanal agendado para \(notificationTime.formatted(.dateTime.day().month().hour().minute())) (Semana: \(weekStartMonday.formatted(.dateTime.day().month())) - \(notificationSaturday.formatted(.dateTime.day().month())))", category: .notification)
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
    
    /// Busca agendamentos em um intervalo de datas (excluindo compromissos pessoais)
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
            
            // Filtrar APENAS agendamentos reais (excluir compromissos pessoais)
            // isPersonal = true são compromissos pessoais
            // isPersonal = false ou nil são agendamentos de pacientes
            return result.filter { $0.isPersonal != true }
        } catch {
            print("❌ Erro ao buscar agendamentos (Notifications): \(error)")
            return []
        }
    }
    
    /// Calcula receita para notificações usando FinancialReportViewModel
    /// Garante que o valor seja idêntico ao mostrado no Relatório Financeiro
    private func calculateRevenue(from start: Date, to end: Date) async -> Decimal {
        let viewModel = FinancialReportViewModel()
        return await viewModel.calculateRevenueForNotification(from: start, to: end)
    }
    
    /// Conta pacientes atendidos na semana (reutiliza lógica simplificada)
    private func countAttendedPatientsInRange(from start: Date, to end: Date) async -> Int {
        return await countAttendedPatients(from: start, to: end)
    }
    

    
    private func parseDate(_ dateString: String) -> Date? {
        let iso8601 = ISO8601DateFormatter()
        iso8601.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = iso8601.date(from: dateString) { return date }
        
        iso8601.formatOptions = [.withInternetDateTime]
        if let date = iso8601.date(from: dateString) { return date }
        
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter.date(from: dateString)
    }
    
    private func fetchProcedures(ids: [String]) async -> [String: Procedure] {
        guard !ids.isEmpty, let userId = supabase.effectiveUserId else { return [:] }
        
        let uniqueIds = Array(Set(ids)) // Remover duplicatas
        
        do {
            // Supabase postgrest-swift não tem 'in' fácil, vamos fazer or ou vários requests?
            // "in" operator: .in("id", value: ids)
            
            let result: [Procedure] = try await supabase.client
                .from("procedures")
                .select()
                .eq("user_id", value: userId)
                .in("id", values: uniqueIds) // Correção para usar operador IN
                .execute()
                .value
            
            return Dictionary(uniqueKeysWithValues: result.map { ($0.id.uuidString, $0) })
            
        } catch {
            print("❌ Erro ao buscar procedimentos (Notifications): \(error)")
            return [:]
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
