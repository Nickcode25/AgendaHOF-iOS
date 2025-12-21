import Foundation

enum Constants {
    // MARK: - Supabase Configuration
    static let supabaseURL = "https://zgdxszwjbbxepsvyjtrb.supabase.co"
    static let supabaseAnonKey = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InpnZHhzendqYmJ4ZXBzdnlqdHJiIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NTk0MTU4MTAsImV4cCI6MjA3NDk5MTgxMH0.NZdEYYCOZlMUo5h7TM-gsSTxmgMx7ta9W_gsi7ZNHCA"

    // MARK: - Keychain
    static let keychainService = "com.agendahof.swift"
    static let keychainAccountKey = "userAccount"

    // MARK: - UserDefaults Keys
    static let rememberMeKey = "rememberMe"
    static let savedEmailKey = "savedEmail"

    // MARK: - App Configuration
    static let appName = "Agenda HOF"
    static let appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"

    // MARK: - Date Formats
    static let dateFormat = "dd/MM/yyyy"
    static let timeFormat = "HH:mm"
    static let dateTimeFormat = "dd/MM/yyyy HH:mm"

    // MARK: - Database Tables
    enum Tables {
        static let userProfiles = "user_profiles"
        static let patients = "patients"
        static let appointments = "appointments"
        static let professionals = "professionals"
        static let recurringBlocks = "recurring_blocks"
        static let financialRecords = "financial_records"
    }

    // MARK: - UI Constants
    enum UI {
        static let cornerRadius: CGFloat = 12
        static let smallCornerRadius: CGFloat = 8
        static let largeCornerRadius: CGFloat = 16

        static let padding: CGFloat = 16
        static let smallPadding: CGFloat = 8
        static let largePadding: CGFloat = 24

        static let iconSize: CGFloat = 24
        static let largeIconSize: CGFloat = 32

        static let avatarSize: CGFloat = 40
        static let largeAvatarSize: CGFloat = 60
    }

    // MARK: - Notifications
    enum Notifications {
        static let dailySummaryTime = "08:00"
        static let weeklySummaryDay = 1 // Segunda-feira
        static let birthdayNotificationTime = "09:00"
    }
}
