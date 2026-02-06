import Foundation
import SwiftUI

// MARK: - App Constants

/// Constantes centralizadas do aplicativo Agenda HOF
/// Mantém valores compartilhados em um único local para fácil manutenção
enum Constants {

    // MARK: - App Info

    /// Versão atual do aplicativo
    static let appVersion = "1.0.0"

    /// Nome do aplicativo
    static let appName = "Agenda HOF"

    /// Bundle ID do aplicativo
    static let bundleId = "com.agendahof.app"

    // MARK: - Backend URLs

    /// URL base do backend (Railway)
    static let backendURL = "https://agenda-hof-production.up.railway.app"

    /// Endpoint para reset de senha
    static let resetPasswordEndpoint = "\(backendURL)/api/auth/reset-password"

    /// Endpoint para forgot password
    static let forgotPasswordEndpoint = "\(backendURL)/api/auth/request-password-reset"

    // MARK: - Deep Links

    /// Scheme para Universal Links
    static let universalLinkScheme = "agendahof"

    /// Host para Universal Links
    static let universalLinkHost = "app.agendahof.com"

    // MARK: - WhatsApp

    /// Código do país Brasil para WhatsApp
    static let whatsAppCountryCode = "55"

    /// URL base do WhatsApp
    static let whatsAppBaseURL = "https://wa.me"

    /// Gera URL do WhatsApp para um número brasileiro
    /// - Parameter phone: Número de telefone (apenas dígitos)
    /// - Returns: URL formatada para abertura no WhatsApp
    static func whatsAppURL(for phone: String) -> String {
        let cleanPhone = phone.filter { $0.isNumber }
        return "\(whatsAppBaseURL)/\(whatsAppCountryCode)\(cleanPhone)"
    }

    // MARK: - Supabase

    /// URL do Supabase
    static let supabaseURL = "https://zgdxszwjbbxepsvyjtrb.supabase.co"

    /// Anon Key do Supabase
    static let supabaseAnonKey = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InpnZHhzendqYmJ4ZXBzdnlqdHJiIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NTk0MTU4MTAsImV4cCI6MjA3NDk5MTgxMH0.NZdEYYCOZlMUo5h7TM-gsSTxmgMx7ta9W_gsi7ZNHCA"

    /// Nome do App Group para compartilhamento de dados com Widgets
    static let appGroupName = "group.com.agendahof.shared"

    /// Chave do UserDefaults para última sincronização
    static let lastSyncKey = "lastWidgetSync"

    // MARK: - Keychain

    /// Service name para armazenamento no Keychain
    static let keychainService = "com.agendahof.keychain"
    static let keychainAccountKey = "userAccount"

    // MARK: - User Defaults Keys

    /// Chave para lembrar usuário
    static let rememberMeKey = "rememberMe"

    /// Chave para email salvo
    static let savedEmailKey = "savedEmail"

    // MARK: - UI Constants

    /// Cor primária do app (laranja HOF)
    static let primaryColor = Color(hex: "ff6b00")

    /// Cor de fundo padrão dos cards
    static let cardBackgroundColor = Color.white

    /// Raio dos cantos arredondados dos cards
    static let cardCornerRadius: CGFloat = 12

    /// Sombra padrão dos cards
    static let cardShadowRadius: CGFloat = 8
    static let cardShadowOpacity: Double = 0.04

    /// Padding padrão horizontal
    static let horizontalPadding: CGFloat = 16

    /// Padding padrão vertical
    static let verticalPadding: CGFloat = 20

    /// Tamanho dos ícones em botões circulares
    static let circularButtonSize: CGFloat = 40

    /// Tamanho dos ícones quadrados
    static let squareIconSize: CGFloat = 56

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

    // MARK: - Notifications
    enum Notifications {
        static let dailySummaryTime = "08:00"
        static let weeklySummaryDay = 1 // Segunda-feira
        static let birthdayNotificationTime = "09:00"
    }

    // MARK: - Calendar Constants

    /// Altura da hora no calendário
    static let hourHeight: CGFloat = 60

    /// Horas exibidas no calendário (7h às 22h)
    static let calendarStartHour = 7
    static let calendarEndHour = 22

    /// Número de horas exibidas
    static let totalCalendarHours = calendarEndHour - calendarStartHour

    // MARK: - Business Rules

    /// Dias de inatividade para considerar paciente inativo (6 meses)
    static let inactiveDaysThreshold = 180

    /// Tempo mínimo entre reenvios de email (segundos)
    static let resendEmailCooldown: TimeInterval = 60

    /// Duração padrão de um agendamento (minutos)
    static let defaultAppointmentDuration = 60

    // MARK: - Validation Rules

    /// Tamanho mínimo de senha
    static let minPasswordLength = 8

    /// Tamanho máximo de senha
    static let maxPasswordLength = 128

    /// Tamanho de telefone brasileiro (com DDD)
    static let phoneMinDigits = 10
    static let phoneMaxDigits = 11

    /// Range de DDDs válidos no Brasil
    static let validDDDRange = 11...99

    // MARK: - Animation Durations

    /// Duração padrão de animações
    static let defaultAnimationDuration: Double = 0.3

    /// Duração de toast messages
    static let toastDuration: Double = 3.0

    // MARK: - Image Assets

    /// Nome do logo do app
    static let appLogo = "AppLogo"

    /// Placeholder de avatar
    static let avatarPlaceholder = "person.circle.fill"
}

// MARK: - Color Extension Helper

extension Color {
    /// Inicializa uma cor a partir de uma string hexadecimal
    /// - Parameter hex: String no formato "RRGGBB" ou "#RRGGBB"
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3: // RGB (12-bit)
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6: // RGB (24-bit)
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8: // ARGB (32-bit)
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (1, 1, 1, 0)
        }

        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue:  Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}
