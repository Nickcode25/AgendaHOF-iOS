import SwiftUI

/// Vista de calendário para um único dia com grid de tempo
/// Implementa layout similar ao Apple Calendar / Google Calendar
struct CalendarDayView: View {
    @ObservedObject var viewModel: AgendaViewModel
    
    private var isToday: Bool {
        Calendar.current.isDateInToday(viewModel.selectedDate)
    }

    @State private var dragStartPoint: CGPoint?
    @State private var isDragging = false
    @State private var ghostEventRawY: CGFloat = 0
    @State private var ghostEventHeight: CGFloat = 0

    private let impactFeedback = UIImpactFeedbackGenerator(style: .medium)

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical, showsIndicators: true) {
                HStack(alignment: .top, spacing: 0) {
                    // Coluna de horas (fixa à esquerda)
                    CalendarTimeColumn()
                        .frame(width: CalendarConstants.timeColumnWidth)

                    // Grid principal com agendamentos
                    GeometryReader { geometry in
                        ZStack(alignment: .topLeading) {
                            // Linhas de hora (background)
                            CalendarHourLines()

                            // Camada de detecção de long press para CRIAR
                            LongPressGestureView(
                                onLongPressStart: { point in
                                    startCreatingEvent(at: point, geometry: geometry)
                                },
                                onLongPressDrag: { point in
                                    updateCreatingEvent(at: point, geometry: geometry)
                                },
                                onLongPressEnd: {
                                    finishCreatingEvent()
                                },
                                isActive: $isDragging
                            )

                            // Bloqueios recorrentes (atrás dos agendamentos)
                            recurringBlocksLayer(width: geometry.size.width)

                            // Agendamentos posicionados com resolução de conflitos
                            appointmentsLayer(width: geometry.size.width)
                            
                            // Evento Fantasma (Drag-to-Create)
                            if isDragging {
                                GhostEventView(
                                    yPosition: ghostEventRawY,
                                    height: ghostEventHeight,
                                    width: geometry.size.width,
                                    startTime: ghostStartTime,
                                    endTime: ghostEndTime
                                )
                            }

                            // Indicador de hora atual (linha vermelha)
                            if isToday {
                                CurrentTimeIndicator(isToday: isToday)
                                    .padding(.leading, -4)
                            }
                        }
                        .contentShape(Rectangle())
                    }
                    .frame(height: CalendarConstants.totalGridHeight)
                }
                .padding(.top, 8)
                .id("calendarTop")
            }
            .scrollDisabled(isDragging)
            .background(Color(.systemGroupedBackground))
            .onAppear {
                if isToday {
                    scrollToCurrentTime(proxy: proxy)
                }
            }
        }
    }

    // MARK: - Recurring Blocks Layer

    @ViewBuilder
    private func recurringBlocksLayer(width: CGFloat) -> some View {
        let blocks = viewModel.blocksForDate(viewModel.selectedDate)
        let appointments = viewModel.appointmentsForSelectedDate

        ForEach(blocks, id: \.id) { block in
            let segments = calculateBlockSegments(block: block, appointments: appointments)

            ForEach(segments, id: \.id) { segment in
                DayRecurringBlockSegmentView(
                    segment: segment,
                    block: block,
                    availableWidth: width
                ) {
                    viewModel.activeSheet = .editRecurringBlock(block)
                }
            }
        }
    }

    private func calculateBlockSegments(block: RecurringBlock, appointments: [Appointment]) -> [BlockSegment] {
        let blockStartMinutes = timeToMinutes(block.startTime)
        let blockEndMinutes = timeToMinutes(block.endTime)

        var occupiedRanges: [(start: Int, end: Int)] = []

        for appointment in appointments {
            let calendar = Calendar.current
            let appointmentStartMinutes = calendar.component(.hour, from: appointment.start) * 60 +
                                          calendar.component(.minute, from: appointment.start)
            let appointmentEndMinutes = calendar.component(.hour, from: appointment.end) * 60 +
                                        calendar.component(.minute, from: appointment.end)

            if appointmentStartMinutes < blockEndMinutes && appointmentEndMinutes > blockStartMinutes {
                occupiedRanges.append((start: appointmentStartMinutes, end: appointmentEndMinutes))
            }
        }

        if occupiedRanges.isEmpty {
            return [BlockSegment(
                id: "\(block.id)-full",
                startMinutes: blockStartMinutes,
                endMinutes: blockEndMinutes
            )]
        }

        let sortedRanges = occupiedRanges.sorted { $0.start < $1.start }

        var segments: [BlockSegment] = []
        var currentStart = blockStartMinutes

        for range in sortedRanges {
            if currentStart < range.start {
                let segmentEnd = min(range.start, blockEndMinutes)
                if segmentEnd > currentStart {
                    segments.append(BlockSegment(
                        id: "\(block.id)-\(currentStart)-\(segmentEnd)",
                        startMinutes: currentStart,
                        endMinutes: segmentEnd
                    ))
                }
            }
            currentStart = max(currentStart, range.end)
        }

        if currentStart < blockEndMinutes {
            segments.append(BlockSegment(
                id: "\(block.id)-\(currentStart)-\(blockEndMinutes)",
                startMinutes: currentStart,
                endMinutes: blockEndMinutes
            ))
        }

        return segments
    }

    private func timeToMinutes(_ time: String) -> Int {
        let hour = Int(time.prefix(2)) ?? 0
        let minute = Int(time.dropFirst(3).prefix(2)) ?? 0
        return hour * 60 + minute
    }

    // MARK: - Appointments Layer

    @ViewBuilder
    private func appointmentsLayer(width: CGFloat) -> some View {
        let appointments = viewModel.appointmentsForSelectedDate
        let positionedAppointments = OverlapLayoutEngine.calculateLayout(for: appointments)

        ForEach(positionedAppointments) { positioned in
            DayAppointmentBlock(
                positioned: positioned,
                availableWidth: width
            ) {
                viewModel.activeSheet = .appointmentDetails(positioned.appointment)
            }
        }
    }

    // MARK: - Gesture Handling (Create Event)

    private func startCreatingEvent(at point: CGPoint, geometry: GeometryProxy) {
        DispatchQueue.main.async {
            self.dragStartPoint = point
            self.ghostEventRawY = self.snapToGrid(y: point.y)
            self.ghostEventHeight = CalendarConstants.hourHeight / 4
            self.impactFeedback.impactOccurred()
        }
    }

    private func updateCreatingEvent(at point: CGPoint, geometry: GeometryProxy) {
        guard let startPoint = dragStartPoint else { return }
        
        let diff = point.y - startPoint.y
        let minHeight = CalendarConstants.hourHeight / 4
        
        DispatchQueue.main.async {
            if diff >= 0 {
                self.ghostEventHeight = max(minHeight, self.snapToGrid(y: diff))
            } else {
                self.ghostEventRawY = self.snapToGrid(y: point.y)
                self.ghostEventHeight = max(minHeight, self.snapToGrid(y: startPoint.y - point.y))
            }
        }
    }

    private func finishCreatingEvent() {
        guard isDragging else { return }
        
        let start = ghostStartTime
        let end = ghostEndTime
        
        DispatchQueue.main.async {
            self.viewModel.activeSheet = .newAppointment(start: start, end: end)
            
            self.isDragging = false
            self.dragStartPoint = nil
            self.ghostEventHeight = 0
        }
    }
    
    // MARK: - Helpers
    
    private func snapToGrid(y: CGFloat) -> CGFloat {
        let step = CalendarConstants.hourHeight / 4
        return (y / step).rounded() * step
    }

    private var ghostStartTime: Date {
        CalendarConstants.date(for: ghostEventRawY, baseDate: viewModel.selectedDate)
    }
    
    private var ghostEndTime: Date {
        let durationMinutes = (ghostEventHeight / CalendarConstants.hourHeight) * 60
        return Calendar.current.date(byAdding: .minute, value: Int(durationMinutes), to: ghostStartTime) ?? ghostStartTime
    }

    // MARK: - Scroll to Current Time

    private func scrollToCurrentTime(proxy: ScrollViewProxy) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            withAnimation(.easeInOut(duration: 0.3)) {
                proxy.scrollTo("calendarTop", anchor: .top)
            }
        }
    }
}

// MARK: - Ghost Event View

struct GhostEventView: View {
    let yPosition: CGFloat
    let height: CGFloat
    let width: CGFloat
    let startTime: Date
    let endTime: Date

    var body: some View {
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 6)
                .fill(Color.appPrimary.opacity(0.3))
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .strokeBorder(Color.appPrimary, lineWidth: 2, antialiased: true)
                )

            VStack(alignment: .leading, spacing: 2) {
                Text("Novo Agendamento")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(.white)
                
                Text("\(startTime.timeRange(to: endTime))")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.white.opacity(0.9))
            }
            .padding(6)
        }
        .frame(width: width, height: max(height, 15), alignment: .top)
        .offset(y: yPosition)
        .shadow(radius: 4)
    }
}

private extension Date {
    func timeRange(to end: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return "\(formatter.string(from: self)) - \(formatter.string(from: end))"
    }
}

// MARK: - Day Appointment Block (SIMPLIFICADO)

struct DayAppointmentBlock: View {
    @Environment(\.horizontalSizeClass) private var sizeClass

    let positioned: PositionedAppointment
    let availableWidth: CGFloat
    var onTap: () -> Void

    private var appointment: Appointment {
        positioned.appointment
    }

    private var blockColor: Color {
        CalendarConstants.appointmentColor(for: appointment)
    }

    private var blockWidth: CGFloat {
        positioned.width(for: availableWidth)
    }

    private var xOffset: CGFloat {
        positioned.xOffset(for: availableWidth)
    }

    private var blockHeight: CGFloat {
        positioned.height
    }

    private var textFont: Font {
        .system(size: 13, weight: .medium)
    }

    private var barWidth: CGFloat {
        sizeClass == .regular ? 6 : 4
    }

    var body: some View {
        HStack(spacing: 0) {
            RoundedRectangle(cornerRadius: 2)
                .fill(blockColor)
                .frame(width: barWidth)

            Text("\(appointment.start.formatted(date: .omitted, time: .shortened)) \(appointment.displayTitle)")
                .font(textFont)
                .fontWeight(.medium)
                .foregroundColor(.primary)
                .lineLimit(1)
                .padding(.horizontal, sizeClass == .regular ? 8 : 6)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(width: blockWidth, height: blockHeight)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(CalendarConstants.appointmentBackgroundColor(for: appointment))
        )
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(Color(.systemGroupedBackground))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .strokeBorder(blockColor.opacity(0.3), lineWidth: 1)
        )
        .contentShape(Rectangle())
        .onTapGesture {
            onTap()
        }
        .offset(x: xOffset, y: positioned.yPosition)
    }
}

// MARK: - Block Segment (mantido)

struct BlockSegment: Identifiable {
    let id: String
    let startMinutes: Int
    let endMinutes: Int

    var startTimeFormatted: String {
        let hour = startMinutes / 60
        let minute = startMinutes % 60
        return String(format: "%02d:%02d", hour, minute)
    }

    var endTimeFormatted: String {
        let hour = endMinutes / 60
        let minute = endMinutes % 60
        return String(format: "%02d:%02d", hour, minute)
    }

    var durationMinutes: Int {
        endMinutes - startMinutes
    }
}

// MARK: - Day Recurring Block Segment View (mantido)

struct DayRecurringBlockSegmentView: View {
    let segment: BlockSegment
    let block: RecurringBlock
    let availableWidth: CGFloat
    var onTap: (() -> Void)?

    private let blockColor = Color.gray

    private var yPosition: CGFloat {
        let startHour = segment.startMinutes / 60
        let startMinute = segment.startMinutes % 60

        let hoursFromStart = CGFloat(startHour - CalendarConstants.startHour)
        let minuteFraction = CGFloat(startMinute) / 60.0

        let position = (hoursFromStart + minuteFraction) * CalendarConstants.hourHeight
        return max(0, position)
    }

    private var blockHeight: CGFloat {
        let height = CGFloat(segment.durationMinutes) / 60.0 * CalendarConstants.hourHeight
        return max(height, 15)
    }

    var body: some View {
        HStack(spacing: 0) {
            RoundedRectangle(cornerRadius: 2)
                .fill(blockColor)
                .frame(width: 4)

            Text("\(segment.startTimeFormatted) \(block.title)")
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(.secondary)
                .lineLimit(1)
                .padding(.horizontal, 6)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(width: availableWidth - 8, height: blockHeight)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(blockColor.opacity(0.1))
        )
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(Color(.systemGroupedBackground))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .strokeBorder(blockColor.opacity(0.2), lineWidth: 1)
        )
        .contentShape(Rectangle())
        .onTapGesture {
            onTap?()
        }
        .offset(x: 4, y: yPosition)
    }
}

// MARK: - Long Press Gesture View (mantido)

struct LongPressGestureView: UIViewRepresentable {
    let onLongPressStart: (CGPoint) -> Void
    let onLongPressDrag: (CGPoint) -> Void
    let onLongPressEnd: () -> Void
    @Binding var isActive: Bool
    
    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.backgroundColor = .clear
        
        let longPress = UILongPressGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handleLongPress(_:))
        )
        longPress.minimumPressDuration = 0.5
        longPress.allowableMovement = .infinity
        longPress.delegate = context.coordinator
        
        view.addGestureRecognizer(longPress)
        return view
    }
    
    func updateUIView(_ uiView: UIView, context: Context) {}
    
    func makeCoordinator() -> Coordinator {
        Coordinator(
            onLongPressStart: onLongPressStart,
            onLongPressDrag: onLongPressDrag,
            onLongPressEnd: onLongPressEnd,
            isActive: $isActive
        )
    }
    
    class Coordinator: NSObject, UIGestureRecognizerDelegate {
        let onLongPressStart: (CGPoint) -> Void
        let onLongPressDrag: (CGPoint) -> Void
        let onLongPressEnd: () -> Void
        @Binding var isActive: Bool
        
        init(
            onLongPressStart: @escaping (CGPoint) -> Void,
            onLongPressDrag: @escaping (CGPoint) -> Void,
            onLongPressEnd: @escaping () -> Void,
            isActive: Binding<Bool>
        ) {
            self.onLongPressStart = onLongPressStart
            self.onLongPressDrag = onLongPressDrag
            self.onLongPressEnd = onLongPressEnd
            self._isActive = isActive
        }
        
        @objc func handleLongPress(_ gesture: UILongPressGestureRecognizer) {
            let location = gesture.location(in: gesture.view)
            
            switch gesture.state {
            case .began:
                isActive = true
                onLongPressStart(location)
                
            case .changed:
                if isActive {
                    onLongPressDrag(location)
                }
                
            case .ended, .cancelled, .failed:
                if isActive {
                    onLongPressEnd()
                    isActive = false
                }
                
            default:
                break
            }
        }
        
        func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer,
            shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
        ) -> Bool {
            return !isActive
        }
    }
}

// MARK: - Preview

struct CalendarDayView_Previews: PreviewProvider {
    static var previews: some View {
        PreviewWrapper()
            .previewDisplayName("Day View")
    }

    struct PreviewWrapper: View {
        @StateObject var viewModel = AgendaViewModel()

        var body: some View {
            NavigationStack {
                CalendarDayView(viewModel: viewModel)
                    .navigationTitle("Agenda")
            }
            .environmentObject(SupabaseManager.shared)
        }
    }
}
