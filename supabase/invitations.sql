-- ═══════════════════════════════════════════════
-- KAIZEN COACHING — Invitaciones de clientes
-- Correr UNA vez en: Supabase Dashboard → SQL Editor
-- ═══════════════════════════════════════════════

CREATE TABLE IF NOT EXISTS kaizen_invitations (
  id          uuid DEFAULT gen_random_uuid() PRIMARY KEY,
  email       text NOT NULL UNIQUE,
  name        text,
  plan        text,
  notes       text,
  status      text DEFAULT 'pending',   -- pending | accepted
  invited_at  timestamptz DEFAULT now(),
  accepted_at timestamptz
);
ALTER TABLE kaizen_invitations ENABLE ROW LEVEL SECURITY;

-- Solo admins pueden leer y escribir invitaciones
DROP POLICY IF EXISTS "inv admin all" ON kaizen_invitations;
CREATE POLICY "inv admin all" ON kaizen_invitations FOR ALL TO authenticated
  USING ((auth.jwt()->>'email') IN ('coachkaizen@gmail.com','contactoavalverde@gmail.com'))
  WITH CHECK ((auth.jwt()->>'email') IN ('coachkaizen@gmail.com','contactoavalverde@gmail.com'));

-- El propio cliente puede actualizar su invitación a "accepted" al hacer login
DROP POLICY IF EXISTS "inv self update" ON kaizen_invitations;
CREATE POLICY "inv self update" ON kaizen_invitations FOR UPDATE TO authenticated
  USING (email = (auth.jwt()->>'email'))
  WITH CHECK (email = (auth.jwt()->>'email'));
