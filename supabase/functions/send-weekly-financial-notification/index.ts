// Supabase Edge Function: send-weekly-financial-notification
// Sends weekly push notifications with financial summary every Saturday at 22:00 BRT
// 
// Deploy: supabase functions deploy send-weekly-financial-notification --no-verify-jwt

import { serve } from "https://deno.land/std@0.168.0/http/server.ts"
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'
import { create, getNumericDate } from "https://deno.land/x/djwt@v2.8/mod.ts"

// APNs configuration from Supabase secrets
const APNS_KEY_ID = Deno.env.get('APNS_KEY_ID')!
const APNS_TEAM_ID = Deno.env.get('APNS_TEAM_ID')!
const APNS_KEY_PEM = Deno.env.get('APNS_KEY')!
const APNS_TOPIC = 'com.agendahof.swift' // Bundle ID
const APNS_ENDPOINT = Deno.env.get('APNS_ENDPOINT') || 'https://api.push.apple.com'

console.log('🚀 Weekly Notification Function initialized')
console.log('APNs Endpoint:', APNS_ENDPOINT)

serve(async (req) => {
    try {
        console.log('📨 Received request to send weekly financial notifications')

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
            console.log(`💰 Calculating weekly financial data for user ${userId}`)

            // Calculate this week's financial data (Monday to Saturday)
            const financialData = await calculateWeeklyFinancialData(supabase, userId)

            console.log(`  💵 Weekly Revenue: R$ ${financialData.totalRevenue} | Patients: ${financialData.patientCount}`)

            // Skip if no patients (no activity this week)
            if (financialData.patientCount === 0) {
                console.log(`  ⏭️  Skipping user ${userId}: no patients this week`)
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
                } catch (error) {
                    failCount++
                    console.error(`  ❌ Failed to send to device:`, error)

                    // Auto-cleanup: Delete invalid tokens (410 Gone / 404 BadDeviceToken)
                    if (error.message && (error.message.includes('410') || error.message.includes('404'))) {
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
 * Calculate financial data for a user for this week (Sunday to Saturday, São Paulo timezone)
 */
async function calculateWeeklyFinancialData(supabase: any, userId: string) {
    // Get current date in São Paulo timezone
    const now = new Date()
    const formatter = new Intl.DateTimeFormat('en-CA', {
        timeZone: 'America/Sao_Paulo',
        year: 'numeric',
        month: '2-digit',
        day: '2-digit'
    })

    // Calculate the current week (Sunday to Saturday, matching iOS app logic)
    const nowSP = new Date(now.toLocaleString('en-US', { timeZone: 'America/Sao_Paulo' }))
    const dayOfWeek = nowSP.getDay() // 0 = Sunday, 1 = Monday, ..., 6 = Saturday

    // Calculate week end (Saturday)
    let weekEnd: Date
    if (dayOfWeek === 6) {
        // Today is Saturday - use today as week end
        weekEnd = nowSP
    } else if (dayOfWeek === 0) {
        // Today is Sunday - use yesterday (Saturday) as week end
        weekEnd = new Date(nowSP)
        weekEnd.setDate(weekEnd.getDate() - 1)
    } else {
        // Monday-Friday - use next Saturday as week end
        const daysUntilSaturday = 6 - dayOfWeek
        weekEnd = new Date(nowSP)
        weekEnd.setDate(weekEnd.getDate() + daysUntilSaturday)
    }

    // Week start is Sunday (6 days before Saturday) - THIS IS THE FIX!
    const weekStart = new Date(weekEnd)
    weekStart.setDate(weekStart.getDate() - 6) // Changed from -5 to -6 for Sunday to Saturday (7 days)

    const startStr = formatter.format(weekStart)
    const endStr = formatter.format(weekEnd)

    const startOfWeek = `${startStr}T00:00:00-03:00`
    const endOfWeek = `${endStr}T23:59:59-03:00`

    console.log(`  📅 Week range: ${startOfWeek} to ${endOfWeek}`)

    // Fetch appointments for patient count
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

    // Calculate revenue from all sources in parallel
    const [proceduresRevenue, salesRevenue, subscriptionsRevenue, coursesRevenue] = await Promise.all([
        fetchProceduresRevenue(supabase, userId, startStr, endStr),
        fetchSalesRevenue(supabase, userId, startStr, endStr),
        fetchSubscriptionsRevenue(supabase, userId, startStr, endStr),
        fetchCoursesRevenue(supabase, userId, startStr, endStr)
    ])

    const totalRevenue = proceduresRevenue + salesRevenue + subscriptionsRevenue + coursesRevenue

    console.log(`  💰 Revenue breakdown:`)
    console.log(`    Procedures: R$ ${proceduresRevenue}`)
    console.log(`    Sales: R$ ${salesRevenue}`)
    console.log(`    Subscriptions: R$ ${subscriptionsRevenue}`)
    console.log(`    Courses: R$ ${coursesRevenue}`)
    console.log(`    TOTAL: R$ ${totalRevenue}`)

    return {
        patientCount,
        totalRevenue,
        formattedRevenue: formatCurrency(totalRevenue),
        weekStart: startStr,
        weekEnd: endStr
    }
}

/**
 * Fetch procedures revenue from patients table (matches iOS logic)
 */
async function fetchProceduresRevenue(supabase: any, userId: string, startDate: string, endDate: string): Promise<number> {
    try {
        const { data: patients, error } = await supabase
            .from('patients')
            .select('planned_procedures')
            .eq('user_id', userId)
            .eq('is_active', true)

        if (error) throw error

        let total = 0

        for (const patient of patients || []) {
            if (!patient.planned_procedures) continue

            // Handle JSONB - convert to array if needed
            let procedures = patient.planned_procedures
            if (typeof procedures === 'string') {
                procedures = JSON.parse(procedures)
            }
            if (!Array.isArray(procedures)) {
                console.log('  ⚠️ planned_procedures is not an array, skipping patient')
                continue
            }

            const completedProcs = procedures.filter((p: any) => p.status === 'completed')

            for (const proc of completedProcs) {
                const procDate = proc.performedAt || proc.completedAt || ''
                const procDateOnly = procDate.substring(0, 10)

                // Case 1: Parcelado (installment payments with dates)
                if (proc.permitirParcelado && proc.pagamentos?.length > 0) {
                    for (const pag of proc.pagamentos) {
                        const pagDate = pag.data.substring(0, 10)
                        if (pagDate >= startDate && pagDate <= endDate) {
                            total += pag.valor || 0
                        }
                    }
                }
                // Case 2: Split payments (multiple payment methods)
                else if (proc.paymentSplits?.length > 0 && procDateOnly >= startDate && procDateOnly <= endDate) {
                    for (const split of proc.paymentSplits) {
                        total += split.amount || 0
                    }
                }
                // Case 3: Traditional single payment
                else if (!proc.permitirParcelado && procDateOnly >= startDate && procDateOnly <= endDate) {
                    total += proc.totalValue || proc.value || 0
                }
            }
        }

        return total
    } catch (error) {
        console.error('  ⚠️ Error fetching procedures:', error)
        return 0
    }
}

/**
 * Fetch sales revenue
 */
async function fetchSalesRevenue(supabase: any, userId: string, startDate: string, endDate: string): Promise<number> {
    try {
        const { data: sales, error } = await supabase
            .from('sales')
            .select('total_amount, sold_at, created_at')
            .eq('user_id', userId)
            .eq('payment_status', 'paid')

        if (error) throw error

        let total = 0
        for (const sale of sales || []) {
            const dateStr = sale.sold_at || sale.created_at
            if (!dateStr) continue

            const dateOnly = dateStr.substring(0, 10)
            if (dateOnly >= startDate && dateOnly <= endDate) {
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
async function fetchSubscriptionsRevenue(supabase: any, userId: string, startDate: string, endDate: string): Promise<number> {
    try {
        const { data: subscriptions, error: subsError } = await supabase
            .from('patient_subscriptions')
            .select('id')
            .eq('user_id', userId)

        if (subsError || !subscriptions?.length) return 0

        const subscriptionIds = subscriptions.map((s: any) => s.id)

        const { data: payments, error: paymentsError } = await supabase
            .from('subscription_payments')
            .select('amount, paid_at')
            .in('subscription_id', subscriptionIds)
            .eq('status', 'paid')

        if (paymentsError) throw paymentsError

        let total = 0
        for (const payment of payments || []) {
            const dateStr = payment.paid_at
            if (!dateStr) continue

            const dateOnly = dateStr.substring(0, 10)
            if (dateOnly >= startDate && dateOnly <= endDate) {
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
async function fetchCoursesRevenue(supabase: any, userId: string, startDate: string, endDate: string): Promise<number> {
    try {
        const { data: enrollments, error } = await supabase
            .from('enrollments')
            .select('amount_paid, enrollment_date')
            .eq('user_id', userId)
            .gt('amount_paid', 0)

        if (error) throw error

        let total = 0
        for (const enrollment of enrollments || []) {
            const dateStr = enrollment.enrollment_date
            if (!dateStr) continue

            const dateOnly = dateStr.substring(0, 10)
            if (dateOnly >= startDate && dateOnly <= endDate) {
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
 * Get motivational message for weekly summary
 */
function getWeeklyMotivationalMessage(revenue: number, patientCount: number, formattedRevenue: string): string {
    const patientText = `Você atendeu ${patientCount} paciente${patientCount === 1 ? '' : 's'} e faturou`

    if (revenue <= 5000) return `${patientText} ${formattedRevenue} esta semana. Continue assim! 💪`
    if (revenue <= 15000) return `Ótima semana! ${patientText} ${formattedRevenue}. Você está no caminho certo! 🚀`
    if (revenue <= 30000) return `Excelente semana! ${patientText} ${formattedRevenue}. Continue assim! 🔥`
    if (revenue <= 50000) return `Semana espetacular! ${patientText} ${formattedRevenue}. Você está arrasando! ⭐️`
    if (revenue <= 70000) return `Semana fantástica! ${patientText} ${formattedRevenue}. Seu sucesso é inspirador! 🌟`
    if (revenue <= 100000) return `Semana extraordinária! ${patientText} ${formattedRevenue}. Você é uma referência! 👑`
    return `Semana INCRÍVEL! ${patientText} ${formattedRevenue}. Parabéns pelo sucesso absoluto! 🏆✨`
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
                title: '📊 Resumo da Semana',
                body: getWeeklyMotivationalMessage(data.totalRevenue, data.patientCount, data.formattedRevenue)
            },
            sound: 'default',
            badge: 1
        },
        data: {
            type: 'weekly_summary',
            revenue: data.totalRevenue,
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
