# Base de datos — Supabase (`YOUR_PROJECT_REF`)

Postgres con **Row Level Security (RLS)** activado en todas las tablas. Todo el acceso desde el
navegador usa la **anon key** (pública); RLS es lo que protege los datos.

**Patrón de RLS usado en todo el proyecto:**
- **Lectura pública** (`anon`, `authenticated`) en contenido que se muestra en la web.
- **Escritura solo admin**: políticas que validan
  `(auth.jwt()->>'email') IN ('coachkaizen@gmail.com','contactoavalverde@gmail.com')`.
- **Inserción pública** solo en `kaizen_leads` y `kaizen_events` (para que visitantes anónimos puedan
  enviar el formulario y registrar eventos).
- **Datos de cliente** (`kaizen_subscriptions`, `kaizen_payments`, `kaizen_messages`, `kaizen_clients`):
  cada usuario solo ve/edita lo suyo (`user_id = auth.uid()`); admin ve todo.

---

## Tablas (16)

### Contenido público / CMS (lectura pública, escritura admin)

#### `kaizen_testimonios` — screenshots de testimonios
`id uuid · image_url text · path text · created_at · sort int`

#### `kaizen_blog` — entradas de blog
`id uuid · category · title · excerpt · image_url · image_path · video_url · date · read_time · sort int · created_at`

#### `kaizen_transformaciones` — antes/después
`id uuid · name · tag · badge · badge_sub · category · quote · before_url · before_path · after_url · after_path · sort int · created_at`
> La sección en la web se oculta si esta tabla está vacía.

#### `kaizen_videos` — sección "En Acción"
`id uuid · title · type · youtube_url · video_url · video_path · thumb_url · sort int · created_at`
> `type` = `youtube` (usa `youtube_url` + thumbnail automático) o `upload` (usa `video_url` del bucket `content`).

#### `kaizen_orbital` — nodos del sistema "Metodología KAIZEN"
`id uuid · icon · label · title · descr · feats · sort int · created_at`
> `icon` = clave string resuelta a SVG por `resolveIcon()` en index.html. `feats` = lista separada por saltos de línea.

#### `kaizen_settings` — textos editables (key/value)
`key text · value text · updated_at`
> Claves usadas: `orbital_tag`, `orbital_title`, `orbital_sub`.

---

### Captura de leads (inserción pública)

#### `kaizen_leads` — aplicaciones del formulario
`id uuid · name · email · phone · goal · status · source · programa · metas · pais · edad int · listo_invertir · rango_capital · created_at`
> RLS: INSERT permitido a `anon`. SELECT/UPDATE solo admin. `goal` se mantiene por compatibilidad (= `metas`).

#### `kaizen_events` — analítica + auditoría de eventos
`id uuid · event text · data jsonb · created_at`
> Eventos: `page_view`, `lead_captured` (públicos), y del backend: `subscription_started`,
> `payment_failed`, `subscription_cancelled`, `checkout_success`. INSERT público.

---

### Clientes y membresías (RLS por usuario + admin)

#### `kaizen_clients` — perfil de cliente
`id uuid · user_id uuid · name · email · phone · tag · notes · onvo_customer_id · created_at`
> Se crea automáticamente en el primer login del cliente (`ensureProfile()`) o al provisionar un
> pago (webhook). `tag` (intro/medium/high_end) y `notes` son **solo-admin** (trigger).
> El cliente puede editar name/email/phone desde el portal.

#### `kaizen_subscriptions` — suscripciones
`id uuid · user_id uuid · plan · status · start_date · end_date · monthly_price numeric · app_url · onvo_subscription_id (UNIQUE) · onvo_customer_id · grace_until date · created_at`
> `status` = active / past_due / cancelled / expired. `onvo_subscription_id` UNIQUE = candado de
> idempotencia del webhook. `grace_until` = fin del período de gracia del dunning.

#### `kaizen_payments` — pagos
`id uuid · user_id uuid · amount numeric · paid_on date · period · method · status · onvo_payment_intent_id · created_at`
> `onvo_payment_intent_id` con índice único parcial → deduplica pagos del webhook.

#### `kaizen_messages` — mensajes de Kaizen al cliente
`id uuid · user_id uuid · subject · body · is_read bool · created_at`

#### `kaizen_invitations` — invitaciones de clientes
`id uuid · email (unique) · name · plan · notes · status · invited_at · accepted_at`
> `status` = pending / accepted. Solo admin escribe; el cliente puede marcar la suya como accepted.

#### `kaizen_templates` — plantillas de correo (Template Manager)
`id uuid · key (unique) · name · subject · body_html · attachments jsonb · enabled bool · updated_at`
> `key` = welcome_50 / welcome_premium / payment_failed. Solo admin. Variables en subject/body: `{{nombre}} {{plan}} {{app_url}} {{monto}} {{fecha_pago}}`. Ver `supabase/templates.sql`.

#### `kaizen_documents` — documentos por cliente (privados)
`id uuid · user_id uuid · name · path · size bigint · created_at`
> El cliente ve los suyos (`user_id = auth.uid()`), el admin todos. Archivos en el bucket **privado** `client-docs` (carpeta por `user_id`), servidos con URLs firmadas. Ver `supabase/documents.sql`.

> **Nota:** un trigger (`supabase/protect_client_fields.sql`) impide que un no-admin escriba
> `kaizen_clients.tag`/`notes` — cubre **INSERT y UPDATE** (el INSERT-only era explotable, ver pentest
> en `BACKEND.md`).

---

### Pagos ONVO — constraints y dunning (`supabase/onvo.sql`)

- `UNIQUE(kaizen_subscriptions.onvo_subscription_id)` → idempotencia del webhook.
- Índice único parcial `UNIQUE(kaizen_payments.onvo_payment_intent_id)` → dedup de pagos.
- `expire_overdue_subscriptions()` → pasa `past_due` vencidas (cuya `grace_until` ya pasó) a
  `expired`. La corre **`pg_cron`** (job `kaizen-expire-overdue`, diario 09:00 UTC).
- Flujo completo de pagos/correo/seguridad: ver [`BACKEND.md`](BACKEND.md).

---

### Retirada

#### `kaizen_newsletter` — (módulo retirado)
`id uuid · email · source · created_at`
> El módulo de newsletter fue eliminado del frontend/backoffice. La tabla queda por histórico.

---

## Storage (buckets)

| Bucket | Privacidad | Uso |
|---|---|---|
| `testimonios` | público | Screenshots de testimonios |
| `content` | público | Imágenes de blog, videos subidos, fotos before/after, adjuntos de plantillas |
| `client-docs` | **privado** | Documentos por cliente — carpeta por `user_id`, URLs firmadas |

RLS de Storage: lectura pública; insert/delete solo admin.

---

## Cómo correr las migraciones

En **Supabase Dashboard → SQL Editor**, pegar y ejecutar el contenido de los archivos en
`supabase/` (idempotentes; usan `IF NOT EXISTS` / `DROP POLICY IF EXISTS`). El **orden exacto de
los 10 archivos** está en [`DEPLOYMENT.md`](DEPLOYMENT.md) → "Migraciones / Setup desde cero".
Resumen: `migration → admins → portal → testimonios → cms → invitations → templates → documents →
protect_client_fields → onvo`.

> Las tablas `kaizen_orbital`, `kaizen_settings`, `kaizen_videos` se crearon en migraciones puntuales;
> si faltan, ver sus columnas arriba y crearlas con el mismo patrón de RLS (lectura pública,
> escritura admin). Las **Edge Functions** se despliegan con la CLI, no con SQL — ver `BACKEND.md`.
