import SwiftUI

struct InactivePatientsView: View {
    @StateObject private var viewModel = InactivePatientsViewModel()
    @EnvironmentObject var supabase: SupabaseManager
    @State private var selectedPatient: InactivePatient?

    var body: some View {
        VStack(spacing: 0) {
            // Barra de pesquisa sempre visível (se houver pacientes inativos carregados)
            if !viewModel.isLoading && viewModel.errorMessage == nil && !viewModel.inactivePatients.isEmpty {
                searchBar
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                    .padding(.bottom, 16)
                    .background(Color(.systemGroupedBackground))
            }

            // Conteúdo principal
            ZStack {
                if viewModel.isLoading {
                    ProgressView("Carregando pacientes...")
                } else if let error = viewModel.errorMessage {
                    ContentUnavailableView(
                        "Erro ao Carregar",
                        systemImage: "exclamationmark.triangle",
                        description: Text(error)
                    )
                } else if viewModel.inactivePatients.isEmpty {
                    // Não há pacientes inativos de verdade
                    emptyState
                } else if viewModel.filteredPatients.isEmpty {
                    // Busca não retornou resultados
                    searchEmptyState
                } else {
                    // Lista de pacientes (sem a barra de pesquisa)
                    patientsListContent
                }
            }
        }
        .navigationTitle("Reativação")
        .navigationBarTitleDisplayMode(.large)
        .task {
            await viewModel.loadInactivePatients()
        }
        .sheet(item: $selectedPatient) { patient in
            PatientDetailSheet(patient: patient)
                .environmentObject(supabase)
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        ContentUnavailableView(
            "Nenhum Paciente Inativo",
            systemImage: "checkmark.circle.fill",
            description: Text("Todos os seus pacientes estão ativos! 🎉")
        )
    }

    private var searchEmptyState: some View {
        ContentUnavailableView(
            "Nenhum Resultado",
            systemImage: "magnifyingglass",
            description: Text("Não encontramos pacientes inativos com esse nome.\nTente buscar outro nome ou limpe a busca.")
        )
    }

    // MARK: - Patients List Content

    private var patientsListContent: some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                ForEach(viewModel.filteredPatients) { patient in
                    InactivePatientCard(patient: patient) {
                        selectedPatient = patient
                    } onWhatsAppTap: {
                        viewModel.openWhatsApp(for: patient)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 20)
        }
        .background(Color(.systemGroupedBackground))
    }

    // MARK: - Search Bar

    private var searchBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundColor(.gray)
                .font(.system(size: 16))

            TextField("Buscar paciente", text: $viewModel.searchText)
                .textFieldStyle(.plain)
                .autocorrectionDisabled()
                .onChange(of: viewModel.searchText) { _, _ in
                    viewModel.filterPatients()
                }

            if !viewModel.searchText.isEmpty {
                Button {
                    viewModel.searchText = ""
                    viewModel.filterPatients()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.gray)
                        .font(.system(size: 16))
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Color(.systemGray6))
        .cornerRadius(10)
    }
}

// MARK: - Inactive Patient Card

struct InactivePatientCard: View {
    let patient: InactivePatient
    let onCardTap: () -> Void
    let onWhatsAppTap: () -> Void

    var body: some View {
        HStack(spacing: 14) {
            // Ícone do Paciente - Laranja claro com ícone person.badge.plus
            ZStack {
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color(hex: "ff6b00").opacity(0.12))
                    .frame(width: 56, height: 56)

                Image(systemName: "person.badge.plus")
                    .font(.system(size: 24, weight: .medium))
                    .foregroundColor(Color(hex: "ff6b00"))
            }

            // Informações do Paciente
            VStack(alignment: .leading, spacing: 4) {
                // Nome em negrito
                Text(patient.name)
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(.primary)

                // Último Procedimento - cinza
                Text("Último Procedimento - \(patient.lastProcedureDateFormatted)")
                    .font(.system(size: 13, weight: .regular))
                    .foregroundColor(.secondary)

                // Inativo há X dias - laranja/vermelho
                Text(patient.inactiveStatus)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(inactiveStatusColor)
            }

            Spacer()

            // Ações - WhatsApp e Ver Ficha
            HStack(spacing: 10) {
                // Botão WhatsApp - Verde
                Button(action: onWhatsAppTap) {
                    ZStack {
                        Circle()
                            .fill(Color.green)
                            .frame(width: 40, height: 40)

                        Image(systemName: "message.fill")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundColor(.white)
                    }
                }
                .buttonStyle(.plain)

                // Botão Ver Ficha - Azul
                Button(action: onCardTap) {
                    ZStack {
                        Circle()
                            .fill(Color.blue)
                            .frame(width: 40, height: 40)

                        Image(systemName: "person.text.rectangle.fill")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundColor(.white)
                    }
                }
                .buttonStyle(.plain)
            }
        }
        .padding(14)
        .background(Color.white)
        .cornerRadius(12)
        .shadow(color: Color.black.opacity(0.04), radius: 8, x: 0, y: 2)
    }

    /// Cor do status de inatividade (laranja -> vermelho conforme tempo)
    private var inactiveStatusColor: Color {
        let days = patient.daysSinceLastProcedure

        if days >= 365 {
            return .red // Mais de 1 ano
        } else if days >= 270 {
            return Color.orange.mix(with: .red, by: 0.5) // 9+ meses
        } else {
            return Color(hex: "ff6b00") // 6-9 meses
        }
    }
}

// MARK: - Patient Detail Sheet

struct PatientDetailSheet: View {
    let patient: InactivePatient
    @EnvironmentObject var supabase: SupabaseManager
    @Environment(\.dismiss) var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    // Avatar e Nome
                    VStack(spacing: 12) {
                        ZStack {
                            Circle()
                                .fill(Color(hex: "ff6b00").opacity(0.15))
                                .frame(width: 100, height: 100)

                            Text(patient.initials)
                                .font(.system(size: 36, weight: .bold))
                                .foregroundColor(Color(hex: "ff6b00"))
                        }

                        Text(patient.name)
                            .font(.title2)
                            .fontWeight(.bold)

                        Text(patient.inactiveStatus)
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 6)
                            .background(Color.red.opacity(0.1))
                            .cornerRadius(8)
                    }
                    .padding(.top, 20)

                    // Informações
                    VStack(alignment: .leading, spacing: 16) {
                        if let phone = patient.phone {
                            InfoRow(icon: "phone.fill", title: "Telefone", value: phone.formattedPhone)
                        }

                        InfoRow(
                            icon: "calendar",
                            title: "Último Procedimento",
                            value: patient.lastProcedureDateFormatted
                        )

                        InfoRow(
                            icon: "clock.fill",
                            title: "Tempo de Inatividade",
                            value: "\(patient.daysSinceLastProcedure) dias"
                        )
                    }
                    .padding(.horizontal, 20)

                    // Ações
                    VStack(spacing: 12) {
                        if patient.phone != nil {
                            Button {
                                openWhatsApp()
                            } label: {
                                Label("Enviar WhatsApp", systemImage: "message.fill")
                                    .frame(maxWidth: .infinity)
                                    .padding()
                                    .background(Color.green)
                                    .foregroundColor(.white)
                                    .cornerRadius(12)
                                    .fontWeight(.semibold)
                            }
                        }

                        Button {
                            dismiss()
                        } label: {
                            Text("Fechar")
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(Color(.systemGray6))
                                .foregroundColor(.primary)
                                .cornerRadius(12)
                                .fontWeight(.medium)
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 20)
                }
            }
            .navigationTitle("Detalhes do Paciente")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private func openWhatsApp() {
        guard let phone = patient.phone else { return }
        let cleanPhone = phone.filter { $0.isNumber }
        let whatsappURL = "https://wa.me/55\(cleanPhone)"

        if let url = URL(string: whatsappURL) {
            UIApplication.shared.open(url)
        }
    }
}

// MARK: - Info Row

struct InfoRow: View {
    let icon: String
    let title: String
    let value: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 18))
                .foregroundColor(Color(hex: "ff6b00"))
                .frame(width: 30)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.caption)
                    .foregroundColor(.secondary)

                Text(value)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundColor(.primary)
            }

            Spacer()
        }
        .padding(12)
        .background(Color(.systemGray6))
        .cornerRadius(10)
    }
}

// MARK: - Color Extension

extension Color {
    /// Mistura duas cores
    func mix(with color: Color, by percentage: Double) -> Color {
        let percentage = max(0, min(1, percentage))

        guard let components1 = self.cgColor?.components,
              let components2 = color.cgColor?.components else {
            return self
        }

        let r = components1[0] + (components2[0] - components1[0]) * percentage
        let g = components1[1] + (components2[1] - components1[1]) * percentage
        let b = components1[2] + (components2[2] - components1[2]) * percentage

        return Color(red: r, green: g, blue: b)
    }
}

// MARK: - Preview

#Preview {
    NavigationStack {
        InactivePatientsView()
            .environmentObject(SupabaseManager.shared)
    }
}
