// Supabase Edge Function: send-week-preview-notification
// Sends push notifications with next week's preview every Sunday at 20:00 BRT
// 
// Deploy: supabase functions deploy send-week-preview-notification --no-verify-jwt

import { serve } from "https://deno.land/std@0.168.0/http/server.ts"
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'
import { create, getNumericDate } from "https://deno.land/x/djwt@v2.8/mod.ts"

// APNs configuration from Supabase secrets
const APNS_KEY_ID = Deno.env.get('APNS_KEY_ID')!
const APNS_TEAM_ID = Deno.env.get('APNS_TEAM_ID')!
const APNS_KEY_PEM = Deno.env.get('APNS_KEY')!
const APNS_TOPIC = 'com.agendahof.swift' // Bundle ID
const APNS_ENDPOINT = Deno.env.get('APNS_ENDPOINT') || 'https://api.push.apple.com'

console.log('🚀 Week Preview Notification Function initialized')
console.log('APNs Endpoint:', APNS_ENDPOINT)

serve(async (req) => {
  try {
    console.log('📨 Received request to send week preview notifications')

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

    // Get all user profiles (preview for all users, not just owners)
    const userIds = [...new Set(deviceTokens?.map(t => t.user_id) || [])]

    console.log(`✅ Processing ${userIds.length} users`)

    // Group tokens by user
    const userDevices = new Map<string, any[]>()
    for (const token of deviceTokens || []) {
      const userId = token.user_id
      if (!userDevices.has(userId)) {
        userDevices.set(userId, [])
      }
      userDevices.get(userId)!.push(token)
    }

    let successCount = 0
    let failCount = 0

    // Process each user
    for (const [userId, devices] of userDevices.entries()) {
      console.log(`🔮 Calculating next week appointments for user ${userId}`)

      // Calculate next week's appointments
      const weekData = await calculateNextWeekAppointments(supabase, userId)

      console.log(`  📅 Next week: ${weekData.patientCount} patients scheduled`)



      // Send notification to all devices for this user
      for (const device of devices) {
        try {
          await sendPushNotification(
            device.device_token,
            weekData,
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
        users: userDevices.size,
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
 * Calculate next week's appointments for a user (São Paulo timezone)
 * Next week = Monday to Sunday starting from the next Monday after notification
 */
async function calculateNextWeekAppointments(supabase: any, userId: string) {
  // Get current date/time in São Paulo timezone
  const now = new Date()
  const nowSP = new Date(now.toLocaleString('en-US', { timeZone: 'America/Sao_Paulo' }))

  const currentDayOfWeek = nowSP.getDay() // 0=Sunday, 1=Monday, ..., 6=Saturday
  const currentHour = nowSP.getHours()

  console.log(`  📍 Current day: ${currentDayOfWeek}, hour: ${currentHour}`)

  // Calculate days until next Monday
  let daysUntilNextMonday: number

  if (currentDayOfWeek === 0) {
    // It's Sunday
    if (currentHour < 20) {
      // Before 20:00: next week starts tomorrow (Monday)
      daysUntilNextMonday = 1
    } else {
      // After 20:00: next week starts in 8 days (next Monday)
      daysUntilNextMonday = 8
    }
  } else {
    // Monday to Saturday: calculate days to next Monday
    daysUntilNextMonday = (8 - currentDayOfWeek) % 7
    if (daysUntilNextMonday === 0) daysUntilNextMonday = 7
  }

  // Calculate next Monday at 00:00:00
  const nextMonday = new Date(nowSP)
  nextMonday.setDate(nowSP.getDate() + daysUntilNextMonday)
  nextMonday.setHours(0, 0, 0, 0)

  // Calculate next Sunday at 23:59:59
  const nextSunday = new Date(nextMonday)
  nextSunday.setDate(nextMonday.getDate() + 6)
  nextSunday.setHours(23, 59, 59, 999)

  // Format dates for Supabase query (ISO format with timezone)
  const formatter = new Intl.DateTimeFormat('en-CA', {
    timeZone: 'America/Sao_Paulo',
    year: 'numeric',
    month: '2-digit',
    day: '2-digit'
  })

  const mondayStr = formatter.format(nextMonday)
  const sundayStr = formatter.format(nextSunday)

  const startOfWeek = `${mondayStr}T00:00:00-03:00`
  const endOfWeek = `${sundayStr}T23:59:59-03:00`

  console.log(`  📅 Next week range: ${startOfWeek} to ${endOfWeek}`)

  // Fetch appointments for next week (non-cancelled, non-personal)
  const { data: appointments, error: aptError } = await supabase
    .from('appointments')
    .select('id')
    .eq('user_id', userId)
    .gte('start', startOfWeek)
    .lte('start', endOfWeek)
    .neq('status', 'cancelled')
    .or('is_personal.is.null,is_personal.eq.false')

  if (aptError) {
    console.error('  ❌ Error fetching appointments:', aptError)
    throw aptError
  }

  const patientCount = appointments?.length || 0

  return {
    patientCount,
    weekStart: mondayStr,
    weekEnd: sundayStr
  }
}

/**
 * Get motivational message based on patient count
 */
function getMotivationalMessage(patientCount: number): string {
  switch (true) {
    case patientCount === 0:
      return "Sua semana está livre! Aproveite para planejar e relaxar. 🌟"
    case patientCount === 1:
      return "Você tem 1 paciente esta semana. Vamos começar com energia! 💪"
    case patientCount <= 10:
      return `Você tem ${patientCount} pacientes esta semana. Vamos começar com energia! 💪`
    case patientCount <= 20:
      return `Semana movimentada! ${patientCount} pacientes te aguardam. Você vai arrasar! 🚀`
    default:
      return `Wow! ${patientCount} pacientes agendados. Prepare-se para uma semana incrível! 🔥`
  }
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
        title: '🌟 Prévia da Semana',
        body: getMotivationalMessage(data.patientCount)
      },
      sound: 'default',
      badge: 1
    },
    data: {
      type: 'week_preview',
      patientCount: data.patientCount,
      weekStart: data.weekStart,
      weekEnd: data.weekEnd
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
