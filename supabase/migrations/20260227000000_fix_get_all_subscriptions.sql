-- ============================================================
-- Fix: Atualizar função get_all_subscriptions para retornar
-- next_billing_date, plan_name real, plan_type e stripe_subscription_id
--
-- Problema: A versão antiga da função não retornava esses campos,
-- então o admin panel mostrava "Plano Personalizado" e "Renova: -"
-- mesmo após o Sync Stripe atualizar o banco corretamente.
-- ============================================================

-- Dropar versão antiga (tem campos diferentes, precisa recriar)
DROP FUNCTION IF EXISTS public.get_all_subscriptions();
-- Nova versão com todos os campos necessários para o admin panel
CREATE FUNCTION public.get_all_subscriptions()
RETURNS TABLE (
  subscription_id           UUID,
  user_id                   UUID,
  user_email                TEXT,
  user_name                 TEXT,
  plan_name                 TEXT,
  plan_type                 TEXT,
  status                    TEXT,
  plan_amount               NUMERIC,
  discount_percentage       INTEGER,
  next_billing_date         TIMESTAMPTZ,
  created_at                TIMESTAMPTZ,
  stripe_subscription_id    TEXT
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  -- Apenas super admins podem chamar esta função
  IF NOT EXISTS (
    SELECT 1 FROM public.super_admins
    WHERE user_id = auth.uid()
       OR id = auth.uid()
  ) THEN
    RAISE EXCEPTION 'Acesso negado. Apenas super admins.';
  END IF;

  RETURN QUERY
  SELECT
    us.id                             AS subscription_id,
    us.user_id,
    u.email::TEXT                     AS user_email,
    COALESCE(
      (u.raw_user_meta_data->>'full_name'),
      split_part(u.email, '@', 1)
    )::TEXT                           AS user_name,
    -- plan_name: usar o campo real do banco (atualizado pelo Sync)
    COALESCE(us.plan_name, 'Plano Premium')::TEXT AS plan_name,
    -- plan_type: usar o campo real do banco
    COALESCE(us.plan_type, 'premium')::TEXT       AS plan_type,
    us.status::TEXT,
    us.plan_amount,
    COALESCE(us.discount_percentage, 0)::INTEGER  AS discount_percentage,
    us.next_billing_date,
    us.created_at,
    us.stripe_subscription_id::TEXT
  FROM public.user_subscriptions us
  JOIN auth.users u ON us.user_id = u.id
  ORDER BY us.created_at DESC;
END;
$$;
-- Conceder permissão de execução
GRANT EXECUTE ON FUNCTION public.get_all_subscriptions() TO authenticated;
DO $$
BEGIN
  RAISE NOTICE 'Migration 20260227_fix_get_all_subscriptions: função atualizada com next_billing_date, plan_name, plan_type e stripe_subscription_id';
END $$;
