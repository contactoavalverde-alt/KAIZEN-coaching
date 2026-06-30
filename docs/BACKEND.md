# Backend — Edge Functions, Pagos (ONVO) y Correo (Resend)

Este doc cubre la parte servidor del proyecto: las **Supabase Edge Functions** (Deno),
el **loop de pagos con ONVO** ($50/mes recurrente, en producción) y el **correo branded con
Resend**. Es lo que NO se ve en el HTML y lo más fácil de perder en un handoff.

Proyecto Supabase: `YOUR_PROJECT_REF` · Dominio: `kaizencoaching.com`

---

## 1. Edge Functions (`supabase/functions/`)

| Función | Qué hace | Auth | Secretos que usa |
|---|---|---|---|
| `create-subscription` | Crea la suscripción $50/mes en ONVO con el `paymentMethodId` tokenizado client-side. Devuelve `requiresAction` + `paymentIntentId` si el banco pide 3DS. | Ninguna (checkout anónimo); requiere PM válido | `ONVO_SECRET_KEY`, `ONVO_PRICE_ID` |
| `onvo-webhook` | **Fuente de verdad del provisioning.** ONVO avisa por webhook firmado. Primer cobro → crea cliente + suscripción + pago + correo de bienvenida. Renovación → registra pago. Falla → dunning (past_due + gracia). Cancelada → cancelled. | Firma `X-Webhook-Secret` | `ONVO_SECRET_KEY`, `ONVO_WEBHOOK_SECRET`, `INVITE_INTERNAL_SECRET`, service role |
| `cancel-subscription` | El cliente cancela SU suscripción desde el portal. Verifica el JWT y solo cancela la sub de ese `user_id` (nunca un id arbitrario). DELETE en ONVO + `cancelled` en Supabase. | JWT del cliente | `ONVO_SECRET_KEY`, anon, service role |
| `send-invite` | Manda los correos branded (plantillas `kaizen_templates`) por Resend. `welcome` genera magic link de auto-login; `dunning` manda `payment_failed`. Fallback al magic link nativo si Resend falla. | `x-internal-secret` (webhook) **o** JWT admin (panel) | `RESEND_API_KEY`, `RESEND_FROM`, `RESEND_REPLY_TO`, `INVITE_INTERNAL_SECRET`, anon, service role |
| `list-payment-links` | Lista los links de pago de ONVO para el admin (la secret key no toca el browser). Cruza cada link contra `kaizen_subscriptions` y devuelve `paid`/`activeLoops` por link (match por nickname del precio). | JWT admin | `ONVO_SECRET_KEY`, anon, service role |

### Deploy de Edge Functions (Supabase CLI)

```bash
export SUPABASE_ACCESS_TOKEN=<PAT sbp_...>
supabase functions deploy <nombre> \
  --project-ref YOUR_PROJECT_REF --no-verify-jwt --use-api
```
`--no-verify-jwt` porque la autorización la hace cada función internamente (firma de webhook,
JWT de admin, o secreto interno), no el gateway.

### Secretos de las funciones

`supabase secrets set CLAVE="valor" --project-ref YOUR_PROJECT_REF`

| Secreto | Valor / dónde sale |
|---|---|
| `ONVO_SECRET_KEY` | `onvo_live_secret_key_...` (Dashboard ONVO → Producción → Developers) |
| `ONVO_PRICE_ID` | id del precio $50/mes recurrente. **LIVE: `cmqmvadjn8ylwlh23yg0axr0e`** (producto `cmqmvad9f8ylvlh23dpdgks4k`) |
| `ONVO_WEBHOOK_SECRET` | el signing secret que da ONVO al registrar el webhook |
| `RESEND_API_KEY` | `re_...` (dashboard de Resend) |
| `RESEND_FROM` | `"Coach Kaizen - KAIZEN Coaching <hola@kaizencoaching.com>"` |
| `RESEND_REPLY_TO` | `coachkaizen@gmail.com` (hola@ no recibe; las respuestas van al Gmail real) |
| `INVITE_INTERNAL_SECRET` | secreto compartido webhook→send-invite (string aleatorio) |
| Auto-inyectados | `SUPABASE_URL`, `SUPABASE_ANON_KEY`, `SUPABASE_SERVICE_ROLE_KEY` (los provee Supabase) |

> Las funciones NO se redeployan al cambiar un secreto: el cambio toma efecto en la próxima
> invocación. Aun así, tras cambiar `RESEND_FROM` conviene redeploy para forzar cold start.

---

## 2. Loop de pagos — ONVO ($50/mes recurrente, EN PRODUCCIÓN)

ONVO es el procesador (Costa Rica). API base `https://api.onvopay.com/v1` (misma para test y live;
distingue por la llave). Modelo tipo Stripe: producto → precio (recurring month) → suscripción.

### Checkout (en `index.html`, modal `#pay-modal`)
- 100% **con la marca de KAIZEN** (resumen, precio, disclaimer de cargo mensual automático).
- El formulario de tarjeta es propio → **PCI SAQ-A-EP** (la tarjeta pasa por el JS de la página).
  Decisión consciente del cliente (quería todo branded, no los inputs de ONVO).
- `ONVO_PUBLIC_KEY` (publishable, **live**) está inline en `index.html` — es pública por diseño.

### Flujo completo
```
1. Cliente llena contacto + tarjeta en el checkout branded
2. Tokeniza la tarjeta DIRECTO a ONVO (POST /payment-methods con la publishable key)
   → la tarjeta NUNCA toca nuestro servidor; devuelve paymentMethodId + customerId
3. create-subscription (Edge Fn, secret key) crea la suscripción $50/mes
4. 3DS: si el banco lo pide, la sub queda 'incomplete' y el paymentIntent 'requires_action'
   → create-subscription devuelve {requiresAction:true, paymentIntentId}
   → el front muestra el challenge EN la página con el SDK de ONVO:
       const onvo = ONVO(ONVO_PUBLIC_KEY);
       await onvo.handleNextAction({ paymentIntentId });   // js.onvopay.com/v1
   → solo se da por bueno si el paymentIntent queda 'succeeded'
5. ONVO cobra → dispara webhook firmado → onvo-webhook PROVISIONA
   (crea auth user + kaizen_clients + kaizen_subscriptions + kaizen_payments + correo de bienvenida)
```
> El provisioning SIEMPRE ocurre en el webhook firmado, NUNCA confiando en el redirect del browser.

### Webhook (registrar en ONVO Dashboard → Producción → Developers → Webhooks)
- URL: `https://YOUR_PROJECT_REF.supabase.co/functions/v1/onvo-webhook`
- Eventos: `payment-intent.succeeded`, `payment-intent.failed`,
  `subscription.renewal.succeeded`, `subscription.renewal.failed`, `subscription.cancelled`
- ONVO da un **signing secret** → va en `ONVO_WEBHOOK_SECRET`. El webhook responde 401 sin firma.

### Idempotencia y dunning (robustez de producción)
- **Idempotencia:** `UNIQUE(kaizen_subscriptions.onvo_subscription_id)` actúa de candado (la sub se
  inserta primero; entregas duplicadas del webhook no duplican nada). Pagos deduplicados por
  índice único parcial `UNIQUE(kaizen_payments.onvo_payment_intent_id)`.
- **Dunning:** renovación fallida → `status='past_due'` + `grace_until = hoy + 7d`. `pg_cron`
  (`kaizen-expire-overdue`, diario 09:00 UTC) corre `expire_overdue_subscriptions()` y pasa a
  `expired` lo vencido. Un cobro exitoso reactiva `past_due → active`.
- **Cancelación:** el cliente cancela desde el portal (`cancel-subscription`). Estados en el
  portal: active/past_due (mantienen acceso, banner de gracia), expired (reactivar por WhatsApp),
  cancelled (re-suscribir).

### Links de pago de ONVO
- Se crean en el panel de ONVO (lineItems con un priceId). Un link **mensual** que recolecte el
  **email** del cliente provisiona igual que el checkout: el webhook lee los datos del *customer*
  de ONVO (no de metadata) y manda el correo de crear cuenta.
- El admin los ve en Pagos → panel "Links de pago" (vía `list-payment-links`), con conteo de
  **pagados** por link (cruce por nickname del precio). ONVO solo expone `isActive` por link;
  no expone conversión pagada → por eso la cruzamos contra `kaizen_subscriptions`.

### Cutover a producción (ya hecho, jun 2026)
Para repetirlo en otra cuenta: crear producto+precio live, setear los 3 secretos ONVO live,
cambiar `ONVO_PUBLIC_KEY` en `index.html` a la publishable live, registrar el webhook live, y
hacer un cobro real de prueba. Hacerlo TODO junto (un estado "a medias" cobra pero no provisiona).

---

## 3. Correo branded — Resend

- Proveedor: **Resend**. Dominio `kaizencoaching.com` **verificado** (DKIM+SPF+MX vía Vercel DNS).
- Remitente: `hola@kaizencoaching.com`; **Reply-To** a `coachkaizen@gmail.com` (hola@ no tiene buzón).
- La función `send-invite` arma el correo con la plantilla de `kaizen_templates`, sustituye las
  variables y envía por Resend. Tipos: `welcome` (genera magic link de auto-login) y `dunning`.
- **Fallback:** si Resend no puede entregar (p.ej. dominio sin verificar), `welcome` cae al magic
  link nativo de Supabase para que el cliente no quede sin acceso.
- **Quién la llama:** `onvo-webhook` (con `x-internal-secret`) al provisionar/fallar pago, y el
  admin (`doSendInvite` en `crearAcceso`/CSV/re-invitar, con JWT admin).
- Plantillas (`kaizen_templates`, editables desde el Template Manager del backoffice):
  `welcome_50`, `welcome_premium`, `payment_failed`. Variables: `{{nombre}} {{plan}} {{app_url}}
  {{monto}} {{fecha_pago}}`. En welcome, `{{app_url}}` = magic link de auto-login.

---

## 4. Seguridad (pentest jun 2026)

Pentest hecho como atacante real (solo anon key + cuenta de cliente). Resultado: sólido.
- ✅ Sin secretos en el código desplegado (solo publishable/anon).
- ✅ RLS de lectura: un cliente ve `[]` en todas las tablas sensibles ajenas.
- ✅ Auto-otorgarse suscripción/pago → 403. Webhook no forjable → 401.
- ✅ `send-invite`/`list-payment-links`/`cancel-subscription` bien gateados; sin IDOR.
- ✅ Storage privado; sin XSS almacenado (admin escapa con `esc()`).
- 🔧 **Corregido:** el trigger `protect_client_admin_fields` ahora cubre `INSERT OR UPDATE`
  (antes un cliente podía sembrarse `tag`/`notes` al crear su perfil).
- 🔧 **Agregado:** headers de seguridad en `vercel.json` (X-Frame-Options, nosniff, Referrer-Policy,
  Permissions-Policy).

### Endurecimiento (jun 2026, `supabase/security.sql`)
- **Rate limiting** (anti-abuso/card-testing): tabla `rate_limits` + función `rl_hit(key,max,window)`
  atómica. Aplicado en `create-subscription` (8 / 10 min por IP), `send-invite` (30 / min por IP),
  `cancel-subscription` (5 / 5 min por usuario). Devuelve **429** al exceder.
- **Validación estricta de entrada** en las Edge Functions: tipos forzados, email por regex,
  ids de ONVO por patrón, longitudes recortadas, cuerpos no-objeto rechazados (**400**),
  `templateKey` restringido a claves conocidas.
- **Formulario de leads**: trigger `validate_lead` (INSERT/UPDATE) recorta longitudes, normaliza
  y **fuerza `status='new'`** (nadie entra como `client` por el form). Honeypot anti-bot en la web.
- **Subidas de archivos**: cada bucket tiene `file_size_limit` + `allowed_mime_types`
  (content 100MB img/video, testimonios 10MB img, client-docs 25MB pdf/doc/img) → rechaza
  archivos no permitidos o enormes.
- **Contraseñas**: mínimo 8 + mayúscula/minúscula/dígito + bloqueo de contraseñas filtradas
  (HIBP). Hashing y verificación los maneja Supabase Auth (nunca guardamos contraseñas).
- **Auth**: email **verificado obligatorio** (`mailer_autoconfirm=false`), JWT expira en 1h con
  **rotación de refresh tokens**, cambio de email con doble confirmación. Secretos de auth nunca
  expuestos (solo anon/publishable, públicas por diseño).
- **Inyección**: todo el acceso a datos va por supabase-js/PostgREST **parametrizado** (sin SQL
  concatenado en código de usuario); el único SQL crudo es la Management API, solo manual con PAT.
  XSS mitigado por `esc()`/`_esc()` al renderizar. Encriptación: TLS en tránsito + AES-256 en
  reposo (Supabase) + tarjetas tokenizadas a ONVO (nunca tocan nuestra DB/servidor).

> **3DS en links de pago:** los links de pago de ONVO se cobran en su página hospedada
> (`buy.onvopay.com`), así que **ONVO ejecuta el 3DS ahí**; nuestro webhook solo provisiona en
> `payment-intent.succeeded` (que dispara después de pasar el 3DS). En el checkout propio el 3DS
> lo maneja `onvo.handleNextAction` (ver sección 2). Ambos caminos quedan cubiertos.

### Resultados de pentest (jun 2026)
Ambos pentests se hicieron como atacante real (solo anon key + cuenta de cliente; nunca service key).

**Pentest #1 — estructura:**
| Prueba | Resultado |
|---|---|
| Secretos en el código desplegado | ninguno (solo publishable/anon) |
| RLS lectura de tablas ajenas (clientes/pagos/subs/leads/plantillas/docs) | `[]` — sin fuga |
| Auto-otorgarse suscripción / pago | 403 bloqueado |
| Forjar webhook | 401 |
| IDOR en cancel-subscription | sin IDOR (usa el JWT propio) |
| Storage privado / XSS almacenado | privado / sin XSS (`esc()`, notas en textarea) |
| **Fix aplicado** | trigger `tag/notes` ahora cubre INSERT (antes explotable) + headers en `vercel.json` |

**Pentest #2 — controles nuevos (todo aguanta, sin cambios):**
| Prueba | Resultado |
|---|---|
| Rate limit (hammer create-subscription) | 429 |
| Rate limit — bypass falseando `x-forwarded-for` (12 IPs) | **no se esquiva** (usa la IP real, 1 sola clave) |
| Validación ids/email/body inválidos | 400 |
| Trigger de leads (`status:client`, nombre 400 chars, `edad:999`) | saneado → `status:new`, 120, `null` |
| Contraseña débil / filtrada (HIBP) | 422 rechazada |
| Contraseña fuerte válida | creada con verificación de email pendiente |
| Forja de webhook / storage anónimo | 401 / bloqueado |
