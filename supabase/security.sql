-- ═══════════════════════════════════════════════
-- KAIZEN COACHING — Endurecimiento de seguridad
-- Rate limiting (anti-abuso) + límites de subida en Storage.
-- Correr en: Supabase Dashboard → SQL Editor.
-- ═══════════════════════════════════════════════

-- ── Rate limiting ─────────────────────────────────────────────
-- Contador por clave (acción:ip o acción:user) con ventana deslizante simple.
-- Lo usan las Edge Functions vía rl_hit() con service role; nadie más lo toca.
CREATE TABLE IF NOT EXISTS rate_limits (
  key      text PRIMARY KEY,
  count    int  NOT NULL DEFAULT 0,
  reset_at timestamptz NOT NULL
);
ALTER TABLE rate_limits ENABLE ROW LEVEL SECURITY;  -- sin políticas = denegado a anon/authenticated

-- Devuelve TRUE si la petición está permitida; FALSE si excede el límite.
-- Atómico (insert ... on conflict) → seguro ante concurrencia.
CREATE OR REPLACE FUNCTION rl_hit(p_key text, p_max int, p_window int)
RETURNS boolean LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE c int; r timestamptz;
BEGIN
  INSERT INTO rate_limits(key, count, reset_at)
    VALUES (p_key, 1, now() + make_interval(secs => p_window))
  ON CONFLICT (key) DO UPDATE
    SET count    = CASE WHEN rate_limits.reset_at < now() THEN 1 ELSE rate_limits.count + 1 END,
        reset_at = CASE WHEN rate_limits.reset_at < now() THEN now() + make_interval(secs => p_window) ELSE rate_limits.reset_at END
  RETURNING count, reset_at INTO c, r;
  RETURN c <= p_max;
END; $$;

-- Limpieza periódica de filas viejas (pg_cron, si está disponible)
CREATE OR REPLACE FUNCTION rl_gc() RETURNS void LANGUAGE sql SECURITY DEFINER AS $$
  DELETE FROM rate_limits WHERE reset_at < now() - interval '1 day';
$$;
-- SELECT cron.schedule('kaizen-rl-gc','0 4 * * *','SELECT rl_gc();');  -- correr una vez

-- ── Límites de subida en Storage (previene archivos no permitidos / enormes) ──
-- content: imágenes + video (blog, transformaciones, "En Acción", adjuntos)
UPDATE storage.buckets
   SET file_size_limit = 104857600,  -- 100 MB
       allowed_mime_types = ARRAY['image/jpeg','image/png','image/webp','image/gif','video/mp4','video/webm','video/quicktime']
 WHERE id = 'content';
-- testimonios: solo imágenes
UPDATE storage.buckets
   SET file_size_limit = 10485760,   -- 10 MB
       allowed_mime_types = ARRAY['image/jpeg','image/png','image/webp']
 WHERE id = 'testimonios';
-- client-docs: documentos (privado)
UPDATE storage.buckets
   SET file_size_limit = 26214400,   -- 25 MB
       allowed_mime_types = ARRAY['application/pdf','image/jpeg','image/png','image/webp','application/vnd.openxmlformats-officedocument.wordprocessingml.document','application/msword']
 WHERE id = 'client-docs';

-- ── Validación del formulario público de leads ────────────────
-- INSERT es público (anon). Este trigger recorta longitudes, normaliza y fuerza
-- el status, para que un bot/atacante no pueda inyectar datos enormes ni un
-- status arbitrario (ej. 'client'). Los tipos ya los valida Postgres (edad int…).
CREATE OR REPLACE FUNCTION validate_lead() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  NEW.name          := left(btrim(coalesce(NEW.name,'')), 120);
  NEW.email         := left(lower(btrim(coalesce(NEW.email,''))), 254);
  NEW.phone         := left(btrim(coalesce(NEW.phone,'')), 40);
  NEW.programa      := left(coalesce(NEW.programa,''), 120);
  NEW.metas         := left(coalesce(NEW.metas,''), 2000);
  NEW.goal          := left(coalesce(NEW.goal,''), 2000);
  NEW.pais          := left(coalesce(NEW.pais,''), 80);
  NEW.rango_capital := left(coalesce(NEW.rango_capital,''), 60);
  NEW.listo_invertir:= left(coalesce(NEW.listo_invertir,''), 60);
  NEW.source        := left(coalesce(NEW.source,'web'), 60);
  IF TG_OP = 'INSERT' THEN NEW.status := 'new'; END IF;  -- nadie entra como 'client' por el form
  IF NEW.edad IS NOT NULL AND (NEW.edad < 0 OR NEW.edad > 120) THEN NEW.edad := NULL; END IF;
  RETURN NEW;
END; $$;
DROP TRIGGER IF EXISTS trg_validate_lead ON kaizen_leads;
CREATE TRIGGER trg_validate_lead BEFORE INSERT OR UPDATE ON kaizen_leads
  FOR EACH ROW EXECUTE FUNCTION validate_lead();
