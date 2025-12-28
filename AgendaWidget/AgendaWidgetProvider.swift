import WidgetKit
import SwiftUI

// Função helper para carregar agendamentos do App Group
func loadWidgetAppointments() -> [WidgetAppointment] {
    let appGroupIdentifier = "group.com.agendahof.shared"
    let widgetDataKey = "widgetAppointments"

    guard let userDefaults = UserDefaults(suiteName: appGroupIdentifier),
          let data = userDefaults.data(forKey: widgetDataKey) else {
        return []
    }

    do {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let widgetData = try decoder.decode(WidgetData.self, from: data)
        return widgetData.appointments
    } catch {
        print("❌ [Widget] Error decoding data: \(error.localizedDescription)")
        return []
    }
}

struct AgendaWidgetProvider: TimelineProvider {

    // Dados de placeholder (quando widget está sendo carregado)
    func placeholder(in context: Context) -> AgendaWidgetEntry {
        AgendaWidgetEntry(
            date: Date(),
            appointments: [
                WidgetAppointment(
                    id: "1",
                    patientName: "Maria Silva",
                    procedure: "Botox",
                    start: Date(),
                    end: Date().addingTimeInterval(3600),
                    status: "scheduled",
                    isPersonal: false,
                    title: nil
                )
            ]
        )
    }

    // Dados de snapshot (para galeria de widgets)
    func getSnapshot(in context: Context, completion: @escaping (AgendaWidgetEntry) -> Void) {
        let appointments = loadWidgetAppointments()
        let entry = AgendaWidgetEntry(date: Date(), appointments: appointments)
        completion(entry)
    }

    // Timeline principal (atualização automática)
    func getTimeline(in context: Context, completion: @escaping (Timeline<AgendaWidgetEntry>) -> Void) {
        let appointments = loadWidgetAppointments()
        let currentDate = Date()

        // Criar entry para agora
        let entry = AgendaWidgetEntry(date: currentDate, appointments: appointments)

        // Atualizar a cada 15 minutos
        let nextUpdate = Calendar.current.date(byAdding: .minute, value: 15, to: currentDate)!

        let timeline = Timeline(entries: [entry], policy: .after(nextUpdate))
        completion(timeline)
    }
}

struct AgendaWidgetEntry: TimelineEntry {
    let date: Date
    let appointments: [WidgetAppointment]

    var nextAppointment: WidgetAppointment? {
        let now = Date()
        return appointments.first { $0.start >= now }
    }

    var todayAppointments: [WidgetAppointment] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: today)!

        return appointments.filter { appointment in
            appointment.start >= today && appointment.start < tomorrow
        }
    }
}
