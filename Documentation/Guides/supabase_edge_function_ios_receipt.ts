// =====================================================
// EDGE FUNCTION: /api/ios-receipt
// Recebe e valida recibos de compras Apple (StoreKit 2)
// =====================================================
// Deploy: supabase functions deploy ios-receipt
// =====================================================

import { serve } from "https://deno.land/std@0.168.0/http/server.ts"
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

const corsHeaders = {
    'Access-Control-Allow-Origin': '*',
    'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
}

interface AppleReceiptPayload {
    user_id: string
    transaction_id: string
    original_transaction_id: string
    product_id: string
    purchase_date: string
    expiration_date?: string
    jws_token: string
    environment: string
}

serve(async (req) => {
    // Handle CORS preflight
    if (req.method === 'OPTIONS') {
        return new Response('ok', { headers: corsHeaders })
    }

    try {
        // Verificar método
        if (req.method !== 'POST') {
            return new Response(
                JSON.stringify({ error: 'Method not allowed' }),
                { status: 405, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
            )
        }

        // Obter token de autenticação
        const authHeader = req.headers.get('Authorization')
        if (!authHeader) {
            return new Response(
                JSON.stringify({ error: 'Missing authorization header' }),
                { status: 401, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
            )
        }

        // Criar cliente Supabase com service role (para operações admin)
        const supabaseAdmin = createClient(
            Deno.env.get('SUPABASE_URL') ?? '',
            Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? '',
            { auth: { persistSession: false } }
        )

        // Criar cliente Supabase com token do usuário (para verificar identidade)
        const supabaseUser = createClient(
            Deno.env.get('SUPABASE_URL') ?? '',
            Deno.env.get('SUPABASE_ANON_KEY') ?? '',
            {
                auth: { persistSession: false },
                global: { headers: { Authorization: authHeader } }
            }
        )

        // Verificar usuário autenticado
        const { data: { user }, error: userError } = await supabaseUser.auth.getUser()
        if (userError || !user) {
            return new Response(
                JSON.stringify({ error: 'Invalid or expired token' }),
                { status: 401, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
            )
        }

        // Parsear payload
        const payload: AppleReceiptPayload = await req.json()

        // Validar campos obrigatórios
        if (!payload.transaction_id || !payload.product_id || !payload.jws_token) {
            return new Response(
                JSON.stringify({ error: 'Missing required fields' }),
                { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
            )
        }

        // Verificar se o user_id do payload corresponde ao usuário autenticado
        if (payload.user_id !== user.id) {
            return new Response(
                JSON.stringify({ error: 'User ID mismatch' }),
                { status: 403, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
            )
        }

        console.log(`[ios-receipt] Processing receipt for user ${user.id}, product: ${payload.product_id}`)

        // =====================================================
        // OPCIONAL: Validação do JWS Token com Apple
        // Para produção, você deve validar o JWS com a Apple:
        // https://developer.apple.com/documentation/appstoreserverapi
        // =====================================================
        // const isValid = await validateWithApple(payload.jws_token)
        // if (!isValid) {
        //   return new Response(
        //     JSON.stringify({ error: 'Invalid receipt' }),
        //     { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
        //   )
        // }

        // Upsert recibo na tabela apple_receipts
        const { error: upsertError } = await supabaseAdmin
            .from('apple_receipts')
            .upsert({
                user_id: user.id,
                transaction_id: payload.transaction_id,
                original_transaction_id: payload.original_transaction_id,
                product_id: payload.product_id,
                purchase_date: payload.purchase_date,
                expiration_date: payload.expiration_date || null,
                jws_token: payload.jws_token,
                environment: payload.environment || 'Production',
                status: 'active',
                updated_at: new Date().toISOString()
            }, {
                onConflict: 'transaction_id'
            })

        if (upsertError) {
            console.error('[ios-receipt] Error upserting receipt:', upsertError)
            return new Response(
                JSON.stringify({ error: 'Failed to save receipt' }),
                { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
            )
        }

        // Atualizar is_premium do usuário
        const { error: updateError } = await supabaseAdmin
            .from('user_profiles')
            .update({
                is_premium: true,
                updated_at: new Date().toISOString()
            })
            .eq('id', user.id)

        if (updateError) {
            console.error('[ios-receipt] Error updating user premium status:', updateError)
            // Não falha a request, pois o recibo já foi salvo
        }

        console.log(`[ios-receipt] Successfully processed receipt for user ${user.id}`)

        return new Response(
            JSON.stringify({
                success: true,
                message: 'Receipt processed successfully',
                is_premium: true
            }),
            {
                status: 200,
                headers: { ...corsHeaders, 'Content-Type': 'application/json' }
            }
        )

    } catch (error) {
        console.error('[ios-receipt] Unexpected error:', error)
        return new Response(
            JSON.stringify({ error: 'Internal server error' }),
            { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
        )
    }
})
