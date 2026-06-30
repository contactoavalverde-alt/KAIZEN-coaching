-- ════════════════════════════════════════════════════════════════════════
-- site_content.sql — tablas de contenido editable del sitio (CMS)
-- kaizen_settings (key/value, alimenta el orbital + "Textos del Sitio"),
-- kaizen_orbital (nodos del sistema) y kaizen_videos (sección "En Acción").
-- Patrón RLS: lectura pública (anon, authenticated), escritura solo admin.
-- Idempotente: re-correr es seguro.
-- ════════════════════════════════════════════════════════════════════════

-- ───────── kaizen_settings (key/value) ─────────
CREATE TABLE IF NOT EXISTS kaizen_settings (
  key        text PRIMARY KEY,
  value      text,
  updated_at timestamptz DEFAULT now()
);
ALTER TABLE kaizen_settings ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "settings public read" ON kaizen_settings;
CREATE POLICY "settings public read" ON kaizen_settings FOR SELECT TO anon, authenticated USING (true);
DROP POLICY IF EXISTS "settings admin write" ON kaizen_settings;
CREATE POLICY "settings admin write" ON kaizen_settings FOR ALL TO authenticated
  USING ((auth.jwt()->>'email') IN ('coachkaizen@gmail.com','contactoavalverde@gmail.com'))
  WITH CHECK ((auth.jwt()->>'email') IN ('coachkaizen@gmail.com','contactoavalverde@gmail.com'));

-- ───────── kaizen_orbital (nodos del sistema "Metodología") ─────────
CREATE TABLE IF NOT EXISTS kaizen_orbital (
  id         uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  icon       text,
  label      text,
  title      text,
  descr      text,
  feats      text,
  sort       int  DEFAULT 0,
  created_at timestamptz DEFAULT now()
);
ALTER TABLE kaizen_orbital ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "orbital public read" ON kaizen_orbital;
CREATE POLICY "orbital public read" ON kaizen_orbital FOR SELECT TO anon, authenticated USING (true);
DROP POLICY IF EXISTS "orbital admin write" ON kaizen_orbital;
CREATE POLICY "orbital admin write" ON kaizen_orbital FOR ALL TO authenticated
  USING ((auth.jwt()->>'email') IN ('coachkaizen@gmail.com','contactoavalverde@gmail.com'))
  WITH CHECK ((auth.jwt()->>'email') IN ('coachkaizen@gmail.com','contactoavalverde@gmail.com'));

-- ───────── kaizen_videos (sección "En Acción") ─────────
CREATE TABLE IF NOT EXISTS kaizen_videos (
  id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  title       text,
  type        text,
  youtube_url text,
  video_url   text,
  video_path  text,
  thumb_url   text,
  sort        int  DEFAULT 0,
  created_at  timestamptz DEFAULT now()
);
ALTER TABLE kaizen_videos ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "videos public read" ON kaizen_videos;
CREATE POLICY "videos public read" ON kaizen_videos FOR SELECT TO anon, authenticated USING (true);
DROP POLICY IF EXISTS "videos admin write" ON kaizen_videos;
CREATE POLICY "videos admin write" ON kaizen_videos FOR ALL TO authenticated
  USING ((auth.jwt()->>'email') IN ('coachkaizen@gmail.com','contactoavalverde@gmail.com'))
  WITH CHECK ((auth.jwt()->>'email') IN ('coachkaizen@gmail.com','contactoavalverde@gmail.com'));
