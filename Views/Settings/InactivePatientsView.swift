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
                    InactivePatientCard(patient: patient)
                        .onTapGesture {
                            selectedPatient = patient
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

            // Indicador visual (chevron)
            Image(systemName: "chevron.right")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.quaternary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color(.secondarySystemGroupedBackground))
        )
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
            List {
                // Header com avatar e nome
                Section {
                    HStack(spacing: 16) {
                        // Avatar
                        ZStack {
                            Circle()
                                .fill(Color(hex: "ff6b00").opacity(0.15))
                                .frame(width: 70, height: 70)

                            Text(patient.initials)
                                .font(.system(size: 28, weight: .bold))
                                .foregroundColor(Color(hex: "ff6b00"))
                        }

                        VStack(alignment: .leading, spacing: 4) {
                            Text(patient.name)
                                .font(.title2)
                                .fontWeight(.bold)

                            Text(patient.inactiveStatus)
                                .font(.subheadline)
                                .foregroundColor(inactiveStatusColor)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 4)
                                .background(inactiveStatusColor.opacity(0.1))
                                .cornerRadius(6)
                        }
                    }
                    .padding(.vertical, 8)
                }

                // Contato
                Section("Contato") {
                    if let phone = patient.phone, !phone.isEmpty {
                        // Link para ligar
                        Link(destination: URL(string: "tel:\(phone.filter { $0.isNumber })")!) {
                            Label(phone.formattedPhone, systemImage: "phone.fill")
                        }

                        // Link para WhatsApp
                        Link(destination: URL(string: "https://wa.me/55\(phone.filter { $0.isNumber })")!) {
                            HStack {
                                Image("whatsapp")
                                    .resizable()
                                    .scaledToFit()
                                    .frame(width: 20, height: 20)
                                Text("WhatsApp")
                            }
                            .foregroundColor(.green)
                        }
                    } else {
                        Text("Nenhum telefone cadastrado")
                            .foregroundColor(.secondary)
                            .font(.subheadline)
                    }
                }

                // Último Procedimento
                Section("Último Procedimento") {
                    Text(patient.lastProcedureDateFormatted)
                        .font(.subheadline)
                }
            }
            .navigationTitle("Detalhes do Paciente")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Fechar") {
                        dismiss()
                    }
                }
            }
        }
    }

    private var inactiveStatusColor: Color {
        let days = patient.daysSinceLastProcedure

        if days >= 365 {
            return .red
        } else if days >= 270 {
            return Color.orange.mix(with: .red, by: 0.5)
        } else {
            return Color(hex: "ff6b00")
        }
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
