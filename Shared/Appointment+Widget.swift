import Foundation

/// Extensão para permitir que Appointment seja usado com WidgetDataManager
/// Este arquivo deve estar APENAS no target AgendaHOF (não no widget)
extension Appointment: AppointmentConvertible {
    // Appointment já implementa todas as propriedades necessárias
    // Esta extensão apenas formaliza a conformidade com o protocolo
}
