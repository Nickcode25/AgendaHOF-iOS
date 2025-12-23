# 🐛 Backend Fix - Token Expirado Imediatamente

## 🎯 Problema

Os tokens de recuperação de senha estão expirando imediatamente, mesmo quando o usuário clica no link em menos de 1 minuto.

### Erro no Console do App:
```
❌ [ResetPassword] ERRO ao resetar senha:
   - AuthError: "Email link is invalid or has expired"
   - errorCode: "otp_expired"
   - Status Code: 403
```

### Análise do Token JWT:
```json
{
  "iat": 1766489550,  // Criado: 23 Dez 2025 08:32:30 GMT
  "exp": 1766493150,  // Expira: 23 Dez 2025 09:32:30 GMT
  "expires_in": 3600  // 1 hora
}
```

**Erro usado em:** 23 Dez 2025 11:33:50 GMT (3 horas depois!)

---

## 🔍 Causa Raiz

O backend está usando `supabase.auth.admin.generateLink()` que gera um **token de acesso direto**, não um **link de recuperação OTP**.

### Diferença entre os métodos:

#### ❌ `admin.generateLink()` (MÉTODO ATUAL - INCORRETO)
```javascript
const { data: otpData, error: otpError } = await supabase.auth.admin.generateLink({
  type: 'recovery',
  email: email,
  options: {
    redirectTo: process.env.MOBILE_APP_URL
  }
})
```

**Problema:**
- Gera um **access_token JWT** diretamente
- O JWT tem timestamp fixo (`iat` e `exp`)
- Se houver diferença de fuso horário entre backend e Supabase, o token fica inválido
- Token expira baseado no timestamp de criação, não no envio do email

#### ✅ `resetPasswordForEmail()` (MÉTODO CORRETO)
```javascript
const { data, error } = await supabase.auth.resetPasswordForEmail(email, {
  redirectTo: process.env.MOBILE_APP_URL || `${process.env.FRONTEND_URL}/reset-password`
})
```

**Vantagem:**
- Gera um **OTP token** que é validado pelo Supabase
- Token só começa a contar após o envio do email
- Não tem problema de fuso horário
- Expira 1 hora **após o envio**, não após a criação

---

## 🔧 Mudanças Necessárias

### Arquivo: `backend/server.js`

**Localizar:** Função de recuperação de senha (provavelmente linha ~376)

**ANTES:**
```javascript
const { data: otpData, error: otpError } = await supabase.auth.admin.generateLink({
  type: 'recovery',
  email: email,
  options: {
    redirectTo: process.env.MOBILE_APP_URL || `${process.env.FRONTEND_URL}/reset-password`
  }
})

if (otpError) {
  throw otpError
}

// Enviar email com o link
const resetLink = otpData.properties.action_link
```

**DEPOIS:**
```javascript
// Usar resetPasswordForEmail em vez de admin.generateLink
const { data, error } = await supabase.auth.resetPasswordForEmail(email, {
  redirectTo: process.env.MOBILE_APP_URL || `${process.env.FRONTEND_URL}/reset-password`
})

if (error) {
  throw error
}

// O Supabase envia o email automaticamente
// NÃO precisa enviar email manualmente via Resend
```

---

### Arquivo: `backend/routes/auth.js`

**Localizar:** Rota de recuperação de senha (provavelmente linha ~513)

**Verificar se já está usando `resetPasswordForEmail()`:**

```javascript
// ✅ CORRETO - Se já estiver assim, não precisa mudar
const { data, error } = await supabase.auth.resetPasswordForEmail(email, {
  redirectTo: process.env.MOBILE_APP_URL || `${process.env.FRONTEND_URL}/reset-password`
})
```

---

## ⚠️ IMPORTANTE: Sobre os Emails

### Se estiver usando Resend para enviar emails:

**OPÇÃO 1: Deixar o Supabase enviar (RECOMENDADO)**
```javascript
// Apenas chamar resetPasswordForEmail
const { data, error } = await supabase.auth.resetPasswordForEmail(email, {
  redirectTo: process.env.MOBILE_APP_URL
})

// O Supabase envia o email automaticamente
// NÃO enviar via Resend
```

**OPÇÃO 2: Continuar usando Resend**

Se você PRECISA usar Resend (por template customizado), use este fluxo:

```javascript
// 1. Gerar o link usando generateLink
const { data: linkData, error: linkError } = await supabase.auth.admin.generateLink({
  type: 'recovery',
  email: email,
  options: {
    redirectTo: process.env.MOBILE_APP_URL
  }
})

if (linkError) throw linkError

// 2. IMPORTANTE: Extrair apenas o TOKEN, não o access_token
const actionLink = linkData.properties.action_link
const url = new URL(actionLink)
const token = url.searchParams.get('token')  // ← Pegar o 'token', NÃO o 'access_token'

// 3. Construir o link correto
const resetLink = `${process.env.SUPABASE_URL}/auth/v1/verify?token=${token}&type=recovery&redirect_to=${encodeURIComponent(process.env.MOBILE_APP_URL)}`

// 4. Enviar via Resend com o link correto
await resend.emails.send({
  from: 'Agenda HOF <noreply@agendahof.com>',
  to: email,
  subject: 'Recuperação de Senha',
  html: `<a href="${resetLink}">Redefinir minha senha</a>`
})
```

**Por que isso funciona?**
- O `token` (não `access_token`) é validado pelo Supabase no endpoint `/auth/v1/verify`
- O Supabase converte o `token` em um `access_token` válido no momento do click
- Resolve o problema de timezone/timestamp

---

## 🧪 Como Testar

Depois de fazer as mudanças:

1. **Deploy no Railway** (acontece automaticamente ao fazer push)

2. **No app:**
   - Solicitar recuperação de senha
   - Abrir email **imediatamente**
   - Clicar no link
   - App deve abrir com a tela de redefinir senha

3. **Verificar logs do Xcode:**
   ```
   ✅ [Deep Link] Token extraído com sucesso!
   🔐 [ResetPassword] Passo 1: Verificando token com verifyOTP...
   ✅ [ResetPassword] Passo 1: Token verificado com sucesso!
   ```

4. **Preencher nova senha e clicar em "Redefinir Senha"**

5. **Deve aparecer:**
   ```
   🎉 [ResetPassword] Reset de senha concluído com sucesso!
   ```

---

## 📊 Comparação dos Métodos

| Método | Quando Usar | Token Gerado | Email | Timezone Safe |
|--------|-------------|--------------|-------|---------------|
| `resetPasswordForEmail()` | ✅ **Recomendado** | OTP token | Supabase envia | ✅ Sim |
| `admin.generateLink()` + token | ⚠️ Se usar Resend | OTP token | Manual via Resend | ✅ Sim |
| `admin.generateLink()` + access_token | ❌ **NÃO USAR** | JWT access token | Manual via Resend | ❌ Não |

---

## 🔍 Como Identificar o Problema no Código Atual

Procure no código do backend por:

```javascript
// ❌ PROBLEMA: Se você vê "access_token" ou "action_link"
const resetLink = otpData.properties.action_link

// ❌ PROBLEMA: Se você está enviando o access_token diretamente
const accessToken = otpData.properties.access_token

// ✅ CORRETO: Se você vê "resetPasswordForEmail"
await supabase.auth.resetPasswordForEmail(email, {...})

// ✅ CORRETO: Se você está extraindo o 'token' (não access_token)
const token = url.searchParams.get('token')
```

---

## 📁 Arquivos a Verificar

1. **`backend/server.js`** - Função principal de recuperação de senha
2. **`backend/routes/auth.js`** - Rotas de autenticação
3. **`backend/services/email.js`** ou similar - Se tiver serviço separado de email

---

## 🎯 Resumo da Solução

**Problema:** Backend está gerando `access_token` JWT com timestamp incorreto

**Solução:** Usar `resetPasswordForEmail()` que gera OTP token sem problema de timezone

**Resultado:** Token válido por 1 hora a partir do momento do envio do email

---

**Data:** 2024-12-23
**Status:** 🔴 CRÍTICO - Impede recuperação de senha
**Prioridade:** ALTA
