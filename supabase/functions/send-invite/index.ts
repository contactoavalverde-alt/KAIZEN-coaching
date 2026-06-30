// ───────────────────────────────────────────────────────────
// KAIZEN Coaching — send-invite
// Envía los correos branded (plantillas de kaizen_templates) por Resend.
//   type "welcome"  → genera magic link, manda welcome_50 / welcome_premium
//   type "dunning"  → manda payment_failed (link al portal)
// Si Resend falla (p.ej. dominio aún sin verificar) hace FALLBACK al
// magic link nativo de Supabase, para que el cliente nunca quede sin acceso.
// Lo llaman: onvo-webhook (service role) y el admin (JWT de admin).
// ───────────────────────────────────────────────────────────
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const SUPA_URL = Deno.env.get("SUPABASE_URL")!;
const SERVICE = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
const ANON = Deno.env.get("SUPABASE_ANON_KEY")!;
const INTERNAL_SECRET = Deno.env.get("INVITE_INTERNAL_SECRET") || "";
const RESEND_KEY = Deno.env.get("RESEND_API_KEY") || "";
const RESEND_FROM = Deno.env.get("RESEND_FROM") || "KAIZEN Coaching <onboarding@resend.dev>";
// Las respuestas del cliente van al buzón real de Kaizen (hola@kaizencoaching.com no recibe).
const RESEND_REPLY_TO = Deno.env.get("RESEND_REPLY_TO") || "coachkaizen@gmail.com";
const APP_URL = "https://kaizencoaching.com/portal";
const ADMIN_EMAILS = ["contactoavalverde@gmail.com", "luismariano@vegabarca.com"];

const admin = createClient(SUPA_URL, SERVICE);
const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, content-type, apikey",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};
const json = (b: unknown, s = 200) => new Response(JSON.stringify(b), { status: s, headers: { ...cors, "Content-Type": "application/json" } });

// Sustituye {{var}} en subject/html
function fill(tpl: string, vars: Record<string, string>): string {
  return (tpl || "").replace(/\{\{\s*(\w+)\s*\}\}/g, (_m, k) => vars[k] ?? "");
}

// Crea el usuario si no existe (idempotente) — necesario para generar magic link
async function ensureUser(email: string, name: string, phone: string) {
  const r = await admin.auth.admin.createUser({ email, email_confirm: true, user_metadata: { name, phone, source: "invite" } });
  // Si ya existe, createUser devuelve error; lo ignoramos.
  return !r.error || /already|exists|registered/i.test(r.error.message);
}

// Magic link branded (auto-login al portal). Requiere que el usuario exista.
async function magicLink(email: string): Promise<string | null> {
  const r = await admin.auth.admin.generateLink({ type: "magiclink", email, options: { redirectTo: APP_URL } });
  return (r.data?.properties as any)?.action_link || null;
}

async function sendResend(to: string, subject: string, html: string, attachments: any[]): Promise<{ ok: boolean; err?: string }> {
  if (!RESEND_KEY) return { ok: false, err: "no RESEND_API_KEY" };
  const body: Record<string, unknown> = { from: RESEND_FROM, to: [to], subject, html };
  if (RESEND_REPLY_TO) body.reply_to = RESEND_REPLY_TO;
  const att = (attachments || []).filter((a) => a?.url).map((a) => ({ filename: a.name || "adjunto", path: a.url }));
  if (att.length) body.attachments = att;
  const r = await fetch("https://api.resend.com/emails", {
    method: "POST", headers: { Authorization: `Bearer ${RESEND_KEY}`, "Content-Type": "application/json" }, body: JSON.stringify(body),
  });
  if (r.ok) return { ok: true };
  const t = await r.text().catch(() => "");
  return { ok: false, err: `resend ${r.status}: ${t.slice(0, 160)}` };
}

// Fallback: magic link nativo de Supabase (envía su propio correo)
async function supabaseFallback(email: string): Promise<boolean> {
  try {
    const pub = createClient(SUPA_URL, ANON);
    const { error } = await pub.auth.signInWithOtp({ email, options: { shouldCreateUser: true, emailRedirectTo: APP_URL } });
    return !error;
  } catch { return false; }
}

async function authorize(req: Request): Promise<boolean> {
  // Llamada interna (webhook): header x-internal-secret
  const internal = (req.headers.get("x-internal-secret") || "").trim();
  if (INTERNAL_SECRET && internal === INTERNAL_SECRET) return true;
  // Llamada del admin (browser): JWT de un correo admin
  const token = (req.headers.get("Authorization") || "").replace("Bearer ", "").trim();
  if (!token) return false;
  try {
    const uc = createClient(SUPA_URL, ANON, { global: { headers: { Authorization: `Bearer ${token}` } } });
    const { data: { user } } = await uc.auth.getUser();
    return !!user && ADMIN_EMAILS.includes((user.email || "").toLowerCase());
  } catch { return false; }
}

const EMAIL_RE = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;
const ipOf = (req: Request) =>
  (req.headers.get("x-forwarded-for") || "").split(",")[0].trim() || req.headers.get("x-real-ip") || "unknown";

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  if (req.method !== "POST") return json({ error: "method not allowed" }, 405);
  if (!(await authorize(req))) return json({ error: "no autorizado" }, 401);

  // Rate limit (defensa en profundidad anti-spam de correo): 30 envíos / min por IP
  try { const { data } = await admin.rpc("rl_hit", { p_key: `send-invite:${ipOf(req)}`, p_max: 30, p_window: 60 }); if (data === false) return json({ error: "demasiados envíos, esperá un minuto" }, 429); } catch { /* no bloquear si falla */ }

  let p: any;
  try { p = await req.json(); } catch { return json({ error: "bad json" }, 400); }
  if (!p || typeof p !== "object") return json({ error: "bad json" }, 400);

  // Validación estricta
  const email = String(p.to || p.email || "").trim().toLowerCase().slice(0, 254);
  if (!email || email.length > 254 || !EMAIL_RE.test(email)) return json({ error: "correo inválido" }, 400);
  const type = p.type === "dunning" ? "dunning" : "welcome";
  const name = String(p.name || "").slice(0, 120);
  const phone = String(p.phone || "").slice(0, 32);
  const plan = (String(p.plan || "").slice(0, 60)) || "Programa grupal";

  // Plantilla: explícita (solo claves conocidas) > inferida por tipo/monto
  const KEYS = ["welcome_50", "welcome_premium", "payment_failed"];
  let key: string = KEYS.includes(p.templateKey) ? p.templateKey : "";
  if (!key) {
    if (type === "dunning") key = "payment_failed";
    else key = (Number(p.amount) > 50 || /premium|1:1|personal/i.test(plan)) ? "welcome_premium" : "welcome_50";
  }

  const { data: tpl } = await admin.from("kaizen_templates").select("subject,body_html,attachments,enabled").eq("key", key).maybeSingle();
  if (!tpl || tpl.enabled === false) {
    // sin plantilla: para welcome igual aseguramos acceso por fallback
    if (type === "welcome") { await ensureUser(email, name, phone); const fb = await supabaseFallback(email); return json({ ok: fb, channel: "supabase", note: "sin plantilla, magic link nativo" }); }
    return json({ ok: false, error: "plantilla no encontrada: " + key }, 404);
  }

  // Link del CTA: welcome = magic link auto-login; dunning = portal normal
  let link = APP_URL;
  if (type === "welcome") { await ensureUser(email, name, phone); link = (await magicLink(email)) || APP_URL; }

  const vars: Record<string, string> = {
    nombre: name || "", plan,
    app_url: link,
    monto: p.amount != null ? "$" + Number(p.amount).toFixed(2) : "",
    fecha_pago: String(p.paidOn || ""),
  };
  const subject = fill(tpl.subject || "KAIZEN Coaching", vars);
  const html = fill(tpl.body_html || "", vars);
  const attachments = Array.isArray(tpl.attachments) ? tpl.attachments : [];

  const sent = await sendResend(email, subject, html, attachments);
  if (sent.ok) return json({ ok: true, channel: "resend", key });

  // Resend falló → fallback (solo welcome puede recuperarse con magic link nativo)
  if (type === "welcome") {
    const fb = await supabaseFallback(email);
    return json({ ok: fb, channel: "supabase", key, resendError: sent.err });
  }
  // dunning sin Resend: no hay fallback de correo; reportamos para reintento/log
  return json({ ok: false, channel: "none", key, resendError: sent.err });
});
