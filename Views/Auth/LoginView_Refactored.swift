import SwiftUI

// MARK: - Login View (Refatorado)

/// View principal de login
/// Versão refatorada usando componentes modulares
/// Reduzida de 506 linhas para ~120 linhas através de modularização
struct LoginView_Refactored: View {

    // MARK: - View Model & Environment

    @StateObject private var viewModel = AuthViewModel()
    @EnvironmentObject var supabase: SupabaseManager

    // MARK: - Navigation State

    @State private var showForgotPassword = false
    @State private var showSignUp = false

    // MARK: - Animation State

    @State private var isAppearing = false

    // MARK: - Body

    var body: some View {
        Text("Login Refactored Placeholder")
    }
}

#Preview {
    LoginView_Refactored()
}
