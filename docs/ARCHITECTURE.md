# Arquitectura técnica

Detalle módulo por módulo del **frontend**. Todo es **HTML/CSS/JS inline**, sin build step, sin
framework. Las librerías se cargan por CDN.

> ⚙️ La parte **servidor** (Edge Functions, pagos ONVO + 3DS, correo Resend, seguridad) está en
> [`BACKEND.md`](BACKEND.md). Este doc es el frontend.

---

## index.html — Landing pública

### Inicialización
```js
const SUPA_URL = 'https://YOUR_PROJECT_REF.supabase.co';
const SUPA_KEY = '<anon key — pública>';
const db = supabase.createClient(SUPA_URL, SUPA_KEY);
const WEB3FORMS_KEY = '<access key>';   // notificación de leads por correo
```

### Hero — videos dramáticos vía Pexels
- Dos `<video class="hero-vid">` (`#hero-vid-1`, `#hero-vid-2`) con crossfade por CSS keyframes.
- Los URLs hardcodeados de `videos.pexels.com` dan **403** (hotlinking). Solución: al cargar la
  página se piden URLs **frescas** a la API de Pexels y se reemplaza el `<source>`.
- Para cambiar los videos: editar `HERO_IDS = [5320001, 5319435]` (IDs de Pexels).
  - `5320001` = levantamiento pesado · `5319435` = bodybuilder hipertrofia.

### Texto "decrypt" del hero
`decryptText()` scramblea las letras y las resuelve. GSAP hace solo el fade-in (opacity); el
default del CSS es visible (para que screenshots/SEO no queden vacíos).

### Orbital "Metodología KAIZEN"
- Clase `OrbitalTimeline` con `requestAnimationFrame`; nodos clicables que se expanden.
- `DEFAULT_SERVICES` = fallback; `SERVICES` se sobreescribe desde `kaizen_orbital`.
- `resolveIcon(key)` mapea claves string a SVG line icons (objeto `ICONS`).
- Textos (`orbital_tag/title/sub`) vienen de `kaizen_settings`. El title soporta `\n` → `<br>`.

### Carruseles (Swiper 11)
| Selector | Contenido | Fuente |
|---|---|---|
| `.swiper-testi` | Testimonios | `kaizen_testimonios` (oculta la sección si vacío) |
| `.swiper-results` | Transformaciones | `kaizen_transformaciones` (oculta si vacío) |
| `.swiper-vids` | En Acción | `kaizen_videos` |
| `.swiper-coach` | Coach (coverflow 3D) | `assets/coach-1..10.jpg` |
> `loop` es condicional (`rows.length > 2`, coach `> 4`) para evitar el warning de Swiper.
> **Secciones que se ocultan si no hay contenido** (no se muestran placeholders demo):
> Transformaciones, Testimonios y Blog. Kaizen los activa subiéndolos desde el backoffice.

### Checkout de pagos (modal `#pay-modal`)
Resumen de suscripción branded + formulario de tarjeta propio. Tokeniza la tarjeta directo a ONVO
con `ONVO_PUBLIC_KEY`, llama a `create-subscription`, y si el banco pide **3DS** muestra el
challenge en la página con el SDK de ONVO (`onvo.handleNextAction`). Detalle completo del flujo
de pagos en [`BACKEND.md`](BACKEND.md).

### Formulario de leads — `handleLead()` (a prueba de fallos)
Diseño clave: **el lead llega por dos vías independientes** y se muestra éxito si al menos una
funciona. Nunca se cuelga.

```
1. Guardar en Supabase (kaizen_leads)
   ├── OK   → mostrar "LET'S GO!!" YA; enviar correo en segundo plano (fire-and-forget)
   └── falla→ ir al paso 2
2. Enviar correo (Web3Forms → coachkaizen@gmail.com)  [respaldo]
   ├── OK   → mostrar éxito
   └── falla→ mostrar error con el motivo real en pantalla
```
- `sendMail()` usa `AbortController` con **timeout de 7s** → el correo nunca cuelga el form.
- `showSuccess()` cambia el estado **directo** (no depende de gsap) y luego anima.
- Campos → columnas: `programa, metas, name, pais, edad, phone, listo_invertir, rango_capital`.

### Helpers
- `_esc(str)` → escape HTML seguro al renderizar contenido del CMS.
- `_ytId(url)` → extrae el ID de YouTube para thumbnails/embeds.

### Barra social y sección Comunidad
- `.social-top` (fija arriba-derecha): IG, TikTok, YouTube, Facebook, Skool, WhatsApp.
- `#social`: card de Skool + grid de redes.

---

## admin.html — Backoffice

### Auth
Login con Supabase Auth. Solo emails admin pueden entrar (RLS bloquea el resto a nivel DB).

### Layout
`.sidebar` (sticky, 228px) + `.main`. Sidebar en dos grupos:
- **Gestión:** `dash, leads, clients, memb, pays, comm, cal, events`
- **Contenido & Diseño:** `testi, blog, trans, vids, orbital`

`TABS = ['dash','leads','clients','memb','pays','comm','testi','blog','trans','vids','orbital','cal','events']`

### Carga de datos
`loadAll()` corre en paralelo: `loadLeads, loadEvents, loadClients, loadPaysGlobal,
loadTestimonios, loadBlog, loadTrans, loadVids, loadInvitations` → luego render de dashboard,
membresías, pagos, contadores.

### Dashboard
6 gráficas Chart.js: leads/mes (bar), revenue/mes (line), por programa / por status / por plan
(pie), rango de capital (bar).

### Clientes + Invitaciones
- Tabla de clientes con modal de gestión (suscripción, registrar pago, enviar mensaje).
- **Invitar:** form individual o **carga masiva CSV** (`email,nombre,plan`).
  - `doSendInvite()` → upsert en `kaizen_invitations` + `db.auth.signInWithOtp()` (magic link).
  - CSV: preview + envío con rate-limit de ~1.1s entre cada uno.

### CMS (Contenido & Diseño)
Cada tab sube a su tabla `kaizen_*` y a Storage cuando aplica (`uploadContent(file, prefix)` →
bucket `content`; testimonios → bucket `testimonios`). En Acción acepta link de YouTube
(thumbnail auto vía `ytId()`) o subida de video.

---

## portal.html — Portal de clientes

- Login/registro con Supabase Auth (`signUp` / `signInWithPassword`); magic link de invitación.
- `ADMIN_EMAILS` → si entra un admin, se redirige a `/admin`.
- `ensureProfile()` → crea fila en `kaizen_clients` en el primer login; marca la invitación
  (`kaizen_invitations`) como `accepted`.
- Muestra: suscripción con estados **active/past_due/expired/cancelled** (banner de gracia en
  past_due), historial de pagos, mensajes de Kaizen, **Mis Documentos** (descarga de `kaizen_documents`
  con URL firmada).
- **Editar datos personales** (name/email/phone; el cambio de email dispara confirmación).
- **Cambio de contraseña seguro:** re-valida la contraseña actual (`signInWithPassword`) antes de
  cambiar; quienes entraron por magic link usan `resetPasswordForEmail` (evento `PASSWORD_RECOVERY`).
- **Cancelar suscripción** self-serve → Edge Function `cancel-subscription` (ver `BACKEND.md`).

---

## Convenciones de código

- **Sin build, sin dependencias locales.** Editar el HTML directamente.
- Mantener el estilo del código existente (densidad de comentarios, nombres, idioma ES).
- La anon key es pública; cualquier secreto real va en `.env.local` (ignorado).
- Después de editar: `git add -A && git commit && git push origin main` → Vercel despliega.
