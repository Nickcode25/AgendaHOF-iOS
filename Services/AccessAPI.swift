import Foundation

enum AccessAPI {
    static func fetchAccess(accessToken: String) async throws -> AccessResponse {
        guard let url = URL(string: "\(BackendConfig.baseURL)/api/access") else {
            throw URLError(.badURL)
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 12 // Timeout de 12s
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")

        AppLogger.log("🌐 [AccessAPI] Fetching: \(url.absoluteString)", category: .network)
        let (data, response) = try await URLSession.shared.data(for: request)

        guard let http = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }
        
        if http.statusCode == 401 {
            throw URLError(.userAuthenticationRequired)
        }
        
        guard (200...299).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }

        AppLogger.log("✅ [AccessAPI] Success: \(http.statusCode)", category: .network)
        return try JSONDecoder().decode(AccessResponse.self, from: data)
    }

    static func notifyApplePurchase(
        accessToken: String,
        planType: String,
        planName: String,
        expirationDate: String?,
        originalTransactionId: String,
        transactionId: String
    ) async throws {
        guard let url = URL(string: "\(BackendConfig.baseURL)/api/iap/apple/notify") else {
            throw URLError(.badURL)
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        var payload: [String: Any] = [
            "planType": planType,
            "planName": planName,
            "originalTransactionId": originalTransactionId,
            "transactionId": transactionId
        ]
        if let expirationDate, !expirationDate.isEmpty {
            payload["expirationDate"] = expirationDate
        }

        request.httpBody = try JSONSerialization.data(withJSONObject: payload)

        AppLogger.log("🌐 [AccessAPI] Notifying Apple Purchase: \(url.absoluteString)", category: .network)
        let (_, response) = try await URLSession.shared.data(for: request)
        
        guard let http = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }
        
        if http.statusCode == 401 {
            throw URLError(.userAuthenticationRequired)
        }
        
        guard (200...299).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
        AppLogger.log("✅ [AccessAPI] Notification Success: \(http.statusCode)", category: .network)
    }
}
