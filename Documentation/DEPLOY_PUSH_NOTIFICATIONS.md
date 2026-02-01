# Deploy Guide - Push Notification System

## Pré-requisitos Completos ✅

- ✅ Credenciais APNs configuradas
- ✅ Database migration executada
- ✅ Cron job agendado
- ✅ Edge Function com JWT implementado

---

## Passo 1: Configurar Secrets no Supabase

Execute o script que criei:

```bash
cd /Volumes/Untitled/AgendaHOF-iOS
./Documentation/Scripts/configure-apns-secrets.sh
```

Ou configure manualmente:

```bash
supabase secrets set APNS_KEY="-----BEGIN PRIVATE KEY-----
MIGTAgEAMBMGByqGSM49AgEGCCqGSM49AwEHBHkwdwIBAQQgcHKdmjC84lRtDdSi
434c0XmTK1tkTt+DW/Ny2hw62MSgCgYIKoZIzj0DAQehRANCAAQLZNOrK3JUwPgZ
n+PKSfMHTBsOysirbYbZK4MWK9hyji6bheG99HSj6rCOpWP5v9Z2CpwEvF4/Kaet
IooCkhMC
-----END PRIVATE KEY-----"

supabase secrets set APNS_KEY_ID="N5478XK6QR"
supabase secrets set APNS_TEAM_ID="J5YU2V26FV"
supabase secrets set APNS_ENDPOINT="https://api.push.apple.com"
```

**Verificar secrets**:
```bash
supabase secrets list
```

---

## Passo 2: Deploy da Edge Function

```bash
cd /Volumes/Untitled/AgendaHOF-iOS

# Deploy da função
supabase functions deploy send-daily-financial-notification --no-verify-jwt
```

**Output esperado**:
```
Deploying function send-daily-financial-notification...
✓ Function deployed successfully
Function URL: https://your-project.supabase.co/functions/v1/send-daily-financial-notification
```

---

## Passo 3: Testar a Função Manualmente

### 3.1 Build e Instalar o App

1. **Xcode**: Build do app (Debug ou Release)
2. **Instalar** no dispositivo ou simulador
3. **Fazer login** no app
4. **Verificar logs** no Xcode Console:
   ```
   ✅ Device token recebido: abc123...
   ✅ Device token armazenado no Supabase
   ```

### 3.2 Verificar Token no Supabase

No **SQL Editor**:
```sql
SELECT * FROM device_tokens ORDER BY created_at DESC LIMIT 5;
```

Deve retornar algo como:
```
id | user_id | device_token | platform | environment | is_active
---|---------|--------------|----------|-------------|----------
... | ...    | abc123...    | ios      | sandbox     | true
```

### 3.3 Trigger Manual da Edge Function

Obtenha sua **Service Role Key** em: Project Settings > API > service_role (secret)

```bash
curl -X POST 'https://YOUR_PROJECT_REF.supabase.co/functions/v1/send-daily-financial-notification' \
  -H "Authorization: Bearer YOUR_SERVICE_ROLE_KEY" \
  -H "Content-Type: application/json"
```

**Substitua**:
- `YOUR_PROJECT_REF.supabase.co` com sua URL do Supabase
- `YOUR_SERVICE_ROLE_KEY` com a service role key

**Output esperado**:
```json
{
  "success": true,
  "owners": 1,
  "sent": 1,
  "failed": 0
}
```

### 3.4 Verificar Notificação no Dispositivo

- ✅ Notificação deve aparecer no dispositivo
- ✅ Título: "📊 Resumo do Dia"
- ✅ Mensagem com dados financeiros do dia

---

## Passo 4: Verificar Logs da Edge Function

```bash
supabase functions logs send-daily-financial-notification --tail
```

ou via dashboard Supabase: Edge Functions > send-daily-financial-notification > Logs

---

## Passo 5: Verificar Execução do Cron (21:00)

Amanhã às 21:00, a notificação deve ser enviada automaticamente.

**Verificar histórico do cron**:
```sql
SELECT * FROM cron.job_run_details 
WHERE jobid = (SELECT jobid FROM cron.job WHERE jobname = 'daily-financial-notification')
ORDER BY start_time DESC
LIMIT 10;
```

---

## Troubleshooting

### Erro: "Failed to generate APNs JWT"

**Causa**: Problema ao importar/assinar com a chave privada

**Solução**:
1. Verificar se `APNS_KEY` foi configurado corretamente (com `-----BEGIN/END-----`)
2. Verificar logs da Edge Function: `supabase functions logs ...`

### Notificação não chegou

**Debug checklist**:
1. ✅ Device token está na tabela? `SELECT * FROM device_tokens WHERE is_active = true`
2. ✅ Edge Function foi chamada? Verificar logs
3. ✅ Ambiente correto? (sandbox para Debug, production para Release)
4. ✅ Dados financeiros? Usuário teve pacientes hoje?

### Erro 400/403 do APNs

**Causas comuns**:
- Bundle ID incorreto (deve ser `com.agendahof.app`)
- Ambiente errado (sandbox vs production)
- Token expirado ou inválido
- Certificado APNs não configurado corretamente

---

## Próximos Passos

1. ✅ Fazer deploy seguindo este guia
2. ✅ Testar manualmente hoje
3. ✅ Aguardar notificação automática amanhã às 21:00
4. ✅ Monitorar logs por 2-3 dias
5. ✅ Build de produção e testar via TestFlight

---

## Comandos Úteis

```bash
# Ver secrets configurados
supabase secrets list

# Atualizar Edge Function
supabase functions deploy send-daily-financial-notification --no-verify-jwt

# Ver logs em tempo real
supabase functions logs send-daily-financial-notification --tail

# Deletar secret (se necessário)
supabase secrets unset APNS_KEY

# Ver status do cron job
# Executar no SQL Editor:
SELECT * FROM cron.job WHERE jobname = 'daily-financial-notification';
```

---

## Sucesso! 🎉

Se tudo funcionou:
- ✅ Device token registrado no Supabase
- ✅ Edge Function executada sem erros
- ✅ Notificação recebida no dispositivo
- ✅ Dados financeiros corretos

**Sistema pronto para produção!** As notificações serão enviadas automaticamente todos os dias às 21:00 com dados precisos e atualizados.
