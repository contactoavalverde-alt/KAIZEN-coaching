-- ═══════════════════════════════════════════════
-- KAIZEN COACHING — Proteger campos internos del cliente (tag, notes)
-- Solo un admin puede modificar kaizen_clients.tag y kaizen_clients.notes.
-- Un cliente puede seguir editando su propio perfil (name, phone), pero
-- si intenta tocar tag/notes, el trigger conserva los valores anteriores.
-- NO modifica ninguna política RLS existente.
-- Correr UNA vez en: Supabase Dashboard → SQL Editor
-- ═══════════════════════════════════════════════

-- Columnas internas del cliente (las usa el trigger de abajo y el perfil en el admin)
ALTER TABLE kaizen_clients ADD COLUMN IF NOT EXISTS tag   text;   -- intro | medium | high_end
ALTER TABLE kaizen_clients ADD COLUMN IF NOT EXISTS notes text;   -- notas internas (no las ve el cliente)

CREATE OR REPLACE FUNCTION protect_client_admin_fields() RETURNS trigger AS $$
BEGIN
  -- Si quien escribe NO es admin, los campos internos quedan fuera de su control.
  IF COALESCE(auth.jwt()->>'email','') NOT IN ('contactoavalverde@gmail.com','luismariano@vegabarca.com') THEN
    IF TG_OP = 'INSERT' THEN
      NEW.tag   := NULL;   -- un cliente NO puede sembrar tag/notes al crear su perfil
      NEW.notes := NULL;
    ELSE
      NEW.tag   := OLD.tag;   -- al actualizar se preservan los valores del admin
      NEW.notes := OLD.notes;
    END IF;
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Cubre INSERT y UPDATE. El trigger BEFORE UPDATE-only era explotable: un cliente
-- podía auto-asignarse tag=high_end y notas al INSERTAR su perfil (pentest jun 2026).
DROP TRIGGER IF EXISTS trg_protect_client_admin_fields ON kaizen_clients;
CREATE TRIGGER trg_protect_client_admin_fields
  BEFORE INSERT OR UPDATE ON kaizen_clients
  FOR EACH ROW EXECUTE FUNCTION protect_client_admin_fields();
