// ───────────────────────────────────────────────────────────
// KAIZEN Coaching — create-subscription (ONVO)
// El cliente tokeniza la tarjeta client-side con la PUBLISHABLE key
// (la tarjeta va directo a ONVO, nunca a este server) y nos manda el
// paymentMethodId. Acá creamos la suscripción $50/mes con ese PM.
// Endurecido: rate limit por IP (anti card-testing/abuso) + validación estricta.
// El secret key de ONVO vive SOLO como secreto de esta function.
// ───────────────────────────────────────────────────────────
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const ONVO_API = "https://api.onvopay.com/v1";
const ONVO_SECRET = Deno.env.get("ONVO_SECRET_KEY")!;
const ONVO_PRICE_ID = Deno.env.get("ONVO_PRICE_ID")!;      // fallback si no hay precio configurado
const ONVO_PRODUCT_ID = Deno.env.get("ONVO_PRODUCT_ID") || ""; // producto base para precios dinámicos
const sb = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!);

// Resuelve el priceId según el precio configurado en el backoffice (kaizen_settings:
// price_amount + price_currency). Crea el precio recurrente en ONVO la 1ª vez y lo
// cachea por monto+moneda. Si no hay producto/config, cae al ONVO_PRICE_ID fijo.
async function resolvePriceId(): Promise<string> {
  if (!ONVO_PRODUCT_ID) return ONVO_PRICE_ID;
  try {
    const { data } = await sb.from("kaizen_settings").select("key,value").in("key", ["price_amount", "price_currency"]);
    const cfg = Object.fromEntries((data || []).map((r: any) => [r.key, r.value]));
    const currency = String(cfg.price_currency || "USD").toUpperCase().slice(0, 3);
    const amount = Math.round((parseFloat(cfg.price_amount) || 50) * 100); // unidad menor
    if (!(amount > 0)) return ONVO_PRICE_ID;
    const cacheKey = `onvo_price_${currency}_${amount}`;
    const { data: hit } = await sb.from("kaizen_settings").select("value").eq("key", cacheKey).maybeSingle();
    if (hit?.value) return hit.value;
    const r = await onvo("/prices", "POST", {
      productId: ONVO_PRODUCT_ID, currency, unitAmount: amount,
      type: "recurring", recurring: { interval: "month", intervalCount: 1 },
    });
    const price = await r.json();
    if (!r.ok || !price?.id) return ONVO_PRICE_ID;
    await sb.from("kaizen_settings").upsert({ key: cacheKey, value: price.id }, { onConflict: "key" });
    return price.id;
  } catch { return ONVO_PRICE_ID; }
}

const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, content-type, apikey",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};
const json = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), { status, headers: { ...cors, "Content-Type": "application/json" } });

// ── Validación estricta de entrada ──
const EMAIL_RE = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;
const ID_RE = /^[A-Za-z0-9_-]{6,128}$/;            // ids de ONVO
const isEmail = (v: unknown) => typeof v === "string" && v.length <= 254 && EMAIL_RE.test(v);
const isId = (v: unknown) => typeof v === "string" && ID_RE.test(v);
const clampStr = (v: unknown, max: number) => (typeof v === "string" ? v.slice(0, max).trim() : "");
const ipOf = (req: Request) =>
  (req.headers.get("x-forwarded-for") || "").split(",")[0].trim() || req.headers.get("x-real-ip") || "unknown";
async function allowed(key: string, max: number, windowSec: number) {
  try { const { data } = await sb.rpc("rl_hit", { p_key: key, p_max: max, p_window: windowSec }); return data !== false; }
  catch { return true; } // si el rate-limiter falla, no bloqueamos el pago
}

const onvo = (path: string, method: string, body?: unknown) =>
  fetch(`${ONVO_API}${path}`, {
    method,
    headers: { Authorization: `Bearer ${ONVO_SECRET}`, "Content-Type": "application/json" },
    body: body ? JSON.stringify(body) : undefined,
  });

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  if (req.method !== "POST") return json({ error: "method not allowed" }, 405);

  // Rate limit por IP: máx 8 intentos de suscripción / 10 min (anti card-testing)
  if (!(await allowed(`create-sub:${ipOf(req)}`, 8, 600)))
    return json({ error: "Demasiados intentos. Esperá unos minutos e intentá de nuevo." }, 429);

  let body: any;
  try { body = await req.json(); } catch { return json({ error: "Cuerpo inválido" }, 400); }
  if (!body || typeof body !== "object") return json({ error: "Cuerpo inválido" }, 400);

  // Validación estricta de tipos/formatos
  const { paymentMethodId, customerId } = body;
  if (!isId(paymentMethodId) || !isId(customerId)) return json({ error: "Datos de pago inválidos" }, 400);
  if (!isEmail(body.email)) return json({ error: "Correo inválido" }, 400);
  const email = String(body.email).toLowerCase().slice(0, 254);
  const name = clampStr(body.name, 120);
  const phone = clampStr(body.phone, 32);
  const plan = clampStr(body.plan, 60) || "Programa grupal";

  try {
    // Crear la suscripción $50/mes con el PM tokenizado. El contacto va en metadata
    // (ONVO no permite editar el customer auto-creado) → el webhook lo usa para provisionar.
    const priceId = await resolvePriceId();
    const r = await onvo("/subscriptions", "POST", {
      customerId, paymentMethodId,
      items: [{ priceId, quantity: 1 }],
      metadata: { email, name, phone, plan },
    });
    const sub = await r.json();
    if (!r.ok) return json({ error: sub.message || "No se pudo crear la suscripción" }, 400);

    // 3DS: si el banco pide autenticación, la sub queda "incomplete" y el
    // payment-intent de la factura queda "requires_action". Devolvemos su id
    // para que el front muestre el challenge con onvo.handleNextAction().
    const pi = sub.latestInvoice?.paymentIntent || null;
    const requiresAction = sub.status === "incomplete" || pi?.status === "requires_action";
    const paymentIntentId = pi?.id || sub.latestInvoice?.paymentIntentId || null;

    // El acceso se provisiona en el webhook firmado, no acá.
    return json({ ok: true, subscriptionId: sub.id, status: sub.status, requiresAction, paymentIntentId });
  } catch (e) {
    return json({ error: String(e) }, 500);
  }
});
