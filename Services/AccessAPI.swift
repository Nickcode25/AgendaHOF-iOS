import Foundation

enum AccessHTTPError: Error {
    case unauthorized
}

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
                request.timeoutInterval = 6
                let requestId = UUID().uuidString
                request.setValue(requestId, forHTTPHeaderField: "X-Request-Id")
                request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")

                AppLogger.log("🌐 [AccessAPI] Fetching: \(url.absoluteString) (attempt \(attempt)/\(maxAttempts)) [ReqID: \(requestId)]", category: .network)
                let (data, response) = try await URLSession.shared.data(for: request)

                guard let http = response as? HTTPURLResponse else {
                    throw URLError(.badServerResponse)
                }

                if http.statusCode == 401 {
                    // ✅ Não use URLError(.userAuthenticationRequired) aqui.
                    // Deixe o SubscriptionManager decidir refresh/retry.
                    throw AccessHTTPError.unauthorized
                }

                guard (200...299).contains(http.statusCode) else {
                    throw URLError(.badServerResponse)
                }

                AppLogger.log("✅ [AccessAPI] Success: \(http.statusCode)", category: .network)
                let decoded = try JSONDecoder().decode(AccessResponse.self, from: data)
                
                // ✅ Log do resultado para debug de Paywall
                let logMsg = "📊 [AccessAPI] Result | hasAccess: \(decoded.hasAccess), plan: \(decoded.planType ?? "nil"), status: \(decoded.status ?? "nil"), source: \(decoded.source ?? "nil"), reason: \(decoded.reason ?? "nil")"
                AppLogger.log(logMsg, category: .network)
                
                return decoded

            } catch {
                lastError = error

                let shouldRetry: Bool
                if let urlError = error as? URLError {
                    shouldRetry = [
                        .timedOut,
                        .networkConnectionLost,
                        .notConnectedToInternet,
                        .cannotFindHost,
                        .cannotConnectToHost,
                        .dnsLookupFailed
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
        request.timeoutInterval = 10
        let requestId = UUID().uuidString
        request.setValue(requestId, forHTTPHeaderField: "X-Request-Id")
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

        AppLogger.log("🌐 [AccessAPI] Notifying Apple Purchase: \(url.absoluteString) [ReqID: \(requestId)]", category: .network)
        let (_, response) = try await URLSession.shared.data(for: request)

        guard let http = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }

        if http.statusCode == 401 {
            throw AccessHTTPError.unauthorized
        }

        guard (200...299).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }

        AppLogger.log("✅ [AccessAPI] Notification Success: \(http.statusCode)", category: .network)
    }
}
