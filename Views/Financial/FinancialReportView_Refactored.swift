import SwiftUI

// MARK: - Financial Report View (Refatorado)

/// View principal do relatório financeiro
/// Versão refatorada usando MVVM e componentes modulares
/// Reduzida de 1175 linhas para ~200 linhas através de modularização
struct FinancialReportView_Refactored: View {

    // MARK: - Environment & State

    @Environment(\.dismiss) var dismiss
    @StateObject private var viewModel = FinancialReportViewModel()
    @State private var isAppearing = false

    // MARK: - Body

    var body: some View {
        NavigationStack {
            ZStack {
                // Background
                Color(.systemGroupedBackground)
                    .ignoresSafeArea()

                // Conteúdo
                VStack(spacing: 0) {
                    headerSection
                    contentSection
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    closeButton
                }
            }
            .task {
                await viewModel.loadData()
            }
            .onChange(of: viewModel.selectedPeriod) {
                Task { await viewModel.loadData() }
            }
            .onAppear {
                withAnimation(.easeOut(duration: 0.5)) {
                    isAppearing = true
                }
            }
        }
    }

    // MARK: - Header Section

    private var headerSection: some View {
        VStack(spacing: 24) {
            // Título
            Text("Relatório Financeiro")
                .font(.system(size: 28, weight: .semibold))
                .foregroundStyle(.primary)

            // Seletor de período
            PeriodFilterView(selectedPeriod: $viewModel.selectedPeriod)
        }
        .padding(.horizontal, Constants.horizontalPadding)
        .padding(.vertical, Constants.verticalPadding)
        .background(Color(.systemBackground))
    }

    // MARK: - Content Section

    @ViewBuilder
    private var contentSection: some View {
        if viewModel.isLoading {
            loadingView
        } else if let error = viewModel.errorMessage {
            errorView(error)
        } else if let data = viewModel.reportData {
            dataView(data)
        } else {
            emptyView
        }
    }

    // MARK: - Data View

    private func dataView(_ viewModelData: FinancialReportViewModelData) -> some View {
        // Convert ViewModel data to View data format
        let data = FinancialReportData(
            proceduresRevenue: viewModelData.proceduresRevenue,
            salesRevenue: viewModelData.salesRevenue,
            subscriptionsRevenue: viewModelData.subscriptionsRevenue,
            coursesRevenue: viewModelData.coursesRevenue,
            otherRevenue: 0,
            totalRevenue: viewModelData.totalRevenue,
            totalExpenses: viewModelData.totalExpenses,
            netProfit: viewModelData.profit,
            expensesByCategory: []
        )
        
        return ScrollView {
            VStack(spacing: 20) {
                // Cards de resumo (Receita, Despesas, Lucro)
                FinancialSummaryCards(data: data)
                    .opacity(isAppearing ? 1 : 0)
                    .offset(y: isAppearing ? 0 : 20)
                    .animation(.easeOut(duration: 0.5).delay(0.1), value: isAppearing)

                // Detalhamento de Receitas
                RevenueBreakdownSection(data: data)
                    .opacity(isAppearing ? 1 : 0)
                    .offset(y: isAppearing ? 0 : 20)
                    .animation(.easeOut(duration: 0.5).delay(0.2), value: isAppearing)
            }
            .padding(Constants.horizontalPadding)
            .padding(.bottom, Constants.verticalPadding)
        }
    }

    // MARK: - Loading View

    private var loadingView: some View {
        VStack(spacing: 16) {
            ProgressView()
                .scaleEffect(1.2)

            Text("Carregando dados financeiros...")
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Error View

    private func errorView(_ error: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 50))
                .foregroundColor(.red)

            Text("Erro ao Carregar")
                .font(.title2)
                .fontWeight(.bold)

            Text(error)
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)

            Button {
                Task { await viewModel.loadData() }
            } label: {
                Text("Tentar Novamente")
                    .fontWeight(.semibold)
                    .foregroundColor(.white)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 12)
                    .background(Constants.primaryColor)
                    .cornerRadius(10)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Empty View

    private var emptyView: some View {
        VStack(spacing: 16) {
            Image(systemName: "chart.bar.doc.horizontal")
                .font(.system(size: 60))
                .foregroundColor(.secondary)

            Text("Nenhum Dado Disponível")
                .font(.title2)
                .fontWeight(.bold)

            Text("Não há dados financeiros para o período selecionado.")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Close Button

    private var closeButton: some View {
        Button {
            dismiss()
        } label: {
            Image(systemName: "xmark")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(width: 30, height: 30)
                .background(Color(.systemGray6))
                .clipShape(Circle())
        }
    }
}

// MARK: - Preview

#Preview {
    FinancialReportView_Refactored()
        .environmentObject(SupabaseManager.shared)
}
