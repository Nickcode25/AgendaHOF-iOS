import Foundation
import WidgetKit

/// Gerenciador de dados compartilhados entre o app principal e os widgets
/// Usa App Groups via arquivo JSON no container compartilhado.
@MainActor
class WidgetDataManager {
    static let shared = WidgetDataManager()

    // IMPORTANTE: Configurar App Group no Xcode primeiro!
    // 1. Target AgendaHOF -> Signing & Capabilities -> + Capability -> App Groups
    // 2. Marcar: group.com.agendahof.shared
    // 3. Repetir para o target AgendaWidget
    private let appGroupIdentifier = "group.com.agendahof.shared"
    private let widgetDataFileName = "widgetAppointments.json"

    private init() {}

    private func widgetDataURL() -> URL? {
        FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: appGroupIdentifier)?
            .appendingPathComponent(widgetDataFileName)
    }

    /// Salvar agendamentos para os widgets acessarem
    func saveAppointments<T: AppointmentConvertible>(_ appointments: [T], status: ((String) -> String)? = nil) {
        let _ = status

        let widgetAppointments = appointments.map { appointment in
            WidgetAppointment(
                id: appointment.id,
                patientName: appointment.patientName ?? "Sem nome",
                procedure: appointment.procedure ?? "Sem procedimento",
                start: appointment.start,
                end: appointment.end,
                status: "scheduled",
                isPersonal: appointment.isPersonal ?? false,
                title: appointment.title
            )
        }

        let widgetData = WidgetData(
            appointments: widgetAppointments,
            lastUpdate: Date()
        )

        guard let fileURL = widgetDataURL() else {
            print("❌ [Widget] Failed to resolve App Group container URL")
            print("⚠️ [Widget] Verifique se o App Group está configurado corretamente:")
            print("   1. Target AgendaHOF -> Signing & Capabilities")
            print("   2. + Capability -> App Groups")
            print("   3. Marcar: \(appGroupIdentifier)")
            return
        }

        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(widgetData)
            try data.write(to: fileURL, options: .atomic)

            #if DEBUG
            print("✅ [Widget] Saved \(widgetAppointments.count) appointments")
            print("📊 [Widget] Next appointment: \(widgetData.nextAppointment?.displayTitle ?? "None")")
            print("📅 [Widget] Today: \(widgetData.todayAppointments.count) appointments")
            #endif

            WidgetCenter.shared.reloadAllTimelines()

            #if DEBUG
            print("🔄 [Widget] Timeline reload requested")
            #endif
        } catch {
            print("❌ [Widget] Error writing shared widget data: \(error.localizedDescription)")
        }
    }

    /// Carregar agendamentos do App Group (usado pelos widgets)
    static func loadAppointments() -> [WidgetAppointment] {
        let appGroupIdentifier = "group.com.agendahof.shared"
        let fileName = "widgetAppointments.json"

        guard let containerURL = FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: appGroupIdentifier) else {
            #if DEBUG
            print("❌ [Widget] Failed to resolve App Group container URL")
            #endif
            return []
        }

        let fileURL = containerURL.appendingPathComponent(fileName)

        guard let data = try? Data(contentsOf: fileURL) else {
            #if DEBUG
            print("⚠️ [Widget] No shared file found")
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
        guard let fileURL = widgetDataURL() else {
            return
        }

        do {
            if FileManager.default.fileExists(atPath: fileURL.path) {
                try FileManager.default.removeItem(at: fileURL)
            }
        } catch {
            print("❌ [Widget] Error clearing shared widget data: \(error.localizedDescription)")
        }

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
        guard let containerURL = FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: appGroupIdentifier) else {
            print("❌ [Widget] App Group not accessible")
            print("⚠️ [Widget] Configure o App Group:")
            print("   1. Apple Developer -> Certificates, Identifiers & Profiles")
            print("   2. Create App Group: \(appGroupIdentifier)")
            print("   3. Xcode -> Target -> Signing & Capabilities -> Add App Group")
            return false
        }

        let testURL = containerURL.appendingPathComponent("widget_access_test.txt")
        let testValue = "test_\(Date().timeIntervalSince1970)"

        do {
            try testValue.data(using: .utf8)?.write(to: testURL, options: .atomic)
            let readValue = try String(contentsOf: testURL, encoding: .utf8)
            try? FileManager.default.removeItem(at: testURL)

            let success = readValue == testValue
            if success {
                print("✅ [Widget] App Group access verified")
            } else {
                print("❌ [Widget] App Group test failed")
            }
            return success
        } catch {
            print("❌ [Widget] App Group test failed: \(error.localizedDescription)")
            return false
        }
    }
}
