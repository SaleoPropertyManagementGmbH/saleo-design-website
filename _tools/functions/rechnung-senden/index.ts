import { createClient } from "npm:@supabase/supabase-js@2";
import { SMTPClient } from "https://deno.land/x/denomailer@1.6.0/mod.ts";

// Rechnung per E-Mail über das IONOS-Postfach senden. Nur angemeldete Nutzer der App (Freigabe durch Samuel oder Leon).
// DATEV (Rechnungsausgang) bekommt jede freigegebene Rechnung, immer. Mit Kunden-E-Mail: an den Kunden, Blindkopie an DATEV und das eigene Postfach.
// Ohne Kunden-E-Mail (Kunde möchte keine Rechnung per Mail): nur an DATEV, Kopie ans eigene Postfach.
const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};
const antwort = (b: unknown, s = 200) => new Response(JSON.stringify(b), { status: s, headers: { ...cors, "Content-Type": "application/json" } });
const PUBLISHABLE = "sb_publishable_HmAnd_xg6k-R2Nl2VAXecg_d-_OM9Kf";
const istMail = (x: string) => /^[^@\s]+@[^@\s]+\.[^@\s]+$/.test(x);

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  try {
    const auth = req.headers.get("Authorization") ?? "";
    const sb = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_ANON_KEY") ?? PUBLISHABLE, { global: { headers: { Authorization: auth } } });
    const { data: ok } = await sb.rpc("ist_nutzer");
    if (!ok) return antwort({ error: "Kein Zugriff" }, 403);
    const { rechnung_id, pdf_base64, an, wer, betreff, text, test, ohne_kunde } = await req.json();
    const { data: r, error } = await sb.from("rechnung").select("*").eq("id", rechnung_id).single();
    if (error || !r) return antwort({ error: "Rechnung nicht gefunden" }, 404);
    const { data: f } = await sb.from("firma").select("*");
    const F: Record<string, string> = Object.fromEntries((f ?? []).map((x: { schluessel: string; wert: string }) => [x.schluessel, x.wert]));
    const passwort = Deno.env.get("SMTP_PASSWORT");
    if (!passwort) return antwort({ error: "Das Postfach-Passwort ist noch nicht hinterlegt." }, 400);
    const datev = (F.datev_rechnungsausgang || "").trim(), eigen = (F.email || F.smtp_user || "").trim();
    const kunde = ohne_kunde ? "" : (an ?? r.kunde_email ?? "").trim();
    if (kunde && !istMail(kunde)) return antwort({ error: "Die E-Mail-Adresse des Kunden ist ungültig. Feld leer lassen, wenn der Kunde keine Rechnung per Mail möchte." }, 400);
    if (!kunde && !istMail(datev)) return antwort({ error: "Ohne Kunden-E-Mail geht die Rechnung nur an DATEV, aber die DATEV-Adresse fehlt in den Firmendaten." }, 400);
    const anhang = [{ filename: "Rechnung_" + r.nummer + "_Saleo_Design.pdf", content: pdf_base64, encoding: "base64", contentType: "application/pdf" }];
    const client = new SMTPClient({ connection: { hostname: F.smtp_host || "smtp.ionos.de", port: Number(F.smtp_port || 465), tls: true, auth: { username: F.smtp_user || F.email, password: passwort } } });
    let to: string, bcc: string[];
    if (kunde) {
      // Schon freigegebene Rechnung erneut senden: DATEV hat sie bereits, darum nur an den Kunden und in euer Postfach
      to = kunde; bcc = test ? [] : [r.status === "entwurf" ? datev : "", eigen].filter(istMail);
      await client.send({ from: "Saleo Design <" + eigen + ">", to, bcc, subject: betreff || ("Ihre Rechnung " + r.nummer + " von Saleo Design"), content: text || ("Anbei Ihre Rechnung " + r.nummer + "."), attachments: anhang });
    } else {
      to = test ? eigen : datev; bcc = test ? [] : [eigen].filter(istMail);
      await client.send({ from: "Saleo Design <" + eigen + ">", to, bcc, subject: "Rechnung " + r.nummer + " Saleo Design UG", content: "Rechnung " + r.nummer + " im Anhang. Der Kunde hat keine Zusendung per E-Mail gewünscht.", attachments: anhang });
    }
    await client.close();
    if (!test) await sb.rpc("rechnung_gesendet", { p_id: rechnung_id, p_wer: wer || null, p_an: kunde || null });
    return antwort({ ok: true, an: kunde || null, datev: kunde ? bcc.includes(datev) : to === datev, bcc });
  } catch (e) {
    return antwort({ error: String((e as Error)?.message ?? e) }, 500);
  }
});
