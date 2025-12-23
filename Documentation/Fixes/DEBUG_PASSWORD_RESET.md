# 🔍 Debug: Password Reset Error Investigation

## 🎯 PROBLEMA IDENTIFICADO! ✅

### Erro Encontrado:
```
❌ [ResetPassword] ERRO ao resetar senha:
   - AuthError: "Email link is invalid or has expired"
   - errorCode: "otp_expired"
   - Status Code: 403
```

### Causa Raiz:
O **backend está gerando tokens incorretamente** usando `admin.generateLink()` com `access_token` JWT direto, causando problemas de timezone.

**Token criado:** 08:32 GMT
**Token usado:** 11:33 GMT (3 horas depois!)
**Resultado:** Token já expirado ❌

### Solução:
O backend precisa usar `resetPasswordForEmail()` em vez de `admin.generateLink()`.

📄 **Veja instruções completas em:** [BACKEND_TOKEN_FIX.md](BACKEND_TOKEN_FIX.md)

---

## 📝 O Que Foi Adicionado no App

Adicionei **logs detalhados** no arquivo `ViewModels/ResetPasswordViewModel.swift` para identificar exatamente onde o erro está ocorrendo no processo de redefinição de senha.

## 🔬 Logs Adicionados

Agora, quando você tentar redefinir a senha, verá logs detalhados de cada passo:

### Passo 1: Verificação do Token
```
🔐 [ResetPassword] Passo 1: Verificando token com verifyOTP...
```

Se der sucesso:
```
✅ [ResetPassword] Passo 1: Token verificado com sucesso!
   - User ID: abc123...
   - Email: seu@email.com
```

### Passo 2: Verificação de Senha Duplicada
```
🔐 [ResetPassword] Passo 2: Verificando senha duplicada...
   - Senha duplicada: false
```

### Passo 3: Atualização da Senha
```
🔐 [ResetPassword] Passo 3: Atualizando senha...
✅ [ResetPassword] Passo 3: Senha atualizada com sucesso!
```

### Passo 4: Histórico de Senhas
```
🔐 [ResetPassword] Passo 4: Adicionando ao histórico...
✅ [ResetPassword] Passo 4: Histórico atualizado!
```

### Passo 5: Email de Notificação
```
🔐 [ResetPassword] Passo 5: Enviando email de notificação...
✅ [ResetPassword] Passo 5: Email enviado!
```

### Passo 6: Logout de Outros Dispositivos
```
🔐 [ResetPassword] Passo 6: Fazendo logout de outros dispositivos...
✅ [ResetPassword] Passo 6: Sessões antigas invalidadas!
```

### Se Houver Erro
```
❌ [ResetPassword] ERRO ao resetar senha:
   - Tipo: <tipo do erro>
   - Descrição: <descrição completa>
   - LocalizedDescription: <mensagem localizada>
   - AuthError específico: <detalhes do Supabase>
<dump completo do erro>
```

## 🧪 Como Testar

1. **Solicite um novo link de recuperação:**
   - No app, toque em "Esqueceu?"
   - Digite seu email
   - Toque em "Enviar link de recuperação"

2. **Abra o link no email**
   - Link abrirá o app automaticamente
   - ResetPasswordView aparecerá

3. **Preencha o formulário:**
   - Nova senha (mínimo 8 caracteres, 1 maiúscula, 1 minúscula, 1 número, 1 especial)
   - Confirmar senha (deve ser igual)
   - Deixe marcado "Desconectar de todos os dispositivos"

4. **Clique em "Redefinir Senha"**

5. **IMPORTANTE: Capture os logs do console no Xcode**
   - Abra o Console (View → Debug Area → Activate Console ou `Cmd+Shift+Y`)
   - Procure pelos logs que começam com `🔐 [ResetPassword]`
   - **Copie TODOS os logs do reset** (desde "Iniciando reset de senha..." até o erro)

## 📊 O Que Esperar

Com esses logs, poderemos identificar **exatamente** onde está falhando:

### Cenário 1: Erro no Passo 1 (verifyOTP)
**Possíveis causas:**
- Token realmente expirado (mas você disse que usou imediatamente)
- Token já foi usado antes
- Formato do token incorreto
- Problema de comunicação com Supabase

### Cenário 2: Erro no Passo 2 (Senha Duplicada)
**Possíveis causas:**
- Backend não está respondendo
- Senha já foi usada recentemente

### Cenário 3: Erro no Passo 3 (Atualizar Senha)
**Possíveis causas:**
- Sessão inválida após verifyOTP
- Senha não atende requisitos do Supabase
- Problema de rede

### Cenário 4: Erro nos Passos 4-6
**Possíveis causas:**
- Backend offline ou com erro
- Problemas menores que não deveriam bloquear o reset

## 🎯 Próximos Passos

1. **Execute o teste completo** conforme descrito acima
2. **Capture os logs completos** do console do Xcode
3. **Me envie os logs** - especialmente a parte que mostra o erro:
   ```
   ❌ [ResetPassword] ERRO ao resetar senha:
   ```

Com esses logs detalhados, vou conseguir identificar **exatamente** qual é o problema e corrigi-lo! 🎯

---

**Arquivo modificado:** [ViewModels/ResetPasswordViewModel.swift](ViewModels/ResetPasswordViewModel.swift) (linhas 55-175)

**Status:** ✅ Pronto para teste
