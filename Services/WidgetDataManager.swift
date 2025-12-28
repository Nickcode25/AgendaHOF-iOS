import Foundation
import WidgetKit

/// Gerenciador de dados compartilhados entre o app principal e os widgets
/// Usa App Groups para compartilhar dados via UserDefaults
@MainActor
class WidgetDataManager {
    static let shared = WidgetDataManager()

    // IMPORTANTE: Configurar App Group no Xcode primeiro!
    // 1. Target AgendaHOF → Signing & Capabilities → + Capability → App Groups
    // 2. Marcar: group.com.agendahof.shared
    // 3. Repetir para o target AgendaWidget
    private let appGroupIdentifier = "group.com.agendahof.shared"
    private let widgetDataKey = "widgetAppointments"

    private init() {}

    /// Salvar agendamentos para os widgets acessarem
    func saveAppointments<T: AppointmentConvertible>(_ appointments: [T], status: ((String) -> String)? = nil) {
        // Converter para modelo simplificado (sem dependências de Supabase)
        let widgetAppointments = appointments.map { appointment in
            WidgetAppointment(
                id: appointment.id,
                patientName: appointment.patientName ?? "Sem nome",
                procedure: appointment.procedure ?? "Sem procedimento",
                start: appointment.start,
                end: appointment.end,
                status: "scheduled", // Status genérico para widgets
                isPersonal: appointment.isPersonal ?? false,
                title: appointment.title
            )
        }

        let widgetData = WidgetData(
            appointments: widgetAppointments,
            lastUpdate: Date()
        )

        // Salvar no App Group UserDefaults
        guard let userDefaults = UserDefaults(suiteName: appGroupIdentifier) else {
            print("❌ [Widget] Failed to access App Group UserDefaults")
            print("⚠️ [Widget] Verifique se o App Group está configurado corretamente:")
            print("   1. Target AgendaHOF → Signing & Capabilities")
            print("   2. + Capability → App Groups")
            print("   3. Marcar: \(appGroupIdentifier)")
            return
        }

        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(widgetData)
            userDefaults.set(data, forKey: widgetDataKey)
            userDefaults.synchronize()  // Forçar sync imediato

            #if DEBUG
            print("✅ [Widget] Saved \(widgetAppointments.count) appointments")
            print("📊 [Widget] Next appointment: \(widgetData.nextAppointment?.displayTitle ?? "None")")
            print("📅 [Widget] Today: \(widgetData.todayAppointments.count) appointments")
            #endif

            // Notificar os widgets para atualizar
            WidgetCenter.shared.reloadAllTimelines()

            #if DEBUG
            print("🔄 [Widget] Timeline reload requested")
            #endif
        } catch {
            print("❌ [Widget] Error encoding data: \(error.localizedDescription)")
        }
    }

    /// Carregar agendamentos do App Group (usado pelos widgets)
    static func loadAppointments() -> [WidgetAppointment] {
        let appGroupIdentifier = "group.com.agendahof.shared"
        let widgetDataKey = "widgetAppointments"

        guard let userDefaults = UserDefaults(suiteName: appGroupIdentifier) else {
            #if DEBUG
            print("❌ [Widget] Failed to access App Group UserDefaults")
            #endif
            return []
        }

        guard let data = userDefaults.data(forKey: widgetDataKey) else {
            #if DEBUG
            print("⚠️ [Widget] No data found in UserDefaults")
            #endif
            return []
        }

        do {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let widgetData = try decoder.decode(WidgetData.self, from: data)

            #if DEBUG
            print("✅ [Widget] Loaded \(widgetData.appointments.count) appointments")
            print("⏰ [Widget] Last update: \(widgetData.lastUpdate)")
            #endif

            return widgetData.appointments
        } catch {
            print("❌ [Widget] Error decoding data: \(error.localizedDescription)")
            return []
        }
    }

    /// Limpar dados dos widgets (útil no logout)
    func clearWidgetData() {
        guard let userDefaults = UserDefaults(suiteName: appGroupIdentifier) else {
            return
        }

        userDefaults.removeObject(forKey: widgetDataKey)
        userDefaults.synchronize()

        // Atualizar widgets para mostrar estado vazio
        WidgetCenter.shared.reloadAllTimelines()

        #if DEBUG
        print("🗑️ [Widget] Data cleared")
        #endif
    }

    /// Forçar atualização imediata dos widgets
    func forceWidgetUpdate() {
        WidgetCenter.shared.reloadAllTimelines()

        #if DEBUG
        print("🔄 [Widget] Forced timeline reload")
        #endif
    }

    /// Verificar se App Group está configurado corretamente
    func verifyAppGroupAccess() -> Bool {
        guard let userDefaults = UserDefaults(suiteName: appGroupIdentifier) else {
            print("❌ [Widget] App Group not accessible")
            print("⚠️ [Widget] Configure o App Group:")
            print("   1. Apple Developer → Certificates, Identifiers & Profiles")
            print("   2. Create App Group: \(appGroupIdentifier)")
            print("   3. Xcode → Target → Signing & Capabilities → Add App Group")
            return false
        }

        // Testar escrita e leitura
        let testKey = "widget_test"
        let testValue = "test_\(Date().timeIntervalSince1970)"

        userDefaults.set(testValue, forKey: testKey)
        userDefaults.synchronize()

        let readValue = userDefaults.string(forKey: testKey)
        userDefaults.removeObject(forKey: testKey)

        let success = readValue == testValue

        if success {
            print("✅ [Widget] App Group access verified")
        } else {
            print("❌ [Widget] App Group test failed")
        }

        return success
    }
}
