# 🚀 Widgets iOS - Guia Rápido de Implementação

**Tempo estimado**: 30-45 minutos

---

## ✅ Arquivos Já Criados

Os seguintes arquivos já foram criados e estão prontos:

- ✅ `Shared/WidgetAppointment.swift` - Modelo de dados
- ✅ `Services/WidgetDataManager.swift` - Gerenciador de dados
- ✅ `Services/AppointmentService.swift` - Integração adicionada
- ✅ `Documentation/WIDGETS_IOS_IMPLEMENTATION.md` - Documentação completa

---

## 📋 Checklist de Implementação

### **PARTE 1: Configuração no Apple Developer (5 min)**

- [ ] 1. Acessar [Apple Developer Portal](https://developer.apple.com/account)
- [ ] 2. Ir em **Certificates, Identifiers & Profiles → Identifiers**
- [ ] 3. Clicar em **+** para criar novo identifier
- [ ] 4. Selecionar **App Groups**
- [ ] 5. Nome: `AgendaHOF Shared Data`
- [ ] 6. Identifier: `group.com.agendahof.shared`
- [ ] 7. Clicar em **Continue** e **Register**

---

### **PARTE 2: Criar Widget Extension no Xcode (10 min)**

- [ ] 1. Abrir projeto **Agenda HOF** no Xcode
- [ ] 2. Menu **File → New → Target...**
- [ ] 3. Procurar e selecionar **Widget Extension**
- [ ] 4. Preencher:
  - **Product Name**: `AgendaWidget`
  - **Include Configuration Intent**: ❌ Desmarcar
- [ ] 5. Clicar em **Finish**
- [ ] 6. Quando perguntado "Activate AgendaWidget scheme?", clicar em **Activate**

---

### **PARTE 3: Configurar App Groups (5 min)**

#### **3.1 - Target AgendaHOF (App Principal)**

- [ ] 1. No Navigator, selecionar o projeto **Agenda HOF**
- [ ] 2. Selecionar target **AgendaHOF**
- [ ] 3. Aba **Signing & Capabilities**
- [ ] 4. Clicar em **+ Capability**
- [ ] 5. Procurar e adicionar **App Groups**
- [ ] 6. Marcar checkbox: `group.com.agendahof.shared`
- [ ] 7. Se não aparecer, clicar em **+** e adicionar manualmente

#### **3.2 - Target AgendaWidget (Widget Extension)**

- [ ] 1. Selecionar target **AgendaWidget**
- [ ] 2. Aba **Signing & Capabilities**
- [ ] 3. Clicar em **+ Capability**
- [ ] 4. Adicionar **App Groups**
- [ ] 5. Marcar checkbox: `group.com.agendahof.shared`

---

### **PARTE 4: Adicionar Arquivos ao Target Widget (5 min)**

- [ ] 1. No Navigator, localizar arquivo **`Shared/WidgetAppointment.swift`**
- [ ] 2. Clicar no arquivo para selecioná-lo
- [ ] 3. No **File Inspector** (lado direito), em **Target Membership**:
  - ✅ Marcar **AgendaHOF**
  - ✅ Marcar **AgendaWidget**
- [ ] 4. Verificar que `WidgetAppointment.swift` está compartilhado entre ambos targets

---

### **PARTE 5: Copiar Código dos Widgets (10 min)**

Agora você precisa substituir o código gerado automaticamente pelo Xcode.

#### **5.1 - Deletar arquivo gerado automaticamente**

- [ ] 1. No folder **AgendaWidget/**, deletar arquivo **`AgendaWidget.swift`** (gerado pelo Xcode)

#### **5.2 - Criar estrutura de pastas**

No folder **AgendaWidget/**, criar:

```
AgendaWidget/
├── AgendaWidget.swift           ← Entry point
├── AgendaWidgetProvider.swift   ← Timeline provider
└── Views/
    ├── SmallWidgetView.swift
    ├── MediumWidgetView.swift
    └── LargeWidgetView.swift
```

#### **5.3 - Copiar código**

Copie o código dos arquivos da documentação completa (`WIDGETS_IOS_IMPLEMENTATION.md`):

- [ ] 1. Criar **`AgendaWidgetProvider.swift`** (PASSO 6 da doc)
- [ ] 2. Criar **`Views/SmallWidgetView.swift`** (PASSO 7.1)
- [ ] 3. Criar **`Views/MediumWidgetView.swift`** (PASSO 7.2)
- [ ] 4. Criar **`Views/LargeWidgetView.swift`** (PASSO 7.3)
- [ ] 5. Criar **`AgendaWidget.swift`** (PASSO 8)

**IMPORTANTE**: Adicionar todos os arquivos ao target **AgendaWidget** (Target Membership).

---

### **PARTE 6: Configurar Deep Linking (5 min)**

#### **6.1 - Atualizar AgendaWidget.swift**

No arquivo **`AgendaWidget/AgendaWidget.swift`**, adicionar `.widgetURL()`:

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
        .widgetURL(URL(string: "agendahof://agenda")!)  // ✅ Adicionar
    }
}
```

#### **6.2 - Atualizar AgendaHofApp.swift**

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
            .onOpenURL { url in  // ✅ Adicionar handler
                if url.scheme == "agendahof", url.host == "agenda" {
                    selectedTab = 0
                }
            }
            // ... código existente de deep link para reset-password
        }
    }
}
```

#### **6.3 - Atualizar MainTabView.swift**

```swift
struct MainTabView: View {
    @Binding var selectedTab: Int  // ✅ Mudar de @State para @Binding
    @EnvironmentObject var supabase: SupabaseManager

    // ... resto do código continua igual
}
```

---

### **PARTE 7: Build e Teste (5 min)**

- [ ] 1. Selecionar scheme **AgendaWidget** na toolbar do Xcode
- [ ] 2. Escolher simulador (iPhone 15 Pro recomendado)
- [ ] 3. Clicar em **Run** (Cmd+R)
- [ ] 4. Quando o widget aparecer, escolher tamanho para testar:
  - Small (pequeno)
  - Medium (médio)
  - Large (grande)

#### **Testar dados reais:**

- [ ] 1. Parar execução do widget
- [ ] 2. Selecionar scheme **AgendaHOF** (app principal)
- [ ] 3. Run no simulador
- [ ] 4. Fazer login
- [ ] 5. Ir para aba **Agenda**
- [ ] 6. Criar alguns agendamentos para hoje e amanhã
- [ ] 7. Voltar para Home Screen (Cmd+Shift+H)
- [ ] 8. Long press na tela → **+** → Buscar "Agenda HOF"
- [ ] 9. Adicionar widget (testar os 3 tamanhos)
- [ ] 10. Verificar se os agendamentos aparecem

---

## 🧪 Testes Importantes

### **Teste 1: Dados aparecem no widget**
- [ ] Criar agendamento no app
- [ ] Fechar app
- [ ] Widget atualiza em até 15 minutos
- [ ] Força atualização: Long press widget → Edit Widget

### **Teste 2: Deep linking funciona**
- [ ] Tocar no widget
- [ ] App abre na aba Agenda

### **Teste 3: Dark mode**
- [ ] Settings → Developer → Dark Appearance
- [ ] Verificar widget em modo escuro

### **Teste 4: Diferentes estados**
- [ ] Widget sem agendamentos (estado vazio)
- [ ] Widget com 1 agendamento
- [ ] Widget com vários agendamentos
- [ ] Widget com agendamento "Agora"

---

## 🐛 Troubleshooting

### **Problema: "Failed to access App Group"**

**Solução:**
1. Verificar que App Group foi criado no Apple Developer
2. Verificar que está marcado em AMBOS targets (AgendaHOF + AgendaWidget)
3. Clean Build Folder (Shift+Cmd+K)
4. Rebuild

### **Problema: Widget não atualiza**

**Solução:**
1. Verificar console do Xcode para erros
2. Verificar que `WidgetDataManager.saveAppointments()` está sendo chamado
3. Forçar atualização: Long press widget → Remove → Add novamente

### **Problema: Widget mostra "No data"**

**Solução:**
1. Verificar que `WidgetAppointment.swift` está no target AgendaWidget
2. Verificar que App Group identifier está correto em ambos lados
3. Criar agendamento no app e verificar console

### **Problema: Deep linking não funciona**

**Solução:**
1. Verificar que `.widgetURL()` foi adicionado
2. Verificar que `.onOpenURL()` foi adicionado no AgendaHofApp
3. Verificar que MainTabView aceita binding

---

## 📊 Como Verificar no Console

Ao rodar o app principal, você deve ver logs como:

```
✅ [Widget] Saved 5 appointments
📊 [Widget] Next appointment: Maria Silva
📅 [Widget] Today: 3 appointments
🔄 [Widget] Timeline reload requested
```

Ao rodar o widget, deve ver:

```
✅ [Widget] Loaded 5 appointments
⏰ [Widget] Last update: 2025-12-23 14:30:00 +0000
```

---

## ✅ Checklist Final

- [ ] App Groups configurado no Apple Developer
- [ ] App Groups adicionado em ambos targets
- [ ] Widget Extension criada
- [ ] Arquivos compartilhados entre targets
- [ ] Código dos widgets copiado corretamente
- [ ] Deep linking configurado
- [ ] Build sem erros
- [ ] Widget Small testado
- [ ] Widget Medium testado
- [ ] Widget Large testado
- [ ] Dark mode testado
- [ ] Deep linking testado

---

## 🎉 Próximos Passos

Após implementar com sucesso:

1. **Testar em dispositivo real** (não apenas simulador)
2. **Testar diferentes timezones** (se relevante)
3. **Adicionar screenshots dos widgets** para App Store
4. **Considerar Live Activities** (iOS 16.1+) para countdown
5. **Adicionar configuração por Intent** (escolher profissional)

---

**Tempo total estimado: 30-45 minutos** ⏱️

Se encontrar problemas, consulte a documentação completa em `WIDGETS_IOS_IMPLEMENTATION.md`.
