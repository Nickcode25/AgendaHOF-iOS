# ✅ Checklist de Teste - Reset de Senha Corrigido

## 🎯 Objetivo
Verificar se a correção do token OTP resolveu o problema de expiração imediata.

---

## 📋 Pré-requisitos

- [ ] Backend atualizado com as mudanças em `server.js` e `routes/auth.js`
- [ ] Railway fez o deploy (verifique o log de deploy)
- [ ] App iOS rodando no Xcode com console aberto (Cmd+Shift+Y)
- [ ] Email válido para teste

---

## 🧪 Teste 1: Fluxo Completo de Recuperação

### Passo 1: Solicitar Recuperação
1. [ ] Abrir o app iOS
2. [ ] Tocar em "Esqueci minha senha"
3. [ ] Digitar email válido
4. [ ] Tocar em "Enviar link de recuperação"

**Verificar console:**
```
✅ Deve aparecer confirmação de que email foi enviado
```

---

### Passo 2: Verificar Email
1. [ ] Abrir inbox do email
2. [ ] Verificar se email chegou com assunto: "🔑 Redefinir sua senha - Agenda HOF"
3. [ ] Verificar se o design do email está bonito (template HTML)

**Verificar link no email:**
- [ ] Link deve começar com: `https://zgdxszwjbbxepsvyjtrb.supabase.co/auth/v1/verify?token=...`
- [ ] Link deve ter parâmetro `&type=recovery`
- [ ] Link deve ter parâmetro `&redirect_to=agendahof://reset-password`

**❌ Se o link estiver diferente:**
- Se começar com `...&access_token=...` → Backend não foi atualizado corretamente
- Se não tiver `redirect_to=agendahof://` → Variável MOBILE_APP_SCHEME não está configurada

---

### Passo 3: Clicar no Link (IMEDIATAMENTE)
1. [ ] Clicar no botão "Redefinir minha senha" no email
2. [ ] Aguardar app abrir

**Verificar console do Xcode:**
```
🔗 [Deep Link] Received URL: agendahof://reset-password#access_token=eyJhbG...
✅ [Deep Link] Token extraído com sucesso!
   - Token: eyJhbGciOiJIUzI1NiIs...
   - Type: recovery
🔨 [ResetPasswordView] Init chamado com token: eyJhbGciOiJIUzI1NiIs...
🎬 [ContentView] Sheet ResetPasswordView apareceu!
📱 [ResetPasswordView] Mostrando: Formulário
```

**Resultado esperado:**
- [ ] App abre automaticamente (não Safari)
- [ ] Tela de "Redefinir Senha" aparece
- [ ] Formulário com 2 campos de senha visível

---

### Passo 4: Redefinir Senha
1. [ ] Digitar nova senha forte (ex: `Teste@123456`)
   - Mínimo 8 caracteres
   - 1 maiúscula
   - 1 minúscula
   - 1 número
   - 1 caractere especial
2. [ ] Confirmar senha (repetir exatamente)
3. [ ] Deixar "Desconectar de todos os dispositivos" marcado
4. [ ] Clicar em "Redefinir Senha"

**Verificar console do Xcode:**
```
🔐 [ResetPassword] Iniciando reset de senha...
   - Token: eyJhbGciOiJIUzI1NiIs...
   - Logout todos dispositivos: true
🔐 [ResetPassword] Passo 1: Verificando token com verifyOTP...
✅ [ResetPassword] Passo 1: Token verificado com sucesso!
   - User ID: 502f0090-d7ea-4310-8361-4869a70bcb10
   - Email: seu@email.com
🔐 [ResetPassword] Passo 2: Verificando senha duplicada...
   - Senha duplicada: false
🔐 [ResetPassword] Passo 3: Atualizando senha...
✅ [ResetPassword] Passo 3: Senha atualizada com sucesso!
🔐 [ResetPassword] Passo 4: Adicionando ao histórico...
✅ [ResetPassword] Passo 4: Histórico atualizado!
🔐 [ResetPassword] Passo 5: Enviando email de notificação...
✅ [ResetPassword] Passo 5: Email enviado!
🔐 [ResetPassword] Passo 6: Fazendo logout de outros dispositivos...
✅ [ResetPassword] Passo 6: Sessões antigas invalidadas!
🎉 [ResetPassword] Reset de senha concluído com sucesso!
```

**Resultado esperado:**
- [ ] Todos os passos aparecem com ✅
- [ ] **NÃO deve aparecer erro "otp_expired"** ← CHAVE DO TESTE
- [ ] Tela de sucesso aparece
- [ ] Mensagem de confirmação visível

---

### Passo 5: Fazer Login com Nova Senha
1. [ ] Voltar para tela de login
2. [ ] Digitar email
3. [ ] Digitar a **nova senha** (ex: `Teste@123456`)
4. [ ] Clicar em "Entrar"

**Resultado esperado:**
- [ ] Login com sucesso
- [ ] App abre normalmente
- [ ] Usuário logado

---

## 🧪 Teste 2: Token com Tempo (Opcional mas Recomendado)

### Objetivo: Verificar que o token é válido por 1 hora completa

1. [ ] Solicitar nova recuperação de senha
2. [ ] Abrir email
3. [ ] **AGUARDAR 10-15 minutos** sem clicar no link
4. [ ] Clicar no link após esperar
5. [ ] Redefinir senha

**Resultado esperado:**
- [ ] Token ainda válido após 10-15 minutos
- [ ] Reset de senha funciona normalmente
- [ ] Todos os passos com ✅ no console

**❌ Se falhar:**
- Token ainda expira rapidamente → Backend não foi atualizado corretamente

---

## 🧪 Teste 3: Email de Notificação

### Objetivo: Verificar que email de notificação é enviado após reset

1. [ ] Após redefinir senha com sucesso
2. [ ] Abrir inbox do email
3. [ ] Verificar se chegou email: "🔒 Sua senha foi alterada - Agenda HOF"

**Verificar email:**
- [ ] Assunto correto
- [ ] Design bonito (template HTML)
- [ ] Mostra data/hora da alteração
- [ ] Mostra dispositivo/IP
- [ ] Tem botão "Redefinir senha novamente"
- [ ] Tem botão "Relatar problema"

---

## ❌ Troubleshooting

### Erro: "otp_expired" ainda aparece

**Possíveis causas:**
1. Backend não foi atualizado corretamente
   - Verificar no código se está extraindo `token` (não `action_link`)
   - Verificar logs do Railway: `railway logs`

2. Cache do email
   - Email antigo ainda estava na inbox
   - Solicitar **novo** email de recuperação

3. Token já foi usado antes
   - Tokens OTP só podem ser usados uma vez
   - Solicitar novo email

---

### Erro: Link abre Safari, não o app

**Solução:**
1. Deletar o app completamente
2. Reiniciar iPhone
3. Reinstalar app do Xcode
4. iOS vai re-baixar o AASA file

---

### Erro: "Token não encontrado na URL"

**Causa:** Backend enviou link incorreto

**Verificar:**
1. Abrir email recebido
2. Inspecionar o link (clicar e segurar → copiar link)
3. Verificar se tem `#access_token=...` ou `?token=...`

**Link correto deve ter:**
```
https://zgdxszwjbbxepsvyjtrb.supabase.co/auth/v1/verify?token=ABC123&type=recovery&redirect_to=agendahof://reset-password
```

**Depois do redirect, app recebe:**
```
agendahof://reset-password#access_token=eyJhbG...&type=recovery
```

---

## 📊 Resultados Esperados vs Reais

| Teste | Resultado Esperado | Resultado Real | Status |
|-------|-------------------|----------------|--------|
| 1. Solicitar recuperação | Email enviado | | ⬜ |
| 2. Email chega | Sim, com template bonito | | ⬜ |
| 3. Link correto | `/auth/v1/verify?token=...` | | ⬜ |
| 4. App abre | Sim, automaticamente | | ⬜ |
| 5. Formulário aparece | Sim, com 2 campos | | ⬜ |
| 6. Passo 1: verifyOTP | ✅ Sucesso | | ⬜ |
| 7. Passo 2: Duplicada | ✅ Não duplicada | | ⬜ |
| 8. Passo 3: Atualizar | ✅ Sucesso | | ⬜ |
| 9. Passo 4: Histórico | ✅ Sucesso | | ⬜ |
| 10. Passo 5: Email notif | ✅ Sucesso | | ⬜ |
| 11. Passo 6: Logout | ✅ Sucesso | | ⬜ |
| 12. Tela sucesso | Aparece | | ⬜ |
| 13. Login nova senha | Sucesso | | ⬜ |
| 14. Token após 15min | Ainda válido | | ⬜ |
| 15. Email notificação | Recebido | | ⬜ |

---

## ✅ Critério de Sucesso

**O fix está funcionando se:**
- ✅ Token NÃO expira imediatamente
- ✅ Todos os passos do reset aparecem com ✅
- ✅ NÃO aparece erro "otp_expired" ao resetar
- ✅ Login com nova senha funciona

**Status Final:** ⬜ PENDENTE | ✅ SUCESSO | ❌ FALHOU

---

**Data do teste:** ___/___/___
**Testado por:** _______________
**Versão do backend:** _______________
**Resultado:** ⬜ PENDENTE
