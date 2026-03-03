import Foundation
import Network

// MARK: - NetworkMonitor
// Declared here to avoid Xcode target membership issues with separately created files.
// If NetworkMonitor.swift is already in the project target, remove this block.

@MainActor
final class NetworkMonitor: ObservableObject {
    static let shared = NetworkMonitor()
    @Published private(set) var isOnline: Bool = false

    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "NetworkMonitor")

    private init() {
        monitor.pathUpdateHandler = { [weak self] path in
            Task { @MainActor in
                self?.isOnline = (path.status == .satisfied)
            }
        }
        monitor.start(queue: queue)
    }
}

// MARK: - AppointmentsCache

struct MonthlyAppointmentsCacheFile: Codable {
    let ownerId: String
    let monthKey: String
    let updatedAt: Date
    let appointments: [Appointment]
}

enum AppointmentsCache {
    private static func cacheDirectory() throws -> URL {
        let fm = FileManager.default
        let appDir = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!.appendingPathComponent("AgendaHOF")
        try fm.createDirectory(at: appDir, withIntermediateDirectories: true, attributes: nil)
        return appDir
    }

    private static func fileURL(ownerId: String, monthKey: String) throws -> URL {
        try cacheDirectory().appendingPathComponent("appointments_\(ownerId)_\(monthKey).json")
    }

    static func save(ownerId: String, monthKey: String, appointments: [Appointment]) -> Date {
        let now = Date()
        let file = MonthlyAppointmentsCacheFile(
            ownerId: ownerId,
            monthKey: monthKey,
            updatedAt: now,
            appointments: appointments
        )
        
        do {
            let appDir = try cacheDirectory()
            let fileName = "appointments_\(ownerId)_\(monthKey).json"
            let fileURL = appDir.appendingPathComponent(fileName)
            
            let data = try JSONEncoder().encode(file)
            try data.write(to: fileURL, options: [.atomic])
            return now
        } catch {
            AppLogger.warning("⚠️ [Cache] Failed saving month \(monthKey): \(error)")
            return now
        }
    }

    static func load(ownerId: String, monthKey: String) -> MonthlyAppointmentsCacheFile? {
        guard let url = try? fileURL(ownerId: ownerId, monthKey: monthKey),
              let data = try? Data(contentsOf: url),
              let file = try? JSONDecoder().decode(MonthlyAppointmentsCacheFile.self, from: data) else { return nil }
        return file
    }

    static func clearAll() {
        guard let dir = try? cacheDirectory(),
              let files = try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) else { return }
        for f in files where f.lastPathComponent.hasPrefix("appointments_") {
            try? FileManager.default.removeItem(at: f)
        }
        AppLogger.log("🗑️ [Cache] All monthly appointments caches cleared.", category: .business)
    }

    // Helpers
    static func monthKey(for date: Date) -> String {
        let c = Calendar.current
        let y = c.component(.year, from: date)
        let m = c.component(.month, from: date)
        return String(format: "%04d-%02d", y, m)
    }

    static func monthRange(for date: Date) -> (start: Date, end: Date) {
        let c = Calendar.current
        let start = c.date(from: c.dateComponents([.year, .month], from: date))!
        let startNextMonth = c.date(byAdding: .month, value: 1, to: start)!
        let end = startNextMonth.addingTimeInterval(-1) // 23:59:59 do último dia
        return (start, end)
    }
}

@MainActor
class AppointmentService: ObservableObject {
    static let shared = AppointmentService()
    private let supabase = SupabaseManager.shared

    @Published var appointments: [Appointment] = []
    @Published var isLoading = false
    @Published var error: String?
    @Published var isOfflineMode: Bool = false
    @Published var cachedUpdatedAt: Date? = nil
    @Published var cachedDateRange: (start: Date, end: Date)? = nil
    
    // Tracking para evitar sync duplicado
    private var lastSyncedMonthKey: String? = nil
    private var lastSyncedAt: Date? = nil
    
    // Filtros persistentes para sync de background
    private var lastProfessionalId: String? = nil
    private var lastProfessionalName: String? = nil

    // MARK: - Fetch by Date Range

    /// Busca agendamentos por intervalo de datas e opcionalmente por profissional
    /// - Parameters:
    ///   - startDate: Data inicial
    ///   - endDate: Data final
    ///   - professionalId: ID do profissional (preferencial, mais preciso)
    ///   - professional: Nome do profissional (fallback para compatibilidade)
    func fetchAppointments(from startDate: Date, to endDate: Date, professionalId: String? = nil, professional: String? = nil) async {
        guard let userId = supabase.effectiveUserId else {
            error = "Usuário não autenticado"
            return
        }
        let ownerId = userId

        isLoading = true
        error = nil
        
        // ✅ Captura os filtros para persistir no background sync
        self.lastProfessionalId = professionalId
        self.lastProfessionalName = professional
        
        let key = AppointmentsCache.monthKey(for: startDate)
        let range = AppointmentsCache.monthRange(for: startDate)
        let isOnline = NetworkMonitor.shared.isOnline

        if isOnline {
            do {
                // 1) Sincroniza o mês inteiro no cache
                let monthApps = try await syncMonthCache(ownerId: ownerId, userId: userId, monthKey: key, range: range)
                
                // 2) Filtra apenas o necessário para a UI
                let filtered = filter(appointments: monthApps, from: startDate, to: endDate, profId: professionalId, prof: professional)
                
                self.appointments = filtered
                self.isOfflineMode = false
                // self.cachedUpdatedAt ja foi setado pelo syncMonthCache
                self.cachedDateRange = (startDate, endDate)
                
                // 3) Atualiza widgets com o mês todo
                await updateWidgetData(monthAppointments: monthApps)

            } catch is CancellationError {
                AppLogger.log("🔄 [Appointments] Busca cancelada", category: .business)
            } catch {
                AppLogger.warning("⚠️ [Appointments] Erro online: \(error). Fallback cache.")
                loadFromCache(ownerId: ownerId, startDate: startDate, endDate: endDate, key: key, professionalId: professionalId, professional: professional)
            }
        } else {
            loadFromCache(ownerId: ownerId, startDate: startDate, endDate: endDate, key: key, professionalId: professionalId, professional: professional)
        }

        isLoading = false
    }

    @MainActor
    func refreshCurrentMonthIfNeeded(selectedDate: Date, force: Bool = false) async {
        guard NetworkMonitor.shared.isOnline, let userId = supabase.effectiveUserId else { return }
        
        let key = AppointmentsCache.monthKey(for: selectedDate)
        if !force, lastSyncedMonthKey == key, let last = lastSyncedAt, Date().timeIntervalSince(last) < 60 {
            return
        }
        
        lastSyncedMonthKey = key
        lastSyncedAt = Date()
        
        let range = AppointmentsCache.monthRange(for: selectedDate)
        let ownerId = userId // Garante consistência de nomenclatura
        
        do {
            // Sincroniza sem trocar a lista da UI imediatamente (evita pulo se a UI estiver vendo um dia)
            let monthApps = try await syncMonthCache(ownerId: ownerId, userId: userId, monthKey: key, range: range)
            
            // Se a UI está carregada e o range atual faz parte deste mês, atualizamos a lista mantendo o range e filtros
            if let currentRange = cachedDateRange, 
               AppointmentsCache.monthKey(for: currentRange.start) == key {
                let updated = filter(appointments: monthApps, 
                                     from: currentRange.start, 
                                     to: currentRange.end, 
                                     profId: lastProfessionalId, 
                                     prof: lastProfessionalName)
                self.appointments = updated
            } else if cachedDateRange == nil {
                // Se não tinha range (ex: boot sem dados), define o mês como range padrão para não ficar vazio
                self.cachedDateRange = (range.start, range.end)
                self.appointments = filter(appointments: monthApps, from: range.start, to: range.end, profId: lastProfessionalId, prof: lastProfessionalName)
            }
            
            self.isOfflineMode = false
            // O syncMonthCache já setou cachedUpdatedAt
            
            await updateWidgetData(monthAppointments: monthApps)
            AppLogger.log("🌐 [Appointments] Sync silencioso do mês \(key) concluído.", category: .business)
        } catch {
            AppLogger.warning("⚠️ [Appointments] Falha no sync silencioso: \(error)")
        }
    }

    // MARK: - Internal Helpers
    
    private func syncMonthCache(ownerId: String, userId: String, monthKey: String, range: (start: Date, end: Date)) async throws -> [Appointment] {
        let fmt = ISO8601DateFormatter()
        let startString = fmt.string(from: range.start)
        let endString = fmt.string(from: range.end)

        let monthApps: [Appointment] = try await supabase.client
            .from("appointments")
            .select()
            .eq("user_id", value: userId)
            .gte("start", value: startString)
            .lte("start", value: endString)
            .order("start", ascending: true)
            .execute()
            .value

        let updatedAt = AppointmentsCache.save(ownerId: ownerId, monthKey: monthKey, appointments: monthApps)
        self.cachedUpdatedAt = updatedAt
        return monthApps
    }

    private func filter(appointments: [Appointment], from start: Date, to end: Date, profId: String?, prof: String?) -> [Appointment] {
        var result = appointments.filter { $0.start >= start && $0.start <= end }
        
        if let profId = profId {
            result = result.filter { $0.professionalId == profId }
        } else if let prof = prof {
            result = result.filter { $0.professional.isRoughlyEqual(to: prof) }
        }
        
        return result
    }

    // MARK: - Cache Fallback

    private func loadFromCache(ownerId: String, startDate: Date, endDate: Date, key: String, professionalId: String?, professional: String?) {
        if let cached = AppointmentsCache.load(ownerId: ownerId, monthKey: key) {
            let filtered = filter(appointments: cached.appointments, from: startDate, to: endDate, profId: professionalId, prof: professional)
            appointments = filtered
            cachedUpdatedAt = cached.updatedAt
            cachedDateRange = (startDate, endDate)
            isOfflineMode = true
            AppLogger.log("📦 [Cache] Carregados \(filtered.count) agendamentos do cache mensal (\(key)).", category: .business)
        } else {
            appointments = []
            cachedUpdatedAt = nil
            cachedDateRange = nil
            isOfflineMode = true
            AppLogger.warning("⚠️ [Cache] Sem dados em cache para o mês \(key).")
        }
    }

    // MARK: - Widget Integration

    /// Atualizar dados dos widgets com agendamentos futuros
    @MainActor
    private func updateWidgetData(monthAppointments: [Appointment]) async {
        let now = Date()
        let calendar = Calendar.current
        let todayStart = calendar.startOfDay(for: now)
        // Widget mostra até 14 dias para frente
        guard let twoWeeksLater = calendar.date(byAdding: .day, value: 14, to: todayStart) else { return }

        let upcoming = monthAppointments.filter { 
            $0.start >= todayStart && $0.start <= twoWeeksLater && $0.status != .cancelled 
        }.sorted { $0.start < $1.start }
        
        // Limitar a 20 agendamentos (suficiente para widgets)
        let limited = Array(upcoming.prefix(20))
        
        WidgetDataManager.shared.saveAppointments(limited)
    }



    // MARK: - Write guard

    /// Returns an error string if writes should be blocked right now.
    func offlineWriteError() -> String? {
        guard !NetworkMonitor.shared.isOnline else { return nil }
        return "Sem internet no momento. Conecte-se para salvar alterações."
    }

    // MARK: - Fetch for Day

    func fetchAppointmentsForDay(_ date: Date, professionalId: String? = nil, professional: String? = nil) async {
        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: date)
        let endOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay)!

        await fetchAppointments(from: startOfDay, to: endOfDay, professionalId: professionalId, professional: professional)
    }

    // MARK: - Fetch for Week

    func fetchAppointmentsForWeek(of date: Date, professionalId: String? = nil, professional: String? = nil) async {
        var calendar = Calendar.current
        calendar.firstWeekday = 2 // Forçar segunda-feira como início da semana para alinhar com a View
        
        let startOfWeek = calendar.dateInterval(of: .weekOfYear, for: date)?.start ?? date
        let endOfWeek = calendar.date(byAdding: .day, value: 7, to: startOfWeek)!
        
        AppLogger.log("📅 [Service] Fetching Week: \(startOfWeek) to \(endOfWeek)", category: .business)

        await fetchAppointments(from: startOfWeek, to: endOfWeek, professionalId: professionalId, professional: professional)
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
        if let offlineErr = offlineWriteError() { throw NSError(domain: "Offline", code: -1, userInfo: [NSLocalizedDescriptionKey: offlineErr]) }

        let result: Appointment = try await supabase.client
            .from("appointments")
            .insert(appointment)
            .select()
            .single()
            .execute()
            .value

        Task { await NotificationManager.shared.refreshNotifications() }

        return result
    }

    // MARK: - Update

    func updateAppointment(id: String, updates: [String: AnyEncodable]) async throws {
        if let offlineErr = offlineWriteError() { throw NSError(domain: "Offline", code: -1, userInfo: [NSLocalizedDescriptionKey: offlineErr]) }

        try await supabase.client
            .from("appointments")
            .update(updates)
            .eq("id", value: id)
            .execute()

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
        if let offlineErr = offlineWriteError() { throw NSError(domain: "Offline", code: -1, userInfo: [NSLocalizedDescriptionKey: offlineErr]) }

        try await supabase.client
            .from("appointments")
            .delete()
            .eq("id", value: id)
            .execute()

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

    func hasConflict(start: Date, end: Date, professionalId: String? = nil, professional: String, excludingId: String? = nil) async -> Bool {
        guard let userId = supabase.effectiveUserId else { return false }

        do {
            let formatter = ISO8601DateFormatter()

            let result: [Appointment]

            if let excludingId = excludingId {
                result = try await supabase.client
                    .from("appointments")
                    .select("id, professional, professional_id")
                    .eq("user_id", value: userId)
                    .neq("status", value: "cancelled")
                    .neq("id", value: excludingId)
                    .lt("start", value: formatter.string(from: end))
                    .gt("end", value: formatter.string(from: start))
                    .execute()
                    .value
            } else {
                result = try await supabase.client
                    .from("appointments")
                    .select("id, professional, professional_id")
                    .eq("user_id", value: userId)
                    .neq("status", value: "cancelled")
                    .lt("start", value: formatter.string(from: end))
                    .gt("end", value: formatter.string(from: start))
                    .execute()
                    .value
            }
            
            // Priorizar filtro por professionalId (mais preciso)
            if let professionalId = professionalId {
                return result.contains { appointment in
                    appointment.professionalId == professionalId
                }
            }
            
            // Fallback: filtro por nome
            return result.contains { appointment in
                appointment.professional.isRoughlyEqual(to: professional)
            }
        } catch {
            print("Erro ao verificar conflitos: \(error)")
            return false
        }
    }
}
