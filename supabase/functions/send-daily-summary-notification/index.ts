// Supabase Edge Function: send-daily-summary-notification
// Sends push notifications with daily appointment summary at 08:00 BRT
// 
// Deploy: supabase functions deploy send-daily-summary-notification --no-verify-jwt

import { serve } from "https://deno.land/std@0.168.0/http/server.ts"
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'
import { create, getNumericDate } from "https://deno.land/x/djwt@v2.8/mod.ts"

// APNs configuration from Supabase secrets
const APNS_KEY_ID = Deno.env.get('APNS_KEY_ID')!
const APNS_TEAM_ID = Deno.env.get('APNS_TEAM_ID')!
const APNS_KEY_PEM = Deno.env.get('APNS_KEY')!
const APNS_TOPIC = 'com.agendahof.swift' // Bundle ID
const APNS_ENDPOINT = Deno.env.get('APNS_ENDPOINT') || 'https://api.push.apple.com'

console.log('🚀 Daily Summary Notification Function initialized')
console.log('APNs Endpoint:', APNS_ENDPOINT)

serve(async (req) => {
    try {
        console.log('📨 Received request to send daily summary notifications')

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
            console.log(`📅 Calculating today's appointments for user ${userId}`)

            // Get today's appointments
            const summaryData = await calculateTodaysSummary(supabase, userId)

            console.log(`  📊 Today: ${summaryData.appointmentCount} appointments`)

            // Send notification to all devices for this user
            for (const device of devices) {
                try {
                    await sendPushNotification(
                        device.device_token,
                        summaryData,
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
 * Calculate today's appointments summary (São Paulo timezone)
 */
async function calculateTodaysSummary(supabase: any, userId: string) {
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

    // Fetch appointments for today (non-cancelled, non-personal, ordered by start time)
    const { data: appointments, error: aptError } = await supabase
        .from('appointments')
        .select('patient_name, title, start, is_personal')
        .eq('user_id', userId)
        .gte('start', startOfDay)
        .lte('start', endOfDay)
        .neq('status', 'cancelled')
        .or('is_personal.is.null,is_personal.eq.false')
        .order('start', { ascending: true })

    if (aptError) {
        console.error('  ❌ Error fetching appointments:', aptError)
        throw aptError
    }

    const appointmentCount = appointments?.length || 0
    const firstAppointment = appointments?.[0] || null

    return {
        appointmentCount,
        firstAppointment,
        todayStr
    }
}

/**
 * Format time from ISO string to HH:mm
 */
function formatTime(isoString: string): string {
    const date = new Date(isoString)
    const hours = date.getHours().toString().padStart(2, '0')
    const minutes = date.getMinutes().toString().padStart(2, '0')
    return `${hours}:${minutes}`
}

/**
 * Get notification message based on appointment count and first appointment
 */
function getNotificationMessage(count: number, firstAppointment: any): string {
    if (count === 0) {
        return "Você não tem agendamentos para hoje. Aproveite o dia!"
    }

    if (count === 1) {
        let message = "Você tem 1 agendamento para hoje."
        if (firstAppointment) {
            const displayName = firstAppointment.patient_name || firstAppointment.title || "Paciente"
            const time = formatTime(firstAppointment.start)
            message += ` Primeiro: ${displayName} às ${time}`
        }
        return message
    }

    // Multiple appointments
    let message = `Você tem ${count} agendamentos para hoje.`
    if (firstAppointment) {
        const displayName = firstAppointment.patient_name || firstAppointment.title || "Paciente"
        const time = formatTime(firstAppointment.start)
        message += ` Primeiro: ${displayName} às ${time}`
    }
    return message
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
                title: '📅 Resumo do Dia',
                body: getNotificationMessage(data.appointmentCount, data.firstAppointment)
            },
            sound: 'default',
            badge: 1
        },
        data: {
            type: 'daily_summary',
            appointmentCount: data.appointmentCount,
            date: data.todayStr
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
