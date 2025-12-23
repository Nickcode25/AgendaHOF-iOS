# Agenda HOF - iOS App

Sistema de gestão para clínicas médicas desenvolvido em SwiftUI.

## 📱 Características

- **Autenticação Segura**: Login, cadastro e recuperação de senha com Supabase
- **Deep Linking**: Suporte a Universal Links para redefinição de senha via email
- **Validação de Senha**: Histórico de senhas e validação de força
- **Notificações por Email**: Sistema automatizado via Resend
- **Interface Adaptativa**: Suporte completo para modo claro e escuro
- **Gestão de Sessões**: Logout de múltiplos dispositivos

## 🛠️ Tecnologias

- **iOS**: SwiftUI, Swift 5.9+
- **Backend**: Supabase (Authentication, Database)
- **Email**: Resend API
- **Deep Linking**: Universal Links + Custom URL Scheme

## 📋 Requisitos

- Xcode 15.0+
- iOS 16.0+
- Swift Package Manager

## 🚀 Configuração

### 1. Clonar o Repositório

```bash
git clone <repository-url>
cd "Agenda HOF Swift"
```

### 2. Instalar Dependências

As dependências são gerenciadas via Swift Package Manager e serão instaladas automaticamente ao abrir o projeto no Xcode.

Pacotes incluídos:
- Supabase Swift
- Auth
- PostgREST
- Realtime
- Storage

### 3. Configurar Variáveis de Ambiente

Certifique-se de que o backend Railway está configurado com:

```env
SUPABASE_URL=your_supabase_url
SUPABASE_SERVICE_KEY=your_service_key
RESEND_API_KEY=your_resend_key
SMTP_FROM=noreply@email.agendahof.com
EMAIL_FROM=Agenda HOF <noreply@email.agendahof.com>
MOBILE_APP_SCHEME=agendahof://reset-password
FRONTEND_URL=https://agendahof.com
```

### 4. Configurar Deep Linking

O projeto já está configurado com:
- **Bundle ID**: `com.agendahof.swift`
- **Team ID**: `J5YU2V26FV`
- **Associated Domains**: `applinks:agendahof.com`
- **Custom URL Scheme**: `agendahof://`

O arquivo `apple-app-site-association` já está incluído no projeto.

### 5. Build e Run

1. Abra `AgendaHOF.xcodeproj` no Xcode
2. Selecione um simulador ou dispositivo
3. Pressione Cmd + R para executar

## 📂 Estrutura do Projeto

```
Agenda HOF Swift/
├── AgendaHofApp.swift          # Entry point do app
├── Views/
│   ├── Auth/
│   │   ├── LoginView.swift
│   │   ├── SignUpView.swift
│   │   ├── ResetPasswordView.swift
│   │   └── PasswordStrengthIndicator.swift
│   └── Settings/
│       └── SettingsView.swift
├── ViewModels/
│   ├── ForgotPasswordViewModel.swift
│   └── ResetPasswordViewModel.swift
├── Services/
│   └── NotificationManager.swift
├── Models/
└── Documentation/              # Documentação técnica
    ├── Fixes/                 # Histórico de correções
    └── Guides/                # Guias de implementação
```

## 🔐 Fluxo de Autenticação

### Login
1. Usuário insere email e senha
2. Autenticação via Supabase
3. Armazenamento seguro da sessão

### Cadastro
1. Validação de dados (nome, email, telefone, senha)
2. Verificação de força da senha
3. Criação de conta no Supabase
4. Email de confirmação enviado

### Recuperação de Senha
1. Usuário solicita reset via email
2. Backend gera token OTP válido por 1 hora
3. Email enviado com link de deep linking
4. App abre automaticamente via Universal Link
5. Usuário define nova senha
6. Validação de senha duplicada (últimas 5 senhas)
7. Email de notificação de alteração enviado
8. Logout de todos os dispositivos (opcional)

## 🔗 Deep Linking

### Como Funciona

1. **Email com Link**: `https://agendahof.com/auth/v1/verify?token=...`
2. **Redirect do Supabase**: `agendahof://reset-password#access_token=...`
3. **App Handling**: Token extraído e processado
4. **Apresentação**: ResetPasswordView exibido

### Testando Deep Links

```bash
# Via linha de comando
xcrun simctl openurl booted "agendahof://reset-password#access_token=test123"

# Via script incluído
./test-universal-link.sh
```

## 🎨 Temas

O app suporta totalmente modo claro e escuro com:
- Cores adaptativas automáticas
- Logos específicos para cada tema
- Contraste otimizado em todos os componentes

## 📧 Sistema de Email

### Templates Incluídos

1. **Recuperação de Senha**
   - Design profissional HTML
   - Link de redefinição
   - Informações de expiração

2. **Notificação de Alteração**
   - Detalhes da mudança (data, dispositivo, IP)
   - Alerta de segurança
   - Botão de ação rápida

## 🧪 Testes

### Testar Recuperação de Senha

1. Na tela de login, clique em "Esqueceu?"
2. Digite um email válido
3. Clique em "Enviar link de recuperação"
4. Abra o email recebido
5. Clique no link (deve abrir o app automaticamente)
6. Digite e confirme a nova senha
7. Verifique email de notificação

## 🐛 Troubleshooting

### Deep Links não abrem o app
- Delete o app completamente
- Reinicie o dispositivo/simulador
- Reinstale o app
- iOS precisará re-baixar o AASA file

### Email não chega
- Verifique spam
- Confirme que `email.agendahof.com` está verificado no Resend
- Verifique variáveis `SMTP_FROM` e `EMAIL_FROM` no Railway

### Token expirado imediatamente
- Backend deve usar `admin.generateLink()` com token OTP
- App usa `setSession()` para evitar validação server-side
- Token válido por 1 hora e uso único

## 📝 Documentação Adicional

- [Histórico de Fixes](Documentation/Fixes/)
- [Guias de Implementação](Documentation/Guides/)
- [Resumo da Solução](Documentation/SOLUCAO_RESUMO.md)

## 🤝 Contribuindo

Este é um projeto privado. Para reportar bugs ou sugerir melhorias, entre em contato com a equipe de desenvolvimento.

## 📄 Licença

© 2025 Agenda HOF. Todos os direitos reservados.
