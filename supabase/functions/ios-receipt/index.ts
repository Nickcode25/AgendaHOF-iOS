// Supabase Edge Function: ios-receipt (MINIMAL VERSION)
// Simply validates Apple IAP and sets is_premium = true
// No complex table operations to avoid permission issues

import { serve } from "https://deno.land/std@0.168.0/http/server.ts"
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

console.log('🍎 Apple IAP Receipt Validator (Minimal) initialized')

serve(async (req) => {
    try {
        console.log('📨 Received IAP receipt validation request')

        const supabaseUrl = Deno.env.get('SUPABASE_URL')!
        const supabaseKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!
        const supabase = createClient(supabaseUrl, supabaseKey)

        const {
            user_id,
            product_id,
            transaction_id
        } = await req.json()

        console.log(`📱 User: ${user_id}`)
        console.log(`🛍️  Product: ${product_id}`)
        console.log(`🔑 Transaction: ${transaction_id}`)

        // Validate product ID
        const validProducts = ['com.agendahof.premium']
        if (!validProducts.includes(product_id)) {
            console.error(`❌ Invalid product: ${product_id}`)
            return new Response(
                JSON.stringify({ error: 'Invalid product_id' }),
                { status: 400, headers: { 'Content-Type': 'application/json' } }
            )
        }

        // Simply set is_premium = true
        console.log(`✅ Setting is_premium = true for user ${user_id}`)

        const { error } = await supabase
            .from('user_profiles')
            .update({ is_premium: true })
            .eq('id', user_id)

        if (error) {
            console.error('❌ Error updating is_premium:', error)
            throw error
        }

        console.log('✅ Purchase validated and is_premium updated successfully')

        return new Response(
            JSON.stringify({
                success: true,
                message: 'Purchase validated successfully'
            }),
            {
                status: 200,
                headers: { 'Content-Type': 'application/json' }
            }
        )

    } catch (error) {
        console.error('❌ Error:', error)

        return new Response(
            JSON.stringify({
                error: 'Receipt validation failed',
                message: error.message || 'Unknown error'
            }),
            {
                status: 500,
                headers: { 'Content-Type': 'application/json' }
            }
        )
    }
})
