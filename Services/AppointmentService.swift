import Foundation

@MainActor
class AppointmentService: ObservableObject {
    private let supabase = SupabaseManager.shared

    @Published var appointments: [Appointment] = []
    @Published var isLoading = false
    @Published var error: String?

    // MARK: - Fetch by Date Range

    func fetchAppointments(from startDate: Date, to endDate: Date, professional: String? = nil) async {
        guard let userId = supabase.effectiveUserId else {
            error = "Usuário não autenticado"
            return
        }

        isLoading = true
        error = nil
        
        // Log de diagnóstico
        if let prof = professional {
            AppLogger.log("📅 [Appointments] Filtro Profissional: \(prof)", category: .business)
        }

        do {
            let formatter = ISO8601DateFormatter()
            let startString = formatter.string(from: startDate)
            let endString = formatter.string(from: endDate)

            let result: [Appointment]

            if let professional = professional {
                result = try await supabase.client
                    .from("appointments")
                    .select()
                    .eq("user_id", value: userId)
                    .eq("professional", value: professional)
                    .gte("start", value: startString)
                    .lte("start", value: endString)
                    .order("start", ascending: true)
                    .execute()
                    .value
            } else {
                result = try await supabase.client
                    .from("appointments")
                    .select()
                    .eq("user_id", value: userId)
                    .gte("start", value: startString)
                    .lte("start", value: endString)
                    .order("start", ascending: true)
                    .execute()
                    .value
            }
            
            appointments = result

            // ✅ WIDGET: Salvar agendamentos futuros para os widgets
            await updateWidgetData()
        } catch is CancellationError {
            // Ignorar erros de cancelamento (pull-to-refresh interrompido)
            print("Busca de agendamentos cancelada")
        } catch {
            self.error = error.localizedDescription
            AppLogger.error("[Appointments] Erro ao buscar: \(error)")
        }

        isLoading = false
    }

    // MARK: - Widget Integration

    /// Atualizar dados dos widgets com agendamentos futuros
    private func updateWidgetData() async {
        let now = Date()
        let calendar = Calendar.current
        let todayStart = calendar.startOfDay(for: now)
        let twoWeeksLater = calendar.date(byAdding: .day, value: 14, to: todayStart)!

        // Filtrar apenas agendamentos futuros (hoje em diante) e não cancelados
        let upcomingAppointments = appointments.filter { appointment in
            appointment.start >= todayStart &&
            appointment.start <= twoWeeksLater &&
            appointment.status != .cancelled
        }.sorted { $0.start < $1.start }

        // Limitar a 20 agendamentos (suficiente para widgets)
        let limitedAppointments = Array(upcomingAppointments.prefix(20))

        // Salvar para os widgets
        WidgetDataManager.shared.saveAppointments(limitedAppointments)
    }

    // MARK: - Fetch for Day

    func fetchAppointmentsForDay(_ date: Date, professional: String? = nil) async {
        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: date)
        let endOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay)!

        await fetchAppointments(from: startOfDay, to: endOfDay, professional: professional)
    }

    // MARK: - Fetch for Week

    func fetchAppointmentsForWeek(of date: Date, professional: String? = nil) async {
        var calendar = Calendar.current
        calendar.firstWeekday = 2 // Forçar segunda-feira como início da semana para alinhar com a View
        
        let startOfWeek = calendar.dateInterval(of: .weekOfYear, for: date)?.start ?? date
        let endOfWeek = calendar.date(byAdding: .day, value: 7, to: startOfWeek)!
        
        AppLogger.log("📅 [Service] Fetching Week: \(startOfWeek) to \(endOfWeek)", category: .business)

        await fetchAppointments(from: startOfWeek, to: endOfWeek, professional: professional)
    }

    // MARK: - Fetch One

    func fetchAppointment(id: String) async -> Appointment? {
        do {
            let appointment: Appointment = try await supabase.client
                .from("appointments")
                .select()
                .eq("id", value: id)
                .single()
                .execute()
                .value

            return appointment
        } catch {
            print("Erro ao buscar agendamento: \(error)")
            return nil
        }
    }

    // MARK: - Create

    func createAppointment(_ appointment: Appointment.Insert) async throws -> Appointment {
        // #if DEBUG block removed for cleanup

        let result: Appointment = try await supabase.client
            .from("appointments")
            .insert(appointment)
            .select()
            .single()
            .execute()
            .value

        // #if DEBUG block removed for cleanup

        // 🔔 Atualizar notificações
        // 🔔 Atualizar notificações
        Task { await NotificationManager.shared.refreshNotifications() }

        return result
    }

    // MARK: - Update

    func updateAppointment(id: String, updates: [String: AnyEncodable]) async throws {
        try await supabase.client
            .from("appointments")
            .update(updates)
            .eq("id", value: id)
            .execute()
            
        // 🔔 Atualizar notificações
        // 🔔 Atualizar notificações
        Task { await NotificationManager.shared.refreshNotifications() }
    }

    // MARK: - Update Status

    func updateStatus(id: String, status: Appointment.AppointmentStatus) async throws {
        try await updateAppointment(id: id, updates: ["status": AnyEncodable(status.rawValue)])
    }

    // MARK: - Cancel

    func cancelAppointment(id: String) async throws {
        try await updateStatus(id: id, status: .cancelled)
    }

    // MARK: - Delete

    func deleteAppointment(id: String) async throws {
        try await supabase.client
            .from("appointments")
            .delete()
            .eq("id", value: id)
            .execute()
            
        // 🔔 Atualizar notificações
        // 🔔 Atualizar notificações
        Task { await NotificationManager.shared.refreshNotifications() }
    }

    // MARK: - Fetch by Patient

    func fetchAppointmentsByPatient(patientId: String, limit: Int = 10) async -> [Appointment] {
        guard let userId = supabase.effectiveUserId else { return [] }

        do {
            let result: [Appointment] = try await supabase.client
                .from("appointments")
                .select()
                .eq("user_id", value: userId)
                .eq("patient_id", value: patientId)
                .eq("is_personal", value: false)
                .neq("status", value: "cancelled")
                .order("start", ascending: false)
                .limit(limit)
                .execute()
                .value

            return result
        } catch {
            print("Erro ao buscar agendamentos do paciente: \(error)")
            return []
        }
    }

    // MARK: - Check Conflicts

    func hasConflict(start: Date, end: Date, professional: String, excludingId: String? = nil) async -> Bool {
        guard let userId = supabase.effectiveUserId else { return false }

        do {
            let formatter = ISO8601DateFormatter()

            let result: [Appointment]

            if let excludingId = excludingId {
                result = try await supabase.client
                    .from("appointments")
                    .select("id")
                    .eq("user_id", value: userId)
                    .eq("professional", value: professional)
                    .neq("status", value: "cancelled")
                    .neq("id", value: excludingId)
                    .lt("start", value: formatter.string(from: end))
                    .gt("end", value: formatter.string(from: start))
                    .execute()
                    .value
            } else {
                result = try await supabase.client
                    .from("appointments")
                    .select("id")
                    .eq("user_id", value: userId)
                    .eq("professional", value: professional)
                    .neq("status", value: "cancelled")
                    .lt("start", value: formatter.string(from: end))
                    .gt("end", value: formatter.string(from: start))
                    .execute()
                    .value
            }

            return !result.isEmpty
        } catch {
            print("Erro ao verificar conflitos: \(error)")
            return false
        }
    }
}
