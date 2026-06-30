// ───────────────────────────────────────────────────────────
// KAIZEN Coaching — list-payment-links
// Lista los links de pago de ONVO para el admin (la secret key vive
// solo acá, nunca en el browser). Gated por JWT de admin.
// ONVO expone isActive por link (activo/inactivo); no expone conversión
// pagada por link — los pagos exitosos se ven como "Loops activos".
// ───────────────────────────────────────────────────────────
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const ONVO_API = "https://api.onvopay.com/v1";
const ONVO_SECRET = Deno.env.get("ONVO_SECRET_KEY")!;
const SUPA_URL = Deno.env.get("SUPABASE_URL")!;
const ANON = Deno.env.get("SUPABASE_ANON_KEY")!;
const SERVICE = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
const ADMIN_EMAILS = ["coachkaizen@gmail.com", "contactoavalverde@gmail.com"];

const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, content-type, apikey",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};
const json = (b: unknown, s = 200) => new Response(JSON.stringify(b), { status: s, headers: { ...cors, "Content-Type": "application/json" } });

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  if (req.method !== "POST") return json({ error: "method not allowed" }, 405);

  // Solo admins
  const token = (req.headers.get("Authorization") || "").replace("Bearer ", "").trim();
  if (!token) return json({ error: "no autorizado" }, 401);
  try {
    const uc = createClient(SUPA_URL, ANON, { global: { headers: { Authorization: `Bearer ${token}` } } });
    const { data: { user } } = await uc.auth.getUser();
    if (!user || !ADMIN_EMAILS.includes((user.email || "").toLowerCase())) return json({ error: "no autorizado" }, 401);
  } catch { return json({ error: "no autorizado" }, 401); }

  try {
    const r = await fetch(`${ONVO_API}/payment-links?limit=100`, { headers: { Authorization: `Bearer ${ONVO_SECRET}` } });
    const body = await r.json();
    if (!r.ok) return json({ error: body.message || "Error ONVO", detail: body }, 400);
    const arr = Array.isArray(body) ? body : (body.data || []);

    // Conversiones por link: cruzamos contra las suscripciones provisionadas.
    // Un pago por link (sin metadata) deja kaizen_subscriptions.plan = nickname del precio
    // → contamos por nickname (los pagos del checkout web usan plan propio, no chocan).
    const admin = createClient(SUPA_URL, SERVICE);
    const { data: subs } = await admin.from("kaizen_subscriptions").select("plan,status");
    const paidByPlan: Record<string, { paid: number; active: number }> = {};
    for (const s of (subs || [])) {
      const k = (s.plan || "").trim();
      if (!k) continue;
      (paidByPlan[k] ||= { paid: 0, active: 0 });
      paidByPlan[k].paid++;
      if (s.status === "active") paidByPlan[k].active++;
    }

    const links = arr.map((l: any) => {
      const li = (l.lineItems && l.lineItems[0]) || {};
      const price = li.price || {};
      const nickname = price.nickname || "";
      const conv = paidByPlan[nickname.trim()] || { paid: 0, active: 0 };
      return {
        id: l.id,
        url: l.url,
        isActive: !!l.isActive,
        plan: price.product?.name || nickname || "—",
        nickname,
        amount: price.unitAmount != null ? price.unitAmount / 100 : null,
        currency: price.currency || "USD",
        recurring: price.type === "recurring",
        createdAt: l.createdAt,
        paid: conv.paid,        // suscripciones provisionadas vía este link (por nickname)
        activeLoops: conv.active,
      };
    });
    return json({ ok: true, links, total: links.length });
  } catch (e) {
    return json({ error: String(e) }, 500);
  }
});
