import Foundation

enum AccessAPI {
    static func fetchAccess(accessToken: String) async throws -> AccessResponse {
        guard let url = URL(string: "\(BackendConfig.baseURL)/api/access") else {
            throw URLError(.badURL)
        }
        
        var lastError: Error?
        let maxAttempts = 2
        
        for attempt in 1...maxAttempts {
            do {
                var request = URLRequest(url: url)
                request.httpMethod = "GET"
                request.timeoutInterval = 6 // Fail fast para usar fallback local sem travar UI
                request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")

                AppLogger.log("🌐 [AccessAPI] Fetching: \(url.absoluteString) (attempt \(attempt)/\(maxAttempts))", category: .network)
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
            } catch {
                lastError = error
                
                let shouldRetry: Bool
                if let urlError = error as? URLError {
                    shouldRetry = [
                        .timedOut,
                        .networkConnectionLost,
                        .notConnectedToInternet,
                        .cannotFindHost,
                        .cannotConnectToHost
                    ].contains(urlError.code)
                } else {
                    shouldRetry = false
                }
                
                if shouldRetry && attempt < maxAttempts {
                    AppLogger.warning("[AccessAPI] Falha transitória (\(error.localizedDescription)). Tentando novamente...")
                    try? await Task.sleep(nanoseconds: 600_000_000)
                    continue
                }
                
                throw error
            }
        }
        
        throw lastError ?? URLError(.unknown)
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
