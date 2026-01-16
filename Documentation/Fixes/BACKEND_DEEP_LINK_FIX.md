# Backend - Fix Deep Linking para App Mobile

## 🎯 Objetivo

Fazer com que os emails de recuperação de senha abram o **app mobile** em vez do navegador (site).

---

## 📋 Mudanças Necessárias

### 1. Adicionar Nova Variável de Ambiente no Railway

**Variável:**
```
MOBILE_APP_URL=agendahof://reset-password
```

**Como fazer:**
1. Acesse o projeto no Railway
2. Vá em **Variables**
3. Clique em **+ New Variable**
4. Adicione:
   - Nome: `MOBILE_APP_URL`
   - Valor: `agendahof://reset-password`
5. Clique em **Add**
6. O Railway fará redeploy automaticamente

---

### 2. Atualizar `backend/server.js`

**Localização:** Linha 376

**ANTES:**
```javascript
const { data: otpData, error: otpError } = await supabase.auth.admin.generateLink({
  type: 'recovery',
  email: email,
  options: {
    redirectTo: `${process.env.FRONTEND_URL}/reset-password`  // ❌ Abre o site
  }
})
```

**DEPOIS:**
```javascript
const { data: otpData, error: otpError } = await supabase.auth.admin.generateLink({
  type: 'recovery',
  email: email,
  options: {
    redirectTo: process.env.MOBILE_APP_URL || `${process.env.FRONTEND_URL}/reset-password`  // ✅ Abre o app
  }
})
```

---

### 3. Atualizar `backend/routes/auth.js`

**Localização:** Linha 525

**ANTES:**
```javascript
const { data, error } = await supabase.auth.resetPasswordForEmail(email, {
  redirectTo: `${process.env.FRONTEND_URL}/reset-password`  // ❌ Abre o site
})
```

**DEPOIS:**
```javascript
const { data, error } = await supabase.auth.resetPasswordForEmail(email, {
  redirectTo: process.env.MOBILE_APP_URL || `${process.env.FRONTEND_URL}/reset-password`  // ✅ Abre o app
})
```

---

## 🔍 Explicação

### O que acontece agora:
1. Usuário solicita recuperação de senha
2. Backend gera link com `redirectTo: https://agendahof.com/reset-password`
3. Email enviado com link do Supabase que redireciona para o **site**
4. Abre o Safari ❌

### O que vai acontecer depois:
1. Usuário solicita recuperação de senha
2. Backend gera link com `redirectTo: agendahof://reset-password`
3. Email enviado com link do Supabase que redireciona para o **app**
4. Abre o Agenda HOF App ✅

---

## 🧪 Como Testar

Depois de fazer as mudanças:

1. **Restart o backend** (Railway faz automaticamente ao adicionar variável)
2. No app, vá em **"Esqueci minha senha"**
3. Digite um email válido
4. Abra o email recebido
5. Clique no botão **"Redefinir minha senha"**
6. **Deve abrir o app diretamente** 🎉

---

## 📝 Detalhes Técnicos

### Formato da URL do Email

**Antes:**
```
https://zgdxszwjbbxepsvyjtrb.supabase.co/auth/v1/verify?token=XXX&type=recovery&redirect_to=https://agendahof.com/reset-password
```

**Depois:**
```
https://zgdxszwjbbxepsvyjtrb.supabase.co/auth/v1/verify?token=XXX&type=recovery&redirect_to=agendahof://reset-password
```

### Fluxo Completo

1. **Usuário clica no link do email**
2. **Supabase valida o token** (no servidor deles)
3. **Supabase redireciona para** `agendahof://reset-password#access_token=ABC&type=recovery`
4. **iOS detecta o Custom URL Scheme** `agendahof://`
5. **iOS abre o Agenda HOF App**
6. **App processa o deep link** ([AgendaHofApp.swift:27-106](AgendaHofApp.swift))
7. **App extrai o token** do fragment `#access_token=ABC&type=recovery`
8. **App abre a tela** `ResetPasswordView` com o token
9. **Usuário define nova senha** ✅

---

## ✅ Checklist

- [ ] Adicionar variável `MOBILE_APP_URL=agendahof://reset-password` no Railway
- [ ] Aguardar redeploy automático do Railway
- [ ] Atualizar `backend/server.js` linha 376
- [ ] Atualizar `backend/routes/auth.js` linha 525
- [ ] Commit e push das mudanças
- [ ] Testar solicitação de recuperação de senha
- [ ] Verificar que o link abre o app (não o Safari)
- [ ] Verificar que o token é extraído corretamente
- [ ] Verificar que a senha pode ser alterada

---

## 🚨 Importante

### Fallback para Web

O código usa **fallback** para garantir compatibilidade:

```javascript
process.env.MOBILE_APP_URL || `${process.env.FRONTEND_URL}/reset-password`
```

**Se `MOBILE_APP_URL` não estiver definida:**
- Usa `FRONTEND_URL` (site)
- Mantém funcionamento atual

**Se `MOBILE_APP_URL` estiver definida:**
- Usa o Custom URL Scheme (app)
- Novo comportamento ✅

### Compatibilidade

Esta mudança **NÃO quebra** o web app:
- Usuários do site continuam funcionando
- Apenas usuários do app mobile terão a experiência melhorada
- O app mobile já suporta ambos os formatos de URL

---

## 📚 Referências

- **Custom URL Scheme:** `agendahof://`
- **Bundle ID:** `com.agendahof.swift`
- **Team ID:** `J5YU2V26FV`
- **Domain:** `agendahof.com`

**Arquivos do App iOS:**
- Deep Link Handler: [AgendaHofApp.swift:27-106](AgendaHofApp.swift)
- Reset Password View: [Views/Auth/ResetPasswordView.swift](Views/Auth/ResetPasswordView.swift)
- Reset Password ViewModel: [ViewModels/ResetPasswordViewModel.swift](ViewModels/ResetPasswordViewModel.swift)

**Arquivos do Backend:**
- Server principal: `backend/server.js` (linha 343-487)
- Rotas de auth: `backend/routes/auth.js` (linha 513-550)

---

**Data:** 2024-12-23
**Autor:** Claude Code Assistant
**Projeto:** Agenda HOF - Deep Linking Implementation
