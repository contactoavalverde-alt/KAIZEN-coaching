# Despliegue y operación

## Hosting

- **Vercel** conectado a GitHub (`contactoavalverde-alt/KAIZEN-coaching`, rama `main`).
- Cada `git push origin main` dispara un **deploy automático**. No hay comando de build.
- `vercel.json`:
  ```json
  {
    "cleanUrls": true,
    "headers": [ { "source": "/(.*)\\.html", "headers": [ { "key": "Cache-Control", "value": "no-cache, must-revalidate" } ] },
                 { "source": "/",          "headers": [ { "key": "Cache-Control", "value": "no-cache, must-revalidate" } ] } ]
  }
  ```
  - `cleanUrls` → `/admin` sirve `admin.html`.
  - `no-cache` en HTML → el navegador siempre trae la última versión.

## Dominio

`kaizencoaching.com` comprado y gestionado vía Vercel. Apunta al proyecto directamente.

---

## Flujo de cambios

```bash
# 1. editar index.html / admin.html / portal.html
# 2. (opcional) verificar localmente:
python3 -m http.server 8000   # → http://localhost:8000/index.html
# 3. commit + push
git add -A
git commit -m "feat: descripción del cambio"
git push origin main
# 4. Vercel despliega solo en ~1-2 min
```

> Si un cambio "no aparece" en producción: hard refresh (`Cmd+Shift+R`) o incógnito.
> Con el `no-cache` ya configurado esto debería ser raro.

---

## Migraciones de base de datos

No hay CLI de Supabase configurado. Las migraciones se corren **manualmente**.

### Setup desde cero — orden exacto

Para una base nueva, correr los 9 archivos de `supabase/` **en este orden** (respeta dependencias).
Todos son idempotentes (`IF NOT EXISTS`, `DROP POLICY IF EXISTS`), así que re-correrlos es seguro.

| # | Archivo | Crea |
|---|---------|------|
| 1 | `migration.sql` | `kaizen_leads`, `kaizen_events` (tablas base + insert público) |
| 2 | `admins.sql` | Admins + RLS base |
| 3 | `portal.sql` | `kaizen_clients`, `kaizen_subscriptions`, `kaizen_payments`, `kaizen_messages` |
| 4 | `testimonios.sql` | `kaizen_testimonios` + bucket `testimonios` |
| 5 | `cms.sql` | `kaizen_blog`, `kaizen_transformaciones` + bucket `content` |
| 6 | `invitations.sql` | `kaizen_invitations` |
| 7 | `templates.sql` | `kaizen_templates` (+ seed de 3 plantillas) |
| 8 | `documents.sql` | `kaizen_documents` + bucket privado `client-docs` |
| 9 | `protect_client_fields.sql` | Columnas `kaizen_clients.tag/notes` + trigger (INSERT+UPDATE) |
| 10 | `onvo.sql` | Columnas/constraints ONVO, `grace_until`, dedup de pagos, `expire_overdue_subscriptions()` + `pg_cron` |
| 11 | `security.sql` | Rate limiting (`rate_limits` + `rl_hit`), límites de Storage, validación de leads (trigger) |

> `kaizen_orbital`, `kaizen_settings` y `kaizen_videos` se crearon en migraciones puntuales del CMS;
> si faltan, ver sus columnas en `docs/DATABASE.md` y crearlas con el mismo patrón (lectura
> pública, escritura admin). El paso 9 **debe ir al final**: agrega `tag/notes` a `kaizen_clients`
> (creada en el paso 3) y el trigger que las usa.

**Opción A — SQL Editor (recomendado):**
Supabase Dashboard → SQL Editor → pegar el contenido de cada archivo (en el orden de arriba) → Run.

**Opción B — API (requiere PAT temporal):**
```bash
curl -s -X POST "https://api.supabase.com/v1/projects/YOUR_PROJECT_REF/database/query" \
  -H "Authorization: Bearer <SUPABASE_PAT>" \
  -H "Content-Type: application/json" \
  -d '{"query": "<SQL aquí>"}'
```
⚠️ El PAT (`sbp_...`) es sensible: usarlo solo de forma temporal y **revocarlo** después.
Nunca comitearlo.

---

## Edge Functions (Supabase CLI)

Las 5 funciones (`supabase/functions/`) se despliegan con la CLI. Ver detalle de cada una y sus
secretos en [`BACKEND.md`](BACKEND.md).

```bash
export SUPABASE_ACCESS_TOKEN=<PAT sbp_...>
for fn in create-subscription onvo-webhook cancel-subscription send-invite list-payment-links; do
  supabase functions deploy $fn --project-ref YOUR_PROJECT_REF --no-verify-jwt --use-api
done
```

---

## Secretos

**En el frontend (públicos por diseño, van inline en los `.html`):**
| Secreto | Dónde vive |
|---|---|
| Anon key Supabase | inline en los `.html` (protegida por RLS) |
| `ONVO_PUBLIC_KEY` (publishable live) | inline en `index.html` (tokeniza la tarjeta) |
| Pexels API key | inline en `index.html` (solo lectura de videos) |

**De Edge Functions (`supabase secrets set ... --project-ref YOUR_PROJECT_REF`):**
`ONVO_SECRET_KEY`, `ONVO_PRICE_ID`, `ONVO_WEBHOOK_SECRET`, `RESEND_API_KEY`, `RESEND_FROM`,
`RESEND_REPLY_TO`, `INVITE_INTERNAL_SECRET`. Inventario con valores/origen en [`BACKEND.md`](BACKEND.md).

**Nunca comitear:** Supabase PAT `sbp_...`, service role key, las llaves *secret* de ONVO/Resend.
`.env.local` está en `.gitignore` (`git check-ignore .env.local`).

---

## Correo transaccional (Resend)

- Pasó de Web3Forms a **Resend**. Dominio `kaizencoaching.com` verificado (DKIM+SPF+MX en Vercel DNS).
- Invitaciones de bienvenida y dunning salen branded desde `hola@kaizencoaching.com` (Reply-To
  `coachkaizen@gmail.com`) vía la Edge Function `send-invite`. Ver [`BACKEND.md`](BACKEND.md).

---

## Cutover de pagos a producción (ONVO)

Resumen (detalle en [`BACKEND.md`](BACKEND.md)): crear producto+precio live, setear los 3 secretos
ONVO live, cambiar `ONVO_PUBLIC_KEY` en `index.html`, registrar el webhook live, y hacer un cobro
real de prueba. Hacerlo TODO junto (un estado "a medias" cobra pero no provisiona).

---

## Checklist de salud

- [ ] `kaizencoaching.com` carga y el hero reproduce videos.
- [ ] Enviar el formulario muestra **"LET'S GO!!"** y aparece el lead en el backoffice.
- [ ] Llega el correo de notificación a `coachkaizen@gmail.com`.
- [ ] Login en `/admin` con email admin funciona y carga datos.
- [ ] Subir contenido en el backoffice se refleja en la landing.
- [ ] `/admin` y `/portal` bloqueados en `robots.txt`.
