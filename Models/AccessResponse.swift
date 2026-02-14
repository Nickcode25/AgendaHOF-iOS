import Foundation

struct AccessResponse: Codable {
    let hasAccess: Bool
    let planType: String?
    let planName: String?
    let expiresAt: String?
    let status: String?
    let source: String?
    let role: String?
    let ownerId: String?
    let clinicId: String?
    let permissions: [String]?
}

extension AccessResponse {
    var expiresAtDate: Date? {
        guard let expiresAt else { return nil }
        // Se a data já vier com milissegundos ou formato diferente, o ISO8601DateFormatter padrão pode falhar.
        // O Railway geralmente manda ISO8601 padrão. 
        // Vamos garantir fallback seguro.
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: expiresAt) { return date }
        
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: expiresAt)
    }
}
