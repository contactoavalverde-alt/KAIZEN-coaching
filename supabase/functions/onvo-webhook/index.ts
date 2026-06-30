// ───────────────────────────────────────────────────────────
// KAIZEN Coaching — onvo-webhook
// Fuente de verdad del provisioning: ONVO avisa por webhook FIRMADO.
// NUNCA confiamos en el redirect del browser.
//   - primer cobro  → crea cliente + suscripción + pago + invitación
//   - renovación OK → registra el pago (dedup por payment-intent id)
//   - renovación FALLIDA → marca past_due + gracia (pg_cron expira luego)
//   - cancelada     → marca cancelled
// Idempotente: UNIQUE(onvo_subscription_id) + UNIQUE(onvo_payment_intent_id).
// ───────────────────────────────────────────────────────────
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const ONVO_API = "https://api.onvopay.com/v1";
const ONVO_SECRET = Deno.env.get("ONVO_SECRET_KEY")!;
const WEBHOOK_SECRET = Deno.env.get("ONVO_WEBHOOK_SECRET")!;
const GRACE_DAYS = 7;
const supabase = createClient(
  Deno.env.get("SUPABASE_URL")!,
  Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
);

const onvoGet = async (path: string) => {
  const r = await fetch(`${ONVO_API}${path}`, { headers: { Authorization: `Bearer ${ONVO_SECRET}` } });
  return r.ok ? await r.json() : null;
};
const FUNCS_URL = `${Deno.env.get("SUPABASE_URL")}/functions/v1`;
const INTERNAL = Deno.env.get("INVITE_INTERNAL_SECRET") || "";
// Dispara un correo branded (welcome / dunning) vía la función send-invite.
async function sendInvite(payload: Record<string, unknown>) {
  try {
    const r = await fetch(`${FUNCS_URL}/send-invite`, {
      method: "POST", headers: { "x-internal-secret": INTERNAL, "Content-Type": "application/json" }, body: JSON.stringify(payload),
    });
    return await r.json();
  } catch (e) { return { ok: false, err: String(e) }; }
}
const APP_URL = "https://kaizencoaching.com/portal";
const fmtDate = (d: Date) => d.toISOString().slice(0, 10);
const ok = (msg: string) => new Response(msg, { status: 200 });

// Resuelve el subscriptionId desde el payload (renewal lo trae; payment-intent no → vía customer)
async function resolveSubId(data: any): Promise<string | null> {
  let subId = data.subscriptionId || data.subscription?.id || data.renewal?.subscriptionId || null;
  if (!subId && data.customerId) {
    const cust = await onvoGet(`/customers/${data.customerId}`);
    const subs = (cust?.subscriptions || []).filter((s: any) => s.status !== "cancelled");
    subs.sort((a: any, b: any) => new Date(b.createdAt || 0).getTime() - new Date(a.createdAt || 0).getTime());
    if (subs.length) subId = subs[0].id;
  }
  return subId;
}

// Registra un pago de forma idempotente (dedup por el id del payment-intent de ONVO)
async function recordPayment(userId: string, amount: number, intentId: string | null) {
  const row: Record<string, unknown> = {
    user_id: userId, amount, method: "ONVO",
    period: fmtDate(new Date()), paid_on: fmtDate(new Date()), status: "paid",
  };
  if (intentId) row.onvo_payment_intent_id = intentId;
  await supabase.from("kaizen_payments").insert(row); // UNIQUE(onvo_payment_intent_id) ignora duplicados
}

Deno.serve(async (req) => {
  // 1) Verificar firma
  const sig = req.headers.get("x-webhook-secret") || req.headers.get("X-Webhook-Secret");
  if (!WEBHOOK_SECRET || sig !== WEBHOOK_SECRET) return new Response("unauthorized", { status: 401 });

  let evt: any;
  try { evt = await req.json(); } catch { return new Response("bad json", { status: 400 }); }
  const type: string = evt?.type || "";
  const data: any = evt?.data || {};
  const intentId: string | null = (type.startsWith("payment-intent") ? data.id : null) || data.paymentIntentId || null;

  try {
    // ── COBRO EXITOSO (activación o renovación) ──
    if (type === "subscription.renewal.succeeded" || type === "payment-intent.succeeded") {
      const subId = await resolveSubId(data);
      const sub: any = subId ? await onvoGet(`/subscriptions/${subId}`) : (data.subscription || null);
      if (!sub) return ok("ok (no sub)");

      const onvoSubId = sub.id;
      const onvoCusId = sub.customerId;
      const customer = onvoCusId ? await onvoGet(`/customers/${onvoCusId}`) : null;
      // Datos del cliente: metadata (nuestro checkout) o, si no, el customer de ONVO
      // (caso LINK DE PAGO de ONVO, que llena email/name/phone en el customer).
      const md = sub.metadata || {};
      const priceObj = sub.items?.[0]?.price || {};
      const email = md.email || customer?.email;
      const name = md.name || customer?.name || "";
      const phone = md.phone || customer?.phone || "";
      // Plan: metadata > nickname del precio (link de pago) > genérico
      const plan = md.plan || priceObj.nickname || "Programa grupal";
      const amount = (priceObj.unitAmount ?? 5000) / 100;

      // ¿Ya existe la suscripción? → renovación: solo registrar pago (idempotente)
      const { data: existing } = await supabase
        .from("kaizen_subscriptions").select("id,user_id,status").eq("onvo_subscription_id", onvoSubId).maybeSingle();
      if (existing) {
        await recordPayment(existing.user_id, amount, intentId);
        // un cobro exitoso reactiva una sub que estaba past_due
        if (existing.status === "past_due") {
          const end = new Date(); end.setMonth(end.getMonth() + 1);
          await supabase.from("kaizen_subscriptions").update({ status: "active", grace_until: null, end_date: fmtDate(end) }).eq("id", existing.id);
        }
        return ok("ok (renewal)");
      }

      // Primer cobro → provisionar
      if (!email) return ok("ok (no email)");
      let userId: string | null = null;
      const cre = await supabase.auth.admin.createUser({ email, email_confirm: true, user_metadata: { name, phone, source: "onvo" } });
      if (cre.data?.user) userId = cre.data.user.id;
      if (!userId) {
        const { data: list } = await supabase.auth.admin.listUsers();
        userId = list?.users?.find((u: any) => u.email?.toLowerCase() === email.toLowerCase())?.id || null;
      }
      if (!userId) return ok("ok (no user)");

      // Insertar la SUSCRIPCIÓN PRIMERO (UNIQUE onvo_subscription_id) = candado de idempotencia.
      // Si otra entrega del webhook ya la creó, este insert falla → salimos sin duplicar nada.
      const start = new Date(); const end = new Date(); end.setMonth(end.getMonth() + 1);
      const insSub = await supabase.from("kaizen_subscriptions").insert({
        user_id: userId, plan, status: "active",
        start_date: fmtDate(start), end_date: fmtDate(end),
        monthly_price: amount, app_url: APP_URL,
        onvo_subscription_id: onvoSubId, onvo_customer_id: onvoCusId,
      });
      if (insSub.error) return ok("ok (already provisioned)"); // entrega concurrente ganó

      await supabase.from("kaizen_clients").upsert(
        { user_id: userId, name, email, phone, onvo_customer_id: onvoCusId },
        { onConflict: "user_id" },
      );
      await recordPayment(userId, amount, intentId);
      // Correo de bienvenida branded (con magic link) — Resend; si no hay dominio, cae al magic link nativo
      const inv = await sendInvite({ to: email, name, phone, plan, type: "welcome", amount });
      try { await supabase.from("kaizen_events").insert({ event: "subscription_started", data: { plan, email, invite_channel: (inv as any)?.channel || null, invite_ok: !!(inv as any)?.ok } }); } catch (_) { /* noop */ }
      return ok("ok (provisioned)");
    }

    // ── RENOVACIÓN FALLIDA → dunning (past_due + gracia; pg_cron expira luego) ──
    if (type === "subscription.renewal.failed") {
      const subId = await resolveSubId(data);
      if (subId) {
        const grace = new Date(); grace.setDate(grace.getDate() + GRACE_DAYS);
        const { data: row } = await supabase.from("kaizen_subscriptions")
          .update({ status: "past_due", grace_until: fmtDate(grace) })
          .eq("onvo_subscription_id", subId).select("user_id, plan, monthly_price").maybeSingle();
        // Correo branded de seguimiento (plantilla payment_failed)
        let mail: any = null;
        if (row?.user_id) {
          const { data: cli } = await supabase.from("kaizen_clients").select("email, name").eq("user_id", row.user_id).maybeSingle();
          if (cli?.email) mail = await sendInvite({ to: cli.email, name: cli.name || "", plan: row.plan || "tu plan", type: "dunning", amount: row.monthly_price ?? 50, paidOn: fmtDate(new Date()) });
        }
        await supabase.from("kaizen_events").insert({ event: "payment_failed", data: { subId, user_id: row?.user_id || null, grace_until: fmtDate(grace), mail_channel: mail?.channel || null, mail_ok: !!mail?.ok } });
      } else {
        await supabase.from("kaizen_events").insert({ event: "payment_failed", data: { type, unresolved: true } });
      }
      return ok("ok (past_due)");
    }

    // ── CANCELACIÓN (por si ONVO la notifica; el portal también la marca al cancelar) ──
    if (type === "subscription.cancelled" || type === "subscription.canceled") {
      const subId = await resolveSubId(data);
      if (subId) await supabase.from("kaizen_subscriptions").update({ status: "cancelled" }).eq("onvo_subscription_id", subId);
      return ok("ok (cancelled)");
    }

    if (type === "payment-intent.failed") {
      await supabase.from("kaizen_events").insert({ event: "payment_failed", data: { type } });
      return ok("ok (failure logged)");
    }

    return ok("ok (ignored)");
  } catch (e) {
    console.error("webhook error", String(e));
    return ok("ok (error logged)"); // 2xx para no entrar en loop de reintentos
  }
});
