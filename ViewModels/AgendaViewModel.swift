import Foundation
import SwiftUI

@MainActor
class AgendaViewModel: ObservableObject {
    // MARK: - Published Properties

    @Published var selectedDate = Date()
    @Published var appointments: [Appointment] = []
    @Published var recurringBlocks: [RecurringBlock] = []
    @Published var isLoading = false
    @Published var error: String?
    @Published var viewMode: ViewMode = .day
    @Published var selectedProfessional: Professional?

    // MARK: - Private

    private let appointmentService = AppointmentService()
    private let supabase = SupabaseManager.shared

    // MARK: - View Modes

    enum ViewMode: String, CaseIterable {
        case day = "Dia"
        case week = "Semana"

        var icon: String {
            switch self {
            case .day: return "calendar.day.timeline.left"
            case .week: return "calendar"
            }
        }
    }

    // MARK: - Computed Properties

    var displayDateTitle: String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "pt_BR")

        switch viewMode {
        case .day:
            if Calendar.current.isDateInToday(selectedDate) {
                return "Hoje"
            } else if Calendar.current.isDateInTomorrow(selectedDate) {
                return "Amanhã"
            } else if Calendar.current.isDateInYesterday(selectedDate) {
                return "Ontem"
            }
            formatter.dateFormat = "EEEE, d 'de' MMMM"
            return formatter.string(from: selectedDate).capitalized

        case .week:
            let calendar = Calendar.current
            let startOfWeek = calendar.dateInterval(of: .weekOfYear, for: selectedDate)?.start ?? selectedDate
            let endOfWeek = calendar.date(byAdding: .day, value: 6, to: startOfWeek)!

            let dayFormatter = DateFormatter()
            dayFormatter.locale = Locale(identifier: "pt_BR")
            dayFormatter.dateFormat = "d"

            let monthFormatter = DateFormatter()
            monthFormatter.locale = Locale(identifier: "pt_BR")
            monthFormatter.dateFormat = "MMM"

            return "\(dayFormatter.string(from: startOfWeek)) - \(dayFormatter.string(from: endOfWeek)) \(monthFormatter.string(from: selectedDate))"
        }
    }

    /// Título compacto para o header (ex: "19 dez" ou "16-22 dez")
    var compactDateTitle: String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "pt_BR")

        switch viewMode {
        case .day:
            formatter.dateFormat = "d MMM"
            return formatter.string(from: selectedDate)

        case .week:
            let calendar = Calendar.current
            let startOfWeek = calendar.dateInterval(of: .weekOfYear, for: selectedDate)?.start ?? selectedDate
            let endOfWeek = calendar.date(byAdding: .day, value: 6, to: startOfWeek)!

            let dayFormatter = DateFormatter()
            dayFormatter.locale = Locale(identifier: "pt_BR")
            dayFormatter.dateFormat = "d"

            let monthFormatter = DateFormatter()
            monthFormatter.locale = Locale(identifier: "pt_BR")
            monthFormatter.dateFormat = "MMM"

            return "\(dayFormatter.string(from: startOfWeek))-\(dayFormatter.string(from: endOfWeek)) \(monthFormatter.string(from: selectedDate))"
        }
    }

    var appointmentsForSelectedDate: [Appointment] {
        let calendar = Calendar.current
        return appointments.filter { calendar.isDate($0.start, inSameDayAs: selectedDate) }
    }

    var appointmentsByHour: [Int: [Appointment]] {
        var result: [Int: [Appointment]] = [:]
        for appointment in appointmentsForSelectedDate {
            let hour = Calendar.current.component(.hour, from: appointment.start)
            if result[hour] == nil {
                result[hour] = []
            }
            result[hour]?.append(appointment)
        }
        return result
    }

    // MARK: - Actions

    func loadData() async {
        isLoading = true
        error = nil

        switch viewMode {
        case .day:
            await appointmentService.fetchAppointmentsForDay(
                selectedDate,
                professional: selectedProfessional?.name
            )
        case .week:
            await appointmentService.fetchAppointmentsForWeek(
                of: selectedDate,
                professional: selectedProfessional?.name
            )
        }

        // Verificar se a task foi cancelada antes de atualizar o estado
        guard !Task.isCancelled else {
            isLoading = false
            return
        }

        appointments = appointmentService.appointments
        error = appointmentService.error
        isLoading = false

        // Carregar bloqueios recorrentes
        await loadRecurringBlocks()
    }

    private func loadRecurringBlocks() async {
        guard let userId = supabase.effectiveUserId else { return }
        guard !Task.isCancelled else { return }

        do {
            var query = supabase.client
                .from("recurring_blocks")
                .select()
                .eq("user_id", value: userId)
                .eq("active", value: true)

            if let professional = selectedProfessional {
                query = query.eq("professional_id", value: professional.id)
            }

            let result: [RecurringBlock] = try await query.execute().value

            guard !Task.isCancelled else { return }
            recurringBlocks = result
        } catch is CancellationError {
            // Ignorar erros de cancelamento
        } catch {
            print("Erro ao carregar bloqueios: \(error)")
        }
    }

    func goToToday() {
        selectedDate = Date()
        Task {
            await loadData()
        }
    }

    func goToPreviousDay() {
        selectedDate = Calendar.current.date(byAdding: .day, value: -1, to: selectedDate) ?? selectedDate
        Task {
            await loadData()
        }
    }

    func goToNextDay() {
        selectedDate = Calendar.current.date(byAdding: .day, value: 1, to: selectedDate) ?? selectedDate
        Task {
            await loadData()
        }
    }

    func goToPreviousWeek() {
        selectedDate = Calendar.current.date(byAdding: .weekOfYear, value: -1, to: selectedDate) ?? selectedDate
        Task {
            await loadData()
        }
    }

    func goToNextWeek() {
        selectedDate = Calendar.current.date(byAdding: .weekOfYear, value: 1, to: selectedDate) ?? selectedDate
        Task {
            await loadData()
        }
    }

    func selectDate(_ date: Date) {
        selectedDate = date
        Task {
            await loadData()
        }
    }

    func toggleViewMode() {
        viewMode = viewMode == .day ? .week : .day
        Task {
            await loadData()
        }
    }

    // MARK: - Block Helpers

    func blocksForDate(_ date: Date) -> [RecurringBlock] {
        recurringBlocks.filter { $0.appliesTo(date: date) }
    }

    func isTimeBlocked(_ date: Date, hour: Int) -> Bool {
        let blocks = blocksForDate(date)
        for block in blocks {
            let startHour = Int(block.startTime.prefix(2)) ?? 0
            let endHour = Int(block.endTime.prefix(2)) ?? 0
            if hour >= startHour && hour < endHour {
                return true
            }
        }
        return false
    }
}
