import Foundation
import Supabase
@testable import AgendaHOF

// MARK: - Mock Supabase Manager

/// Mock do SupabaseManager para testes unitários
/// Simula autenticação, perfil de usuário e operações do Supabase
class MockSupabaseManager: ObservableObject {

    // MARK: - Published Properties

    @Published var currentUser: User?
    @Published var userProfile: UserProfile?
    @Published var isAuthenticated = false

    // MARK: - Test Control Properties

    var shouldFailAuth = false
    var shouldFailProfileFetch = false
    var authError: Error?
    var profileFetchError: Error?

    // MARK: - Mock Data

    var mockUser: User?
    var mockProfile: UserProfile?

    // MARK: - Initialization

    init(authenticated: Bool = false) {
        self.isAuthenticated = authenticated
        if authenticated {
            setupMockAuthenticatedUser()
        }
    }

    // MARK: - Setup Methods

    func setupMockAuthenticatedUser() {
        let userId = UUID()

        mockUser = User(
            id: userId,
            email: "test@example.com",
            emailConfirmedAt: Date(),
            createdAt: Date()
        )

        mockProfile = UserProfile(
            id: userId,
            fullName: "Test User",
            role: .owner,
            phone: "11999999999",
            username: "testuser",
            profilePhoto: nil,
            createdAt: Date(),
            updatedAt: Date()
        )

        currentUser = mockUser
        userProfile = mockProfile
        isAuthenticated = true
    }

    // MARK: - Auth Methods

    func signIn(email: String, password: String) async throws {
        if shouldFailAuth {
            throw authError ?? NSError(domain: "MockAuth", code: 401, userInfo: [NSLocalizedDescriptionKey: "Invalid credentials"])
        }

        setupMockAuthenticatedUser()
    }

    func signUp(email: String, password: String, fullName: String) async throws {
        if shouldFailAuth {
            throw authError ?? NSError(domain: "MockAuth", code: 400, userInfo: [NSLocalizedDescriptionKey: "Sign up failed"])
        }

        setupMockAuthenticatedUser()
        userProfile?.fullName = fullName
    }

    func signOut() async throws {
        currentUser = nil
        userProfile = nil
        isAuthenticated = false
    }

    func resetPassword(email: String) async throws {
        if shouldFailAuth {
            throw authError ?? NSError(domain: "MockAuth", code: 400, userInfo: [NSLocalizedDescriptionKey: "Reset failed"])
        }
    }

    // MARK: - Profile Methods

    func fetchUserProfile() async {
        if shouldFailProfileFetch {
            userProfile = nil
            return
        }

        if currentUser != nil && mockProfile != nil {
            userProfile = mockProfile
        }
    }

    func updateUserProfile(fullName: String?, phone: String?, username: String?) async throws {
        guard var profile = userProfile else {
            throw NSError(domain: "MockProfile", code: 404, userInfo: [NSLocalizedDescriptionKey: "No profile found"])
        }

        if let fullName = fullName {
            profile.fullName = fullName
        }
        if let phone = phone {
            profile.phone = phone
        }
        if let username = username {
            profile.username = username
        }

        userProfile = profile
        mockProfile = profile
    }

    // MARK: - Helper Properties

    var isOwner: Bool {
        userProfile?.role == .owner
    }

    var isProfessional: Bool {
        userProfile?.role == .professional
    }
}
