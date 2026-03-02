# Stripe Webhook + Sync de `user_subscriptions`

## Objetivo
Garantir que o status de assinatura ativa seja consistente para todos os dispositivos da conta (multiplos iPhones/iPad no Owner + Staff herdando acesso do Owner).

## Estado atual neste repositório
- O app iOS consome `GET /api/access` em `https://agenda-hof-production.up.railway.app`.
- O codigo do webhook Stripe deste backend Railway nao esta neste repo.
- Este repo agora inclui a migracao SQL de sincronizacao em:
  - `Documentation/Migrations/sync_user_subscriptions_premium_status.sql`

## Contrato minimo do webhook (backend Railway)
1. Verificar assinatura Stripe (`stripe.webhooks.constructEvent`).
2. Processar somente eventos de assinatura:
   - `customer.subscription.created`
   - `customer.subscription.updated`
   - `customer.subscription.deleted`
   - `invoice.paid`
   - `invoice.payment_failed`
3. Idempotencia por `event.id`.
4. Upsert em `user_subscriptions` para o **Owner** (nao para Staff).
5. Recalcular `user_profiles.is_premium` logo apos o upsert.
6. Retornar HTTP 200 sempre que evento ja tiver sido processado.

## Mapeamento recomendado de status Stripe -> app
- `active` -> `active`
- `trialing` -> `trialing`
- `canceled` -> `cancelled`
- `past_due`, `unpaid`, `incomplete`, `incomplete_expired` -> `past_due`
- `active`/`trialing` com `cancel_at_period_end = true` -> `pending_cancellation`

## Exemplo de handler idempotente (Node/Express)
```js
import Stripe from 'stripe'
import { createClient } from '@supabase/supabase-js'

const stripe = new Stripe(process.env.STRIPE_SECRET_KEY)
const supabaseAdmin = createClient(process.env.SUPABASE_URL, process.env.SUPABASE_SERVICE_ROLE_KEY)

function mapStripeStatus(sub) {
  if ((sub.status === 'active' || sub.status === 'trialing') && sub.cancel_at_period_end) {
    return 'pending_cancellation'
  }
  if (sub.status === 'active') return 'active'
  if (sub.status === 'trialing') return 'trialing'
  if (sub.status === 'canceled') return 'cancelled'
  if (['past_due', 'unpaid', 'incomplete', 'incomplete_expired'].includes(sub.status)) return 'past_due'
  return 'expired'
}

async function resolveOwnerUserId(subscription) {
  const metadataUserId = subscription.metadata?.user_id
  if (metadataUserId) return metadataUserId

  const customerId = typeof subscription.customer === 'string'
    ? subscription.customer
    : subscription.customer?.id

  if (!customerId) return null

  // Requer coluna stripe_customer_id em user_profiles (ou tabela de mapeamento equivalente)
  const { data, error } = await supabaseAdmin
    .from('user_profiles')
    .select('id')
    .eq('stripe_customer_id', customerId)
    .limit(1)

  if (error) throw error
  return data?.[0]?.id ?? null
}

router.post('/api/stripe/webhook', rawBodyMiddleware, async (req, res) => {
  let event
  try {
    event = stripe.webhooks.constructEvent(
      req.body,
      req.headers['stripe-signature'],
      process.env.STRIPE_WEBHOOK_SECRET
    )
  } catch (err) {
    return res.status(400).send(`Webhook signature invalid: ${err.message}`)
  }

  const relevant = new Set([
    'customer.subscription.created',
    'customer.subscription.updated',
    'customer.subscription.deleted',
    'invoice.paid',
    'invoice.payment_failed'
  ])

  if (!relevant.has(event.type)) {
    return res.status(200).json({ ok: true, skipped: true })
  }

  try {
    const sub = event.data.object.object === 'subscription'
      ? event.data.object
      : await stripe.subscriptions.retrieve(event.data.object.subscription)

    const ownerUserId = await resolveOwnerUserId(sub)
    if (!ownerUserId) {
      // Nao falha o webhook para evitar retries infinitos sem mapeamento
      return res.status(200).json({ ok: true, ignored: 'owner_not_found' })
    }

    // 1) Idempotencia (tabela criada pela migracao SQL)
    const { data: dedupeRows, error: dedupeError } = await supabaseAdmin
      .rpc('register_stripe_webhook_event', {
        p_event_id: event.id,
        p_event_type: event.type,
        p_livemode: event.livemode,
        p_customer_id: typeof sub.customer === 'string' ? sub.customer : sub.customer?.id ?? null,
        p_subscription_id: sub.id,
        p_payload: event
      })

    if (dedupeError) throw dedupeError
    const shouldProcess = Boolean(dedupeRows)
    if (!shouldProcess) {
      return res.status(200).json({ ok: true, duplicate: true })
    }

    const status = mapStripeStatus(sub)
    const planType = String(sub.items?.data?.[0]?.price?.metadata?.plan_type || '').toLowerCase() || null
    const planName = sub.items?.data?.[0]?.price?.nickname || sub.items?.data?.[0]?.price?.id || null
    const planAmount = (sub.items?.data?.[0]?.price?.unit_amount ?? 0) / 100

    // 2) Fonte de verdade para acesso multi-dispositivo
    const payload = {
      id: sub.id,
      user_id: ownerUserId,
      status,
      plan_id: sub.items?.data?.[0]?.price?.id ?? null,
      plan_type: planType,
      plan_name: planName,
      plan_amount: planAmount,
      current_period_start: sub.current_period_start ? new Date(sub.current_period_start * 1000).toISOString() : null,
      current_period_end: sub.current_period_end ? new Date(sub.current_period_end * 1000).toISOString() : null,
      next_billing_date: sub.current_period_end ? new Date(sub.current_period_end * 1000).toISOString() : null,
      updated_at: new Date().toISOString()
    }

    const { error: upsertError } = await supabaseAdmin
      .from('user_subscriptions')
      .upsert(payload, { onConflict: 'id' })

    if (upsertError) throw upsertError

    // 3) Derivado para fallback do app
    const { error: recalcError } = await supabaseAdmin
      .rpc('recalculate_user_premium_status', { p_user_id: ownerUserId })

    if (recalcError) throw recalcError

    return res.status(200).json({ ok: true })
  } catch (err) {
    console.error('[stripe-webhook] failed:', err)
    return res.status(500).json({ ok: false })
  }
})
```

## Requisito importante para Staff
- O webhook deve atualizar assinatura no `user_id` do Owner.
- O `GET /api/access` da conta Staff deve resolver `ownerId` via `parent_user_id` (ou regra equivalente) e validar a assinatura do Owner.
- Nao criar assinatura separada para Staff.

## Checklist de deploy
1. Executar `Documentation/Migrations/sync_user_subscriptions_premium_status.sql` no Supabase SQL Editor.
2. Deploy do backend Railway com webhook idempotente.
3. Confirmar que metadados Stripe possuem `user_id` do Owner ou mapeamento por `stripe_customer_id`.
4. Testar em paralelo:
   - iPhone Owner (dentista)
   - iPhone Owner (admin)
   - iPad Owner
   - iPhone Staff (secretaria)
5. Validar que todos continuam com acesso apos 24h e apos 72h.

## Queries de auditoria
```sql
-- Divergencias entre derivado (user_profiles) e fonte de verdade (user_subscriptions)
SELECT
  up.id,
  up.role,
  up.is_premium,
  EXISTS (
    SELECT 1
    FROM user_subscriptions us
    WHERE us.user_id::TEXT = up.id
      AND subscription_status_has_access(us.status, us.next_billing_date, us.current_period_end, NOW())
  ) AS expected_is_premium
FROM user_profiles up
WHERE up.role = 'owner';
```

```sql
-- Ultimos eventos Stripe processados
SELECT event_id, event_type, subscription_id, processed_at
FROM stripe_webhook_events
ORDER BY processed_at DESC
LIMIT 50;
```
