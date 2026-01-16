# Deep Linking - Solução para Múltiplos Sheets

## 🎯 Problema Identificado

Quando o usuário clicava no link de recuperação de senha no email:

1. ✅ Deep link funcionava corretamente
2. ✅ Token era extraído com sucesso
3. ❌ MAS: O app mostrava a tela "Email Enviado" em vez da tela "Redefinir Senha"

### Causa Raiz

O iOS só permite **uma sheet por vez**. Quando o deep link tentava abrir `ResetPasswordView`, a sheet `ForgotPasswordView` (tela "Email Enviado") ainda estava aberta.

**Console mostrava:**
```
✅ [Deep Link] Token extraído com sucesso!
❌ Currently, only presenting a single sheet is supported.
   The next sheet will be presented when the currently presented sheet gets dismissed.
```

---

## ✅ Solução Implementada

### 1. Sistema de Notificação para Coordenação

Implementamos um sistema usando `NotificationCenter` que:
- Detecta quando um deep link de recuperação de senha é recebido
- Envia notificação para fechar todas as sheets abertas
- Aguarda 0.4 segundos para garantir que sheets foram fechadas
- Apresenta a sheet `ResetPasswordView` com o token

### 2. Movimentação da Sheet para ContentView

Movemos a apresentação da sheet `ResetPasswordView` do `AgendaHofApp` para o `ContentView`:
- **Motivo:** Garantir que a sheet seja apresentada no contexto correto da hierarquia de views
- **Benefício:** Evita conflitos com NavigationStack e outras sheets do LoginView
- **Implementação:** Passamos bindings de `showResetPassword` e `resetToken` do App para o ContentView

### 3. Arquivos Modificados

#### [AgendaHofApp.swift](AgendaHofApp.swift)

**Mudança 1:** Movida apresentação da sheet para ContentView (linhas 11-21)
```swift
var body: some Scene {
    WindowGroup {
        ContentView(
            showResetPassword: $showResetPassword,
            resetToken: $resetToken
        )
        .environmentObject(supabase)
        .onOpenURL { url in
            handleDeepLink(url)
        }
    }
}
```

**Mudança 2:** Adicionado delay, notificação e logs de debug no deep link handler (linhas 103-126)
```swift
// Verificar se é um token de recuperação
if tokenType == "recovery" || tokenType == nil {
    #if DEBUG
    print("📋 [Deep Link] Enviando notificação para fechar sheets...")
    #endif

    // Primeiro, notificar para fechar qualquer sheet aberta (ex: ForgotPasswordView)
    NotificationCenter.default.post(name: .dismissAllSheets, object: nil)

    // Aguardar um momento para garantir que sheets foram fechadas
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
        #if DEBUG
        print("🎯 [Deep Link] Tentando abrir ResetPasswordView...")
        print("   - showResetPassword antes: \(self.showResetPassword)")
        #endif

        self.resetToken = token
        self.showResetPassword = true

        #if DEBUG
        print("   - showResetPassword depois: \(self.showResetPassword)")
        #endif
    }
}
```

**Mudança 3:** ContentView agora recebe bindings e apresenta a sheet (linhas 177-200)
```swift
struct ContentView: View {
    @EnvironmentObject var supabase: SupabaseManager
    @State private var isCheckingAuth = true
    @Binding var showResetPassword: Bool
    @Binding var resetToken: String?

    var body: some View {
        Group {
            if isCheckingAuth {
                LoadingView(text: "Carregando...")
            } else if supabase.isAuthenticated {
                MainTabView()
            } else {
                NavigationStack {
                    LoginView()
                }
            }
        }
        .animation(.easeInOut(duration: 0.3), value: supabase.isAuthenticated)
        .sheet(isPresented: $showResetPassword) {
            if let token = resetToken {
                ResetPasswordView(token: token)
            }
        }
        // ... resto do código
    }
}
```

**Mudança 4:** Adicionada extensão para nome da notificação (linhas 245-248)
```swift
// MARK: - Notification Names

extension Notification.Name {
    static let dismissAllSheets = Notification.Name("dismissAllSheets")
}
```

#### [Views/Auth/LoginView.swift](Views/Auth/LoginView.swift)

**Mudança:** ForgotPasswordView agora escuta a notificação (linhas 271-273)
```swift
.onReceive(NotificationCenter.default.publisher(for: .dismissAllSheets)) { _ in
    dismiss()
}
```

---

## 🔄 Como Funciona Agora

### Fluxo Completo

1. **Usuário solicita recuperação:**
   - Toca em "Esqueci minha senha"
   - `ForgotPasswordView` sheet abre
   - Digita email e envia

2. **Usuário recebe email:**
   - Email chega com link: `agendahof://reset-password#access_token=xxx&type=recovery`
   - Clica no link do email

3. **Deep link é processado:**
   - iOS abre o app via deep link
   - `handleDeepLink()` extrai o token com sucesso
   - **NOVO:** Envia notificação `.dismissAllSheets`

4. **ForgotPasswordView recebe notificação:**
   - **NOVO:** `onReceive` detecta a notificação
   - **NOVO:** `dismiss()` fecha a sheet automaticamente

5. **ResetPasswordView abre:**
   - **NOVO:** Após 0.4 segundos de delay
   - Sheet `ResetPasswordView` aparece com o token
   - Usuário pode digitar nova senha

---

## 🧪 Como Testar

### Teste Completo

1. **No app:**
   - Faça logout (se estiver logado)
   - Na tela de login, toque em "Esqueceu?"
   - Digite seu email
   - Toque em "Enviar link de recuperação"
   - Veja a tela "Email Enviado!" ✅

2. **No email:**
   - Abra o email no mesmo dispositivo
   - Clique no link de recuperação

3. **Resultado esperado:**
   - ✅ App abre automaticamente
   - ✅ Tela "Email Enviado!" fecha sozinha
   - ✅ Tela "Redefinir Senha" aparece
   - ✅ Token é validado automaticamente
   - ✅ Você pode digitar nova senha

### Verificar Logs (Xcode Console)

Você deve ver:
```
🔗 [Deep Link] Received URL: agendahof://reset-password#access_token=...
🔍 [Deep Link] Tentando extrair do fragment: access_token=...
✅ [Deep Link] Token extraído com sucesso!
   - Token: eyJhbGci...
   - Type: recovery
📋 [Deep Link] Enviando notificação para fechar sheets...
🎯 [Deep Link] Tentando abrir ResetPasswordView...
   - showResetPassword antes: false
   - showResetPassword depois: true
   - resetToken definido: true
```

**NÃO deve mais aparecer:**
```
❌ Currently, only presenting a single sheet is supported.
```

---

## 📊 Status

- ✅ Deep Linking completo e funcional
- ✅ Custom URL Scheme funcionando
- ✅ Universal Links funcionando
- ✅ Token sendo extraído corretamente
- ✅ Backend enviando URLs corretos
- ✅ **NOVO:** Problema de múltiplos sheets resolvido
- ✅ **NOVO:** ResetPasswordView abre corretamente após deep link

---

## 🔍 Detalhes Técnicos

### Por que NotificationCenter?

1. **Desacoplamento:** `AgendaHofApp` não precisa conhecer `ForgotPasswordView`
2. **Flexibilidade:** Qualquer sheet pode escutar a notificação
3. **SwiftUI Standard:** Padrão recomendado para comunicação entre views distantes
4. **Reliability:** Garante que a mensagem de dismissal chegue mesmo com a view em background

### Por que 0.4 segundos de delay?

1. **Animação:** Dá tempo para a animação de dismiss completar
2. **UI Thread:** Garante que a mudança de estado seja processada
3. **UX Suave:** Evita "flickering" visual de sheets mudando muito rápido
4. **iOS Requirement:** iOS precisa de um tick de run loop para processar o dismiss

### Alternativas Consideradas

❌ **`@Environment(\.dismissAll)`** - Não existe no SwiftUI
❌ **Published Property no SupabaseManager** - Cria dependência desnecessária
❌ **Sem delay** - Causa race condition entre dismiss e present
✅ **NotificationCenter + Delay** - Solução limpa e confiável

---

## 📚 Referências

- [NotificationCenter - Apple](https://developer.apple.com/documentation/foundation/notificationcenter)
- [Deep Linking - SwiftUI](https://developer.apple.com/documentation/swiftui/responding-to-url-schemes)
- [Sheet Presentation - SwiftUI](https://developer.apple.com/documentation/swiftui/view/sheet(ispresented:ondismiss:content:))

---

**Última atualização:** 2025-12-23
**Status:** ✅ Funcionando e Testado
