import SwiftUI

struct WeekAgendaView: View {
    @ObservedObject var viewModel: AgendaViewModel
    @State private var selectedAppointment: Appointment?

    private var weekDates: [Date] {
        var calendar = Calendar.current
        calendar.firstWeekday = 2 // Segunda-feira (1 = Domingo, 2 = Segunda)unda-feira (1 = Domingo, 2 = Segunda)
        let startOfWeek = calendar.dateInterval(of: .weekOfYear, for: viewModel.selectedDate)?.start ?? viewModel.selectedDate

        return (0..<7).compactMap { dayOffset in
            calendar.date(byAdding: .day, value: dayOffset, to: startOfWeek)
        }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                // Header dos dias da semana
                weekHeader

                // Conteúdo dos dias
                ForEach(weekDates, id: \.self) { date in
                    WeekDayRow(
                        date: date,
                        appointments: appointmentsFor(date),
                        isSelected: Calendar.current.isDate(date, inSameDayAs: viewModel.selectedDate),
                        onTap: {
                            viewModel.viewMode = .day
                            viewModel.selectDate(date)
                        },
                        onAppointmentTap: { appointment in
                            selectedAppointment = appointment
                        }
                    )
                }
            }
        }
        .sheet(item: $selectedAppointment) { appointment in
            AppointmentDetailSheet(appointment: appointment) {
                Task { await viewModel.loadData() }
            }
        }
    }

    private var weekHeader: some View {
        HStack(spacing: 0) {
            ForEach(weekDates, id: \.self) { date in
                VStack(spacing: 4) {
                    Text(dayOfWeekLetter(for: date))
                        .font(.caption2)
                        .fontWeight(.medium)
                        .foregroundColor(.secondary)

                    Text(dayNumber(for: date))
                        .font(.subheadline)
                        .fontWeight(isToday(date) ? .bold : .regular)
                        .foregroundColor(isToday(date) ? .white : .primary)
                        .frame(width: 28, height: 28)
                        .background(isToday(date) ? Color.appPrimary : Color.clear)
                        .clipShape(Circle())
                }
                .frame(maxWidth: .infinity)
            }
        }
        .padding(.vertical, 12)
        .background(Color(.systemBackground))
    }

    private func appointmentsFor(_ date: Date) -> [Appointment] {
        let calendar = Calendar.current
        
        // 1. Obter agendamentos de pacientes para esta data
        let regularAppts = viewModel.appointments.filter { calendar.isDate($0.start, inSameDayAs: date) }
        
        // 2. Obter bloqueios recorrentes para esta data
        let blocks = viewModel.blocksForDate(date)
        
        // 3. Converter bloqueios recorrentes em Appointments para exibição
        let blockAppts: [Appointment] = blocks.compactMap { block -> Appointment? in
            // Criar um Appointment virtual a partir do RecurringBlock
            let startComponents = block.startTime.split(separator: ":").compactMap { Int($0) }
            let endComponents = block.endTime.split(separator: ":").compactMap { Int($0) }
            
            // Validar que temos hora e minuto
            guard startComponents.count >= 2, endComponents.count >= 2 else {
                return nil
            }
            
            guard let startDate = calendar.date(bySettingHour: startComponents[0], minute: startComponents[1], second: 0, of: date),
                  let endDate = calendar.date(bySettingHour: endComponents[0], minute: endComponents[1], second: 0, of: date) else {
                return nil
            }
            
            // Criar appointment virtual com dados do bloco
            return Appointment(
                id: block.id,
                createdAt: Date(),
                updatedAt: Date(),
                userId: block.userId,
                patientId: nil,  // Bloqueios não têm paciente
                patientName: nil,
                procedure: nil,
                procedureId: nil,
                selectedProducts: nil,
                professional: block.professional ?? "Admin",
                professionalId: block.professionalId,
                room: nil,
                start: startDate,
                end: endDate,
                notes: block.notes,
                status: .done,  // done = cinza
                isPersonal: true,  // IMPORTANTE: true para exibir o título ao invés de patientName
                title: block.title  // Título do bloqueio (ex: "Almoço")
            )
        }
        
        // 4. Combinar e ordenar por horário
        return (regularAppts + blockAppts).sorted { $0.start < $1.start }
    }

    private func dayOfWeekLetter(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "pt_BR")
        formatter.dateFormat = "EEEEE" // Uma letra
        return formatter.string(from: date).uppercased()
    }

    private func dayNumber(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "d"
        return formatter.string(from: date)
    }

    private func isToday(_ date: Date) -> Bool {
        Calendar.current.isDateInToday(date)
    }
}

// MARK: - Week Day Row

struct WeekDayRow: View {
    let date: Date
    let appointments: [Appointment]
    let isSelected: Bool
    var onTap: () -> Void
    var onAppointmentTap: (Appointment) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Cabeçalho do dia
            Button(action: onTap) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(formattedDate)
                            .font(.subheadline)
                            .fontWeight(.semibold)
                            .foregroundColor(isToday ? .appPrimary : .primary)

                        Text("\(appointments.count) agendamento\(appointments.count == 1 ? "" : "s")")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    Spacer()

                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding()
                .background(isSelected ? Color.appPrimary.opacity(0.1) : Color(.systemBackground))
            }

            // Lista de agendamentos
            if !appointments.isEmpty {
                VStack(spacing: 8) {
                    ForEach(appointments.prefix(3)) { appointment in
                        CompactAppointmentRow(appointment: appointment)
                            .onTapGesture {
                                onAppointmentTap(appointment)
                            }
                    }

                    if appointments.count > 3 {
                        Text("+\(appointments.count - 3) mais")
                            .font(.caption)
                            .foregroundColor(.appPrimary)
                            .padding(.leading, 16)
                    }
                }
                .padding(.horizontal)
                .padding(.bottom, 12)
            }

            Divider()
        }
    }

    private var formattedDate: String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "pt_BR")
        formatter.dateFormat = "EEEE, d 'de' MMMM"
        return formatter.string(from: date).capitalized
    }

    private var isToday: Bool {
        Calendar.current.isDateInToday(date)
    }
}

// MARK: - Compact Appointment Row

struct CompactAppointmentRow: View {
    let appointment: Appointment

    var body: some View {
        HStack(spacing: 12) {
            // Indicador de cor
            Rectangle()
                .fill(statusColor)
                .frame(width: 3)
                .cornerRadius(2)

            VStack(alignment: .leading, spacing: 2) {
                Text(appointment.displayTitle)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .lineLimit(1)

                HStack(spacing: 8) {
                    Text(appointment.timeRange)
                        .font(.caption)
                        .foregroundColor(.secondary)

                    Text("•")
                        .foregroundColor(.secondary)

                    Text(appointment.professional)
                        .font(.caption)
                        .foregroundColor(.appPrimary)
                }
            }

            Spacer()
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 12)
        .background(Color(.systemGray6))
        .cornerRadius(8)
    }

    private var statusColor: Color {
        // Compromissos pessoais = AZUL
        if appointment.isPersonalAppointment {
            return .blue
        }

        // Agendamentos de pacientes - cor por status
        switch appointment.status {
        case .confirmed:
            return .green
        case .cancelled:
            return .red
        case .scheduled, .completed, .done:
            return .orange
        }
    }
}

#Preview {
    WeekAgendaView(viewModel: AgendaViewModel())
}
