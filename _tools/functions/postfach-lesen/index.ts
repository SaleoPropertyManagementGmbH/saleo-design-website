// Liest info@saleo-group.de per IMAP und speichert neue Kleinanzeigen-Nachrichten in ka_mail.
// Läuft per pg_cron alle 5 Minuten, rund um die Uhr, ohne Mac.
import { ImapFlow } from "npm:imapflow@1.0.164";
import { simpleParser } from "npm:mailparser@3.7.1";
import { createClient } from "npm:@supabase/supabase-js@2.45.4";

const sb = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!);

function auswerten(betreff: string, text: string, von: string) {
  const titel = (betreff.match(/[„"“»](.+?)[“"”«]/) || [])[1] || null;
  const inserat = (text.match(/Anzeigen(?:-| )?(?:nummer|ID|Nr\.?)\s*:?\s*(\d{8,12})/i) || text.match(/s-anzeige\/[^\s\/]+\/(\d{8,12})/) || [])[1] || null;
  const partner = (von.match(/^"?(.+?)"?\s+(?:über|via)\s+Kleinanzeigen/i) || [])[1] || null;
  const email = (text.match(/[A-Za-z0-9._%+-]+@(?!.*kleinanzeigen)[A-Za-z0-9.-]+\.[A-Za-z]{2,}/) || [])[0] || null;
  return { titel, inserat, partner, email };
}

Deno.serve(async (req) => {
  // Zugang: pg_cron mit internem Schlüssel oder ein angemeldeter Nutzer der App
  const key = req.headers.get("x-cron-key") || "";
  const soll = (await sb.from("intern_schluessel").select("wert").eq("name", "cron").maybeSingle()).data?.wert;
  let erlaubt = !!soll && key === soll;
  if (!erlaubt) {
    const auth = req.headers.get("Authorization") || "";
    if (auth) {
      const u = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_ANON_KEY") || "sb_publishable_HmAnd_xg6k-R2Nl2VAXecg_d-_OM9Kf", { global: { headers: { Authorization: auth } } });
      erlaubt = !!(await u.rpc("ist_nutzer")).data;
    }
  }
  if (!erlaubt) return new Response(JSON.stringify({ error: "Kein Zugriff" }), { status: 403 });
  const user = (await sb.from("firma").select("wert").eq("schluessel", "smtp_user").maybeSingle()).data?.wert || "info@saleo-group.de";
  const client = new ImapFlow({ host: "imap.ionos.de", port: 993, secure: true, logger: false,
    auth: { user, pass: Deno.env.get("SMTP_PASSWORT")! } });
  const neu: string[] = [];
  await client.connect();
  const lock = await client.getMailboxLock("INBOX");
  try {
    const tage = Number(new URL(req.url).searchParams.get("tage") || 2);
    const since = new Date(Date.now() - tage * 24 * 3600e3);
    const uids = await client.search({ since, from: "kleinanzeigen" }, { uid: true }) || [];
    for (const uid of uids.slice(-200)) {
      const msg = await client.fetchOne(String(uid), { source: true, envelope: true }, { uid: true });
      if (!msg?.source) continue;
      const mid = msg.envelope?.messageId || `uid-${uid}`;
      const da = await sb.from("ka_mail").select("message_id").eq("message_id", mid).maybeSingle();
      if (da.data) continue;
      const p = await simpleParser(msg.source);
      const betreff = p.subject || "";
      const von = p.from?.text || "";
      const text = (p.text || "").replace(/\r/g, "").slice(0, 20000);
      if (/Anmeldung|Rechnung|Buchung|Kauf wurde|PRO|Newsletter|Passwort/i.test(betreff) && !/Nachricht|Anfrage/i.test(betreff)) continue;
      const a = auswerten(betreff, text, von);
      const { error } = await sb.from("ka_mail").insert({ message_id: mid, datum: (p.date || new Date()).toISOString(), absender: von,
        antwort_an: p.replyTo?.text || null, betreff, text, ...a });
      if (!error) neu.push(betreff);
    }
  } finally {
    lock.release();
    await client.logout();
  }
  return new Response(JSON.stringify({ neu: neu.length, betreffe: neu }), { headers: { "content-type": "application/json" } });
});
