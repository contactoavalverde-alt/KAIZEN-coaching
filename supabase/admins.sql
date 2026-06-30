-- ═══════════════════════════════════════════════
-- KAIZEN COACHING — Admins múltiples + endurecer lectura
-- Admins: coachkaizen@gmail.com, contactoavalverde@gmail.com
-- ═══════════════════════════════════════════════

-- LEADS: solo admins pueden leer (antes: cualquier autenticado)
DROP POLICY IF EXISTS "Authenticated read leads" ON kaizen_leads;
CREATE POLICY "Admins read leads" ON kaizen_leads FOR SELECT TO authenticated
  USING ((auth.jwt()->>'email') IN ('coachkaizen@gmail.com','contactoavalverde@gmail.com'));
DROP POLICY IF EXISTS "Authenticated update leads" ON kaizen_leads;
CREATE POLICY "Admins update leads" ON kaizen_leads FOR UPDATE TO authenticated
  USING ((auth.jwt()->>'email') IN ('coachkaizen@gmail.com','contactoavalverde@gmail.com'))
  WITH CHECK ((auth.jwt()->>'email') IN ('coachkaizen@gmail.com','contactoavalverde@gmail.com'));

-- NEWSLETTER
DROP POLICY IF EXISTS "Authenticated read newsletter" ON kaizen_newsletter;
CREATE POLICY "Admins read newsletter" ON kaizen_newsletter FOR SELECT TO authenticated
  USING ((auth.jwt()->>'email') IN ('coachkaizen@gmail.com','contactoavalverde@gmail.com'));

-- EVENTS
DROP POLICY IF EXISTS "Authenticated read events" ON kaizen_events;
CREATE POLICY "Admins read events" ON kaizen_events FOR SELECT TO authenticated
  USING ((auth.jwt()->>'email') IN ('coachkaizen@gmail.com','contactoavalverde@gmail.com'));

-- CLIENTS (cliente ve lo suyo; admin todo)
DROP POLICY IF EXISTS "client own profile select" ON kaizen_clients;
CREATE POLICY "client own profile select" ON kaizen_clients FOR SELECT TO authenticated
  USING (user_id = auth.uid() OR (auth.jwt()->>'email') IN ('coachkaizen@gmail.com','contactoavalverde@gmail.com'));
DROP POLICY IF EXISTS "client own profile update" ON kaizen_clients;
CREATE POLICY "client own profile update" ON kaizen_clients FOR UPDATE TO authenticated
  USING (user_id = auth.uid() OR (auth.jwt()->>'email') IN ('coachkaizen@gmail.com','contactoavalverde@gmail.com'))
  WITH CHECK (user_id = auth.uid() OR (auth.jwt()->>'email') IN ('coachkaizen@gmail.com','contactoavalverde@gmail.com'));

-- SUBSCRIPTIONS
DROP POLICY IF EXISTS "sub select" ON kaizen_subscriptions;
CREATE POLICY "sub select" ON kaizen_subscriptions FOR SELECT TO authenticated
  USING (user_id = auth.uid() OR (auth.jwt()->>'email') IN ('coachkaizen@gmail.com','contactoavalverde@gmail.com'));
DROP POLICY IF EXISTS "sub admin write" ON kaizen_subscriptions;
CREATE POLICY "sub admin write" ON kaizen_subscriptions FOR ALL TO authenticated
  USING ((auth.jwt()->>'email') IN ('coachkaizen@gmail.com','contactoavalverde@gmail.com'))
  WITH CHECK ((auth.jwt()->>'email') IN ('coachkaizen@gmail.com','contactoavalverde@gmail.com'));

-- PAYMENTS
DROP POLICY IF EXISTS "pay select" ON kaizen_payments;
CREATE POLICY "pay select" ON kaizen_payments FOR SELECT TO authenticated
  USING (user_id = auth.uid() OR (auth.jwt()->>'email') IN ('coachkaizen@gmail.com','contactoavalverde@gmail.com'));
DROP POLICY IF EXISTS "pay admin write" ON kaizen_payments;
CREATE POLICY "pay admin write" ON kaizen_payments FOR ALL TO authenticated
  USING ((auth.jwt()->>'email') IN ('coachkaizen@gmail.com','contactoavalverde@gmail.com'))
  WITH CHECK ((auth.jwt()->>'email') IN ('coachkaizen@gmail.com','contactoavalverde@gmail.com'));

-- MESSAGES
DROP POLICY IF EXISTS "msg select" ON kaizen_messages;
CREATE POLICY "msg select" ON kaizen_messages FOR SELECT TO authenticated
  USING (user_id = auth.uid() OR (auth.jwt()->>'email') IN ('coachkaizen@gmail.com','contactoavalverde@gmail.com'));
DROP POLICY IF EXISTS "msg client mark read" ON kaizen_messages;
CREATE POLICY "msg client mark read" ON kaizen_messages FOR UPDATE TO authenticated
  USING (user_id = auth.uid() OR (auth.jwt()->>'email') IN ('coachkaizen@gmail.com','contactoavalverde@gmail.com'))
  WITH CHECK (user_id = auth.uid() OR (auth.jwt()->>'email') IN ('coachkaizen@gmail.com','contactoavalverde@gmail.com'));
DROP POLICY IF EXISTS "msg admin write" ON kaizen_messages;
CREATE POLICY "msg admin write" ON kaizen_messages FOR ALL TO authenticated
  USING ((auth.jwt()->>'email') IN ('coachkaizen@gmail.com','contactoavalverde@gmail.com'))
  WITH CHECK ((auth.jwt()->>'email') IN ('coachkaizen@gmail.com','contactoavalverde@gmail.com'));
