-- ═══════════════════════════════════════════════
-- KAIZEN COACHING — Plantillas de correo (Template Manager)
-- Correr UNA vez en: Supabase Dashboard → SQL Editor
-- ═══════════════════════════════════════════════

CREATE TABLE IF NOT EXISTS kaizen_templates (
  id         uuid DEFAULT gen_random_uuid() PRIMARY KEY,
  key        text UNIQUE NOT NULL,          -- welcome_50 | welcome_premium | payment_failed
  name       text NOT NULL,
  subject    text,
  body_html  text,
  attachments jsonb DEFAULT '[]'::jsonb,    -- [{ name, url, path }]
  enabled    boolean DEFAULT true,
  updated_at timestamptz DEFAULT now()
);
ALTER TABLE kaizen_templates ENABLE ROW LEVEL SECURITY;

-- Solo admins editan plantillas. (La Edge Function de envío usa service_role y omite RLS.)
DROP POLICY IF EXISTS "tpl admin all" ON kaizen_templates;
CREATE POLICY "tpl admin all" ON kaizen_templates FOR ALL TO authenticated
  USING ((auth.jwt()->>'email') IN ('coachkaizen@gmail.com','contactoavalverde@gmail.com'))
  WITH CHECK ((auth.jwt()->>'email') IN ('coachkaizen@gmail.com','contactoavalverde@gmail.com'));

-- Seed de las 3 plantillas base (no pisa las existentes)
INSERT INTO kaizen_templates (key, name, subject, body_html) VALUES
('welcome_50', 'Bienvenida — Programa grupal ($50)', '¡Bienvenido a KAIZEN Coaching! 🔥',
 '<h2>¡Bienvenido a KAIZEN Coaching, {{nombre}}! 🔥</h2><p>Tu plan: <b>{{plan}}</b></p><p>Entrá a tu plataforma: <a href="{{app_url}}">{{app_url}}</a></p><p>— Coach Kaizen · KAIZEN Coaching</p>'),
('welcome_premium', 'Bienvenida — Coaching premium (1:1)', 'Bienvenido a tu coaching personalizado — KAIZEN',
 '<h2>Bienvenido al coaching personalizado, {{nombre}}.</h2><p>Tu programa: <b>{{plan}}</b></p><p>Acceso a tu plataforma: <a href="{{app_url}}">{{app_url}}</a></p><p>— Coach Kaizen · KAIZEN Coaching</p>'),
('payment_failed', 'Seguimiento — Pago fallido (ONVO)', 'Recordatorio de pago — KAIZEN Coaching',
 '<h2>Hola {{nombre}}, un recordatorio sobre tu pago</h2><p>Tu pago de <b>{{monto}}</b> de <b>{{plan}}</b> con fecha <b>{{fecha_pago}}</b> no se pudo procesar.</p><p><a href="{{app_url}}">Actualizar mi pago</a></p><p>— Coach Kaizen · KAIZEN Coaching</p>')
ON CONFLICT (key) DO NOTHING;

-- Variables disponibles en subject/body_html:
--   {{nombre}}  {{plan}}  {{app_url}}  {{monto}}  {{fecha_pago}}
--
-- En welcome_50 / welcome_premium, {{app_url}} = MAGIC LINK de auto-login
-- (generado por la Edge Function send-invite). En payment_failed, {{app_url}}
-- = link al portal para actualizar el pago.
--
-- ───────────────────────────────────────────────
-- Envío (Edge Function send-invite, supabase/functions/send-invite):
--   type "welcome" → genera magic link + manda welcome_50/welcome_premium por Resend.
--   type "dunning" → manda payment_failed por Resend.
--   Si Resend falla (dominio sin verificar) → fallback al magic link nativo (solo welcome).
--   La llaman: onvo-webhook (header x-internal-secret) y el admin (JWT de admin).
--
-- Secretos (supabase secrets set ... --project-ref YOUR_PROJECT_REF):
--   RESEND_API_KEY          (re_...)
--   RESEND_FROM             "Coach Kaizen - KAIZEN Coaching <hola@kaizencoaching.com>"
--   RESEND_REPLY_TO         coachkaizen@gmail.com  (hola@ no recibe; las respuestas
--                            del cliente llegan al Gmail real de Kaizen)
--   INVITE_INTERNAL_SECRET  (secreto compartido webhook→send-invite)
--
-- ✅ DOMINIO kaizencoaching.com VERIFICADO en Resend (DKIM+SPF+MX vía Vercel DNS,
--    jun 2026). Resend entrega a cualquier cliente. El fallback al magic link
--    nativo de Supabase queda solo como red de seguridad si Resend fallara.
-- ───────────────────────────────────────────────
