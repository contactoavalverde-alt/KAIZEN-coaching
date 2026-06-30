-- ═══════════════════════════════════════════════
-- KAIZEN COACHING — Documentos por cliente (privados)
-- Kaizen sube documentos desde el admin; el cliente los ve/descarga en su portal.
-- Bucket PRIVADO + URLs firmadas. Cada cliente solo accede a SUS documentos.
-- Correr UNA vez en: Supabase Dashboard → SQL Editor
-- ═══════════════════════════════════════════════

-- 1) Tabla (metadatos)
CREATE TABLE IF NOT EXISTS kaizen_documents (
  id         uuid DEFAULT gen_random_uuid() PRIMARY KEY,
  user_id    uuid NOT NULL,
  name       text NOT NULL,
  path       text NOT NULL,         -- {user_id}/{timestamp}_{rand}.{ext}
  size       bigint,
  created_at timestamptz DEFAULT now()
);
ALTER TABLE kaizen_documents ENABLE ROW LEVEL SECURITY;

-- El cliente ve los suyos; el admin ve todos
DROP POLICY IF EXISTS "docs select" ON kaizen_documents;
CREATE POLICY "docs select" ON kaizen_documents FOR SELECT TO authenticated
  USING (user_id = auth.uid() OR (auth.jwt()->>'email') IN ('contactoavalverde@gmail.com','luismariano@vegabarca.com'));

-- Solo el admin sube/borra registros
DROP POLICY IF EXISTS "docs admin write" ON kaizen_documents;
CREATE POLICY "docs admin write" ON kaizen_documents FOR ALL TO authenticated
  USING ((auth.jwt()->>'email') IN ('contactoavalverde@gmail.com','luismariano@vegabarca.com'))
  WITH CHECK ((auth.jwt()->>'email') IN ('contactoavalverde@gmail.com','luismariano@vegabarca.com'));

-- 2) Bucket PRIVADO
INSERT INTO storage.buckets (id, name, public) VALUES ('client-docs','client-docs',false)
  ON CONFLICT (id) DO UPDATE SET public = false;

-- 3) Storage RLS — el path arranca con el user_id del cliente
DROP POLICY IF EXISTS "client-docs read" ON storage.objects;
CREATE POLICY "client-docs read" ON storage.objects FOR SELECT TO authenticated
  USING (bucket_id='client-docs' AND ((storage.foldername(name))[1] = auth.uid()::text
         OR (auth.jwt()->>'email') IN ('contactoavalverde@gmail.com','luismariano@vegabarca.com')));

DROP POLICY IF EXISTS "client-docs admin insert" ON storage.objects;
CREATE POLICY "client-docs admin insert" ON storage.objects FOR INSERT TO authenticated
  WITH CHECK (bucket_id='client-docs' AND (auth.jwt()->>'email') IN ('contactoavalverde@gmail.com','luismariano@vegabarca.com'));

DROP POLICY IF EXISTS "client-docs admin delete" ON storage.objects;
CREATE POLICY "client-docs admin delete" ON storage.objects FOR DELETE TO authenticated
  USING (bucket_id='client-docs' AND (auth.jwt()->>'email') IN ('contactoavalverde@gmail.com','luismariano@vegabarca.com'));
