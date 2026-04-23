// Supabase Edge Function: send-daily-summary-notification
// Sends push notifications with daily appointment summary at 08:00 BRT
// 
// Deploy: supabase functions deploy send-daily-summary-notification --no-verify-jwt

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
const COURSE_PROCEDURE_NAME = 'Curso'
const DEFAULT_TIME_ZONE = 'America/Sao_Paulo'

function resolveTimeZone(rawTimeZone?: string | null): string {
    const candidate = (rawTimeZone || '').trim()
    if (!candidate) return DEFAULT_TIME_ZONE

    try {
        new Intl.DateTimeFormat('pt-BR', { timeZone: candidate }).format(new Date())
        return candidate
    } catch {
        return DEFAULT_TIME_ZONE
    }
}

function formatDateInTimeZone(date: Date, timeZone: string): string {
    return new Intl.DateTimeFormat('en-CA', {
        timeZone,
        year: 'numeric',
        month: '2-digit',
        day: '2-digit'
    }).format(date)
}

console.log('🚀 Daily Summary Notification Function initialized')
console.log('APNs Endpoint:', APNS_ENDPOINT)
console.log('APNs Topic:', APNS_TOPIC)

serve(async (req) => {
    try {
        console.log('📨 Received request to send daily summary notifications')

        // Validate Environment Variables
        if (!APNS_KEY_ID || !APNS_TEAM_ID || !APNS_KEY_PEM || !SUPABASE_URL || !SUPABASE_SERVICE_ROLE_KEY) {
            const missing = []
            if (!APNS_KEY_ID) missing.push('APNS_KEY_ID')
            if (!APNS_TEAM_ID) missing.push('APNS_TEAM_ID')
            if (!APNS_KEY_PEM) missing.push('APNS_KEY')
            if (!SUPABASE_URL) missing.push('SUPABASE_URL')
            if (!SUPABASE_SERVICE_ROLE_KEY) missing.push('SUPABASE_SERVICE_ROLE_KEY')

            throw new Error(`Missing required environment variables: ${missing.join(', ')}`)
        }

        // Initialize Supabase client with service role for full access
        const supabase = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY)

        // Get all active device tokens
        const { data: deviceTokens, error: tokensError } = await supabase
            .from('device_tokens')
            .select('*')
            .eq('is_active', true)

        if (tokensError) {
            console.error('❌ Error fetching device tokens:', tokensError)
            throw tokensError
        }

        console.log(`✅ Found ${deviceTokens?.length || 0} active device tokens`)

        // Filter: only send to owner accounts
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

        const ownerIds = new Set(profiles?.map(p => p.id) || [])
        const ownerDeviceTokens = deviceTokens?.filter(t => ownerIds.has(t.user_id)) || []

        console.log(`✅ Found ${ownerDeviceTokens.length} device tokens for ${ownerIds.size} owners (staff excluded)`)

        // Group tokens by user (owners only)
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

        // ✅ Generate JWT token ONCE per function execution (Apple recommends reusing for ~20-60 mins)
        // Regenerating per device causes "APNs error 429: TooManyProviderTokenUpdates"
        const jwt = await generateAPNsJWT()
        // Process each user
        for (const [userId, devices] of userDevices.entries()) {
            const summaryByTimeZone = new Map<string, any>()
            const coursesByTimeZone = new Map<string, any>()

            // Send notification to all devices for this user
            for (const device of devices) {
                const isSandbox = device.environment === 'sandbox'
                const deviceTimeZone = resolveTimeZone(device.time_zone)

                let summaryData = summaryByTimeZone.get(deviceTimeZone)
                if (!summaryData) {
                    console.log(`📅 Calculating today's appointments for user ${userId} (tz: ${deviceTimeZone})`)
                    summaryData = await calculateTodaysSummary(supabase, userId, deviceTimeZone)
                    summaryByTimeZone.set(deviceTimeZone, summaryData)
                }

                let courseData = coursesByTimeZone.get(deviceTimeZone)
                if (!courseData) {
                    courseData = await calculateTodaysCourses(supabase, userId, deviceTimeZone)
                    coursesByTimeZone.set(deviceTimeZone, courseData)

                    const holidayLabel = summaryData.holiday
                        ? ` | holiday: ${summaryData.holiday.name} (${summaryData.holiday.kind})`
                        : ''
                    console.log(`  📊 Today (${deviceTimeZone}): ${summaryData.appointmentCount} appointments | ${courseData.courseCount} courses | streakDay: ${courseData.streakDay}${holidayLabel}`)
                }

                const shouldSendDailySummary = !(courseData.courseCount > 0 && summaryData.appointmentCount === 0)

                if (shouldSendDailySummary) {
                    try {
                        await sendPushNotification(
                            device.device_token,
                            summaryData,
                            isSandbox,
                            jwt,
                            deviceTimeZone
                        )
                        successCount++
                        console.log(`  ✅ Daily summary sent to device ${device.device_token.substring(0, 10)}...`)
                    } catch (error: any) {
                        failCount++
                        console.error(`  ❌ Failed to send daily summary to device:`, error.message)

                        // Cleanup stale tokens
                        if (isStaleTokenError(error.message)) {
                            console.log(`  🗑️ Deactivating stale token: ${device.device_token.substring(0, 10)}...`)
                            await supabase
                                .from('device_tokens')
                                .update({ is_active: false })
                                .eq('device_token', device.device_token)
                        }
                        continue
                    }
                } else {
                    console.log(`  ⏭️ Daily summary skipped (courses=${courseData.courseCount}, patients=${summaryData.appointmentCount})`)
                }

                if (courseData.courseCount === 0) {
                    continue
                }

                try {
                    await sendCoursePushNotification(
                        device.device_token,
                        courseData,
                        isSandbox,
                        jwt
                    )
                    successCount++
                    console.log(`  ✅ Course reminder sent to device ${device.device_token.substring(0, 10)}...`)
                } catch (error: any) {
                    failCount++
                    console.error(`  ❌ Failed to send course reminder to device:`, error.message)

                    // Cleanup stale tokens
                    if (isStaleTokenError(error.message)) {
                        console.log(`  🗑️ Deactivating stale token: ${device.device_token.substring(0, 10)}...`)
                        await supabase
                            .from('device_tokens')
                            .update({ is_active: false })
                            .eq('device_token', device.device_token)
                    }
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
    } catch (error: any) {
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
 * Calculate today's appointments summary in user timezone.
 */
async function calculateTodaysSummary(supabase: any, userId: string, timeZone: string) {
    const now = new Date()
    const todayStr = formatDateInTimeZone(now, timeZone)

    // Query a broad UTC window and filter by user timezone locally.
    // This avoids hardcoding offsets such as -03:00 and works for all Brazil timezones.
    const windowStart = new Date(now.getTime() - (36 * 60 * 60 * 1000)).toISOString()
    const windowEnd = new Date(now.getTime() + (36 * 60 * 60 * 1000)).toISOString()

    console.log(`  📅 UTC window: ${windowStart} to ${windowEnd} | day(${timeZone})=${todayStr}`)

    const { data: appointments, error: aptError } = await supabase
        .from('appointments')
        .select('patient_name, title, start, is_personal')
        .eq('user_id', userId)
        .gte('start', windowStart)
        .lte('start', windowEnd)
        .neq('status', 'cancelled')
        .or('is_personal.is.null,is_personal.eq.false')
        .order('start', { ascending: true })

    if (aptError) {
        console.error('  ❌ Error fetching appointments:', aptError)
        throw aptError
    }

    const todaysAppointments = (appointments || []).filter((appointment: any) => {
        if (!appointment.start) return false
        return formatDateInTimeZone(new Date(appointment.start), timeZone) === todayStr
    })

    const appointmentCount = todaysAppointments.length
    const firstAppointment = todaysAppointments[0] || null
    const holiday = getBrazilianHolidayForDate(todayStr)

    return {
        appointmentCount,
        firstAppointment,
        todayStr,
        holiday
    }
}

/**
 * Calculate today's course appointments and consecutive-day streak index
 * for personalized reminders.
 */
async function calculateTodaysCourses(supabase: any, userId: string, timeZone: string) {
    const now = new Date()
    const todayStr = formatDateInTimeZone(now, timeZone)
    const yesterdayStr = shiftDateByDays(todayStr, -1, timeZone)
    const twoDaysAgoStr = shiftDateByDays(todayStr, -2, timeZone)

    const startWindow = new Date(now.getTime() - (96 * 60 * 60 * 1000)).toISOString()
    const endWindow = new Date(now.getTime() + (24 * 60 * 60 * 1000)).toISOString()

    const { data: courseAppointments, error: courseError } = await supabase
        .from('appointments')
        .select('start, procedure, title')
        .eq('user_id', userId)
        .gte('start', startWindow)
        .lte('start', endWindow)
        .neq('status', 'cancelled')
        .eq('is_personal', true)

    if (courseError) {
        console.error('  ❌ Error fetching course appointments:', courseError)
        throw courseError
    }

    const courseCountByDay: Record<string, number> = {}
    for (const appointment of courseAppointments || []) {
        const isCourseByProcedure = normalizeCourseProcedure(appointment.procedure) === normalizeCourseProcedure(COURSE_PROCEDURE_NAME)
        const isCourseByLegacyTitle = looksLikeLegacyCourseTitle(appointment.title)

        if (!isCourseByProcedure && !isCourseByLegacyTitle) {
            continue
        }

        if (!appointment.start) continue
        const dayKey = formatDateInTimeZone(new Date(appointment.start), timeZone)
        courseCountByDay[dayKey] = (courseCountByDay[dayKey] || 0) + 1
    }

    const courseCount = courseCountByDay[todayStr] || 0

    // Day 1 = isolated or first day, Day 2 = second consecutive day, Day 3 = third+ day
    let streakDay = 1
    if (courseCount > 0 && (courseCountByDay[yesterdayStr] || 0) > 0) {
        streakDay = 2
        if ((courseCountByDay[twoDaysAgoStr] || 0) > 0) {
            streakDay = 3
        }
    }

    return {
        courseCount,
        streakDay,
        todayStr
    }
}

function shiftDateByDays(baseDate: string, days: number, timeZone: string): string {
    const [yearStr, monthStr, dayStr] = baseDate.split('-')
    const year = Number(yearStr)
    const month = Number(monthStr)
    const day = Number(dayStr)

    if (!Number.isFinite(year) || !Number.isFinite(month) || !Number.isFinite(day)) {
        return baseDate
    }

    const date = new Date(Date.UTC(year, month - 1, day, 12, 0, 0))
    date.setUTCDate(date.getUTCDate() + days)
    return formatDateInTimeZone(date, timeZone)
}

function normalizeCourseProcedure(value?: string | null): string {
    return (value ?? '')
        .trim()
        .toLowerCase()
        .normalize('NFD')
        .replace(/[\u0300-\u036f]/g, '')
}

// Compatibilidade com registros antigos:
// alguns cursos foram salvos como compromisso pessoal com quebra de linha no title.
function looksLikeLegacyCourseTitle(title?: string | null): boolean {
    if (!title) return false
    const parts = title
        .split('\n')
        .map((part) => part.trim())
        .filter(Boolean)
    return parts.length >= 2
}

/**
 * Format time from ISO string to HH:mm
 */
function formatTime(isoString: string, timeZone: string): string {
    const date = new Date(isoString)
    return new Intl.DateTimeFormat('pt-BR', {
        timeZone,
        hour: '2-digit',
        minute: '2-digit',
        hour12: false
    }).format(date)
}

/**
 * Get notification message based on appointment count and first appointment
 */
function getNotificationMessage(count: number, firstAppointment: any, timeZone: string): string {
    if (count === 0) {
        return "Você não tem agendamentos para hoje. Aproveite o dia!"
    }

    const firstTime = firstAppointment?.start
        ? formatTime(firstAppointment.start, timeZone)
        : null

    const firstPatientSentence = firstTime
        ? ` O primeiro paciente é às ${firstTime}.`
        : ""

    return `Você tem ${count} agendamentos para hoje.${firstPatientSentence}`
}

function getDailySummaryNotificationBody(data: any, timeZone: string): string {
    const count = data?.appointmentCount || 0

    if (count === 0 && data?.holiday) {
        return getHolidayNoAppointmentsMessage(data.holiday)
    }

    return getNotificationMessage(count, data?.firstAppointment, timeZone)
}

function getHolidayNoAppointmentsMessage(holiday: { name: string; kind: string }): string {
    const templates = [
        `Hoje é feriado de ${holiday.name}! Agenda vazia por aqui: aproveite para recarregar as energias e curtir seu feriado. ✨`,
        `Hoje é feriado de ${holiday.name} e sua agenda está livre. Dia perfeito para descansar e voltar ainda mais inspirada amanhã. 💛`,
        `Hoje é feriado de ${holiday.name}, com agenda zerada: respire fundo, desacelere e aproveite esse tempo para você. 🌿`,
        `Hoje é feriado de ${holiday.name} e não há atendimentos marcados. Aproveite o dia para cuidar de você e celebrar o feriado. ☀️`
    ]

    // Determinístico para evitar variar em duplicidade de dispositivos no mesmo dia.
    const index = Math.abs(hashString(holiday.name)) % templates.length
    return templates[index]
}

function hashString(value: string): number {
    let hash = 0
    for (let i = 0; i < value.length; i++) {
        hash = ((hash << 5) - hash) + value.charCodeAt(i)
        hash |= 0
    }
    return hash
}

function getBrazilianHolidayForDate(dateStr: string): { name: string; kind: 'nacional' | 'facultativo' | 'comemorativo' } | null {
    const [yearStr, monthStr, dayStr] = dateStr.split('-')
    const year = Number(yearStr)
    const month = Number(monthStr)
    const day = Number(dayStr)

    if (!Number.isFinite(year) || !Number.isFinite(month) || !Number.isFinite(day)) {
        return null
    }

    const key = formatDateKey(year, month, day)
    const holidays = buildBrazilianHolidaysByDate(year)
    return holidays[key] ?? null
}

function buildBrazilianHolidaysByDate(year: number): Record<string, { name: string; kind: 'nacional' | 'facultativo' | 'comemorativo' }> {
    const holidays: Record<string, { name: string; kind: 'nacional' | 'facultativo' | 'comemorativo' }> = {}

    const fixedHolidays: Array<{ month: number; day: number; name: string; kind: 'nacional' | 'facultativo' | 'comemorativo' }> = [
        { month: 1, day: 1, name: 'Confraternização Universal', kind: 'nacional' },
        { month: 4, day: 21, name: 'Tiradentes', kind: 'nacional' },
        { month: 5, day: 1, name: 'Dia do Trabalho', kind: 'nacional' },
        { month: 9, day: 7, name: 'Independência do Brasil', kind: 'nacional' },
        { month: 10, day: 12, name: 'Nossa Senhora Aparecida', kind: 'nacional' },
        { month: 11, day: 2, name: 'Finados', kind: 'nacional' },
        { month: 11, day: 15, name: 'Proclamação da República', kind: 'nacional' },
        { month: 11, day: 20, name: 'Consciência Negra', kind: 'nacional' },
        { month: 12, day: 25, name: 'Natal', kind: 'nacional' }
    ]

    for (const holiday of fixedHolidays) {
        holidays[formatDateKey(year, holiday.month, holiday.day)] = {
            name: holiday.name,
            kind: holiday.kind
        }
    }

    const easterDate = calculateEasterDate(year)
    const movableHolidays = [
        { offsetDays: -47, name: 'Carnaval', kind: 'facultativo' as const },
        { offsetDays: -2, name: 'Sexta-feira Santa', kind: 'nacional' as const },
        { offsetDays: 0, name: 'Páscoa', kind: 'comemorativo' as const },
        { offsetDays: 60, name: 'Corpus Christi', kind: 'facultativo' as const }
    ]

    for (const holiday of movableHolidays) {
        const date = addDaysUTC(easterDate, holiday.offsetDays)
        holidays[formatDateFromUTC(date)] = {
            name: holiday.name,
            kind: holiday.kind
        }
    }

    return holidays
}

// Meeus/Jones/Butcher algorithm
function calculateEasterDate(year: number): Date {
    const a = year % 19
    const b = Math.floor(year / 100)
    const c = year % 100
    const d = Math.floor(b / 4)
    const e = b % 4
    const f = Math.floor((b + 8) / 25)
    const g = Math.floor((b - f + 1) / 3)
    const h = (19 * a + b - d - g + 15) % 30
    const i = Math.floor(c / 4)
    const k = c % 4
    const l = (32 + 2 * e + 2 * i - h - k) % 7
    const m = Math.floor((a + 11 * h + 22 * l) / 451)
    const month = Math.floor((h + l - 7 * m + 114) / 31)
    const day = ((h + l - 7 * m + 114) % 31) + 1

    return new Date(Date.UTC(year, month - 1, day, 12, 0, 0))
}

function addDaysUTC(date: Date, days: number): Date {
    const next = new Date(date)
    next.setUTCDate(next.getUTCDate() + days)
    return next
}

function formatDateFromUTC(date: Date): string {
    const year = date.getUTCFullYear()
    const month = String(date.getUTCMonth() + 1).padStart(2, '0')
    const day = String(date.getUTCDate()).padStart(2, '0')
    return `${year}-${month}-${day}`
}

function formatDateKey(year: number, month: number, day: number): string {
    return `${String(year).padStart(4, '0')}-${String(month).padStart(2, '0')}-${String(day).padStart(2, '0')}`
}

/**
 * Send push notification via APNs
 */
async function sendPushNotification(
    deviceToken: string,
    data: any,
    isSandbox: boolean,
    jwt: string,
    timeZone: string
) {
    // JWT is now passed in to avoid rate limiting

    const endpoint = isSandbox
        ? 'https://api.sandbox.push.apple.com'
        : 'https://api.push.apple.com'

    const payload = {
        aps: {
            alert: {
                title: '📅 Resumo do Dia',
                body: getDailySummaryNotificationBody(data, timeZone)
            },
            sound: 'default',
            badge: 1
        },
        data: {
            type: 'daily_summary',
            appointmentCount: data.appointmentCount,
            date: data.todayStr,
            holidayName: data.holiday?.name ?? null,
            timeZone
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
 * Send course reminder push notification via APNs
 */
async function sendCoursePushNotification(deviceToken: string, data: any, isSandbox: boolean, jwt: string) {
    const endpoint = isSandbox
        ? 'https://api.sandbox.push.apple.com'
        : 'https://api.push.apple.com'

    const reminderBody = getCourseReminderBody(data.streakDay)

    const payload = {
        aps: {
            alert: {
                title: '🎓 Hoje é dia de Curso!',
                body: reminderBody
            },
            sound: 'default',
            badge: 1
        },
        data: {
            type: 'course_reminder',
            courseCount: data.courseCount,
            streakDay: data.streakDay,
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

function getCourseReminderBody(streakDay: number): string {
    if (streakDay >= 3) {
        return 'Elevando o nível mais uma vez. Vamos!'
    }

    if (streakDay === 2) {
        return 'Mais um dia impactando vidas. Inspire seus alunos!'
    }

    return 'Dia de compartilhar conhecimento. Vai com tudo!'
}

function isStaleTokenError(message: string): boolean {
    return message.includes('410')
        || message.includes('404')
        || message.includes('Unregistered')
        || message.includes('BadDeviceToken')
}

/**
 * Generate JWT token for APNs authentication using ES256 algorithm
 * Documentation: https://developer.apple.com/documentation/usernotifications/setting_up_a_remote_notification_server/establishing_a_token-based_connection_to_apns
 */
async function generateAPNsJWT(): Promise<string> {
    try {
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
    } catch (error: any) {
        console.error('❌ Error generating APNs JWT:', error)
        throw new Error(`Failed to generate APNs JWT: ${error.message}`)
    }
}
