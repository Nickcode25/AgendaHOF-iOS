import Foundation
import SwiftUI

@MainActor
class InactivePatientsViewModel: ObservableObject {
    @Published var inactivePatients: [InactivePatient] = []
    @Published var filteredPatients: [InactivePatient] = []
    @Published var searchText: String = ""
    @Published var isLoading = false
    @Published var errorMessage: String?

    private let supabase: SupabaseManager
    private let inactiveDaysThreshold = Constants.inactiveDaysThreshold // 6 meses (180 dias)

    init(supabase: SupabaseManager? = nil) {
        self.supabase = supabase ?? .shared
    }

    /// Carrega pacientes inativos do banco - VERSÃO OTIMIZADA
    func loadInactivePatients() async {
        isLoading = true
        errorMessage = nil

        do {
            guard let userId = supabase.currentUser?.id.uuidString else {
                errorMessage = "Usuário não autenticado"
                isLoading = false
                return
            }

            // Data limite: 180 dias atrás
            let calendar = Calendar.current
            let limitDate = calendar.date(byAdding: .day, value: -inactiveDaysThreshold, to: Date())!

            print("📅 [InactivePatients] Buscando pacientes sem procedimentos desde: \(limitDate)")

            // 1. Buscar TODOS os pacientes ativos do usuário
            let allPatients: [Patient] = try await supabase.client
                .from("patients")
                .select()
                .eq("user_id", value: userId)
                .eq("is_active", value: true)
                .order("name")
                .execute()
                .value

            print("👥 [InactivePatients] Total de pacientes ativos: \(allPatients.count)")

            // 2. Buscar TODOS os agendamentos concluídos desde a data limite
            // Incluindo todos os status que indicam procedimento realizado
            let recentAppointments: [Appointment] = try await supabase.client
                .from("appointments")
                .select()
                .eq("user_id", value: userId)
                .gte("start", value: limitDate.ISO8601Format())
                .neq("is_personal", value: true) // Ignorar compromissos pessoais
                .execute()
                .value

            print("📋 [InactivePatients] Agendamentos recentes encontrados: \(recentAppointments.count)")

            // 3. Criar um dicionário de paciente_id -> última data de procedimento
            var lastProcedureDates: [String: Date] = [:]

            for appointment in recentAppointments {
                guard let patientId = appointment.patientId else { continue }

                if let existingDate = lastProcedureDates[patientId] {
                    // Manter a data mais recente
                    if appointment.start > existingDate {
                        lastProcedureDates[patientId] = appointment.start
                    }
                } else {
                    lastProcedureDates[patientId] = appointment.start
                }
            }

            print("🗓️ [InactivePatients] Pacientes com procedimentos recentes: \(lastProcedureDates.count)")

            // 4. Também verificar plannedProcedures realizados (performedAt ou completedAt)
            print("💊 [InactivePatients] Verificando plannedProcedures realizados...")

            for patient in allPatients {
                // Buscar a data mais recente de procedimento realizado em plannedProcedures
                if let procedures = patient.plannedProcedures {
                    for procedure in procedures {
                        // Tentar performedAt primeiro, depois completedAt como fallback
                        let dateString = procedure.performedAt ?? procedure.completedAt
                        guard let dateString = dateString else { continue }

                        // Tentar converter a string para Date
                        if let performedDate = parseDateString(dateString) {
                            // Atualizar a data mais recente se for maior
                            if let existingDate = lastProcedureDates[patient.id] {
                                if performedDate > existingDate {
                                    lastProcedureDates[patient.id] = performedDate
                                    print("🔄 [InactivePatients] \(patient.name) - atualizado para \(performedDate)")
                                }
                            } else {
                                lastProcedureDates[patient.id] = performedDate
                                print("✅ [InactivePatients] \(patient.name) - adicionado procedimento em \(performedDate)")
                            }
                        } else {
                            print("⚠️ [InactivePatients] Não foi possível parsear data '\(dateString)' do procedimento '\(procedure.displayName)' de \(patient.name)")
                        }
                    }
                }
            }

            print("🗓️ [InactivePatients] Pacientes com procedimentos recentes (incluindo plannedProcedures): \(lastProcedureDates.count)")

            // 5. Para pacientes sem procedimentos recentes, buscar TODOS os appointments antigos de uma vez
            let patientsWithoutRecent = allPatients.filter { lastProcedureDates[$0.id] == nil }

            if !patientsWithoutRecent.isEmpty {
                print("🔍 [InactivePatients] Buscando procedimentos antigos para \(patientsWithoutRecent.count) pacientes...")

                let patientIds = patientsWithoutRecent.map { $0.id }

                // Buscar TODOS os appointments antigos desses pacientes de uma vez
                let oldAppointments: [Appointment] = try await supabase.client
                    .from("appointments")
                    .select()
                    .eq("user_id", value: userId)
                    .in("patient_id", values: patientIds)
                    .neq("is_personal", value: true)
                    .lt("start", value: limitDate.ISO8601Format())
                    .order("start", ascending: false)
                    .execute()
                    .value

                print("📋 [InactivePatients] Appointments antigos encontrados: \(oldAppointments.count)")

                // Agrupar por paciente e pegar a data mais recente de cada um
                for appointment in oldAppointments {
                    guard let patientId = appointment.patientId else { continue }

                    if let existingDate = lastProcedureDates[patientId] {
                        if appointment.start > existingDate {
                            lastProcedureDates[patientId] = appointment.start
                        }
                    } else {
                        lastProcedureDates[patientId] = appointment.start
                    }
                }
            }

            // 6. Identificar pacientes inativos
            var inactive: [InactivePatient] = []

            for patient in allPatients {
                if let lastDate = lastProcedureDates[patient.id] {
                    // Paciente tem procedimento - verificar se está inativo
                    let daysSince = calendar.dateComponents([.day], from: lastDate, to: Date()).day ?? 0

                    if daysSince >= inactiveDaysThreshold {
                        print("⚠️ [InactivePatients] \(patient.name) - último procedimento há \(daysSince) dias")
                        inactive.append(InactivePatient.from(patient: patient, lastProcedureDate: lastDate))
                    } else {
                        print("✅ [InactivePatients] \(patient.name) - ativo (último procedimento há \(daysSince) dias)")
                    }
                } else {
                    // Paciente nunca fez procedimento
                    print("❌ [InactivePatients] \(patient.name) - nunca fez procedimento")
                    inactive.append(InactivePatient.from(patient: patient, lastProcedureDate: nil))
                }
            }

            print("🎯 [InactivePatients] Total de pacientes inativos: \(inactive.count)")

            // 7. Ordenar por dias de inatividade (do mais antigo para o mais recente)
            inactivePatients = inactive.sorted { $0.daysSinceLastProcedure > $1.daysSinceLastProcedure }
            filteredPatients = inactivePatients

        } catch {
            errorMessage = "Erro ao carregar pacientes: \(error.localizedDescription)"
            print("❌ [InactivePatients] Erro: \(error)")
        }

        isLoading = false
    }

    /// Filtrar pacientes pela busca
    func filterPatients() {
        if searchText.isEmpty {
            filteredPatients = inactivePatients
        } else {
            filteredPatients = inactivePatients.filter { patient in
                patient.name.localizedCaseInsensitiveContains(searchText) ||
                patient.phone?.contains(searchText) == true
            }
        }
    }

    /// Abrir WhatsApp com o paciente
    func openWhatsApp(for patient: InactivePatient) {
        guard let phone = patient.phone else { return }

        // Usa helper do Constants para gerar URL do WhatsApp
        let whatsappURL = Constants.whatsAppURL(for: phone)

        if let url = URL(string: whatsappURL) {
            UIApplication.shared.open(url)
        }
    }

    /// Tenta parsear uma string de data em múltiplos formatos
    private func parseDateString(_ dateString: String) -> Date? {
        // Formato 1: ISO8601 com fração de segundos
        let iso8601WithFraction = ISO8601DateFormatter()
        iso8601WithFraction.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = iso8601WithFraction.date(from: dateString) {
            return date
        }

        // Formato 2: ISO8601 sem fração de segundos
        let iso8601 = ISO8601DateFormatter()
        iso8601.formatOptions = [.withInternetDateTime]
        if let date = iso8601.date(from: dateString) {
            return date
        }

        // Formato 3: DateFormatter com milissegundos
        let formatter1 = DateFormatter()
        formatter1.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSSZ"
        formatter1.locale = Locale(identifier: "en_US_POSIX")
        if let date = formatter1.date(from: dateString) {
            return date
        }

        // Formato 4: DateFormatter sem milissegundos
        let formatter2 = DateFormatter()
        formatter2.dateFormat = "yyyy-MM-dd'T'HH:mm:ssZ"
        formatter2.locale = Locale(identifier: "en_US_POSIX")
        if let date = formatter2.date(from: dateString) {
            return date
        }

        // Formato 5: Apenas data (yyyy-MM-dd)
        let formatter3 = DateFormatter()
        formatter3.dateFormat = "yyyy-MM-dd"
        formatter3.locale = Locale(identifier: "en_US_POSIX")
        if let date = formatter3.date(from: dateString) {
            return date
        }

        return nil
    }
}
