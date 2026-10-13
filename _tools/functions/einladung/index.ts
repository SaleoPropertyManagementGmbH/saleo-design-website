// Einladung in Saleo Design Ops: legt den Nutzer mit Rolle an und schickt einen persönlichen Link zum Einrichten des Passworts.
import { createClient } from "npm:@supabase/supabase-js@2.45.4";
import { SMTPClient } from "https://deno.land/x/denomailer@1.6.0/mod.ts";

const sb = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!);
const cors = { "Access-Control-Allow-Origin": "*", "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type, x-cron-key", "Access-Control-Allow-Methods": "POST, OPTIONS" };
const antwort = (b: unknown, s = 200) => new Response(JSON.stringify(b), { status: s, headers: { ...cors, "Content-Type": "application/json" } });

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  try {
    const key = req.headers.get("x-cron-key") || "";
    const soll = (await sb.from("intern_schluessel").select("wert").eq("name", "cron").maybeSingle()).data?.wert;
    let erlaubt = !!soll && key === soll;
    if (!erlaubt) {
      const auth = req.headers.get("Authorization") || "";
      const u = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_ANON_KEY") || "sb_publishable_HmAnd_xg6k-R2Nl2VAXecg_d-_OM9Kf", { global: { headers: { Authorization: auth } } });
      erlaubt = !!auth && !!(await u.rpc("ist_nutzer")).data;
    }
    if (!erlaubt) return antwort({ error: "Kein Zugriff" }, 403);
    const body = await req.json();
    const email = String(body.email || "").trim().toLowerCase();
    const rolle = body.rolle === "voll" ? "voll" : "social";
    const name = String(body.name || "").trim() || null;
    if (!/^[^@\s]+@[^@\s]+\.[^@\s]+$/.test(email)) return antwort({ error: "E-Mail ungültig" }, 400);

    const { data: vorh } = await sb.from("app_nutzer").select("email").ilike("email", email).maybeSingle();
    if (vorh) await sb.from("app_nutzer").update({ rolle, name }).ilike("email", email);
    else await sb.from("app_nutzer").insert({ email, rolle, name });

    let typ = "invite";
    let { data: l, error } = await sb.auth.admin.generateLink({ type: "invite", email });
    if (error) { typ = "recovery"; ({ data: l, error } = await sb.auth.admin.generateLink({ type: "recovery", email })); }
    if (error || !l?.properties?.hashed_token) return antwort({ error: "Link nicht erzeugt: " + (error?.message || "unbekannt") }, 500);
    const link = `https://saleo-design.de/ops/?einladung=${encodeURIComponent(l.properties.hashed_token)}&typ=${typ}&mail=${encodeURIComponent(email)}`;

    const { data: f } = await sb.from("firma").select("*");
    const F: Record<string, string> = Object.fromEntries((f ?? []).map((x: any) => [x.schluessel, x.wert]));
    const passwort = Deno.env.get("SMTP_PASSWORT");
    if (!passwort) return antwort({ error: "Postfach-Passwort fehlt" }, 400);
    const bereich = rolle === "social" ? "den Social-Media-Bereich" : "die App";
    const text = `Hi${name ? " " + name : ""},\n\nhier ist dein Zugang zu Saleo Design Ops. Damit kommst du in ${bereich}: Instagram und TikTok Zahlen, Beiträge und den Content-Plan.\n\nSo geht es:\n1. Link öffnen: ${link}\n2. Ein eigenes Passwort festlegen (mindestens 8 Zeichen)\n3. Fertig. Danach meldest du dich einfach auf https://saleo-design.de/ops mit dieser E-Mail-Adresse und deinem Passwort an.\n\nDer Link funktioniert nur einmal und nur für dich, also bitte nicht weiterleiten. Falls er nicht mehr geht, kurz Bescheid geben, dann schicken wir einen neuen.\n\nViele Grüße\nSamuel und Leon\nSaleo Design`;
    const client = new SMTPClient({ connection: { hostname: F.smtp_host || "smtp.ionos.de", port: Number(F.smtp_port || 465), tls: true, auth: { username: F.smtp_user || F.email, password: passwort } } });
    await client.send({ from: "Saleo Design <" + (F.email || F.smtp_user) + ">", to: email, bcc: [F.email].filter(Boolean), subject: "Dein Zugang zu Saleo Design Ops", content: text });
    await client.close();
    return antwort({ ok: true, an: email, rolle, typ });
  } catch (e) {
    return antwort({ error: String((e as Error)?.message ?? e) }, 500);
  }
});
