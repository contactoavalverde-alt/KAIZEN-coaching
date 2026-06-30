-- ═══════════════════════════════════════════════
-- KAIZEN COACHING — Supabase Migration
-- Run this in: Supabase Dashboard → SQL Editor
-- ═══════════════════════════════════════════════

-- 1. Newsletter subscribers
CREATE TABLE IF NOT EXISTS kaizen_newsletter (
  id          UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  email       TEXT UNIQUE NOT NULL,
  created_at  TIMESTAMPTZ DEFAULT NOW(),
  source      TEXT DEFAULT 'website'
);

-- Enable RLS
ALTER TABLE kaizen_newsletter ENABLE ROW LEVEL SECURITY;

-- Allow anyone to INSERT (anon key)
CREATE POLICY "Allow public insert" ON kaizen_newsletter
  FOR INSERT TO anon WITH CHECK (true);

-- Only service role can SELECT
CREATE POLICY "Service role only select" ON kaizen_newsletter
  FOR SELECT TO service_role USING (true);


-- 2. Leads / Aplicaciones de Coaching (replica del Google Form)
CREATE TABLE IF NOT EXISTS kaizen_leads (
  id              UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  name            TEXT,
  email           TEXT,
  phone           TEXT,
  goal            TEXT,
  programa        TEXT,
  metas           TEXT,
  pais            TEXT,
  edad            INT,
  listo_invertir  TEXT,
  rango_capital   TEXT,
  created_at      TIMESTAMPTZ DEFAULT NOW(),
  status          TEXT DEFAULT 'new',
  source          TEXT DEFAULT 'website'
);

-- Si la tabla ya existía, agrega las columnas nuevas (idempotente)
ALTER TABLE kaizen_leads ADD COLUMN IF NOT EXISTS programa       TEXT;
ALTER TABLE kaizen_leads ADD COLUMN IF NOT EXISTS metas          TEXT;
ALTER TABLE kaizen_leads ADD COLUMN IF NOT EXISTS pais           TEXT;
ALTER TABLE kaizen_leads ADD COLUMN IF NOT EXISTS edad           INT;
ALTER TABLE kaizen_leads ADD COLUMN IF NOT EXISTS listo_invertir TEXT;
ALTER TABLE kaizen_leads ADD COLUMN IF NOT EXISTS rango_capital  TEXT;

ALTER TABLE kaizen_leads ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Allow public insert" ON kaizen_leads;
CREATE POLICY "Allow public insert" ON kaizen_leads
  FOR INSERT TO anon WITH CHECK (true);

DROP POLICY IF EXISTS "Service role only select" ON kaizen_leads;
CREATE POLICY "Service role only select" ON kaizen_leads
  FOR SELECT TO service_role USING (true);


-- 3. Page views / analytics (optional)
CREATE TABLE IF NOT EXISTS kaizen_events (
  id          UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  event       TEXT NOT NULL,
  data        JSONB,
  created_at  TIMESTAMPTZ DEFAULT NOW()
);

ALTER TABLE kaizen_events ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Allow public insert" ON kaizen_events
  FOR INSERT TO anon WITH CHECK (true);
