import SwiftUI

/// Header customizado para a Agenda seguindo Apple HIG
/// Dividido em 2 linhas: Navegação de Data + Controles
struct AgendaHeaderView: View {
    @ObservedObject var viewModel: AgendaViewModel
    let professionals: [Professional]
    let onDatePickerTap: () -> Void
    let onProfessionalPickerTap: () -> Void
    
    var body: some View {
        VStack(spacing: 0) {
            // Linha 1: Navegação de Data
            dateNavigationRow
            
            // Separador sutil
            Divider()
                .opacity(0.5)
            
            // Linha 2: Filtros e Modo de Visualização
            controlsRow
        }
        .background(.ultraThinMaterial)
    }
    
    // MARK: - Linha 1: Navegação de Data
    
    private var dateNavigationRow: some View {
        HStack(spacing: 0) {
            Spacer()
            
            // Grupo de navegação centralizado
            HStack(spacing: 8) {
                // Botão Anterior
                Button {
                    if viewModel.viewMode == .day {
                        viewModel.goToPreviousDay()
                    } else {
                        viewModel.goToPreviousWeek()
                    }
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.primary)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                
                // Data Central (tappable)
                Button(action: onDatePickerTap) {
                    Text(formattedDate)
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundColor(.primary)
                        .frame(minWidth: 120)
                }
                .buttonStyle(.plain)
                
                // Botão Próximo
                Button {
                    if viewModel.viewMode == .day {
                        viewModel.goToNextDay()
                    } else {
                        viewModel.goToNextWeek()
                    }
                } label: {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.primary)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            
            Spacer()
        }
        .frame(height: 48)
    }
    
    // MARK: - Linha 2: Controles
    
    private var controlsRow: some View {
        HStack(spacing: 12) {
            // Filtro de Profissional
            professionalFilterButton
            
            Spacer()
            
            // Botão "Hoje" (quando não é hoje)
            if !Calendar.current.isDateInToday(viewModel.selectedDate) {
                Button {
                    viewModel.goToToday()
                } label: {
                    Text("Hoje")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.appPrimary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(Color.appPrimary.opacity(0.12))
                        .cornerRadius(8)
                }
                .buttonStyle(.plain)
            }
            
            // Segmented Control - Dia/Semana
            Picker("", selection: $viewModel.viewMode) {
                Text("Dia").tag(AgendaViewModel.ViewMode.day)
                Text("Semana").tag(AgendaViewModel.ViewMode.week)
            }
            .pickerStyle(.segmented)
            .frame(width: 120)
            .onChange(of: viewModel.viewMode) { _, _ in
                Task { await viewModel.loadData() }
            }
        }
        .padding(.horizontal, 16)
        .frame(height: 52)
    }
    
    // MARK: - Subviews
    
    private var professionalFilterButton: some View {
        Button(action: onProfessionalPickerTap) {
            HStack(spacing: 6) {
                Image(systemName: viewModel.selectedProfessional != nil 
                    ? "person.crop.circle.fill" 
                    : "person.crop.circle")
                    .font(.system(size: 18))
                    .foregroundColor(viewModel.selectedProfessional != nil ? .appPrimary : .secondary)
                
                if let professional = viewModel.selectedProfessional {
                    Text(professionalDisplayName(professional))
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.appPrimary)
                        .lineLimit(1)
                    
                    // Botão para remover filtro
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 14))
                        .foregroundColor(.appPrimary.opacity(0.6))
                } else {
                    Text("Todos")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.secondary)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(viewModel.selectedProfessional != nil 
                        ? Color.appPrimary.opacity(0.12)
                        : Color(.systemGray6))
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
    
    // MARK: - Helpers
    
    private var formattedDate: String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "pt_BR")
        
        if viewModel.viewMode == .day {
            if Calendar.current.isDateInToday(viewModel.selectedDate) {
                return "Hoje"
            } else if Calendar.current.isDateInTomorrow(viewModel.selectedDate) {
                return "Amanhã"
            } else if Calendar.current.isDateInYesterday(viewModel.selectedDate) {
                return "Ontem"
            }
            formatter.dateFormat = "d 'de' MMMM"
        } else {
            // Semana: mostrar intervalo
            var calendar = Calendar.current
            calendar.firstWeekday = 2 // Segunda-feira
            let startOfWeek = calendar.dateInterval(of: .weekOfYear, for: viewModel.selectedDate)?.start ?? viewModel.selectedDate
            let endOfWeek = calendar.date(byAdding: .day, value: 6, to: startOfWeek) ?? viewModel.selectedDate
            
            let dayFormatter = DateFormatter()
            dayFormatter.locale = Locale(identifier: "pt_BR")
            dayFormatter.dateFormat = "d"
            
            let monthFormatter = DateFormatter()
            monthFormatter.locale = Locale(identifier: "pt_BR")
            monthFormatter.dateFormat = "MMM"
            
            let startDay = dayFormatter.string(from: startOfWeek)
            let endDay = dayFormatter.string(from: endOfWeek)
            let month = monthFormatter.string(from: endOfWeek)
            
            return "\(startDay) - \(endDay) \(month)"
        }
        
        return formatter.string(from: viewModel.selectedDate)
    }
    
    private func professionalDisplayName(_ professional: Professional) -> String {
        // Retorna primeiro nome ou nome curto
        let components = professional.name.components(separatedBy: " ")
        if components.count > 1 {
            // Se começa com Dr./Dra., pegar título + primeiro nome
            if let first = components.first, 
               (first.lowercased().hasPrefix("dr") || first.lowercased().hasPrefix("prof")) {
                return components.prefix(2).joined(separator: " ")
            }
            return components.first ?? professional.name
        }
        return professional.name
    }
}

#Preview {
    VStack {
        AgendaHeaderView(
            viewModel: AgendaViewModel(),
            professionals: [],
            onDatePickerTap: {},
            onProfessionalPickerTap: {}
        )
        Spacer()
    }
    .background(Color(.systemGroupedBackground))
}
