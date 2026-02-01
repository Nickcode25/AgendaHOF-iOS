// Supabase Edge Function: send-daily-financial-notification
// Sends push notifications with financial summary at 21:00 daily
// 
// Deploy: supabase functions deploy send-daily-financial-notification --no-verify-jwt

import { serve } from "https://deno.land/std@0.168.0/http/server.ts"
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'
import { create, getNumericDate } from "https://deno.land/x/djwt@v2.8/mod.ts"

// APNs configuration from Supabase secrets
const APNS_KEY_ID = Deno.env.get('APNS_KEY_ID')!
const APNS_TEAM_ID = Deno.env.get('APNS_TEAM_ID')!
const APNS_KEY_PEM = Deno.env.get('APNS_KEY')!
const APNS_TOPIC = 'com.agendahof.swift' // Bundle ID
const APNS_ENDPOINT = Deno.env.get('APNS_ENDPOINT') || 'https://api.push.apple.com'

console.log('🚀 Edge Function initialized')
console.log('APNs Endpoint:', APNS_ENDPOINT)

serve(async (req) => {
  try {
    console.log('📨 Received request to send daily financial notifications')

    // Initialize Supabase client with service role for full access
    const supabaseUrl = Deno.env.get('SUPABASE_URL')!
    const supabaseKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!
    const supabase = createClient(supabaseUrl, supabaseKey)

    // Get all active device tokens
    const { data: deviceTokens, error: tokensError } = await supabase
      .from('device_tokens')
      .select('device_token, environment, user_id')
      .eq('is_active', true)

    if (tokensError) {
      console.error('❌ Error fetching device tokens:', tokensError)
      throw tokensError
    }

    console.log(`✅ Found ${deviceTokens?.length || 0} active device tokens`)

    // Get user profiles to check ownership
    const userIds = [...new Set(deviceTokens?.map(t => t.user_id) || [])]
    const { data: profiles, error: profilesError } = await supabase
      .from('user_profiles')
      .select('id, role')
      .in('id', userIds)
      .eq('role', 'owner')

    if (profilesError) {
      console.error('❌ Error fetching user profiles:', profilesError)
      throw profilesError
    }

    // Filter device tokens to only include owners
    const ownerIds = new Set(profiles?.map(p => p.id) || [])
    const ownerDeviceTokens = deviceTokens?.filter(t => ownerIds.has(t.user_id)) || []

    console.log(`✅ Found ${ownerDeviceTokens.length} device tokens for ${ownerIds.size} owners`)

    // Group tokens by user to calculate financial data once per user
    const userDevices = new Map<string, any[]>()
    for (const token of ownerDeviceTokens) {
      const userId = token.user_id
      if (!userDevices.has(userId)) {
        userDevices.set(userId, [])
      }
      userDevices.get(userId)!.push(token)
    }

    let successCount = 0
    let failCount = 0

    // Process each owner
    for (const [userId, devices] of userDevices.entries()) {
      console.log(`💰 Calculating financial data for user ${userId}`)

      // Calculate today's financial data
      const financialData = await calculateFinancialData(supabase, userId)

      console.log(`  💵 Revenue: R$ ${financialData.totalRevenue} | Patients: ${financialData.patientCount}`)

      // Skip if no patients (no activity today)
      if (financialData.patientCount === 0) {
        console.log(`  ⏭️  Skipping user ${userId}: no patients today`)
        continue
      }

      // Send notification to all devices for this user
      for (const device of devices) {
        try {
          await sendPushNotification(
            device.device_token,
            financialData,
            device.environment === 'sandbox'
          )
          successCount++
          console.log(`  ✅ Sent to device ${device.device_token.substring(0, 10)}...`)
        } catch (error) {
          failCount++
          console.error(`  ❌ Failed to send to device:`, error)
        }
      }
    }

    console.log(`📊 Summary: ${successCount} sent, ${failCount} failed`)

    return new Response(
      JSON.stringify({
        success: true,
        owners: userDevices.size,
        sent: successCount,
        failed: failCount
      }),
      {
        status: 200,
        headers: { 'Content-Type': 'application/json' }
      }
    )
  } catch (error) {
    console.error('❌ Fatal error:', error)
    return new Response(
      JSON.stringify({ error: error.message }),
      {
        status: 500,
        headers: { 'Content-Type': 'application/json' }
      }
    )
  }
})

/**
 * Calculate financial data for a user for today (São Paulo timezone)
 */
async function calculateFinancialData(supabase: any, userId: string) {
  // Get today's date range in São Paulo timezone
  const now = new Date()
  const formatter = new Intl.DateTimeFormat('en-CA', {
    timeZone: 'America/Sao_Paulo',
    year: 'numeric',
    month: '2-digit',
    day: '2-digit'
  })
  const todayStr = formatter.format(now)
  const startOfDay = `${todayStr}T00:00:00-03:00`
  const endOfDay = `${todayStr}T23:59:59-03:00`

  console.log(`  📅 Date range: ${startOfDay} to ${endOfDay}`)

  // Fetch appointments for today (non-cancelled, non-personal)
  const { data: appointments, error: aptError } = await supabase
    .from('appointments')
    .select('id, procedure_id')
    .eq('user_id', userId)
    .gte('start', startOfDay)
    .lte('start', endOfDay)
    .neq('status', 'cancelled')
    .or('is_personal.is.null,is_personal.eq.false')

  if (aptError) {
    console.error('  ❌ Error fetching appointments:', aptError)
    throw aptError
  }

  const patientCount = appointments?.length || 0

  // Calculate revenue from procedures
  let totalRevenue = 0

  if (appointments && appointments.length > 0) {
    const procedureIds = appointments
      .map(apt => apt.procedure_id)
      .filter(id => id != null)

    if (procedureIds.length > 0) {
      const { data: procedures, error: procError } = await supabase
        .from('procedures')
        .select('total_cost, installments, paid_installments')
        .in('id', procedureIds)

      if (procError) {
        console.error('  ❌ Error fetching procedures:', procError)
        throw procError
      }

      // Calculate revenue (same logic as FinancialReportViewModel)
      for (const proc of procedures || []) {
        if (proc.installments && proc.installments > 1) {
          // Parceled payment: count only paid installments
          const installmentValue = proc.total_cost / proc.installments
          const paidInstallments = proc.paid_installments || 0
          totalRevenue += installmentValue * paidInstallments
        } else {
          // Full payment
          totalRevenue += proc.total_cost || 0
        }
      }
    }
  }

  return {
    patientCount,
    totalRevenue,
    formattedRevenue: formatCurrency(totalRevenue)
  }
}

/**
 * Format currency in Brazilian Real
 */
function formatCurrency(value: number): string {
  return new Intl.NumberFormat('pt-BR', {
    style: 'currency',
    currency: 'BRL'
  }).format(value)
}

/**
 * Get motivational message based on revenue and patient count
 */
function getMotivationalMessage(revenue: number, patientCount: number, formattedRevenue: string): string {
  const patientText = `Você atendeu ${patientCount} paciente${patientCount === 1 ? '' : 's'} e faturou`

  if (revenue <= 1000) return `${patientText} ${formattedRevenue} hoje. Cada passo conta! 💪`
  if (revenue <= 5000) return `Ótimo! ${patientText} ${formattedRevenue} no dia. Continue firme! 🚀`
  if (revenue <= 10000) return `Excelente! ${patientText} ${formattedRevenue} hoje. Você está arrasando! 🔥`
  if (revenue <= 15000) return `Espetacular! ${patientText} ${formattedRevenue} em um dia. Você é incrível! ⭐️`
  if (revenue <= 20000) return `Fantástico! ${patientText} ${formattedRevenue} hoje. Seu sucesso inspira! 🌟`
  if (revenue <= 25000) return `Extraordinário! ${patientText} ${formattedRevenue} em um dia. Você é referência! 👑`
  return `Simplesmente INCRÍVEL! ${patientText} ${formattedRevenue} hoje. Parabéns pelo sucesso absoluto! 🏆✨`
}

/**
 * Send push notification via APNs
 */
async function sendPushNotification(deviceToken: string, data: any, isSandbox: boolean) {
  // Generate JWT token for APNs authentication
  const jwt = await generateAPNsJWT()

  const endpoint = isSandbox
    ? 'https://api.sandbox.push.apple.com'
    : 'https://api.push.apple.com'

  const payload = {
    aps: {
      alert: {
        title: '📊 Resumo do Dia',
        body: getMotivationalMessage(data.totalRevenue, data.patientCount, data.formattedRevenue)
      },
      sound: 'default',
      badge: 1
    },
    data: {
      type: 'financial_summary',
      revenue: data.totalRevenue,
      patientCount: data.patientCount
    }
  }

  const response = await fetch(`${endpoint}/3/device/${deviceToken}`, {
    method: 'POST',
    headers: {
      'authorization': `bearer ${jwt}`,
      'apns-topic': APNS_TOPIC,
      'apns-push-type': 'alert',
      'apns-priority': '10',
      'apns-expiration': '0'
    },
    body: JSON.stringify(payload)
  })

  if (!response.ok) {
    const errorText = await response.text()
    throw new Error(`APNs error ${response.status}: ${errorText}`)
  }
}

/**
 * Generate JWT token for APNs authentication using ES256 algorithm
 * Documentation: https://developer.apple.com/documentation/usernotifications/setting_up_a_remote_notification_server/establishing_a_token-based_connection_to_apns
 */
async function generateAPNsJWT(): Promise<string> {
  try {
    // Import the private key from PEM format
    const pemHeader = "-----BEGIN PRIVATE KEY-----"
    const pemFooter = "-----END PRIVATE KEY-----"
    const pemContents = APNS_KEY_PEM
      .replace(pemHeader, "")
      .replace(pemFooter, "")
      .replace(/\s/g, "")

    // Decode base64 to binary
    const binaryDer = Uint8Array.from(atob(pemContents), c => c.charCodeAt(0))

    // Import key for ES256 (P-256) signing
    const cryptoKey = await crypto.subtle.importKey(
      "pkcs8",
      binaryDer,
      {
        name: "ECDSA",
        namedCurve: "P-256"
      },
      false,
      ["sign"]
    )

    // Create JWT header
    const header = {
      alg: "ES256" as const,
      kid: APNS_KEY_ID
    }

    // Create JWT payload
    const payload = {
      iss: APNS_TEAM_ID,
      iat: getNumericDate(new Date())
    }

    // Sign and create JWT
    const jwt = await create(header, payload, cryptoKey)

    return jwt
  } catch (error) {
    console.error('❌ Error generating APNs JWT:', error)
    throw new Error(`Failed to generate APNs JWT: ${error.message}`)
  }
}
