import SwiftUI

// MARK: - Positioned Appointment

/// Agendamento com informações de posicionamento para layout
struct PositionedAppointment: Identifiable {
    let appointment: Appointment
    let column: Int           // Coluna onde será renderizado (0, 1, 2...)
    let totalColumns: Int     // Total de colunas no grupo de conflito

    var id: String { appointment.id }

    /// Calcula a largura do bloco baseado no número de colunas
    func width(for availableWidth: CGFloat, padding: CGFloat = 4) -> CGFloat {
        (availableWidth - padding) / CGFloat(totalColumns)
    }

    /// Calcula o offset X baseado na coluna
    func xOffset(for availableWidth: CGFloat, padding: CGFloat = 4) -> CGFloat {
        CGFloat(column) * width(for: availableWidth, padding: padding) + (padding / 2)
    }

    // MARK: - Day View Positioning (hourHeight = 60)

    /// Posição Y baseada no horário de início (vista diária)
    var yPosition: CGFloat {
        CalendarConstants.yPosition(for: appointment.start)
    }

    /// Altura baseada na duração (vista diária)
    /// Proporcional: 15min = 15px, 30min = 30px, 60min = 60px
    var height: CGFloat {
        max(CalendarConstants.height(from: appointment.start, to: appointment.end), 15)
    }

    // MARK: - Week View Positioning (weekHourHeight = 80)

    /// Posição Y para vista semanal (escala maior para legibilidade)
    var weekYPosition: CGFloat {
        CalendarConstants.weekYPosition(for: appointment.start)
    }

    /// Altura para vista semanal (proporcional à escala maior)
    /// Com weekHourHeight = 80: 15min = 20px, 30min = 40px, 60min = 80px
    var weekHeight: CGFloat {
        max(CalendarConstants.weekHeight(from: appointment.start, to: appointment.end), 20)
    }
}

// MARK: - Overlap Layout Engine

/// Motor de layout para resolver sobreposições de agendamentos
/// Implementa algoritmo similar ao Apple Calendar / Google Calendar
enum OverlapLayoutEngine {

    // MARK: - Main Entry Point

    /// Processa uma lista de agendamentos e retorna com informações de posicionamento
    /// - Parameter appointments: Lista de agendamentos do dia
    /// - Returns: Lista de PositionedAppointment com colunas calculadas
    static func calculateLayout(for appointments: [Appointment]) -> [PositionedAppointment] {
        guard !appointments.isEmpty else { return [] }

        // 1. Ordenar por horário de início, depois por duração (maior primeiro)
        let sorted = appointments.sorted { a, b in
            if a.start == b.start {
                return a.end > b.end // Mais longo primeiro
            }
            return a.start < b.start
        }

        // 2. Agrupar em clusters de conflito
        let clusters = buildConflictClusters(sorted)

        // 3. Atribuir colunas dentro de cada cluster
        var result: [PositionedAppointment] = []

        for cluster in clusters {
            let positioned = assignColumns(to: cluster)
            result.append(contentsOf: positioned)
        }

        return result
    }

    // MARK: - Step 1: Build Conflict Clusters

    /// Agrupa agendamentos que se sobrepõem em clusters
    /// Dois agendamentos estão no mesmo cluster se há uma cadeia de sobreposições entre eles
    private static func buildConflictClusters(_ appointments: [Appointment]) -> [[Appointment]] {
        var clusters: [[Appointment]] = []
        var currentCluster: [Appointment] = []
        var clusterEnd: Date?

        for appointment in appointments {
            if let end = clusterEnd, appointment.start >= end {
                // Novo cluster - não sobrepõe com o cluster atual
                if !currentCluster.isEmpty {
                    clusters.append(currentCluster)
                }
                currentCluster = [appointment]
                clusterEnd = appointment.end
            } else {
                // Adiciona ao cluster atual
                currentCluster.append(appointment)
                if let end = clusterEnd {
                    clusterEnd = max(end, appointment.end)
                } else {
                    clusterEnd = appointment.end
                }
            }
        }

        // Adicionar último cluster
        if !currentCluster.isEmpty {
            clusters.append(currentCluster)
        }

        return clusters
    }

    // MARK: - Step 2: Assign Columns (Greedy Algorithm)

    /// Atribui colunas aos agendamentos dentro de um cluster usando algoritmo greedy
    /// Similar ao algoritmo de coloração de grafos de intervalo
    private static func assignColumns(to cluster: [Appointment]) -> [PositionedAppointment] {
        guard !cluster.isEmpty else { return [] }

        // Estrutura para rastrear o fim de cada coluna
        var columnEnds: [Date] = []
        var assignments: [(Appointment, Int)] = [] // (appointment, column)

        for appointment in cluster {
            // Encontrar a primeira coluna disponível
            var assignedColumn: Int?

            for (index, columnEnd) in columnEnds.enumerated() {
                if appointment.start >= columnEnd {
                    // Esta coluna está livre
                    assignedColumn = index
                    columnEnds[index] = appointment.end
                    break
                }
            }

            if assignedColumn == nil {
                // Criar nova coluna
                assignedColumn = columnEnds.count
                columnEnds.append(appointment.end)
            }

            assignments.append((appointment, assignedColumn!))
        }

        // Calcular o número máximo de colunas simultâneas
        let maxColumns = columnEnds.count

        // Criar PositionedAppointments
        return assignments.map { (appointment, column) in
            PositionedAppointment(
                appointment: appointment,
                column: column,
                totalColumns: maxColumns
            )
        }
    }

    // MARK: - Utility: Check Overlap

    /// Verifica se dois agendamentos se sobrepõem
    static func overlaps(_ a: Appointment, _ b: Appointment) -> Bool {
        return a.start < b.end && a.end > b.start
    }

    // MARK: - Advanced: Calculate True Column Width

    /// Calcula a largura real considerando apenas conflitos diretos
    /// (Otimização: agendamentos podem expandir se não tiverem vizinhos)
    static func calculateExpandedLayout(for appointments: [Appointment]) -> [PositionedAppointment] {
        let basic = calculateLayout(for: appointments)

        // Para cada appointment, verificar se pode expandir
        return basic.map { positioned in
            // Encontrar agendamentos que realmente conflitam com este
            let directConflicts = basic.filter { other in
                other.id != positioned.id &&
                overlaps(positioned.appointment, other.appointment)
            }

            if directConflicts.isEmpty {
                // Sem conflitos diretos - usar largura total
                return PositionedAppointment(
                    appointment: positioned.appointment,
                    column: 0,
                    totalColumns: 1
                )
            }

            // Manter posicionamento original
            return positioned
        }
    }
}

// MARK: - Preview Helper

#if DEBUG
extension OverlapLayoutEngine {
    /// Cria dados de exemplo para preview
    static func sampleAppointments() -> [Appointment] {
        let calendar = Calendar.current
        let today = Date()

        func makeDate(hour: Int, minute: Int = 0) -> Date {
            calendar.date(bySettingHour: hour, minute: minute, second: 0, of: today)!
        }

        return [
            // Sem conflito
            Appointment(
                id: "1", createdAt: today, updatedAt: today, userId: "u1",
                patientId: "p1", patientName: "Maria Silva", procedure: "Consulta",
                procedureId: nil, selectedProducts: nil, professional: "Dra. Ana",
                room: nil, start: makeDate(hour: 8), end: makeDate(hour: 9),
                notes: nil, status: .confirmed, isPersonal: false, title: nil
            ),

            // Conflito duplo
            Appointment(
                id: "2", createdAt: today, updatedAt: today, userId: "u1",
                patientId: "p2", patientName: "João Santos", procedure: "Botox",
                procedureId: nil, selectedProducts: nil, professional: "Dra. Ana",
                room: nil, start: makeDate(hour: 10), end: makeDate(hour: 11, minute: 30),
                notes: nil, status: .scheduled, isPersonal: false, title: nil
            ),
            Appointment(
                id: "3", createdAt: today, updatedAt: today, userId: "u1",
                patientId: "p3", patientName: "Ana Costa", procedure: "Limpeza",
                procedureId: nil, selectedProducts: nil, professional: "Dra. Ana",
                room: nil, start: makeDate(hour: 10, minute: 30), end: makeDate(hour: 11),
                notes: nil, status: .confirmed, isPersonal: false, title: nil
            ),

            // Conflito triplo
            Appointment(
                id: "4", createdAt: today, updatedAt: today, userId: "u1",
                patientId: "p4", patientName: "Pedro Lima", procedure: "Retorno",
                procedureId: nil, selectedProducts: nil, professional: "Dra. Ana",
                room: nil, start: makeDate(hour: 14), end: makeDate(hour: 15),
                notes: nil, status: .confirmed, isPersonal: false, title: nil
            ),
            Appointment(
                id: "5", createdAt: today, updatedAt: today, userId: "u1",
                patientId: "p5", patientName: "Carla Mendes", procedure: "Peeling",
                procedureId: nil, selectedProducts: nil, professional: "Dra. Ana",
                room: nil, start: makeDate(hour: 14), end: makeDate(hour: 15, minute: 30),
                notes: nil, status: .scheduled, isPersonal: false, title: nil
            ),
            Appointment(
                id: "6", createdAt: today, updatedAt: today, userId: "u1",
                patientId: "p6", patientName: "Lucas Rocha", procedure: "Avaliação",
                procedureId: nil, selectedProducts: nil, professional: "Dra. Ana",
                room: nil, start: makeDate(hour: 14, minute: 15), end: makeDate(hour: 14, minute: 45),
                notes: nil, status: .confirmed, isPersonal: false, title: nil
            ),
        ]
    }
}
#endif
