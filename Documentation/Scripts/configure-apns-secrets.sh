#!/bin/bash
# Configure Supabase Secrets for APNs Push Notifications
# Run this script after installing Supabase CLI and linking to your project

echo "🔐 Configurando secrets do APNs no Supabase..."

# APNs Private Key (arquivo .p8)
supabase secrets set APNS_KEY="-----BEGIN PRIVATE KEY-----
MIGTAgEAMBMGByqGSM49AgEGCCqGSM49AwEHBHkwdwIBAQQgcHKdmjC84lRtDdSi
434c0XmTK1tkTt+DW/Ny2hw62MSgCgYIKoZIzj0DAQehRANCAAQLZNOrK3JUwPgZ
n+PKSfMHTBsOysirbYbZK4MWK9hyji6bheG99HSj6rCOpWP5v9Z2CpwEvF4/Kaet
IooCkhMC
-----END PRIVATE KEY-----"

# APNs Key ID
supabase secrets set APNS_KEY_ID="N5478XK6QR"

# APNs Team ID
supabase secrets set APNS_TEAM_ID="J5YU2V26FV"

# APNs Endpoint (production)
supabase secrets set APNS_ENDPOINT="https://api.push.apple.com"

echo "✅ Secrets configurados com sucesso!"
echo ""
echo "Para verificar os secrets configurados, execute:"
echo "  supabase secrets list"
