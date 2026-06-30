-- ═══════════════════════════════════════════════
-- KAIZEN COACHING — CMS self-service (Testimonios, Blog, Transformaciones)
-- Correr UNA vez en: Supabase Dashboard → SQL Editor
-- Admins: coachkaizen@gmail.com, contactoavalverde@gmail.com
-- ═══════════════════════════════════════════════

-- ───── Helper macro de emails admin se repite en cada policy ─────

-- 1) TESTIMONIOS
CREATE TABLE IF NOT EXISTS kaizen_testimonios (
  id uuid DEFAULT gen_random_uuid() PRIMARY KEY,
  image_url text NOT NULL, path text,
  created_at timestamptz DEFAULT now(), sort int DEFAULT 0
);
ALTER TABLE kaizen_testimonios ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "testi public read" ON kaizen_testimonios;
CREATE POLICY "testi public read" ON kaizen_testimonios FOR SELECT TO anon, authenticated USING (true);
DROP POLICY IF EXISTS "testi admin write" ON kaizen_testimonios;
CREATE POLICY "testi admin write" ON kaizen_testimonios FOR ALL TO authenticated
  USING ((auth.jwt()->>'email') IN ('contactoavalverde@gmail.com','luismariano@vegabarca.com'))
  WITH CHECK ((auth.jwt()->>'email') IN ('contactoavalverde@gmail.com','luismariano@vegabarca.com'));

-- 2) BLOG
CREATE TABLE IF NOT EXISTS kaizen_blog (
  id uuid DEFAULT gen_random_uuid() PRIMARY KEY,
  category text, title text NOT NULL, excerpt text,
  image_url text, image_path text, video_url text,
  date text, read_time text, sort int DEFAULT 0,
  created_at timestamptz DEFAULT now()
);
ALTER TABLE kaizen_blog ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "blog public read" ON kaizen_blog;
CREATE POLICY "blog public read" ON kaizen_blog FOR SELECT TO anon, authenticated USING (true);
DROP POLICY IF EXISTS "blog admin write" ON kaizen_blog;
CREATE POLICY "blog admin write" ON kaizen_blog FOR ALL TO authenticated
  USING ((auth.jwt()->>'email') IN ('contactoavalverde@gmail.com','luismariano@vegabarca.com'))
  WITH CHECK ((auth.jwt()->>'email') IN ('contactoavalverde@gmail.com','luismariano@vegabarca.com'));

-- 3) TRANSFORMACIONES
CREATE TABLE IF NOT EXISTS kaizen_transformaciones (
  id uuid DEFAULT gen_random_uuid() PRIMARY KEY,
  name text NOT NULL, tag text, badge text, badge_sub text,
  category text, quote text,
  before_url text, before_path text, after_url text, after_path text,
  sort int DEFAULT 0, created_at timestamptz DEFAULT now()
);
ALTER TABLE kaizen_transformaciones ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "trans public read" ON kaizen_transformaciones;
CREATE POLICY "trans public read" ON kaizen_transformaciones FOR SELECT TO anon, authenticated USING (true);
DROP POLICY IF EXISTS "trans admin write" ON kaizen_transformaciones;
CREATE POLICY "trans admin write" ON kaizen_transformaciones FOR ALL TO authenticated
  USING ((auth.jwt()->>'email') IN ('contactoavalverde@gmail.com','luismariano@vegabarca.com'))
  WITH CHECK ((auth.jwt()->>'email') IN ('contactoavalverde@gmail.com','luismariano@vegabarca.com'));

-- 4) STORAGE BUCKETS (públicos)
INSERT INTO storage.buckets (id, name, public) VALUES ('testimonios','testimonios',true)
  ON CONFLICT (id) DO UPDATE SET public = true;
INSERT INTO storage.buckets (id, name, public) VALUES ('content','content',true)
  ON CONFLICT (id) DO UPDATE SET public = true;

-- 5) POLÍTICAS DE STORAGE (lectura pública + escritura admin) para ambos buckets
DROP POLICY IF EXISTS "media public read" ON storage.objects;
CREATE POLICY "media public read" ON storage.objects FOR SELECT TO public
  USING (bucket_id IN ('testimonios','content'));
DROP POLICY IF EXISTS "media admin insert" ON storage.objects;
CREATE POLICY "media admin insert" ON storage.objects FOR INSERT TO authenticated
  WITH CHECK (bucket_id IN ('testimonios','content') AND (auth.jwt()->>'email') IN ('contactoavalverde@gmail.com','luismariano@vegabarca.com'));
DROP POLICY IF EXISTS "media admin delete" ON storage.objects;
CREATE POLICY "media admin delete" ON storage.objects FOR DELETE TO authenticated
  USING (bucket_id IN ('testimonios','content') AND (auth.jwt()->>'email') IN ('contactoavalverde@gmail.com','luismariano@vegabarca.com'));
