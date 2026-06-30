# Changelog

Historial de cambios relevantes (resumido a partir de los commits de git). Lo más reciente arriba.

## Endurecimiento de seguridad + 2 pentests (jun 2026)
- **Rate limiting** (anti-abuso/card-testing): tabla `rate_limits` + `rl_hit()` atómico, aplicado a
  `create-subscription` (8/10min IP), `send-invite` (30/min IP), `cancel-subscription` (5/5min usuario).
- **Validación estricta** en Edge Functions (tipos, email/ids por regex, longitudes, `templateKey`
  whitelisted; cuerpos basura → 400). **Leads**: trigger `validate_lead` (recorta + fuerza `status=new`)
  + honeypot anti-bot.
- **Subidas seguras**: `file_size_limit` + `allowed_mime_types` por bucket.
- **Contraseñas**: min 8 + Aa1 + bloqueo de filtradas (HIBP). **Auth**: email verificado obligatorio,
  JWT 1h + rotación de refresh tokens, cambio de email con doble confirmación.
- **3DS** cubierto en ambos caminos (checkout: `handleNextAction`; links de pago: página de ONVO).
- **Pentest #1 (estructura):** RLS, auto-provisión de subs/pagos, IDOR, XSS, secretos → sólido.
  Fix: el trigger de `tag/notes` ahora cubre INSERT (era explotable solo en INSERT). Headers de
  seguridad agregados a `vercel.json`.
- **Pentest #2 (controles nuevos):** rate limit (incl. no esquivable falseando `x-forwarded-for` —
  usa la IP real), validación, trigger de leads, política de contraseñas, forja de webhook (401) y
  storage anónimo (bloqueado) → **todo aguanta**. Detalle en `docs/BACKEND.md`.

## Correos branded con Resend (jun 2026)
- **Edge Function `send-invite`**: envía las plantillas de `kaizen_templates` por **Resend**.
  - `type:"welcome"` → genera un **magic link de auto-login** y manda `welcome_50` / `welcome_premium` (según monto/plan).
  - `type:"dunning"` → manda `payment_failed`.
  - **Fallback**: si Resend no puede entregar (dominio sin verificar), cae al magic link nativo de Supabase (solo welcome), para que el cliente nunca quede sin acceso.
  - **Auth**: header `x-internal-secret` para el webhook; JWT de admin para el panel.
- **Cableado**: el `onvo-webhook` manda bienvenida al provisionar y seguimiento al fallar un pago; el admin (`doSendInvite` → `crearAcceso`/bulk/re-invite) ahora envía branded en vez del magic link plano.
- **Verificado en vivo**: welcome y dunning llegan branded (canal `resend`); el cableado del webhook registra `invite_channel`/`mail_channel` en `kaizen_events`.
- **✅ Dominio `kaizencoaching.com` VERIFICADO en Resend** (DKIM+SPF+MX vía Vercel DNS). `RESEND_FROM` = `Coach Kaizen - KAIZEN Coaching <hola@kaizencoaching.com>`. Probado: envío branded a un correo de cliente cualquiera entrega OK. El loop de correos quedó 100% operativo.

## Pagos ONVO — endurecido para producción (jun 2026)
- **Cancelación self-serve**: el cliente cancela su suscripción desde el portal (`cancelSub()` → Edge Function `cancel-subscription`, que verifica el JWT y solo cancela la sub de ESE usuario; DELETE en ONVO + `cancelled` en Supabase). Nunca acepta un id de sub arbitrario del cliente.
- **Dunning completo**: `subscription.renewal.failed` → estado `past_due` + `grace_until` (+7 días); `pg_cron` (`kaizen-expire-overdue`, diario 09:00 UTC) corre `expire_overdue_subscriptions()` y pasa a `expired` lo vencido. Un cobro exitoso reactiva la sub `past_due` → `active`.
- **Idempotencia race-safe**: `UNIQUE(onvo_subscription_id)` como candado (la suscripción se inserta primero; entregas concurrentes del webhook no duplican). Pagos deduplicados por índice único parcial `UNIQUE(onvo_payment_intent_id)`.
- **Estados en el portal**: `active`/`past_due` (banner de aviso + fecha de gracia) mantienen acceso; `expired` → reactivar por WhatsApp; `cancelled` → re-suscribir.
- Verificado en vivo (test mode): provisioning, idempotencia (sin duplicar sub/pago), dunning, reactivación y expiración.
- Pendiente: correo branded de pago fallido (requiere cuenta Resend de Kaizen + dominio verificado).

## Backoffice avanzado + portal (jun 2026)
- **Sección "App de Entrenamiento"** en la landing: video en mockup de teléfono + features (rutinas, progreso, biblioteca, **nutrición/macros** con integraciones Apple Health/MyFitnessPal/Fitbit).
- **Calificación de leads (queue)**: `leadTemp` por budget → 🔥 Caliente ($1k–3k) arriba; columna Temp + filtro.
- **Accesos $50**: tab que junta leads de bajo budget; botón "Crear acceso" → invitación (magic link); mapea programa → plan.
- **Template Manager de correos** (`kaizen_templates`): bienvenida $50, premium, pago fallido — asunto + HTML + adjuntos + vista previa. (Envío real pendiente: requiere proveedor de email + Edge Function.)
- **Perfil de cliente enriquecido**: tag (intro/medium/high-end), tenure, último pago (ONVO/SINPE/Transferencia/Efectivo), notas internas.
- **Documentos por cliente** (`kaizen_documents` + bucket privado `client-docs`): Kaizen sube desde el admin, el cliente descarga en su portal vía URL firmada.
- **Seguridad**: panel admin solo para correos admin (gate + RLS auditada en 16 tablas); trigger protege `tag`/`notes` de edición por no-admin.
- **Form de leads**: campo de **correo** (requerido) → `crearAcceso` lo usa directo.
- **Backoffice UX**: métricas solo en Dashboard, Eventos al final, Calendario conectable a Google Calendar; En Acción acepta links de Skool/externos.
- **Fixes de code-review**: renderCal idempotente, crearAcceso no marca 'client' si falla el guardado, tenureText sin días negativos.

## Formulario de leads — robustez (jun 2026)
- Form **a prueba de fallos**: doble vía Supabase + Web3Forms, éxito si al menos una funciona,
  timeout de 7s en el correo, `showSuccess()` sin depender de gsap, error con motivo real en pantalla.
- Mensaje de éxito → **"LET'S GO!! 🔥"**.
- `vercel.json`: `Cache-Control: no-cache` en `.html`.
- Correo de notificación apunta a `coachkaizen@gmail.com`.

## Sistema de invitaciones de clientes
- Backoffice: invitar por email (individual o **CSV masivo**) → magic link de Supabase.
- Tabla `kaizen_invitations` (pending/accepted); el portal marca `accepted` al primer login.

## Contenido 100% editable
- Transformaciones desde backoffice, sin fallback estático (sección se oculta si vacío).
- CMS self-service: Testimonios, Blog, Transformaciones, En Acción (videos), Orbital.
- Backoffice sidebar separado en **Gestión** / **Contenido & Diseño**.

## Hero y multimedia
- Hero con videos dramáticos de Pexels (levantamiento pesado + hipertrofia) vía API en runtime
  para evitar el 403 de hotlinking.
- Carrusel del coach con 10 fotos (coverflow 3D); carruseles en loop infinito condicional.
- Removido el subtítulo del hero.

## Social
- Barra de redes fija arriba-derecha + sección Comunidad con Skool y todas las redes.
- Nav "Videos" → "En Acción".

## Backoffice (construcción)
- Panel admin (`admin.html`) con Supabase Auth + RLS.
- Dashboard de métricas (6 gráficas), Membresías, Pagos, Comunicación, Calendario, Eventos.
- Gestión de Clientes; segundo admin agregado; RLS endurecido.
- Módulo de Newsletter retirado.

## Portal de clientes
- `portal.html`: área de miembros con suscripción, pagos, mensajes, perfil.
- Login unificado: email admin desde `/portal` redirige a `/admin`.

## Landing (base)
- Lanzamiento inicial del sitio; estética dark gym.
- Sección de Programas (KalosBody, Iron Legion, Bellator Temenos, Natus Vincere); precio
  oculto en los planes premium (solo por aplicación).
- Formulario réplica del Google Form + notificación por correo (migrado FormSubmit → Web3Forms)
  + widget de WhatsApp.
- SEO + Open Graph apuntando a `kaizencoaching.com`.
- Fixes: removido fondo "floating paths" (glitch visual); patrón `gsap.from()` para que el texto
  del hero nunca quede invisible; `vercel.json` ya no reescribe los assets a index.html.

---

> Para el detalle commit a commit: `git log --oneline` en el repo.
