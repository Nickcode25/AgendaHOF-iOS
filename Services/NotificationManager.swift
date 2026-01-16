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
        
        if defaults.bool(forKey: "daily_summary_enabled") {
            let hour = defaults.integer(forKey: "daily_summary_hour")
            let minute = defaults.integer(forKey: "daily_summary_minute")
            await scheduleDailySummary(hour: hour == 0 ? 8 : hour, minute: minute)
        }
        
        if defaults.bool(forKey: "daily_financial_summary_enabled") && supabase.isOwner {
             // Agendar para 21:00
             await scheduleDailyFinancialSummary()
        }
        
        if defaults.bool(forKey: "weekly_summary_enabled") {
            // Domingo às 20:00 (horário de Brasília)
            await scheduleWeeklySummary(dayOfWeek: 1, hour: 20)
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
    
    func scheduleDailyFinancialSummary() async {
        AppLogger.log("💰 Tentando agendar Resumo Financeiro...", category: .notification)
        
        center.removePendingNotificationRequests(withIdentifiers: [NotificationID.dailyFinancialSummary])
        
        guard supabase.isOwner else {
            AppLogger.log("💰 Usuário não é Owner. Cancelando.", category: .notification)
            return
        }
        
        var calendar = Calendar.current
        calendar.timeZone = TimeZone(identifier: "America/Sao_Paulo") ?? .current
        
        let now = Date()
        let todayStart = calendar.startOfDay(for: now)
        guard let tomorrowStart = calendar.date(byAdding: .day, value: 1, to: todayStart) else { return }
        
        // Agendar para 21:00
        guard let triggerDate = calendar.date(bySettingHour: 21, minute: 00, second: 0, of: todayStart) else { return }
        
        // Se já passou das 21:00, não agendar para hoje
        if triggerDate < now {
             // AppLogger.log("💰 Horário já passou hoje (\(triggerDate) < \(now)). Ignorando.", category: .notification)
             return
        }
        
        // Buscar agendamentos CONCLUÍDOS/REALIZADOS do dia
        AppLogger.log("💰 Buscando agendamentos entre \(todayStart) e \(tomorrowStart)...", category: .notification)
        let appointments = await fetchAppointments(from: todayStart, to: tomorrowStart)
        
        // Filtrar apenas os que contam para faturamento (Realizados/Concluídos/Confirmados?)
        // TESTE: Considerando TODOS os não cancelados para garantir que a notificação apareça
        // (attendedAppointments agora inclui scheduled/confirmed tb)
        
        let attendedAppointments = appointments
        
        // Log para debug dos status
        let statuses = attendedAppointments.map { $0.status.rawValue }
        AppLogger.log("💰 Status encontrados: \(statuses)", category: .notification)
        
        let patientCount = attendedAppointments.count
        AppLogger.log("💰 Pacientes atendidos (Total hoje): \(patientCount)", category: .notification)
        
        // Se não tiver pacientes, não enviar
        if patientCount == 0 {
            AppLogger.log("💰 Nenhum paciente atendido. Notificação não será enviada.", category: .notification)
            return
        }
        
        // Calcular Faturamento usando a lógica do Relatório Financeiro (buscando procedimentos nos pacientes)
        AppLogger.log("💰 Calculando faturamento via Procedures (Patients)...", category: .notification)
        let totalRevenue = await calculateDailyRevenue(date: now)
        AppLogger.log("💰 Faturamento Total Calculado: \(totalRevenue)", category: .notification)
        
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.locale = Locale(identifier: "pt_BR")
        let revenueString = formatter.string(from: NSNumber(value: totalRevenue)) ?? "R$ 0,00"
        
        // Criar Conteúdo
        let content = UNMutableNotificationContent()
        content.title = "Resumo do dia"
        content.body = "Você atendeu \(patientCount) pacientes e faturou \(revenueString) Parabéns!"
        content.sound = .default
        
        let triggerComponents = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: triggerDate)
        let trigger = UNCalendarNotificationTrigger(dateMatching: triggerComponents, repeats: false)
        
        let request = UNNotificationRequest(
            identifier: NotificationID.dailyFinancialSummary, // Identificador fixo para sobrescrever
            content: content,
            trigger: trigger
        )
        
        addRequest(request, description: "Resumo Financeiro Diário")
        AppLogger.log("✅ Resumo Financeiro agendado para 21:00", category: .notification)
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
        
        // 3. Atualizar Resumo Financeiro (Owner)
        if defaults.bool(forKey: "daily_financial_summary_enabled") && supabase.isOwner {
             await scheduleDailyFinancialSummary()
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
        calendar.firstWeekday = 2 // Segunda-feira
        
        let now = Date()
        let weekday = calendar.component(.weekday, from: now)
        // Calcular dias até próxima segunda (weekday 2)
        let daysUntilMonday = weekday == 2 ? 0 : (9 - weekday) % 7
        
        guard let nextMonday = calendar.date(byAdding: .day, value: daysUntilMonday, to: calendar.startOfDay(for: now)),
              let nextSunday = calendar.date(byAdding: .day, value: 7, to: nextMonday) else {
            return
        }
        
        // Buscar agendamentos
        let appointments = await fetchAppointments(from: nextMonday, to: nextSunday)
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
    

    /// Calcula a receita do dia baseado nos procedimentos dos pacientes (lógica do FinancialReportViewModel)
    private func calculateDailyRevenue(date: Date) async -> Double {
        guard let userId = supabase.effectiveUserId else { return 0 }
        
        // Definir limites do dia (São Paulo)
        var calendar = Calendar.current
        calendar.timeZone = TimeZone(identifier: "America/Sao_Paulo") ?? .current
        let startOfDay = calendar.startOfDay(for: date)
        let endOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay)!
        
        AppLogger.log("💰 Buscando receita total (Procedimentos + Vendas + Assinaturas + Cursos) entre \(startOfDay) e \(endOfDay)", category: .notification)
        
        // 1. Procedimentos
        let proceduresRevenue = await fetchProceduresRevenue(userId: userId, start: startOfDay, end: endOfDay)
        
        // 2. Vendas
        let salesRevenue = await fetchSalesRevenue(userId: userId, start: startOfDay, end: endOfDay)
        AppLogger.log("💰 Receita de Vendas: R$ \(salesRevenue)", category: .notification)
        
        // 3. Assinaturas
        let subscriptionsRevenue = await fetchSubscriptionsRevenue(userId: userId, start: startOfDay, end: endOfDay)
        AppLogger.log("💰 Receita de Assinaturas: R$ \(subscriptionsRevenue)", category: .notification)
        
        // 4. Cursos
        let coursesRevenue = await fetchCoursesRevenue(userId: userId, start: startOfDay, end: endOfDay)
        AppLogger.log("💰 Receita de Cursos: R$ \(coursesRevenue)", category: .notification)
        
        let total = proceduresRevenue + salesRevenue + subscriptionsRevenue + coursesRevenue
        AppLogger.log("💰 RECEITA TOTAL BRUTA: R$ \(total)", category: .notification)
        
        return total
    }
    
    // MARK: - Revenue Helpers
    
    private func fetchProceduresRevenue(userId: String, start: Date, end: Date) async -> Double {
        do {
            // Lógica idêntica ao FinancialReportView (v3.0)
            let patients: [Patient] = try await supabase.client
                .from("patients") // Busca todos e filtra localmente
                .select()
                .eq("user_id", value: userId)
                .execute()
                .value

            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM-dd"
            formatter.timeZone = TimeZone(identifier: "America/Sao_Paulo") // Importante: Mesmo TZ do View
            
            let startDateStr = formatter.string(from: start)
            let endDateStr = formatter.string(from: end)
            
            var total: Double = 0
            
            for patient in patients {
                guard let procedures = patient.plannedProcedures else { continue }
                
                for procedure in procedures {
                    // REGRA 1: Status completed
                    guard procedure.status?.lowercased() == "completed" else { continue }
                    
                    // REGRA 2: Data de realização ou conclusão
                    guard let dateStr = procedure.performedAt ?? procedure.completedAt else { continue }
                    
                    // REGRA 3: Extrair YYYY-MM-DD
                    let dateOnly = String(dateStr.prefix(10))
                    guard dateOnly.count == 10, dateOnly.contains("-") else { continue }
                    
                    // REGRA 4: Comparação de strings
                    if dateOnly >= startDateStr && dateOnly < endDateStr {
                        // REGRA 5: Payment Splits (Prioridade)
                        if let splits = procedure.paymentSplits, !splits.isEmpty {
                            let splitTotal = splits.reduce(0.0) { $0 + ($1.amount ?? 0) }
                            total += splitTotal
                        } else {
                            // REGRA 6: Total Value
                            total += (procedure.totalValue ?? 0)
                        }
                    }
                }
            }
            
            return total
        } catch {
            AppLogger.error("Erro ao buscar procedimentos/pacientes", error: error)
            return 0
        }
    }
    
    private func fetchSalesRevenue(userId: String, start: Date, end: Date) async -> Double {
        do {
            // Lógica replicada do FinancialReportView (v6.0)
            let allSales: [ProductSaleRecord] = try await supabase.client
                .from("sales")
                .select("total_amount, sold_at, created_at, payment_status")
                .eq("user_id", value: userId)
                .eq("payment_status", value: "paid")
                .execute()
                .value

            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM-dd"
            formatter.timeZone = TimeZone(identifier: "America/Sao_Paulo") // Importante: Mesmo TZ do View
            
            let startDateStr = formatter.string(from: start)
            let endDateStr = formatter.string(from: end) // Note: end é o início de amanhã, então a string é OK para < comparação?
            // No View, ele usa <= endDateStr. Se end for 2026-01-08 00:00, a string será 2026-01-08.
            // Se comparar <= 2026-01-08, inclui vendas de amanhã?
            // O Report usa startStr e endStr baseados no range selecionado.
            // Para "Hoje", o Report usa startOfToday e endOfToday (23:59:59).
            // AQUI, recebemos start (00:00) e end (00:00 amanhã).
            // Então devemos comparar: date >= startStr && date < endDateStr.
            
            let targetDateStr = startDateStr // Para dia específico, queremos match exato ou range? Vamos assumir range de 1 dia.
            
            var total: Double = 0
            
            for sale in allSales {
                guard let dateStr = sale.soldAt ?? sale.createdAt else { continue }
                let dateOnly = String(dateStr.prefix(10))
                guard dateOnly.count == 10, dateOnly.contains("-") else { continue }
                
                // Filtro: >= start (hoje) E < end (amanhã). Como são strings YYYY-MM-DD:
                // Se hoje é 07, start=07, end=08.
                // dateOnly >= "2026-01-07" AND dateOnly < "2026-01-08" -> ou seja, dateOnly == "2026-01-07"
                
                if dateOnly >= startDateStr && dateOnly < endDateStr {
                    total += (sale.totalAmount ?? 0)
                }
            }
            
            return total
        } catch {
            AppLogger.error("Erro ao buscar vendas (sales table)", error: error)
            return 0
        }
    }
    
    private func fetchSubscriptionsRevenue(userId: String, start: Date, end: Date) async -> Double {
        do {
            // Lógica replicada do FinancialReportView (v4.0)
            // 1. Buscar IDs no patient_subscriptions
            let subscriptions: [PatientSubscriptionRecord] = try await supabase.client
                .from("patient_subscriptions")
                .select("id, patient_id")
                .eq("user_id", value: userId)
                .execute()
                .value
            
            if subscriptions.isEmpty { return 0 }
            
            let subscriptionIds = subscriptions.map { $0.id }
            
            // 2. Buscar pagamentos
            let allPayments: [SubscriptionPaymentRecord] = try await supabase.client
                .from("subscription_payments")
                .select("amount, paid_at, subscription_id")
                .in("subscription_id", values: subscriptionIds) // Codable array values funciona no client novo?
                // Se .in falhar com [String], tentar lista manual. Mas supabase-swift costuma aceitar.
                // O ReportView usa .in("subscription_id", values: subscriptionIds)
                .eq("status", value: "paid")
                .execute()
                .value
                
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM-dd"
            formatter.timeZone = TimeZone(identifier: "America/Sao_Paulo")
            let startDateStr = formatter.string(from: start)
            let endDateStr = formatter.string(from: end)
            
            var total: Double = 0
            
            for payment in allPayments {
                guard let dateStr = payment.paidAt else { continue }
                let dateOnly = String(dateStr.prefix(10))
                guard dateOnly.count == 10, dateOnly.contains("-") else { continue }
                
                if dateOnly >= startDateStr && dateOnly < endDateStr {
                    total += (payment.amount ?? 0)
                }
            }
            
            return total
        } catch {
            AppLogger.error("Erro ao buscar assinaturas (nova lógica)", error: error)
            return 0
        }
    }
    
    private func fetchCoursesRevenue(userId: String, start: Date, end: Date) async -> Double {
        do {
            // Lógica replicada do FinancialReportView (v3.0) -> Tabela 'enrollments'
            let allEnrollments: [EnrollmentRecord] = try await supabase.client
                .from("enrollments")
                .select("amount_paid, enrollment_date")
                .eq("user_id", value: userId)
                .gt("amount_paid", value: 0)
                .execute()
                .value
                
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM-dd"
            formatter.timeZone = TimeZone(identifier: "America/Sao_Paulo")
            let startDateStr = formatter.string(from: start)
            let endDateStr = formatter.string(from: end)
            
            var total: Double = 0
            
            for enrollment in allEnrollments {
                guard let dateStr = enrollment.enrollmentDate else { continue }
                let dateOnly = String(dateStr.prefix(10))
                guard dateOnly.count == 10, dateOnly.contains("-") else { continue }
                
                if dateOnly >= startDateStr && dateOnly < endDateStr {
                    total += (enrollment.amountPaid ?? 0)
                }
            }
            
            return total
        } catch {
            // Tabela pode não existir (erro comum no log do user)
            // AppLogger.log("Info: Erro ao buscar enrollments (provável inexistência)", category: .notification)
            return 0
        }
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
                .in("id", value: uniqueIds) // Correção para usar operador IN
                .execute()
                .value
            
            return Dictionary(uniqueKeysWithValues: result.map { ($0.id, $0) })
            
        } catch {
            print("❌ Erro ao buscar procedimentos (Notifications): \(error)")
            return [:]
        }
    }

    // MARK: - Database Models (Replicated from FinancialReportView)
    
    private struct ProductSaleRecord: Codable {
        let totalAmount: Double?
        let soldAt: String?
        let createdAt: String?
        let paymentStatus: String?
        
        enum CodingKeys: String, CodingKey {
            case totalAmount = "total_amount"
            case soldAt = "sold_at"
            case createdAt = "created_at"
            case paymentStatus = "payment_status"
        }
    }

    private struct PatientSubscriptionRecord: Codable {
        let id: String
        let patientId: String?
        
        enum CodingKeys: String, CodingKey {
            case id
            case patientId = "patient_id"
        }
    }

    private struct SubscriptionPaymentRecord: Codable {
        let amount: Double?
        let paidAt: String?
        let subscriptionId: String?
        
        enum CodingKeys: String, CodingKey {
            case amount
            case paidAt = "paid_at"
            case subscriptionId = "subscription_id"
        }
    }

    private struct EnrollmentRecord: Codable {
        let amountPaid: Double?
        let enrollmentDate: String?
        
        enum CodingKeys: String, CodingKey {
            case amountPaid = "amount_paid"
            case enrollmentDate = "enrollment_date"
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
