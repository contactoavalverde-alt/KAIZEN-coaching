-- ═══════════════════════════════════════════════
-- KAIZEN COACHING — Portal de Clientes
-- Tablas: clients, subscriptions, payments, messages
-- Seguridad: cada cliente ve solo lo suyo; admin ve todo
-- ═══════════════════════════════════════════════

-- 1) Perfil del cliente (1:1 con auth.users)
CREATE TABLE IF NOT EXISTS kaizen_clients (
  id          UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  user_id     UUID UNIQUE NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  name        TEXT,
  email       TEXT,
  phone       TEXT,
  created_at  TIMESTAMPTZ DEFAULT NOW()
);

-- 2) Suscripción
CREATE TABLE IF NOT EXISTS kaizen_subscriptions (
  id            UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  user_id       UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  plan          TEXT,                     -- KalosBody / Iron Legion / Bellator Temenos / Natus Vincere
  status        TEXT DEFAULT 'active',    -- active / paused / cancelled / expired
  start_date    DATE,
  end_date      DATE,
  monthly_price NUMERIC,
  app_url       TEXT,                     -- link al app de KAIZEN Coaching
  created_at    TIMESTAMPTZ DEFAULT NOW()
);

-- 3) Pagos
CREATE TABLE IF NOT EXISTS kaizen_payments (
  id          UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  user_id     UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  amount      NUMERIC,
  paid_on     DATE,
  period      TEXT,                       -- ej. "Junio 2026"
  method      TEXT,                       -- ej. "ONVO / Transferencia"
  status      TEXT DEFAULT 'paid',        -- paid / pending / failed
  created_at  TIMESTAMPTZ DEFAULT NOW()
);

-- 4) Mensajes de Kaizen al cliente
CREATE TABLE IF NOT EXISTS kaizen_messages (
  id          UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  user_id     UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  subject     TEXT,
  body        TEXT,
  is_read     BOOLEAN DEFAULT FALSE,
  created_at  TIMESTAMPTZ DEFAULT NOW()
);

-- ── RLS ──
ALTER TABLE kaizen_clients       ENABLE ROW LEVEL SECURITY;
ALTER TABLE kaizen_subscriptions ENABLE ROW LEVEL SECURITY;
ALTER TABLE kaizen_payments      ENABLE ROW LEVEL SECURITY;
ALTER TABLE kaizen_messages      ENABLE ROW LEVEL SECURITY;

-- Helper: ¿es el admin?  (auth.jwt() ->> 'email')
-- Cliente: solo sus filas. Admin: todas.

-- kaizen_clients
DROP POLICY IF EXISTS "client own profile select" ON kaizen_clients;
CREATE POLICY "client own profile select" ON kaizen_clients FOR SELECT TO authenticated
  USING (user_id = auth.uid() OR (auth.jwt()->>'email') = 'coachkaizen@gmail.com');
DROP POLICY IF EXISTS "client own profile insert" ON kaizen_clients;
CREATE POLICY "client own profile insert" ON kaizen_clients FOR INSERT TO authenticated
  WITH CHECK (user_id = auth.uid());
DROP POLICY IF EXISTS "client own profile update" ON kaizen_clients;
CREATE POLICY "client own profile update" ON kaizen_clients FOR UPDATE TO authenticated
  USING (user_id = auth.uid() OR (auth.jwt()->>'email') = 'coachkaizen@gmail.com')
  WITH CHECK (user_id = auth.uid() OR (auth.jwt()->>'email') = 'coachkaizen@gmail.com');

-- kaizen_subscriptions
DROP POLICY IF EXISTS "sub select" ON kaizen_subscriptions;
CREATE POLICY "sub select" ON kaizen_subscriptions FOR SELECT TO authenticated
  USING (user_id = auth.uid() OR (auth.jwt()->>'email') = 'coachkaizen@gmail.com');
DROP POLICY IF EXISTS "sub admin write" ON kaizen_subscriptions;
CREATE POLICY "sub admin write" ON kaizen_subscriptions FOR ALL TO authenticated
  USING ((auth.jwt()->>'email') = 'coachkaizen@gmail.com')
  WITH CHECK ((auth.jwt()->>'email') = 'coachkaizen@gmail.com');

-- kaizen_payments
DROP POLICY IF EXISTS "pay select" ON kaizen_payments;
CREATE POLICY "pay select" ON kaizen_payments FOR SELECT TO authenticated
  USING (user_id = auth.uid() OR (auth.jwt()->>'email') = 'coachkaizen@gmail.com');
DROP POLICY IF EXISTS "pay admin write" ON kaizen_payments;
CREATE POLICY "pay admin write" ON kaizen_payments FOR ALL TO authenticated
  USING ((auth.jwt()->>'email') = 'coachkaizen@gmail.com')
  WITH CHECK ((auth.jwt()->>'email') = 'coachkaizen@gmail.com');

-- kaizen_messages
DROP POLICY IF EXISTS "msg select" ON kaizen_messages;
CREATE POLICY "msg select" ON kaizen_messages FOR SELECT TO authenticated
  USING (user_id = auth.uid() OR (auth.jwt()->>'email') = 'coachkaizen@gmail.com');
DROP POLICY IF EXISTS "msg client mark read" ON kaizen_messages;
CREATE POLICY "msg client mark read" ON kaizen_messages FOR UPDATE TO authenticated
  USING (user_id = auth.uid() OR (auth.jwt()->>'email') = 'coachkaizen@gmail.com')
  WITH CHECK (user_id = auth.uid() OR (auth.jwt()->>'email') = 'coachkaizen@gmail.com');
DROP POLICY IF EXISTS "msg admin write" ON kaizen_messages;
CREATE POLICY "msg admin write" ON kaizen_messages FOR ALL TO authenticated
  USING ((auth.jwt()->>'email') = 'coachkaizen@gmail.com')
  WITH CHECK ((auth.jwt()->>'email') = 'coachkaizen@gmail.com');
