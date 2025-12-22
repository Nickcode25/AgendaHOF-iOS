# Deep Linking - Configuração Completa

## ✅ Implementado no Código

O código Swift já está 100% implementado e pronto. Você só precisa fazer as configurações externas abaixo.

---

## 📋 Checklist de Configuração

### 1. Supabase Dashboard

Acesse: **Supabase Dashboard → Authentication → URL Configuration**

Configure:

**Redirect URLs:**
```
https://agendahof.com/reset-password
https://agendahof.com/auth/callback
```

**Site URL:**
```
https://agendahof.com
```

---

### 2. Apple App Site Association (AASA)

**Passo 1:** Encontre seu Apple Team ID no [Apple Developer Portal](https://developer.apple.com/account/)

**Passo 2:** Crie o arquivo JSON substituindo `TEAM_ID` pelo seu Team ID real:

```json
{
  "applinks": {
    "apps": [],
    "details": [
      {
        "appID": "TEAM_ID.com.agendahof.app",
        "paths": [
          "/reset-password",
          "/reset-password/*",
          "/auth/callback",
          "/auth/callback/*"
        ]
      }
    ]
  }
}
```

**Passo 3:** Hospede este arquivo em:
```
https://agendahof.com/.well-known/apple-app-site-association
```

**Requisitos do servidor:**
- ✅ Content-Type: `application/json`
- ✅ HTTPS obrigatório
- ✅ Sem redirecionamento
- ✅ Acessível sem autenticação
- ✅ Sem extensão .json no nome do arquivo

**Teste a configuração:**
```bash
curl -I https://agendahof.com/.well-known/apple-app-site-association
```

Deve retornar `200 OK` e `Content-Type: application/json`

---

### 3. Xcode - Associated Domains

**Passo 1:** Abra o projeto no Xcode

**Passo 2:** Selecione o projeto "AgendaHOF" no navegador

**Passo 3:** Vá em: **Target → AgendaHOF → Signing & Capabilities**

**Passo 4:** Clique em **"+ Capability"** no topo

**Passo 5:** Adicione **"Associated Domains"**

**Passo 6:** Clique no **"+"** dentro de Associated Domains e adicione:
```
applinks:agendahof.com
```

**IMPORTANTE:** Não inclua `https://` nem `www.` no domínio.

---

## 🧪 Como Testar

### Teste 1: Custom URL Scheme (já funciona)
Abra este link no Safari do iPhone:
```
agendahof://reset-password?access_token=test123&type=recovery
```

Deve abrir o app.

### Teste 2: Universal Link (após configurar AASA)
Abra este link no Safari do iPhone:
```
https://agendahof.com/reset-password#access_token=test123&type=recovery
```

Deve abrir o app (não o navegador).

### Teste 3: Email Real
1. No app, vá em "Esqueci minha senha"
2. Digite seu email
3. Verifique o email recebido
4. Clique no link
5. Deve abrir o app (não o navegador)

---

## 🔍 Debug

O app já possui logs detalhados. Para ver os logs:

**Xcode Console:**
```
🔗 [Deep Link] Received URL: https://agendahof.com/reset-password#access_token=xxxxx
🔗 [Deep Link] Path: /reset-password
🔗 [Deep Link] Query Items: [...]
✅ [Deep Link] Token extraído com sucesso (type: recovery)
```

**Se aparecer:**
```
❌ [Deep Link] Token não encontrado na URL
```

Significa que o formato da URL está incorreto. Verifique a configuração do Supabase.

---

## 📱 Como Funciona

### 1. Usuário clica no link do email
```
https://agendahof.com/reset-password#access_token=ABC123&type=recovery
```

### 2. iOS verifica o AASA
O iOS consulta:
```
https://agendahof.com/.well-known/apple-app-site-association
```

### 3. iOS abre o app
Se o AASA estiver correto, o iOS abre o app em vez do navegador.

### 4. App processa o link
- `AppDelegate.application(_:continue:)` recebe o URL
- `.onOpenURL()` no `AgendaHofApp` processa o token
- Abre a tela `ResetPasswordView` com o token

### 5. Usuário redefine a senha
- View valida o token com Supabase
- Usuário digita nova senha
- App atualiza a senha via `auth.verifyOTP()` + `auth.update()`

---

## 🚨 Troubleshooting

### Problema: Link abre o navegador em vez do app

**Solução 1:** Verifique se o AASA está acessível
```bash
curl https://agendahof.com/.well-known/apple-app-site-association
```

**Solução 2:** Verifique se o Team ID está correto no AASA

**Solução 3:** Reinstale o app (iOS baixa o AASA na instalação)

**Solução 4:** Aguarde até 24h (iOS faz cache do AASA)

**Solução 5:** Teste em modo privado do Safari

---

### Problema: Token não é extraído da URL

**Causa:** Supabase pode estar enviando o token em diferentes formatos:
- Query string: `?access_token=xxx`
- Fragment: `#access_token=xxx`
- Parâmetro antigo: `?token=xxx`

**Solução:** O código já suporta todos os formatos. Verifique os logs no Xcode Console.

---

### Problema: Erro "Link expirado"

**Causa:** Tokens de recuperação expiram em 1 hora (configuração padrão do Supabase)

**Solução:** Solicite um novo link de recuperação

---

## 📚 Referências

- [Apple Universal Links](https://developer.apple.com/ios/universal-links/)
- [Supabase Auth](https://supabase.com/docs/guides/auth)
- [AASA Validator](https://branch.io/resources/aasa-validator/)

---

## ✅ Status

- ✅ Custom URL Scheme (`agendahof://`) - **JÁ FUNCIONA**
- ⚠️ Universal Links (`https://agendahof.com/...`) - **REQUER CONFIGURAÇÃO EXTERNA**
  - [ ] Configurar Redirect URLs no Supabase
  - [ ] Hospedar arquivo AASA no servidor
  - [ ] Adicionar Associated Domains no Xcode

---

**Bundle ID:** `com.agendahof.app`
**Domain:** `agendahof.com`
**Custom Scheme:** `agendahof://`
