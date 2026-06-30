-- ═══════════════════════════════════════════════
-- KAIZEN COACHING — Pagos ONVO (suscripción $50/mes)
-- Columnas de mapeo para vincular Supabase ↔ ONVO e idempotencia del webhook.
-- Correr UNA vez en: Supabase Dashboard → SQL Editor
-- ═══════════════════════════════════════════════

ALTER TABLE kaizen_subscriptions ADD COLUMN IF NOT EXISTS onvo_subscription_id text;
ALTER TABLE kaizen_subscriptions ADD COLUMN IF NOT EXISTS onvo_customer_id text;
ALTER TABLE kaizen_subscriptions ADD COLUMN IF NOT EXISTS grace_until date;   -- dunning: fin del período de gracia
ALTER TABLE kaizen_clients        ADD COLUMN IF NOT EXISTS onvo_customer_id text;

-- Idempotencia del webhook: una suscripción ONVO = una fila (reintentos no duplican)
ALTER TABLE kaizen_subscriptions DROP CONSTRAINT IF EXISTS uq_onvo_sub;
ALTER TABLE kaizen_subscriptions ADD CONSTRAINT uq_onvo_sub UNIQUE (onvo_subscription_id);

-- Dedup de pagos por el id del payment-intent de ONVO (evita doble cobro registrado)
ALTER TABLE kaizen_payments ADD COLUMN IF NOT EXISTS onvo_payment_intent_id text;
CREATE UNIQUE INDEX IF NOT EXISTS uq_pay_intent ON kaizen_payments(onvo_payment_intent_id) WHERE onvo_payment_intent_id IS NOT NULL;

-- Dunning: expira las suscripciones past_due cuya gracia venció (lo corre pg_cron a diario)
CREATE OR REPLACE FUNCTION expire_overdue_subscriptions() RETURNS integer AS $$
DECLARE n integer; BEGIN
  UPDATE kaizen_subscriptions SET status='expired'
   WHERE status='past_due' AND grace_until IS NOT NULL AND grace_until < current_date;
  GET DIAGNOSTICS n = ROW_COUNT; RETURN n;
END; $$ LANGUAGE plpgsql SECURITY DEFINER;

CREATE EXTENSION IF NOT EXISTS pg_cron;
-- Correr a diario 09:00 UTC:
--   SELECT cron.schedule('kaizen-expire-overdue','0 9 * * *','SELECT expire_overdue_subscriptions();');

-- ───────────────────────────────────────────────
-- Edge Functions (en supabase/functions/, desplegadas con la CLI):
--   create-subscription : crea customer+suscripción $50/mes en ONVO desde el
--                         paymentMethodId tokenizado client-side por el SDK.
--   onvo-webhook        : provisioning firmado (X-Webhook-Secret). Primer cobro
--                         → crea cliente+suscripción+pago+invitación; renovación
--                         → registra pago. Idempotente por onvo_subscription_id.
--
-- Deploy:
--   SUPABASE_ACCESS_TOKEN=<PAT> supabase functions deploy <fn> \
--     --project-ref YOUR_PROJECT_REF --no-verify-jwt --use-api
--
-- Secretos (supabase secrets set ... --project-ref YOUR_PROJECT_REF):
--   ONVO_SECRET_KEY      (onvo_live_secret_key_...)  ← NUNCA en el HTML/git
--   ONVO_PRICE_ID        (id del price recurrente $50/mes)
--                          LIVE: cmqmvadjn8ylwlh23yg0axr0e (producto cmqmvad9f8ylvlh23dpdgks4k)
--                          test: cmqmpqhp2amo8l623r289e1as
--   ONVO_WEBHOOK_SECRET  (valor que se registra en ONVO Dashboard → Developers → Webhooks)
--
-- ✅ EN PRODUCCIÓN (jun 2026): llaves live activas (secret+publishable+price+webhook),
--    mode "live". La publishable key live está en index.html (ONVO_PUBLIC_KEY).
--
-- Webhook URL a registrar en ONVO (Live):
--   https://YOUR_PROJECT_REF.supabase.co/functions/v1/onvo-webhook
--   eventos: payment-intent.succeeded, payment-intent.failed,
--            subscription.renewal.succeeded, subscription.renewal.failed,
--            subscription.cancelled
-- ───────────────────────────────────────────────
