import SwiftUI

// MARK: - Edit Profile View (Refatorado)

/// View para editar perfil do usuário
/// Versão refatorada usando String extensions para validação de telefone
/// Redução de código duplicado
struct EditProfileView_Refactored: View {

    // MARK: - Environment & Dependencies

    @Environment(\.dismiss) var dismiss
    @EnvironmentObject var supabase: SupabaseManager

    // MARK: - State

    @State private var fullName: String = ""
    @State private var phone: String = ""
    @State private var username: String = ""

    @State private var isLoading = false
    @State private var showError = false
    @State private var errorMessage = ""

    // MARK: - Computed Properties

    private var phoneValidationError: String? {
        phone.phoneValidationError
    }

    private var isFormValid: Bool {
        !fullName.trimmed.isEmpty && phoneValidationError == nil
    }

    // MARK: - Body

    var body: some View {
        NavigationStack {
            Form {
                // Informações Pessoais
                Section("Informações Pessoais") {
                    TextField("Nome completo", text: $fullName)
                        .textContentType(.name)
                        .autocapitalization(.words)

                    TextField("Nome de usuário", text: $username)
                        .textContentType(.username)
                        .autocapitalization(.none)
                        .autocorrectionDisabled()
                }

                // Telefone com validação
                Section {
                    TextField("Telefone", text: $phone)
                        .keyboardType(.phonePad)
                        .onChange(of: phone) { _, newValue in
                            phone = formatPhoneInput(newValue)
                        }
                } header: {
                    Text("Telefone")
                } footer: {
                    if let error = phoneValidationError {
                        Text(error)
                            .foregroundColor(.red)
                    } else {
                        Text("Formato: (XX) XXXXX-XXXX ou (XX) XXXX-XXXX")
                    }
                }
            }
            .navigationTitle("Editar Perfil")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancelar") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Salvar") {
                        Task { await save() }
                    }
                    .disabled(!isFormValid)
                    .fontWeight(.semibold)
                }
            }
            .loadingOverlay(isLoading: isLoading, text: "Salvando...")
            .alert("Erro", isPresented: $showError) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(errorMessage)
            }
            .onAppear {
                loadCurrentProfile()
            }
        }
    }

    // MARK: - Methods

    private func loadCurrentProfile() {
        if let profile = supabase.userProfile {
            fullName = profile.fullName ?? ""
            phone = profile.phone?.formattedPhone ?? ""
            username = profile.username ?? ""
        }
    }

    /// Formata telefone enquanto o usuário digita
    /// Aplica máscara: (XX) XXXXX-XXXX ou (XX) XXXX-XXXX
    private func formatPhoneInput(_ value: String) -> String {
        let numbers = value.onlyNumbers
        var result = ""

        for (index, char) in numbers.prefix(11).enumerated() {
            if index == 0 {
                result += "("
            }
            if index == 2 {
                result += ") "
            }
            // Para 11 dígitos: (XX) XXXXX-XXXX
            // Para 10 dígitos: (XX) XXXX-XXXX
            if numbers.count <= 10 && index == 6 {
                result += "-"
            } else if numbers.count == 11 && index == 7 {
                result += "-"
            }
            result += String(char)
        }

        return result
    }

    private func save() async {
        // Validar telefone antes de salvar (usando String extension)
        guard phoneValidationError == nil else {
            errorMessage = phoneValidationError ?? "Telefone inválido"
            showError = true
            return
        }

        isLoading = true

        do {
            let phoneNumbers = phone.onlyNumbers

            try await supabase.client
                .from("user_profiles")
                .update([
                    "full_name": fullName.trimmed,
                    "phone": phoneNumbers.isEmpty ? nil : phoneNumbers,
                    "username": username.trimmed.isEmpty ? nil : username.trimmed
                ] as [String: String?])
                .eq("id", value: supabase.currentUser?.id.uuidString ?? "")
                .execute()

            // Recarregar perfil
            await supabase.fetchUserProfile()

            dismiss()
        } catch {
            errorMessage = error.localizedDescription
            showError = true
        }

        isLoading = false
    }
}

// MARK: - Preview

#Preview {
    EditProfileView_Refactored()
        .environmentObject(SupabaseManager.shared)
}
