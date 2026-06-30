# KAIZEN Coaching — Sitio web + Backoffice + Portal de clientes

Sitio one-page de **KAIZEN Coaching** (marca de coaching fitness de **Coach Kaizen**) con estética
"dark rockstar gym". Incluye landing comercial, un panel de administración (backoffice) y un
portal de clientes — todo respaldado por **Supabase** y desplegado en **Vercel**.

🌐 **Producción:** https://kaizencoaching.com
📦 **Repo:** https://github.com/contactoavalverde-alt/KAIZEN-coaching
🗄️ **Supabase:** proyecto `YOUR_PROJECT_REF`

---

## ⚠️ Reglas críticas (leer antes de tocar nada)

1. **NUNCA mezclar este proyecto con otros (especialmente "Artesanos Watches").**
   Cada proyecto tiene su **propio** proyecto de Supabase. El de KAIZEN es `YOUR_PROJECT_REF`
   y NADA de otro proyecto debe escribirse aquí, ni viceversa.
2. **No hay build step.** Todo es HTML/CSS/JS plano servido tal cual. No hay `npm`, ni bundler,
   ni framework. Se edita el `.html` directamente y se hace push.
3. **Secretos:** la **anon key** de Supabase es pública por diseño (protegida por RLS) y va en el
   HTML. Las llaves sensibles (PAT de Supabase, etc.) **NUNCA** se comitean — viven en `.env.local`
   (ignorado por git). Ver [SECURITY / Secretos](#-secretos-y-llaves).

---

## 🏗️ Arquitectura

```
Navegador (cliente)
   │
   ├── index.html ........ Landing comercial (público)
   ├── admin.html ........ Backoffice (solo emails admin)
   └── portal.html ....... Portal de clientes (Supabase Auth)
   │
   ▼
Supabase (YOUR_PROJECT_REF)
   ├── Postgres + RLS .... tablas kaizen_* (ver Esquema)
   ├── Auth .............. login de clientes + magic links de invitación
   ├── Storage ........... buckets `testimonios`, `content` (públicos), `client-docs` (privado)
   └── Edge Functions .... pagos ONVO + correo Resend (ver docs/BACKEND.md)
        create-subscription · onvo-webhook · cancel-subscription · send-invite · list-payment-links
   │
Servicios externos
   ├── ONVO Pay .......... suscripción $50/mes recurrente (EN PRODUCCIÓN, con 3DS)
   ├── Resend ............ correos branded desde hola@kaizencoaching.com (dominio verificado)
   └── Pexels API ........ URLs frescas de video para el hero (evita 403 por hotlinking)

Hosting: Vercel (auto-deploy desde la rama `main` de GitHub)
```

> 💳📧 **El sistema de pagos (ONVO) y correo (Resend) está documentado por completo en
> [`docs/BACKEND.md`](docs/BACKEND.md)** — Edge Functions, flujo de checkout + 3DS, webhook,
> dunning, cancelación, links de pago, plantillas y el inventario de secretos. Léelo antes de
> tocar pagos o correo.

**Stack (todo vía CDN, sin instalación):**
- [GSAP 3.12.5](https://gsap.com/) + ScrollTrigger — animaciones
- [Swiper 11](https://swiperjs.com/) — todos los carruseles
- [@supabase/supabase-js v2](https://supabase.com/docs/reference/javascript) — DB + Auth + Storage
- [Chart.js](https://www.chartjs.org/) — gráficas del dashboard del backoffice
- Fuentes: Oswald + Inter (Google Fonts)

---

## 📁 Estructura de archivos

```
kaizen-coaching/
├── index.html            # Landing pública (todo el HTML/CSS/JS inline)
├── admin.html            # Backoffice / panel de administración
├── portal.html           # Portal de clientes (login + suscripción + pagos + mensajes)
├── robots.txt            # Bloquea /admin y /portal de los buscadores
├── vercel.json           # cleanUrls + Cache-Control no-cache para .html
├── .env.local            # Secretos (IGNORADO por git) — no comitear
├── .gitignore
├── assets/
│   ├── coach-1..5.jpg     # Fotos originales de Kaizen (selfies)
│   ├── coach-6..10.jpg    # Fotos nuevas (gym / boxing)
│   └── README.md
├── supabase/             # Migraciones SQL + Edge Functions (ver docs/BACKEND.md)
│   ├── migration.sql     # Tablas base (leads, events)
│   ├── admins.sql        # Setup de admins + RLS base
│   ├── portal.sql        # clients, subscriptions, payments, messages
│   ├── testimonios.sql   # Testimonios + bucket Storage
│   ├── cms.sql           # CMS self-service: testimonios, blog, transformaciones, content bucket
│   ├── invitations.sql   # Sistema de invitaciones de clientes
│   ├── templates.sql     # Plantillas de correo (welcome_50, welcome_premium, payment_failed)
│   ├── documents.sql     # Documentos por cliente (tabla + bucket privado client-docs)
│   ├── onvo.sql          # Columnas/constraints ONVO + dunning (grace_until, expire fn + pg_cron)
│   ├── protect_client_fields.sql  # Trigger: solo admin edita tag/notes (INSERT+UPDATE)
│   └── functions/        # Edge Functions (Deno): create-subscription, onvo-webhook,
│                         #   cancel-subscription, send-invite, list-payment-links
├── .env.example         # Plantilla de credenciales para conectarse (sin valores reales)
└── docs/
    ├── ONBOARDING.md     # 🔌 Cómo conectarse y seguir trabajando en vivo (empezá aquí)
    ├── ARCHITECTURE.md   # Detalle técnico del frontend, módulo por módulo
    ├── BACKEND.md        # ⭐ Edge Functions, pagos ONVO + 3DS, correo Resend, seguridad
    ├── DATABASE.md       # Esquema de tablas + RLS + columnas ONVO
    ├── DEPLOYMENT.md     # Desplegar (sitio + functions), SQL, secretos, cutover prod
    └── CHANGELOG.md      # Historial de cambios relevantes
```

> Las páginas son **monolíticas a propósito**: cada `.html` contiene su CSS y JS inline para
> mantener cero dependencias de build. Es grande pero deliberado.

---

## 🚀 Quick start (para otro dev / otro Claude)

```bash
git clone https://github.com/contactoavalverde-alt/KAIZEN-coaching.git
cd KAIZEN-coaching

# No hay instalación. Servir localmente con cualquier server estático:
python3 -m http.server 8000
# → http://localhost:8000/index.html
#   http://localhost:8000/admin.html
#   http://localhost:8000/portal.html
```

El sitio se conecta a la Supabase de producción usando la **anon key** (es pública y está
protegida por RLS), así que localmente vas a ver los datos reales.

**Para desplegar:** simplemente `git push origin main`. Vercel despliega automáticamente.

---

## 🧩 Módulos principales

### 1. Landing (`index.html`)
Secciones, en orden: Hero (2 videos Pexels en crossfade + título con efecto "decrypt") →
Stats → Orbital "Metodología KAIZEN" (nodos clicables, editable desde admin) → Programas
(KalosBody, Iron Legion, Bellator Temenos, Natus Vincere) → Transformaciones (CMS) →
"En Acción" (videos, CMS) → Testimonios (CMS) → Coach (carrusel coverflow 3D, 10 fotos) →
Blog (CMS) → Formulario de aplicación (replica del Google Form) → Social/Comunidad (Skool +
redes) → Footer.

**Formulario de leads — diseño a prueba de fallos** (ver `handleLead()`):
el lead se envía por **dos vías independientes**: se guarda en Supabase (`kaizen_leads`) y se
notifica por correo vía Web3Forms a `coachkaizen@gmail.com`. Muestra éxito ("LET'S GO!!") si **al
menos una** funciona; el correo tiene timeout de 7s para no colgar nunca el form.

### 2. Backoffice (`admin.html`)
Login con Supabase Auth (solo emails admin). Sidebar en dos grupos:
- **Gestión:** Dashboard (6 gráficas), Leads, Clientes (+ invitaciones/CSV), Membresías,
  Pagos, Comunicación, Calendario, Eventos.
- **Contenido & Diseño:** Testimonios, Blog, Transformaciones, En Acción, Orbital (Sistema).

Todo el contenido del sitio es **self-service**: lo que se sube aquí se publica en la landing.

### 3. Portal de clientes (`portal.html`)
Login/registro con Supabase Auth. El cliente ve su suscripción, pagos, mensajes de Kaizen y su
perfil. Los emails admin son redirigidos a `/admin`.

---

## 🔑 Accesos y credenciales

| Recurso | Valor |
|---|---|
| Dominio | `kaizencoaching.com` (comprado vía Vercel) |
| Supabase project | `YOUR_PROJECT_REF` |
| Emails admin | `coachkaizen@gmail.com`, `contactoavalverde@gmail.com` |
| Correo de notificación de leads | `coachkaizen@gmail.com` (vía Web3Forms) |
| WhatsApp de negocio | `6109 9877` (`wa.me/50600000000`) |
| Comunidad | https://www.skool.com/YOUR-COMMUNITY |

> Las contraseñas, PAT de Supabase y otras llaves sensibles **no** se documentan aquí ni se
> comitean. Ver [Secretos y llaves](#-secretos-y-llaves).

---

## 🔐 Secretos y llaves

- **Anon key de Supabase** → pública por diseño, va inline en los `.html`. Segura porque RLS
  restringe todo acceso a nivel de fila.
- **`ONVO_PUBLIC_KEY`** (publishable, live) → pública por diseño, inline en `index.html` para
  tokenizar la tarjeta client-side.
- **Pexels API key** → usada en runtime solo para descubrir URLs de video del hero.
- **Secretos de Edge Functions** (ONVO secret/price/webhook, Resend, internal) → viven SOLO como
  Supabase function secrets, **nunca** en el HTML/git. Inventario completo en
  [`docs/BACKEND.md`](docs/BACKEND.md).
- **Supabase PAT (`sbp_...`)** y **service role key** → ⚠️ NUNCA comitear. El PAT se usa solo
  manualmente para correr SQL/deploy vía API.
- **`.env.local`** → contiene secretos locales, ignorado por git.
- ℹ️ El correo transaccional pasó de Web3Forms a **Resend** (dominio verificado). Las invitaciones
  y el dunning salen branded desde `hola@kaizencoaching.com`. Ver [`docs/BACKEND.md`](docs/BACKEND.md).

---

## 📚 Documentación detallada

- [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md) — cómo funciona cada módulo por dentro
- [`docs/DATABASE.md`](docs/DATABASE.md) — esquema de las 16 tablas, RLS, buckets
- [`docs/DEPLOYMENT.md`](docs/DEPLOYMENT.md) — desplegar, correr migraciones, secretos
- [`docs/CHANGELOG.md`](docs/CHANGELOG.md) — historial de cambios

---

## 🧠 Notas para retomar el proyecto (contexto que no está en el código)

- **No hay build.** Editás el HTML y hacés push. Punto.
- **Videos del hero:** los URLs de `videos.pexels.com` dan **403 si se hardcodean** (bloqueo de
  hotlinking). Por eso se piden URLs frescas a la API de Pexels en runtime. Si cambiás los videos,
  cambiá los IDs en el array `HERO_IDS` dentro de `index.html`.
- **Transformaciones:** la sección se **oculta** si no hay filas en `kaizen_transformaciones`
  (no hay datos de relleno falsos). Se llena desde el backoffice.
- **Cache:** `vercel.json` fuerza `no-cache` en los `.html`. Si algo "no se actualiza", hacer
  hard refresh (`Cmd+Shift+R`) o probar en incógnito.
- **Invitaciones de clientes:** Kaizen agrega un email (o sube un CSV) en el backoffice →
  Supabase manda un magic link → al entrar, la invitación se marca como `accepted`.
