// ───────────────────────────────────────────────────────────
// KAIZEN Coaching — cancel-subscription
// El cliente cancela SU PROPIA suscripción desde el portal.
// Verifica el JWT del cliente y solo cancela la sub de ESE user_id
// (nunca acepta un id de sub arbitrario del cliente).
// Cancela en ONVO (DELETE) y marca cancelled en Supabase.
// ───────────────────────────────────────────────────────────
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const ONVO_API = "https://api.onvopay.com/v1";
const ONVO_SECRET = Deno.env.get("ONVO_SECRET_KEY")!;
const SUPA_URL = Deno.env.get("SUPABASE_URL")!;
const SERVICE = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
const ANON = Deno.env.get("SUPABASE_ANON_KEY")!;

const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, content-type, apikey",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};
const json = (b: unknown, s = 200) => new Response(JSON.stringify(b), { status: s, headers: { ...cors, "Content-Type": "application/json" } });

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  if (req.method !== "POST") return json({ error: "method not allowed" }, 405);

  try {
    // 1) Identificar al cliente por su JWT (nunca confiar en un id que mande el cliente)
    const token = (req.headers.get("Authorization") || "").replace("Bearer ", "");
    const userClient = createClient(SUPA_URL, ANON, { global: { headers: { Authorization: `Bearer ${token}` } } });
    const { data: { user } } = await userClient.auth.getUser();
    if (!user) return json({ error: "No autenticado" }, 401);

    const admin = createClient(SUPA_URL, SERVICE);
    // Rate limit: máx 5 cancelaciones / 5 min por usuario (anti-abuso)
    try { const { data: ok } = await admin.rpc("rl_hit", { p_key: `cancel-sub:${user.id}`, p_max: 5, p_window: 300 }); if (ok === false) return json({ error: "Demasiados intentos, esperá unos minutos." }, 429); } catch { /* no bloquear si falla */ }
    // 2) Su suscripción activa/past_due (la más reciente no cancelada)
    const { data: sub } = await admin.from("kaizen_subscriptions")
      .select("id, onvo_subscription_id, status")
      .eq("user_id", user.id).neq("status", "cancelled")
      .order("created_at", { ascending: false }).limit(1).maybeSingle();
    if (!sub) return json({ error: "No tenés una suscripción activa para cancelar." }, 404);

    // 3) Cancelar en ONVO
    if (sub.onvo_subscription_id) {
      const r = await fetch(`${ONVO_API}/subscriptions/${sub.onvo_subscription_id}`, {
        method: "DELETE", headers: { Authorization: `Bearer ${ONVO_SECRET}` },
      });
      if (!r.ok) { const t = await r.text().catch(() => ""); return json({ error: "No se pudo cancelar en ONVO: " + t.slice(0, 120) }, 400); }
    }

    // 4) Marcar cancelada en Supabase
    await admin.from("kaizen_subscriptions").update({ status: "cancelled", grace_until: null }).eq("id", sub.id);
    try { await admin.from("kaizen_events").insert({ event: "subscription_cancelled", data: { user_id: user.id } }); } catch (_) { /* noop */ }
    return json({ ok: true });
  } catch (e) {
    return json({ error: String(e) }, 500);
  }
});
