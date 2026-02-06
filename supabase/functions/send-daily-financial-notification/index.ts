// Supabase Edge Function: send-daily-financial-notification
// Sends push notifications with financial summary at 21:00 daily
// 
// Deploy: supabase functions deploy send-daily-financial-notification --no-verify-jwt

import { serve } from "https://deno.land/std@0.168.0/http/server.ts"
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'
import { create, getNumericDate } from "https://deno.land/x/djwt@v2.8/mod.ts"

// APNs configuration from Supabase secrets
const APNS_KEY_ID = Deno.env.get('APNS_KEY_ID')
const APNS_TEAM_ID = Deno.env.get('APNS_TEAM_ID')
const APNS_KEY_PEM = Deno.env.get('APNS_KEY')
const APNS_TOPIC = Deno.env.get('APNS_BUNDLE_ID') || 'com.agendahof.swift' // Bundle ID
const APNS_ENDPOINT = Deno.env.get('APNS_ENDPOINT') || 'https://api.push.apple.com'
const SUPABASE_URL = Deno.env.get('SUPABASE_URL')
const SUPABASE_SERVICE_ROLE_KEY = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')

console.log('🚀 Edge Function initialized')

serve(async (req) => {
  try {
    console.log('📨 Received request to send daily financial notifications')

    // Validate Environment Variables
    if (!APNS_KEY_ID || !APNS_TEAM_ID || !APNS_KEY_PEM || !SUPABASE_URL || !SUPABASE_SERVICE_ROLE_KEY || !Deno.env.get('APNS_BUNDLE_ID')) {
      const missing = []
      if (!APNS_KEY_ID) missing.push('APNS_KEY_ID')
      if (!APNS_TEAM_ID) missing.push('APNS_TEAM_ID')
      if (!APNS_KEY_PEM) missing.push('APNS_KEY')
      if (!SUPABASE_URL) missing.push('SUPABASE_URL')
      if (!SUPABASE_SERVICE_ROLE_KEY) missing.push('SUPABASE_SERVICE_ROLE_KEY')
      if (!Deno.env.get('APNS_BUNDLE_ID')) missing.push('APNS_BUNDLE_ID')

      console.warn(`⚠️ Potentially missing env vars: ${missing.join(', ')}`)
      // Not throwing for APNS_BUNDLE_ID for backward compatibility if user hasn't set it yet but code has default
    }

    console.log('APNs Endpoint:', APNS_ENDPOINT)
    console.log('APNs Topic:', APNS_TOPIC)

    // Initialize Supabase client with service role for full access
    const supabase = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY)

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

      // Skip if no patients AND no revenue (no activity today)
      if (financialData.patientCount === 0 && financialData.totalRevenue === 0) {
        console.log(`  ⏭️  Skipping user ${userId}: no patients and no revenue today`)
        continue
      }

      // Generate JWT token once per batch to avoid APNs rate limits (TooManyProviderTokenUpdates)
      let jwt = ''
      try {
        jwt = await generateAPNsJWT()
      } catch (error) {
        console.error('❌ Failed to generate APNs JWT:', error)
        failCount += devices.length
        continue
      }

      // Send notification to all devices for this user
      for (const device of devices) {
        try {
          await sendPushNotification(
            device.device_token,
            financialData,
            device.environment === 'sandbox',
            jwt
          )
          successCount++
          console.log(`  ✅ Sent to device ${device.device_token.substring(0, 10)}...`)
        } catch (error: any) {
          failCount++
          console.error(`  ❌ Failed to send to device:`, error.message)

          // Cleanup stale tokens
          if (error.message.includes('410') || error.message.includes('404') || error.message.includes('Unregistered') || error.message.includes('BadDeviceToken')) {
            console.log(`  🗑️ Removing invalid token: ${device.device_token.substring(0, 10)}...`)
            await supabase
              .from('device_tokens')
              .delete()
              .eq('device_token', device.device_token)
          }
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
 * Calculates current date in São Paulo timezone (yyyy-mm-dd)
 */
function getSaoPauloDate(isoString: string | Date): string {
  const date = typeof isoString === 'string' ? new Date(isoString) : isoString
  return new Intl.DateTimeFormat('en-CA', {
    timeZone: 'America/Sao_Paulo',
    year: 'numeric',
    month: '2-digit',
    day: '2-digit'
  }).format(date)
}

/**
 * Calculate financial data for a user for today (São Paulo timezone)
 */
async function calculateFinancialData(supabase: any, userId: string) {
  // Get today's date range in São Paulo timezone
  const now = new Date()
  const todayStr = getSaoPauloDate(now)
  const startOfDay = `${todayStr}T00:00:00-03:00`
  const endOfDay = `${todayStr}T23:59:59-03:00`

  console.log(`  📅 Date range: ${startOfDay} to ${endOfDay}`)

  // Fetch appointments for today for patient count
  const { data: appointments, error: aptError } = await supabase
    .from('appointments')
    .select('id')
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

  // Calculate revenue from all sources in parallel
  try {
    const [proceduresRevenue, salesRevenue, subscriptionsRevenue, coursesRevenue] = await Promise.all([
      fetchProceduresRevenue(supabase, userId, todayStr),
      fetchSalesRevenue(supabase, userId, todayStr),
      fetchSubscriptionsRevenue(supabase, userId, todayStr),
      fetchCoursesRevenue(supabase, userId, todayStr)
    ])

    const totalRevenue = proceduresRevenue + salesRevenue + subscriptionsRevenue + coursesRevenue

    console.log(`  💰 Revenue breakdown for ${todayStr}:`)
    console.log(`    Procedures: R$ ${proceduresRevenue}`)
    console.log(`    Sales: R$ ${salesRevenue}`)
    console.log(`    Subscriptions: R$ ${subscriptionsRevenue}`)
    console.log(`    Courses: R$ ${coursesRevenue}`)
    console.log(`    TOTAL: R$ ${totalRevenue}`)

    return {
      patientCount,
      totalRevenue,
      formattedRevenue: formatCurrency(totalRevenue)
    }
  } catch (error) {
    console.error('  ⚠️ Error calculating total revenue:', error)
    // Return 0 if calculation fails, but keep patientCount
    return {
      patientCount,
      totalRevenue: 0,
      formattedRevenue: formatCurrency(0)
    }
  }
}

/**
 * Fetch procedures revenue from patients table
 */
async function fetchProceduresRevenue(supabase: any, userId: string, dateStr: string): Promise<number> {
  try {
    const { data: patients, error: patientsError } = await supabase
      .from('patients')
      .select('planned_procedures')
      .eq('user_id', userId)
      .eq('is_active', true)

    if (patientsError) throw patientsError

    let total = 0

    for (const patient of patients || []) {
      if (!patient.planned_procedures) continue

      let procedures = patient.planned_procedures
      if (typeof procedures === 'string') {
        procedures = JSON.parse(procedures)
      }
      if (!Array.isArray(procedures)) continue

      const completedProcs = procedures.filter((p: any) => p.status === 'completed')

      for (const proc of completedProcs) {
        const procDate = proc.performedAt || proc.completedAt
        if (!procDate) continue

        // Revert: Use substring to match iOS logic exactly (ignore timezone shifts)
        const procDateOnly = procDate.substring(0, 10)



        const isMatch = procDateOnly === dateStr

        // Case 1: Parcelado
        if (proc.permitirParcelado && proc.pagamentos?.length > 0) {
          for (const pag of proc.pagamentos) {
            if (!pag.data) continue
            // Dates in pagamentos usually come as 'yyyy-mm-dd' string from frontend, 
            // but to be safe we treat it if it's full ISO
            const pagDate = pag.data.includes('T') ? getSaoPauloDate(pag.data) : pag.data.substring(0, 10)

            if (pagDate === dateStr) {
              total += pag.valor || 0
            }
          }
        }
        // Case 2: Split payments
        else if (proc.paymentSplits?.length > 0) {
          // Check splits individually if they have dates, otherwise fallback to procedure date?
          // Assuming splits are usually paid on procedure date unless specified elsewhere.
          // But existing logic checked procDateOnly === dateStr.
          if (isMatch) {
            for (const split of proc.paymentSplits) {
              total += split.amount || 0
            }
          }
        }
        // Case 3: Traditional single payment
        else if (!proc.permitirParcelado && isMatch) {
          const val = proc.totalValue || proc.value || 0
          total += val
        }
      }
    }


    return total
  } catch (error) {
    console.error('  ⚠️ Error fetching procedures revenue:', error)
    return 0
  }
}

/**
 * Fetch sales revenue
 */
async function fetchSalesRevenue(supabase: any, userId: string, dateStr: string): Promise<number> {
  try {
    const { data: sales, error } = await supabase
      .from('sales')
      .select('total_amount, sold_at, created_at')
      .eq('user_id', userId)
      .eq('payment_status', 'paid')

    if (error) throw error

    let total = 0
    for (const sale of sales || []) {
      const saleDate = sale.sold_at || sale.created_at
      if (!saleDate) continue

      // Fix: Convert to Sao Paulo date
      if (getSaoPauloDate(saleDate) === dateStr) {
        total += sale.total_amount || 0
      }
    }
    return total
  } catch (error) {
    console.error('  ⚠️ Error fetching sales:', error)
    return 0
  }
}

/**
 * Fetch subscriptions revenue
 */
async function fetchSubscriptionsRevenue(supabase: any, userId: string, dateStr: string): Promise<number> {
  try {
    // 1. Get subscriptions for user
    const { data: subscriptions, error: subsError } = await supabase
      .from('patient_subscriptions')
      .select('id')
      .eq('user_id', userId)

    if (subsError || !subscriptions?.length) return 0

    const subscriptionIds = subscriptions.map((s: any) => s.id)

    // 2. Get payments for these subscriptions on the specific date
    const { data: payments, error: paymentsError } = await supabase
      .from('subscription_payments')
      .select('amount, paid_at')
      .in('subscription_id', subscriptionIds)
      .eq('status', 'paid')

    if (paymentsError) throw paymentsError

    let total = 0
    for (const payment of payments || []) {
      if (!payment.paid_at) continue

      // Fix: Convert to Sao Paulo date
      if (getSaoPauloDate(payment.paid_at) === dateStr) {
        total += payment.amount || 0
      }
    }
    return total
  } catch (error) {
    console.error('  ⚠️ Error fetching subscriptions:', error)
    return 0
  }
}

/**
 * Fetch courses revenue
 */
async function fetchCoursesRevenue(supabase: any, userId: string, dateStr: string): Promise<number> {
  try {
    const { data: enrollments, error } = await supabase
      .from('enrollments')
      .select('amount_paid, enrollment_date')
      .eq('user_id', userId)
      .gt('amount_paid', 0)

    if (error) throw error

    let total = 0
    for (const enrollment of enrollments || []) {
      if (!enrollment.enrollment_date) continue

      // Fix: Convert to Sao Paulo date
      if (getSaoPauloDate(enrollment.enrollment_date) === dateStr) {
        total += enrollment.amount_paid || 0
      }
    }
    return total
  } catch (error) {
    console.error('  ⚠️ Error fetching courses:', error)
    return 0
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
/**
 * Send push notification via APNs
 */
async function sendPushNotification(deviceToken: string, data: any, isSandbox: boolean, jwt: string) {
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
    // Check if key is available
    if (!APNS_KEY_PEM) throw new Error('APNS_KEY is missing')

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
