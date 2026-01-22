-- =====================================================
-- MIGRAÇÃO: Adicionar campo is_premium para assinaturas híbridas
-- Execute este SQL no Supabase Dashboard → SQL Editor
-- =====================================================

-- 1. Adicionar campo is_premium na tabela user_profiles
ALTER TABLE user_profiles 
ADD COLUMN IF NOT EXISTS is_premium BOOLEAN DEFAULT FALSE;

-- 2. Criar índice para consultas rápidas
CREATE INDEX IF NOT EXISTS idx_user_profiles_is_premium 
ON user_profiles(is_premium) 
WHERE is_premium = TRUE;

-- 3. Criar tabela para armazenar recibos Apple (auditoria)
CREATE TABLE IF NOT EXISTS apple_receipts (
    id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    transaction_id TEXT NOT NULL UNIQUE,
    original_transaction_id TEXT NOT NULL,
    product_id TEXT NOT NULL,
    purchase_date TIMESTAMPTZ NOT NULL,
    expiration_date TIMESTAMPTZ,
    jws_token TEXT,
    environment TEXT DEFAULT 'Production',
    status TEXT DEFAULT 'active',
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- 4. Índices para a tabela apple_receipts
CREATE INDEX IF NOT EXISTS idx_apple_receipts_user_id ON apple_receipts(user_id);
CREATE INDEX IF NOT EXISTS idx_apple_receipts_transaction_id ON apple_receipts(transaction_id);
CREATE INDEX IF NOT EXISTS idx_apple_receipts_original_transaction_id ON apple_receipts(original_transaction_id);

-- 5. Habilitar RLS na tabela apple_receipts
ALTER TABLE apple_receipts ENABLE ROW LEVEL SECURITY;

-- 6. Política: Usuários só podem ver seus próprios recibos
CREATE POLICY "Users can view own receipts" ON apple_receipts
    FOR SELECT USING (auth.uid() = user_id);

-- 7. Política: Apenas o backend (service role) pode inserir/atualizar
CREATE POLICY "Service role can manage receipts" ON apple_receipts
    FOR ALL USING (auth.role() = 'service_role');

-- 8. Função para atualizar updated_at automaticamente
CREATE OR REPLACE FUNCTION update_apple_receipts_updated_at()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- 9. Trigger para updated_at
DROP TRIGGER IF EXISTS trigger_apple_receipts_updated_at ON apple_receipts;
CREATE TRIGGER trigger_apple_receipts_updated_at
    BEFORE UPDATE ON apple_receipts
    FOR EACH ROW
    EXECUTE FUNCTION update_apple_receipts_updated_at();

-- 10. Função para atualizar is_premium baseado nos recibos ativos
CREATE OR REPLACE FUNCTION update_user_premium_status(p_user_id UUID)
RETURNS VOID AS $$
DECLARE
    has_active_subscription BOOLEAN;
BEGIN
    -- Verifica se há recibo ativo não expirado
    SELECT EXISTS (
        SELECT 1 FROM apple_receipts 
        WHERE user_id = p_user_id 
        AND status = 'active'
        AND (expiration_date IS NULL OR expiration_date > NOW())
    ) INTO has_active_subscription;
    
    -- Atualiza o status premium do usuário
    UPDATE user_profiles 
    SET is_premium = has_active_subscription,
        updated_at = NOW()
    WHERE id = p_user_id::TEXT;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- =====================================================
-- VERIFICAÇÃO: Execute para confirmar que funcionou
-- =====================================================
-- SELECT column_name, data_type, column_default 
-- FROM information_schema.columns 
-- WHERE table_name = 'user_profiles' AND column_name = 'is_premium';
