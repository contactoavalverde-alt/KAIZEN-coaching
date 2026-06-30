-- ═══════════════════════════════════════════════
-- KAIZEN COACHING — Testimonios (screenshots) + Storage
-- Correr una vez en: Supabase Dashboard → SQL Editor
-- ═══════════════════════════════════════════════

-- 1) Tabla
CREATE TABLE IF NOT EXISTS kaizen_testimonios (
  id          uuid DEFAULT gen_random_uuid() PRIMARY KEY,
  image_url   text NOT NULL,
  path        text,
  created_at  timestamptz DEFAULT now(),
  sort        int DEFAULT 0
);
ALTER TABLE kaizen_testimonios ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "testi public read" ON kaizen_testimonios;
CREATE POLICY "testi public read" ON kaizen_testimonios
  FOR SELECT TO anon, authenticated USING (true);

DROP POLICY IF EXISTS "testi admin write" ON kaizen_testimonios;
CREATE POLICY "testi admin write" ON kaizen_testimonios
  FOR ALL TO authenticated
  USING ((auth.jwt()->>'email') IN ('coachkaizen@gmail.com','contactoavalverde@gmail.com'))
  WITH CHECK ((auth.jwt()->>'email') IN ('coachkaizen@gmail.com','contactoavalverde@gmail.com'));

-- 2) Bucket de Storage (público)
INSERT INTO storage.buckets (id, name, public)
VALUES ('testimonios','testimonios', true)
ON CONFLICT (id) DO UPDATE SET public = true;

-- 3) Políticas de Storage para el bucket 'testimonios'
DROP POLICY IF EXISTS "testi obj public read" ON storage.objects;
CREATE POLICY "testi obj public read" ON storage.objects
  FOR SELECT TO public USING (bucket_id = 'testimonios');

DROP POLICY IF EXISTS "testi obj admin insert" ON storage.objects;
CREATE POLICY "testi obj admin insert" ON storage.objects
  FOR INSERT TO authenticated
  WITH CHECK (bucket_id = 'testimonios' AND (auth.jwt()->>'email') IN ('coachkaizen@gmail.com','contactoavalverde@gmail.com'));

DROP POLICY IF EXISTS "testi obj admin delete" ON storage.objects;
CREATE POLICY "testi obj admin delete" ON storage.objects
  FOR DELETE TO authenticated
  USING (bucket_id = 'testimonios' AND (auth.jwt()->>'email') IN ('coachkaizen@gmail.com','contactoavalverde@gmail.com'));
