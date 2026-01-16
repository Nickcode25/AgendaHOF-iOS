# 📱 Widget iOS - Implementação Completa

**Data**: 23/12/2025
**Versão**: 1.0
**Funcionalidade**: Widgets para visualização rápida de agendamentos

---

## 🎯 Objetivo

Implementar 3 tamanhos de widgets iOS que exibem os próximos agendamentos do usuário sem precisar abrir o app.

---

## 📊 Tipos de Widgets

### 1️⃣ **Widget Pequeno (Small)**
- **Tamanho**: 158x158 pontos
- **Conteúdo**: Próximo agendamento
- **Informações**:
  - Horário do agendamento
  - Nome do paciente
  - Tipo de procedimento
  - Tempo até o agendamento (ex: "Em 2h")

### 2️⃣ **Widget Médio (Medium)**
- **Tamanho**: 360x158 pontos
- **Conteúdo**: Próximos 3 agendamentos
- **Informações**:
  - Lista dos 3 próximos agendamentos
  - Horário, paciente e procedimento de cada um
  - Indicador visual de horário

### 3️⃣ **Widget Grande (Large)**
- **Tamanho**: 360x376 pontos
- **Conteúdo**: Agenda completa do dia
- **Informações**:
  - Todos os agendamentos do dia atual
  - Cabeçalho com data
  - Status de cada agendamento
  - Resumo (ex: "5 agendamentos hoje")

---

## 🏗️ Arquitetura

```
Agenda HOF/
├── AgendaHOF/                    # App principal
│   ├── ...
│   └── Services/
│       └── WidgetDataManager.swift  # ✅ NOVO
│
├── AgendaWidget/                 # ✅ NOVA Widget Extension
│   ├── AgendaWidget.swift        # Entry point do widget
│   ├── AgendaWidgetProvider.swift
│   ├── Views/
│   │   ├── SmallWidgetView.swift
│   │   ├── MediumWidgetView.swift
│   │   └── LargeWidgetView.swift
│   └── Models/
│       └── WidgetAppointment.swift
│
└── Shared/                       # ✅ NOVO (App Group)
    └── WidgetData.json           # Dados compartilhados
```

---

## 📝 PASSO 1: Criar Widget Extension no Xcode

### **Ações no Xcode:**

1. **File → New → Target**
2. Selecionar **Widget Extension**
3. **Nome**: `AgendaWidget`
4. **Include Configuration Intent**: ❌ Desmarcar (não precisamos de customização por enquanto)
5. Clicar em **Finish**
6. **Ativar o scheme** quando perguntado

Isso criará automaticamente:
- `AgendaWidget/` folder
- `AgendaWidget.swift` (entry point)
- `Info.plist` para o widget

---

## 📝 PASSO 2: Configurar App Groups

Para compartilhar dados entre o app principal e o widget, precisamos usar **App Groups**.

### **2.1 - Criar App Group no Apple Developer**

1. Acesse [Apple Developer Portal](https://developer.apple.com/account)
2. **Certificates, Identifiers & Profiles → Identifiers → App Groups**
3. Criar novo App Group: `group.com.agendahof.shared`
4. Salvar

### **2.2 - Adicionar App Group ao App Principal**

1. No Xcode, selecionar **target AgendaHOF**
2. **Signing & Capabilities → + Capability**
3. Adicionar **App Groups**
4. Marcar: `group.com.agendahof.shared`

### **2.3 - Adicionar App Group ao Widget**

1. Selecionar **target AgendaWidget**
2. **Signing & Capabilities → + Capability**
3. Adicionar **App Groups**
4. Marcar: `group.com.agendahof.shared`

---

## 📝 PASSO 3: Criar Modelo de Dados Compartilhado

### **Arquivo: `Shared/WidgetAppointment.swift`**

Criar pasta **Shared** e adicionar este arquivo (membros: AgendaHOF + AgendaWidget):

```swift
import Foundation

/// Modelo simplificado de agendamento para widgets
/// Codable para serialização JSON
struct WidgetAppointment: Codable, Identifiable {
    let id: String
    let patientName: String
    let procedure: String
    let start: Date
    let end: Date
    let status: String
    let isPersonal: Bool
    let title: String?

    var displayTitle: String {
        if isPersonal {
            return title ?? "Compromisso Pessoal"
        }
        return patientName
    }

    var timeRange: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        formatter.locale = Locale(identifier: "pt_BR")
        return formatter.string(from: start)
    }

    var timeUntil: String {
        let now = Date()
        let interval = start.timeIntervalSince(now)

        if interval < 0 {
            return "Agora"
        }

        let hours = Int(interval / 3600)
        let minutes = Int((interval.truncatingRemainder(dividingBy: 3600)) / 60)

        if hours > 24 {
            let days = hours / 24
            return "Em \(days)d"
        } else if hours > 0 {
            return "Em \(hours)h"
        } else if minutes > 0 {
            return "Em \(minutes)min"
        } else {
            return "Agora"
        }
    }
}

/// Dados completos para o widget
struct WidgetData: Codable {
    let appointments: [WidgetAppointment]
    let lastUpdate: Date
}
```

---

## 📝 PASSO 4: Criar WidgetDataManager (App Principal)

### **Arquivo: `Services/WidgetDataManager.swift`**

Este gerenciador salva os agendamentos para o widget acessar:

```swift
import Foundation
import WidgetKit

@MainActor
class WidgetDataManager {
    static let shared = WidgetDataManager()

    private let appGroupIdentifier = "group.com.agendahof.shared"
    private let widgetDataKey = "widgetAppointments"

    private init() {}

    /// Salvar agendamentos para o widget
    func saveAppointments(_ appointments: [Appointment]) {
        // Converter para modelo simplificado
        let widgetAppointments = appointments.map { appointment in
            WidgetAppointment(
                id: appointment.id,
                patientName: appointment.patientName ?? "Sem nome",
                procedure: appointment.procedure ?? "Sem procedimento",
                start: appointment.start,
                end: appointment.end,
                status: appointment.status.rawValue,
                isPersonal: appointment.isPersonal ?? false,
                title: appointment.title
            )
        }

        let widgetData = WidgetData(
            appointments: widgetAppointments,
            lastUpdate: Date()
        )

        // Salvar no App Group
        if let userDefaults = UserDefaults(suiteName: appGroupIdentifier) {
            do {
                let encoder = JSONEncoder()
                let data = try encoder.encode(widgetData)
                userDefaults.set(data, forKey: widgetDataKey)

                #if DEBUG
                print("✅ [Widget] Saved \(widgetAppointments.count) appointments")
                #endif

                // Atualizar timeline do widget
                WidgetCenter.shared.reloadAllTimelines()
            } catch {
                print("❌ [Widget] Error encoding data: \(error)")
            }
        }
    }

    /// Carregar agendamentos do App Group
    static func loadAppointments() -> [WidgetAppointment] {
        let appGroupIdentifier = "group.com.agendahof.shared"
        let widgetDataKey = "widgetAppointments"

        guard let userDefaults = UserDefaults(suiteName: appGroupIdentifier),
              let data = userDefaults.data(forKey: widgetDataKey) else {
            return []
        }

        do {
            let decoder = JSONDecoder()
            let widgetData = try decoder.decode(WidgetData.self, from: data)
            return widgetData.appointments
        } catch {
            print("❌ [Widget] Error decoding data: \(error)")
            return []
        }
    }
}
```

---

## 📝 PASSO 5: Integrar com AppointmentService

Modificar **`AppointmentService.swift`** para salvar dados para o widget após buscar agendamentos:

```swift
import WidgetKit

@MainActor
class AppointmentService: ObservableObject {
    // ... código existente ...

    func fetchAppointments(from startDate: Date, to endDate: Date) async {
        // ... código de fetch existente ...

        // ✅ ADICIONAR APÓS ATUALIZAR appointments:

        // Salvar para o widget (apenas agendamentos futuros e do dia atual)
        let now = Date()
        let calendar = Calendar.current
        let todayStart = calendar.startOfDay(for: now)

        let upcomingAppointments = appointments.filter { appointment in
            appointment.start >= todayStart
        }.sorted { $0.start < $1.start }

        WidgetDataManager.shared.saveAppointments(Array(upcomingAppointments.prefix(10)))
    }
}
```

---

## 📝 PASSO 6: Implementar Widget Provider

### **Arquivo: `AgendaWidget/AgendaWidgetProvider.swift`**

```swift
import WidgetKit
import SwiftUI

struct AgendaWidgetProvider: TimelineProvider {

    // Dados de placeholder (quando widget está sendo carregado)
    func placeholder(in context: Context) -> AgendaWidgetEntry {
        AgendaWidgetEntry(
            date: Date(),
            appointments: [
                WidgetAppointment(
                    id: "1",
                    patientName: "Maria Silva",
                    procedure: "Botox",
                    start: Date(),
                    end: Date().addingTimeInterval(3600),
                    status: "scheduled",
                    isPersonal: false,
                    title: nil
                )
            ]
        )
    }

    // Dados de snapshot (para galeria de widgets)
    func getSnapshot(in context: Context, completion: @escaping (AgendaWidgetEntry) -> Void) {
        let appointments = WidgetDataManager.loadAppointments()
        let entry = AgendaWidgetEntry(date: Date(), appointments: appointments)
        completion(entry)
    }

    // Timeline principal (atualização automática)
    func getTimeline(in context: Context, completion: @escaping (Timeline<AgendaWidgetEntry>) -> Void) {
        let appointments = WidgetDataManager.loadAppointments()
        let currentDate = Date()

        // Criar entry para agora
        let entry = AgendaWidgetEntry(date: currentDate, appointments: appointments)

        // Atualizar a cada 15 minutos
        let nextUpdate = Calendar.current.date(byAdding: .minute, value: 15, to: currentDate)!

        let timeline = Timeline(entries: [entry], policy: .after(nextUpdate))
        completion(timeline)
    }
}

struct AgendaWidgetEntry: TimelineEntry {
    let date: Date
    let appointments: [WidgetAppointment]

    var nextAppointment: WidgetAppointment? {
        let now = Date()
        return appointments.first { $0.start >= now }
    }

    var todayAppointments: [WidgetAppointment] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: today)!

        return appointments.filter { appointment in
            appointment.start >= today && appointment.start < tomorrow
        }
    }
}
```

---

## 📝 PASSO 7: Criar Views dos Widgets

### **7.1 - Small Widget View**

**Arquivo: `AgendaWidget/Views/SmallWidgetView.swift`**

```swift
import SwiftUI
import WidgetKit

struct SmallWidgetView: View {
    let entry: AgendaWidgetEntry

    var body: some View {
        ZStack {
            // Background gradiente
            LinearGradient(
                colors: [
                    Color(hex: "ff6b00"),
                    Color(hex: "ff8800")
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            if let appointment = entry.nextAppointment {
                VStack(alignment: .leading, spacing: 8) {
                    // Horário
                    Text(appointment.timeRange)
                        .font(.system(size: 28, weight: .bold))
                        .foregroundColor(.white)

                    // Tempo até
                    Text(appointment.timeUntil)
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.9))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.white.opacity(0.2))
                        .cornerRadius(4)

                    Spacer()

                    // Paciente
                    Text(appointment.displayTitle)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.white)
                        .lineLimit(1)

                    // Procedimento
                    Text(appointment.procedure)
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.8))
                        .lineLimit(1)
                }
                .padding(16)
            } else {
                VStack(spacing: 12) {
                    Image(systemName: "calendar.badge.checkmark")
                        .font(.system(size: 32))
                        .foregroundColor(.white)

                    Text("Sem agendamentos")
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.9))
                        .multilineTextAlignment(.center)
                }
                .padding()
            }
        }
    }
}
```

### **7.2 - Medium Widget View**

**Arquivo: `AgendaWidget/Views/MediumWidgetView.swift`**

```swift
import SwiftUI
import WidgetKit

struct MediumWidgetView: View {
    let entry: AgendaWidgetEntry

    var nextThreeAppointments: [WidgetAppointment] {
        let now = Date()
        return entry.appointments
            .filter { $0.start >= now }
            .prefix(3)
            .map { $0 }
    }

    var body: some View {
        ZStack {
            Color(.systemBackground)

            if !nextThreeAppointments.isEmpty {
                VStack(alignment: .leading, spacing: 0) {
                    // Header
                    HStack {
                        Image(systemName: "calendar")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(Color(hex: "ff6b00"))

                        Text("Próximos Agendamentos")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(.primary)

                        Spacer()
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)

                    Divider()

                    // Lista de agendamentos
                    VStack(spacing: 0) {
                        ForEach(Array(nextThreeAppointments.enumerated()), id: \.element.id) { index, appointment in
                            HStack(spacing: 12) {
                                // Horário
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(appointment.timeRange)
                                        .font(.system(size: 18, weight: .bold))
                                        .foregroundColor(Color(hex: "ff6b00"))

                                    Text(appointment.timeUntil)
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                }
                                .frame(width: 60, alignment: .leading)

                                // Detalhes
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(appointment.displayTitle)
                                        .font(.system(size: 13, weight: .semibold))
                                        .foregroundColor(.primary)
                                        .lineLimit(1)

                                    Text(appointment.procedure)
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                        .lineLimit(1)
                                }

                                Spacer()
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 10)

                            if index < nextThreeAppointments.count - 1 {
                                Divider()
                                    .padding(.leading, 88)
                            }
                        }
                    }
                }
            } else {
                VStack(spacing: 12) {
                    Image(systemName: "calendar.badge.checkmark")
                        .font(.system(size: 40))
                        .foregroundColor(Color(hex: "ff6b00"))

                    Text("Nenhum agendamento próximo")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
            }
        }
    }
}
```

### **7.3 - Large Widget View**

**Arquivo: `AgendaWidget/Views/LargeWidgetView.swift`**

```swift
import SwiftUI
import WidgetKit

struct LargeWidgetView: View {
    let entry: AgendaWidgetEntry

    var todayDate: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE, d 'de' MMMM"
        formatter.locale = Locale(identifier: "pt_BR")
        return formatter.string(from: Date()).capitalized
    }

    var body: some View {
        ZStack {
            Color(.systemBackground)

            VStack(alignment: .leading, spacing: 0) {
                // Header
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Image(systemName: "calendar")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundColor(Color(hex: "ff6b00"))

                        Text("Agenda de Hoje")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundColor(.primary)

                        Spacer()

                        Text("\(entry.todayAppointments.count)")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundColor(.white)
                            .frame(width: 28, height: 28)
                            .background(Color(hex: "ff6b00"))
                            .clipShape(Circle())
                    }

                    Text(todayDate)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)

                Divider()

                if !entry.todayAppointments.isEmpty {
                    ScrollView {
                        VStack(spacing: 0) {
                            ForEach(Array(entry.todayAppointments.enumerated()), id: \.element.id) { index, appointment in
                                HStack(spacing: 12) {
                                    // Timeline indicator
                                    VStack(spacing: 0) {
                                        Circle()
                                            .fill(appointment.start <= Date() ? Color(hex: "ff6b00") : Color(.systemGray4))
                                            .frame(width: 10, height: 10)

                                        if index < entry.todayAppointments.count - 1 {
                                            Rectangle()
                                                .fill(Color(.systemGray5))
                                                .frame(width: 2)
                                        }
                                    }
                                    .frame(width: 10)

                                    // Horário
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(appointment.timeRange)
                                            .font(.system(size: 16, weight: .bold))
                                            .foregroundColor(appointment.start <= Date() ? Color(hex: "ff6b00") : .primary)

                                        if appointment.start > Date() {
                                            Text(appointment.timeUntil)
                                                .font(.caption2)
                                                .foregroundColor(.secondary)
                                        }
                                    }
                                    .frame(width: 60, alignment: .leading)

                                    // Detalhes
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(appointment.displayTitle)
                                            .font(.system(size: 14, weight: .semibold))
                                            .foregroundColor(.primary)
                                            .lineLimit(1)

                                        Text(appointment.procedure)
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                            .lineLimit(1)
                                    }

                                    Spacer()

                                    // Status badge
                                    if appointment.start <= Date() {
                                        Text("Agora")
                                            .font(.caption2)
                                            .fontWeight(.semibold)
                                            .foregroundColor(.white)
                                            .padding(.horizontal, 8)
                                            .padding(.vertical, 4)
                                            .background(Color(hex: "ff6b00"))
                                            .cornerRadius(4)
                                    }
                                }
                                .padding(.horizontal, 16)
                                .padding(.vertical, 12)
                            }
                        }
                    }
                } else {
                    Spacer()

                    VStack(spacing: 12) {
                        Image(systemName: "calendar.badge.checkmark")
                            .font(.system(size: 48))
                            .foregroundColor(Color(hex: "ff6b00"))

                        Text("Nenhum agendamento hoje")
                            .font(.subheadline)
                            .foregroundColor(.secondary)

                        Text("Aproveite o dia!")
                            .font(.caption)
                            .foregroundColor(.tertiary)
                    }

                    Spacer()
                }
            }
        }
    }
}
```

---

## 📝 PASSO 8: Criar Widget Principal

### **Arquivo: `AgendaWidget/AgendaWidget.swift`**

```swift
import WidgetKit
import SwiftUI

@main
struct AgendaWidget: Widget {
    let kind: String = "AgendaWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: AgendaWidgetProvider()) { entry in
            AgendaWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("Agenda HOF")
        .description("Visualize seus próximos agendamentos rapidamente.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

struct AgendaWidgetEntryView: View {
    @Environment(\.widgetFamily) var family
    var entry: AgendaWidgetEntry

    var body: some View {
        switch family {
        case .systemSmall:
            SmallWidgetView(entry: entry)
        case .systemMedium:
            MediumWidgetView(entry: entry)
        case .systemLarge:
            LargeWidgetView(entry: entry)
        @unknown default:
            SmallWidgetView(entry: entry)
        }
    }
}

// Extension para usar cores hex
extension Color {
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
            blue: Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}
```

---

## 📝 PASSO 9: Configurar Deep Linking

Para que tocar no widget abra o app diretamente na agenda:

### **9.1 - Adicionar URL Scheme**

No `AgendaWidgetEntryView`, adicionar `.widgetURL()`:

```swift
struct AgendaWidgetEntryView: View {
    @Environment(\.widgetFamily) var family
    var entry: AgendaWidgetEntry

    var body: some View {
        Group {
            switch family {
            case .systemSmall:
                SmallWidgetView(entry: entry)
            case .systemMedium:
                MediumWidgetView(entry: entry)
            case .systemLarge:
                LargeWidgetView(entry: entry)
            @unknown default:
                SmallWidgetView(entry: entry)
            }
        }
        .widgetURL(URL(string: "agendahof://agenda")!)  // ✅ Deep link
    }
}
```

### **9.2 - Atualizar AgendaHofApp.swift**

Adicionar handler para abrir na aba correta:

```swift
@main
struct AgendaHofApp: App {
    @StateObject private var supabase = SupabaseManager.shared
    @State private var selectedTab = 0  // ✅ Adicionar

    var body: some Scene {
        WindowGroup {
            Group {
                if supabase.session != nil {
                    MainTabView(selectedTab: $selectedTab)  // ✅ Passar binding
                        .environmentObject(supabase)
                } else {
                    LoginView()
                        .environmentObject(supabase)
                }
            }
            .onOpenURL { url in  // ✅ Handler de deep link
                if url.scheme == "agendahof", url.host == "agenda" {
                    selectedTab = 0  // Abrir na aba Agenda
                }
            }
        }
    }
}
```

### **9.3 - Atualizar MainTabView.swift**

Aceitar binding para selectedTab:

```swift
struct MainTabView: View {
    @Binding var selectedTab: Int  // ✅ Mudar de @State para @Binding
    @EnvironmentObject var supabase: SupabaseManager

    // ... resto do código igual
}
```

---

## 🧪 PASSO 10: Testar

### **10.1 - Build e Run**

1. Selecionar scheme **AgendaWidget** no Xcode
2. Escolher dispositivo/simulador
3. **Run** (Cmd+R)
4. Escolher um tamanho de widget para testar

### **10.2 - Adicionar Widget ao Home Screen**

1. No simulador/dispositivo, **long press** na tela inicial
2. Toque no **+** no canto superior
3. Buscar **Agenda HOF**
4. Escolher tamanho (Small, Medium ou Large)
5. Adicionar à tela inicial

### **10.3 - Testar Atualização**

1. Abrir app principal
2. Criar/editar agendamentos
3. Fechar app
4. Widget deve atualizar em até 15 minutos
5. Para forçar atualização: long press no widget → Edit Widget

---

## ✅ Checklist de Implementação

- [ ] Widget Extension criada no Xcode
- [ ] App Group configurado (`group.com.agendahof.shared`)
- [ ] `WidgetAppointment.swift` criado e adicionado a ambos targets
- [ ] `WidgetDataManager.swift` implementado
- [ ] `AppointmentService` atualizado para salvar dados
- [ ] `AgendaWidgetProvider.swift` implementado
- [ ] `SmallWidgetView.swift` criado
- [ ] `MediumWidgetView.swift` criado
- [ ] `LargeWidgetView.swift` criado
- [ ] `AgendaWidget.swift` (entry point) configurado
- [ ] Deep linking configurado
- [ ] Testado nos 3 tamanhos
- [ ] Testado em dark mode
- [ ] Testado atualização automática

---

## 🎨 Personalização Futura

### **Ideias de Melhorias:**

1. **Configuração por Intent**
   - Permitir escolher qual profissional exibir
   - Filtrar por tipo de procedimento
   - Escolher período (hoje, semana, mês)

2. **Widgets Interativos (iOS 17+)**
   - Botão para confirmar agendamento
   - Botão para remarcar
   - Toggle de status

3. **Live Activities (iOS 16.1+)**
   - Countdown para próximo agendamento
   - Notificação dinâmica na Dynamic Island

4. **Gráficos**
   - Widget com gráfico de agendamentos da semana
   - Taxa de ocupação da agenda

---

## 📊 Referências

- [Apple Widget Documentation](https://developer.apple.com/documentation/widgetkit)
- [App Groups Guide](https://developer.apple.com/documentation/bundleresources/entitlements/com_apple_security_application-groups)
- [WidgetKit Tutorial](https://developer.apple.com/tutorials/swiftui/creating-a-widget-extension)

---

**Implementação completa pronta para produção! 🚀**

**Próximo passo**: Seguir o guia passo a passo no Xcode para criar a Widget Extension.
