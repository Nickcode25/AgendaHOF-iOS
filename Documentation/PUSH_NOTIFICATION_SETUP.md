# Push Notification Backend Setup Guide

## Overview

Este guia explica como configurar o backend de push notifications usando Supabase Edge Functions e pg_cron.

## Pré-requisitos

1. **Conta Apple Developer** (necessária para gerar chaves APNs)
2. **Supabase CLI** instalado (`npm install -g supabase`)
3. **Acesso ao projeto Supabase** (Admin)

---

## Passo 1: Configurar APNs (Apple Push Notification Service)

### 1.1 Criar Chave APNs no Apple Developer Portal

1. Acesse [developer.apple.com](https://developer.apple.com)
2. Vá para **Certificates, Identifiers & Profiles**
3. Clique em **Keys** no menu lateral
4. Clique no botão **+** para criar uma nova chave
5. Dê um nome (ex: "AgendaHOF Push Notifications")
6. Marque a opção **Apple Push Notifications service (APNs)**
7. Clique em **Continue** e depois **Register**
8. **Baixe o arquivo `.p8`** (você NÃO poderá baixar novamente!)
9. **Anote o Key ID** (aparece na tela)
10. **Anote o Team ID** (encontrado em Membership no menu lateral)

### 1.2 Habilitar Push Notifications no Xcode

1. Abra o projeto `AgendaHOF-iOS` no Xcode
2. Selecione o target principal
3. Vá para **Signing & Capabilities**
4. Clique em **+ Capability**
5. Adicione **Push Notifications**
6. (Já está configurado no Info.plist: `UIBackgroundModes` inclui `remote-notification`)

---

## Passo 2: Deploy da Edge Function

### 2.1 Estrutura de Arquivos

A Edge Function está localizada em:
```
Documentation/EdgeFunctions/send-daily-financial-notification/
├── index.ts          # Função principal
├── apns.ts           # Lógica de APNs (JWT e envio)
└── financial.ts      # Cálculo financeiro
```

### 2.2 Instalar Dependências Locais (para desenvolvimento)

```bash
cd Documentation/EdgeFunctions/send-daily-financial-notification
deno cache --reload index.ts
```

### 2.3 Fazer Deploy da Edge Function

```bash
# Login no Supabase CLI (se ainda não estiver logado)
supabase login

# Link ao projeto
supabase link --project-ref your-project-ref

# Deploy da função
supabase functions deploy send-daily-financial-notification --no-verify-jwt
```

**Nota**: `--no-verify-jwt` é necessário porque a função será chamada pelo cron com service role key.

### 2.4 Configurar Secrets da Edge Function

```bash
# Configurar chave APNs (conteúdo do arquivo .p8)
supabase secrets set APNS_KEY="-----BEGIN PRIVATE KEY-----
MIGTAgEAMBMGByqGSM49AgEGCCqGSM49AwEHBHkwdwIBAQQg...
-----END PRIVATE KEY-----"

# Configurar Key ID (da tela do Apple Developer)
supabase secrets set APNS_KEY_ID="ABC123DEF4"

# Configurar Team ID (da página Membership no Apple Developer)
supabase secrets set APNS_TEAM_ID="XYZ9876543"

# Endpoint do APNs (production)
supabase secrets set APNS_ENDPOINT="https://api.push.apple.com"

# Para ambiente de desenvolvimento/sandbox, use:
# supabase secrets set APNS_ENDPOINT="https://api.sandbox.push.apple.com"
```

**Verificar secrets configurados**:
```bash
supabase secrets list
```

---

## Passo 3: Criar Tabela de Device Tokens

Execute o SQL no **Supabase SQL Editor**:

```sql
-- Copiar e colar o conteúdo de:
-- Documentation/Migrations/create_device_tokens_table.sql
```

Ou via CLI:
```bash
supabase db push --file Documentation/Migrations/create_device_tokens_table.sql
```

---

## Passo 4: Configurar Vault e Cron Job

### 4.1 Armazenar URL e Service Role Key no Vault

No **Supabase SQL Editor**, execute (substitua os valores):

```sql
-- URL do projeto
SELECT vault.create_secret(
  'https://your-project-ref.supabase.co', 
'supabase_url'
);

-- Service Role Key (encontrado em Project Settings > API)
SELECT vault.create_secret(
  'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9...',
  'service_role_key'
);
```

### 4.2 Agendar Execução Diária com pg_cron

Execute no **Supabase SQL Editor**:

```sql
-- Copiar e colar o conteúdo de:
-- Documentation/Migrations/schedule_daily_notification_cron.sql
```

**Observação**: O cron está configurado para `0 0 * * *` (00:00 UTC), que corresponde a 21:00 horário de Brasília (UTC-3).

---

## Passo 5: Testar a Implementação

### 5.1 Teste Manual da Edge Function

```bash
# Via curl
curl -X POST 'https://your-project-ref.supabase.co/functions/v1/send-daily-financial-notification' \
  -H "Authorization: Bearer YOUR_SERVICE_ROLE_KEY" \
  -H "Content-Type: application/json"
```

### 5.2 Verificar Logs da Edge Function

```bash
supabase functions logs send-daily-financial-notification --tail
```

### 5.3 Verificar Execução do Cron Job

```sql
-- Ver histórico de execuções
SELECT * FROM cron.job_run_details 
WHERE jobid = (SELECT jobid FROM cron.job WHERE jobname = 'daily-financial-notification')
ORDER BY start_time DESC
LIMIT 10;
```

### 5.4 Teste no iOS App

1. **Instalar o app** (Debug ou TestFlight)
2. **Fazer login** (registra device token automaticamente)
3. **Verificar no Supabase** se o token foi armazenado:
   ```sql
   SELECT * FROM device_tokens ORDER BY created_at DESC;
   ```
4. **Trigger manual** da função para testar notificação:
   ```bash
   curl -X POST 'https://your-project.supabase.co/functions/v1/send-daily-financial-notification' \
     -H "Authorization: Bearer SERVICE_ROLE_KEY"
   ```
5. **Verificar se a notificação chegou** no dispositivo

---

## Troubleshooting

### Notificação não chegou

1. **Verificar device token no banco**:
   ```sql
   SELECT * FROM device_tokens WHERE user_id = 'user-uuid';
   ```

2. **Verificar logs da Edge Function**:
   ```bash
   supabase functions logs send-daily-financial-notification
   ```

3. **Verificar ambiente correto** (sandbox vs production):
   - Debug builds: usar `APNS_ENDPOINT=https://api.sandbox.push.apple.com`
   - Production builds: usar `APNS_ENDPOINT=https://api.push.apple.com`

4. **Verificar certificado APNs**:
   - Key ID e Team ID corretos?
   - Arquivo `.p8` copiado corretamente (incluindo `-----BEGIN/END-----`)?

### Cron job não está executando

1. **Verificar se está agendado**:
   ```sql
   SELECT * FROM cron.job WHERE jobname = 'daily-financial-notification';
   ```

2. **Verificar histórico de erros**:
   ```sql
   SELECT * FROM cron.job_run_details 
   WHERE jobid = (SELECT jobid FROM cron.job WHERE jobname = 'daily-financial-notification')
   AND status = 'failed'
   ORDER BY start_time DESC;
   ```

3. **Testar manualmente** a função via curl (ver seção 5.1)

### Device token não está sendo salvo

1. **Verificar logs do app** no Xcode Console
2. **Verificar RLS policies** na tabela `device_tokens`
3. **Verificar permissões** do usuário autenticado

---

## Manutenção

### Atualizar Edge Function

```bash
supabase functions deploy send-daily-financial-notification
```

### Desagendar Cron Job

```sql
SELECT cron.unschedule('daily-financial-notification');
```

### Limpar tokens inativos antigos

```sql
DELETE FROM device_tokens 
WHERE is_active = false 
AND updated_at < NOW() - INTERVAL '30 days';
```

---

## Custos

- **Edge Functions**: Free tier (500K invocations/mês)
- **pg_cron**: Incluído no Supabase
- **APNs**: Gratuito (serviço da Apple)
- **Database storage**: Mínimo (~1KB por device token)

**Custo total**: R$ 0 para uso normal
