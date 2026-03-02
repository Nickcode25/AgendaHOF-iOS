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

    // Grace period fields (present only when status == "past_due")
    let reason: String?
    let dueAt: String?
    let graceUntil: String?
    let graceDays: Int?
}

extension AccessResponse {
    var expiresAtDate: Date? {
        guard let expiresAt else { return nil }
        let formatter = ISO8601DateFormatter()
        // graceUntil comes as "2026-03-04T23:59:59-03:00" — withInternetDateTime handles this
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: expiresAt) { return date }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: expiresAt)
    }

    /// True when the user is in grace period (paid late, still allowed temporarily)
    var isInGracePeriod: Bool {
        source == "grace" && reason == "past_due"
    }
}
