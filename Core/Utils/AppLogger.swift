import Foundation

enum LogCategory: String {
    case app = "📱 [App]"
    case network = "🌐 [Network]"
    case database = "🗄️ [Database]"
    case auth = "🔐 [Auth]"
    case notification = "🔔 [Notification]"
    case deepLink = "🔗 [DeepLink]"
    case business = "💼 [Business]"
    case widget = "🧩 [Widget]"
    case error = "❌ [ERROR]"
}

struct AppLogger {
    static func log(_ message: String, category: LogCategory = .app) {
        #if DEBUG
        print("\(category.rawValue) \(message)")
        #endif
    }
    
    static func error(_ message: String, error: Error? = nil) {
        if let error = error {
            print("\(LogCategory.error.rawValue) \(message): \(error.localizedDescription)")
        } else {
            print("\(LogCategory.error.rawValue) \(message)")
        }
    }
    
    static func warning(_ message: String) {
        #if DEBUG
        print("⚠️ [WARNING] \(message)")
        #endif
    }
}
