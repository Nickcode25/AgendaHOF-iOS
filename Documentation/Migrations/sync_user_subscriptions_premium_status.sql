-- =====================================================
-- MIGRACAO: Sincronizacao deterministica de assinatura
-- Fonte de verdade: user_subscriptions
-- Destino derivado: user_profiles.is_premium
-- =====================================================

-- COMPATIBILIDADE COM SCHEMAS LEGADOS:
-- garante colunas usadas pelo app/webhook mesmo em bancos antigos.
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1
        FROM information_schema.columns
        WHERE table_schema = 'public'
          AND table_name = 'user_subscriptions'
          AND column_name = 'status'
    ) THEN
        EXECUTE 'ALTER TABLE public.user_subscriptions ADD COLUMN status TEXT';
    END IF;

    IF NOT EXISTS (
        SELECT 1
        FROM information_schema.columns
        WHERE table_schema = 'public'
          AND table_name = 'user_subscriptions'
          AND column_name = 'current_period_start'
    ) THEN
        EXECUTE 'ALTER TABLE public.user_subscriptions ADD COLUMN current_period_start TIMESTAMPTZ';
    END IF;

    IF NOT EXISTS (
        SELECT 1
        FROM information_schema.columns
        WHERE table_schema = 'public'
          AND table_name = 'user_subscriptions'
          AND column_name = 'current_period_end'
    ) THEN
        EXECUTE 'ALTER TABLE public.user_subscriptions ADD COLUMN current_period_end TIMESTAMPTZ';
    END IF;

    IF NOT EXISTS (
        SELECT 1
        FROM information_schema.columns
        WHERE table_schema = 'public'
          AND table_name = 'user_subscriptions'
          AND column_name = 'next_billing_date'
    ) THEN
        EXECUTE 'ALTER TABLE public.user_subscriptions ADD COLUMN next_billing_date TIMESTAMPTZ';
    END IF;

    IF NOT EXISTS (
        SELECT 1
        FROM information_schema.columns
        WHERE table_schema = 'public'
          AND table_name = 'user_subscriptions'
          AND column_name = 'plan_type'
    ) THEN
        EXECUTE 'ALTER TABLE public.user_subscriptions ADD COLUMN plan_type TEXT';
    END IF;

    IF NOT EXISTS (
        SELECT 1
        FROM information_schema.columns
        WHERE table_schema = 'public'
          AND table_name = 'user_subscriptions'
          AND column_name = 'plan_name'
    ) THEN
        EXECUTE 'ALTER TABLE public.user_subscriptions ADD COLUMN plan_name TEXT';
    END IF;

    IF NOT EXISTS (
        SELECT 1
        FROM information_schema.columns
        WHERE table_schema = 'public'
          AND table_name = 'user_subscriptions'
          AND column_name = 'plan_amount'
    ) THEN
        EXECUTE 'ALTER TABLE public.user_subscriptions ADD COLUMN plan_amount NUMERIC';
    END IF;

    -- Backfill de nomes antigos comuns para current_period_end
    IF EXISTS (
        SELECT 1
        FROM information_schema.columns
        WHERE table_schema = 'public'
          AND table_name = 'user_subscriptions'
          AND column_name = 'expires_at'
    ) THEN
        EXECUTE '
            UPDATE public.user_subscriptions
            SET current_period_end = expires_at
            WHERE current_period_end IS NULL
              AND expires_at IS NOT NULL
        ';
    END IF;

    IF EXISTS (
        SELECT 1
        FROM information_schema.columns
        WHERE table_schema = 'public'
          AND table_name = 'user_subscriptions'
          AND column_name = 'period_end'
    ) THEN
        EXECUTE '
            UPDATE public.user_subscriptions
            SET current_period_end = period_end
            WHERE current_period_end IS NULL
              AND period_end IS NOT NULL
        ';
    END IF;

    -- Backfill de nomes antigos comuns para current_period_start
    IF EXISTS (
        SELECT 1
        FROM information_schema.columns
        WHERE table_schema = 'public'
          AND table_name = 'user_subscriptions'
          AND column_name = 'period_start'
    ) THEN
        EXECUTE '
            UPDATE public.user_subscriptions
            SET current_period_start = period_start
            WHERE current_period_start IS NULL
              AND period_start IS NOT NULL
        ';
    END IF;

    -- Normaliza status nulo para evitar falhas de regra
    EXECUTE '
        UPDATE public.user_subscriptions
        SET status = COALESCE(NULLIF(status, ''''), ''expired'')
        WHERE status IS NULL OR status = ''''
    ';
END;
$$;

-- 0) Indices para consultas de acesso
CREATE INDEX IF NOT EXISTS idx_user_subscriptions_user_status_dates
ON user_subscriptions(user_id, status, next_billing_date, current_period_end);

-- 1) Tabela de idempotencia para eventos Stripe (opcional, recomendado)
CREATE TABLE IF NOT EXISTS stripe_webhook_events (
    event_id TEXT PRIMARY KEY,
    event_type TEXT NOT NULL,
    livemode BOOLEAN,
    customer_id TEXT,
    subscription_id TEXT,
    payload JSONB NOT NULL,
    processed_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_stripe_webhook_events_subscription_id
ON stripe_webhook_events(subscription_id);

CREATE INDEX IF NOT EXISTS idx_stripe_webhook_events_processed_at
ON stripe_webhook_events(processed_at DESC);

-- 2) Normaliza regra de "tem acesso" a partir do status de assinatura
CREATE OR REPLACE FUNCTION public.subscription_status_has_access(
    p_status TEXT,
    p_next_billing_date TIMESTAMPTZ,
    p_current_period_end TIMESTAMPTZ,
    p_reference TIMESTAMPTZ DEFAULT NOW()
)
RETURNS BOOLEAN
LANGUAGE plpgsql
AS $$
BEGIN
    IF p_status IN ('active', 'trialing') THEN
        RETURN TRUE;
    END IF;

    IF p_status = 'pending_cancellation' THEN
        RETURN COALESCE(p_next_billing_date, p_current_period_end) > p_reference;
    END IF;

    RETURN FALSE;
END;
$$;

-- 3) Recalcula is_premium de um usuario com base em user_subscriptions
CREATE OR REPLACE FUNCTION public.recalculate_user_premium_status(
    p_user_id TEXT,
    p_reference TIMESTAMPTZ DEFAULT NOW()
)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_has_access BOOLEAN;
BEGIN
    SELECT EXISTS (
        SELECT 1
        FROM user_subscriptions us
        WHERE us.user_id::TEXT = p_user_id
          AND public.subscription_status_has_access(
              us.status,
              us.next_billing_date,
              us.current_period_end,
              p_reference
          )
    )
    INTO v_has_access;

    UPDATE user_profiles up
    SET is_premium = v_has_access,
        updated_at = NOW()
    WHERE up.id::TEXT = p_user_id;

    RETURN v_has_access;
END;
$$;

-- 4) Trigger: sempre que user_subscriptions mudar, sincroniza is_premium
CREATE OR REPLACE FUNCTION public.sync_user_profile_premium_from_subscriptions()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_new_user_id TEXT;
    v_old_user_id TEXT;
BEGIN
    IF TG_OP = 'INSERT' THEN
        v_new_user_id := NEW.user_id::TEXT;
        PERFORM public.recalculate_user_premium_status(v_new_user_id);
        RETURN NEW;
    ELSIF TG_OP = 'UPDATE' THEN
        v_new_user_id := NEW.user_id::TEXT;
        v_old_user_id := OLD.user_id::TEXT;
        IF v_old_user_id IS NOT NULL AND v_old_user_id <> v_new_user_id THEN
            PERFORM public.recalculate_user_premium_status(v_old_user_id);
        END IF;
        IF v_new_user_id IS NOT NULL THEN
            PERFORM public.recalculate_user_premium_status(v_new_user_id);
        END IF;
        RETURN NEW;
    ELSIF TG_OP = 'DELETE' THEN
        v_old_user_id := OLD.user_id::TEXT;
        PERFORM public.recalculate_user_premium_status(v_old_user_id);
        RETURN OLD;
    END IF;

    RETURN NULL;
END;
$$;

DROP TRIGGER IF EXISTS trg_sync_user_profile_premium_from_subscriptions ON user_subscriptions;
CREATE TRIGGER trg_sync_user_profile_premium_from_subscriptions
AFTER INSERT OR UPDATE OR DELETE ON user_subscriptions
FOR EACH ROW
EXECUTE FUNCTION public.sync_user_profile_premium_from_subscriptions();

-- 5) Funcao utilitaria de idempotencia para webhook Stripe (opcional)
CREATE OR REPLACE FUNCTION public.register_stripe_webhook_event(
    p_event_id TEXT,
    p_event_type TEXT,
    p_livemode BOOLEAN,
    p_customer_id TEXT,
    p_subscription_id TEXT,
    p_payload JSONB
)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_inserted INTEGER := 0;
BEGIN
    INSERT INTO stripe_webhook_events (
        event_id,
        event_type,
        livemode,
        customer_id,
        subscription_id,
        payload
    )
    VALUES (
        p_event_id,
        p_event_type,
        p_livemode,
        p_customer_id,
        p_subscription_id,
        p_payload
    )
    ON CONFLICT (event_id) DO NOTHING;

    GET DIAGNOSTICS v_inserted = ROW_COUNT;
    RETURN v_inserted > 0;
END;
$$;

-- 6) Backfill inicial para remover divergencia historica
UPDATE user_profiles up
SET is_premium = EXISTS (
    SELECT 1
    FROM user_subscriptions us
    WHERE us.user_id::TEXT = up.id::TEXT
      AND public.subscription_status_has_access(
          us.status,
          us.next_billing_date,
          us.current_period_end,
          NOW()
      )
),
updated_at = NOW()
WHERE up.role = 'owner'
   OR EXISTS (SELECT 1 FROM user_subscriptions us2 WHERE us2.user_id::TEXT = up.id::TEXT);

-- 7) Query de auditoria (execute manualmente quando quiser)
-- SELECT
--   up.id,
--   up.role,
--   up.is_premium,
--   EXISTS (
--     SELECT 1
--     FROM user_subscriptions us
--     WHERE us.user_id::TEXT = up.id::TEXT
--       AND public.subscription_status_has_access(
--         us.status,
--         us.next_billing_date,
--         us.current_period_end,
--         NOW()
--       )
--   ) AS expected_is_premium
-- FROM user_profiles up
-- WHERE up.role = 'owner';
