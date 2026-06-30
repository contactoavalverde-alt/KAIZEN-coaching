# Conectarse y seguir trabajando (otro Claude / otro dev)

Cómo retomar el proyecto **en vivo** desde cero, en una sesión nueva. Dos niveles:

## Nivel 1 — Solo editar/desplegar el sitio (sin secretos)
Suficiente para tocar el frontend (los 3 `.html`), funciones y SQL, y publicar.
```bash
git clone https://github.com/contactoavalverde-alt/KAIZEN-coaching.git
cd KAIZEN-coaching
# Leer en este orden: README.md → docs/BACKEND.md → docs/DATABASE.md
python3 -m http.server 8000   # http://localhost:8000/index.html  (usa la Supabase real vía anon key)
# editar → git add -A && git commit && git push origin main  → Vercel despliega solo
```
> El sitio en local ya se conecta a la Supabase de producción (anon key, protegida por RLS),
> así que ves datos reales sin configurar nada.

## Nivel 2 — Operar el backend en vivo (necesita secretos)
Para correr SQL, desplegar Edge Functions, setear secretos, consultar/limpiar la DB, operar
ONVO/Resend o entrar al admin. Pegá los valores en `.env.local` (copiá de `.env.example`).

```bash
cp .env.example .env.local        # completá los valores reales (ver .env.example)
set -a; source .env.local; set +a # carga las variables al shell
```

**Verificar conexión (smoke test):**
```bash
# 1) Supabase (Management API) — debe devolver JSON, no error de auth
curl -s -X POST "https://api.supabase.com/v1/projects/$SUPABASE_PROJECT_REF/database/query" \
  -H "Authorization: Bearer $SUPABASE_ACCESS_TOKEN" -H "Content-Type: application/json" \
  -d '{"query":"SELECT count(*) FROM kaizen_clients"}'

# 2) ONVO (llave live) — debe devolver HTTP 200
curl -s -o /dev/null -w "%{http_code}\n" "https://api.onvopay.com/v1/products?limit=1" \
  -H "Authorization: Bearer $ONVO_SECRET_KEY"

# 3) Resend (llave) — debe listar el dominio kaizencoaching.com como "verified"
curl -s "https://api.resend.com/domains" -H "Authorization: Bearer $RESEND_API_KEY"

# 4) Desplegar una Edge Function
supabase functions deploy onvo-webhook --project-ref $SUPABASE_PROJECT_REF --no-verify-jwt --use-api
```

## Qué pegar para "conectar todo de un solo viaje"
1. La URL del repo (o el repo clonado) — todo el código + docs están ahí.
2. El contenido de `.env.local` (los secretos del Nivel 2).

Con esos dos, una sesión nueva tiene **todo**: entiende el sistema por los docs y puede operar
el backend en vivo con los secretos. Sin el (2) solo puede editar/desplegar el sitio.

> ⚠️ Nunca pegues secretos en un canal público ni los comitees. `.env.local` está en `.gitignore`.
> Tras una sesión de trabajo con un PAT temporal, revocalo en el dashboard de Supabase.

## Mapa de docs
- `README.md` — visión general, arquitectura, estructura, reglas críticas.
- `docs/BACKEND.md` ⭐ — Edge Functions, pagos ONVO + 3DS, correo Resend, seguridad, secretos.
- `docs/DATABASE.md` — tablas, RLS, columnas ONVO, dunning.
- `docs/DEPLOYMENT.md` — desplegar sitio + functions, migraciones, cutover.
- `docs/ARCHITECTURE.md` — frontend módulo por módulo.
- `docs/CHANGELOG.md` — historial.
