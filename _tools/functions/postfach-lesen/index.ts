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
  if (new URL(req.url).searchParams.get("debug") === "1") {
    const out: string[] = [];
    const since = new Date(Date.now() - 30 * 24 * 3600e3);
    for (const box of await client.list()) {
      if (box.flags?.has("\\Noselect")) continue;
      const lock = await client.getMailboxLock(box.path);
      try {
        const alle = (await client.search({ since }, { uid: true }) || []).length;
        const ka = await client.search({ since, or: [{ from: "kleinanzeigen" }, { subject: "Kleinanzeigen" }, { body: "kleinanzeigen.de/s-anzeige" }] }, { uid: true }) || [];
        let bsp = "";
        if (ka.length) { const m = await client.fetchOne(String(ka[ka.length - 1]), { envelope: true }, { uid: true }); bsp = (m?.envelope?.from?.[0]?.address || "") + " | " + (m?.envelope?.subject || "").slice(0, 60); }
        out.push(`${box.path}${box.specialUse ? " (" + box.specialUse + ")" : ""}: ${alle} Mails, ${ka.length} Kleinanzeigen ${bsp}`);
      } finally { lock.release(); }
    }
    await client.logout();
    return new Response(JSON.stringify({ debug: out }), { headers: { "content-type": "application/json" } });
  }
  const ordner: string[] = [];
  const nurListe = new URL(req.url).searchParams.get("ordner") === "1";
  const liste = await client.list();
  // Sortieren: laufende Chats in einen eigenen Ordner, erledigte (Verkauf abgeschlossen oder kein Deal) in den Papierkorb
  const zielOffen = "02_VERKAUF/Kleinanzeigen/Offene Chats";
  if (!liste.some((b) => b.path === zielOffen)) { try { await client.mailboxCreate(zielOffen); } catch (_) { /* existiert schon */ } }
  const papierkorb = liste.find((b) => b.specialUse === "\\Trash")?.path || "Papierkorb";
  const verschoben: string[] = [];
  for (const box of liste) {
    if (box.flags?.has("\\Noselect")) continue;
    // Chat-Benachrichtigungen landen teils im Papierkorb oder Spam, darum werden die mit durchsucht; nur Gesendet und Entwürfe nicht
    if (/^(Sent|Gesendet|Drafts|Entw)/i.test(box.name) || box.specialUse && /Sent|Drafts/.test(box.specialUse)) continue;
    const lock = await client.getMailboxLock(box.path);
    try {
      const tage = Number(new URL(req.url).searchParams.get("tage") || 2);
      const since = new Date(Date.now() - tage * 24 * 3600e3);
      const uids = await client.search(box.path === zielOffen ? { from: "kleinanzeigen" } : { since, from: "kleinanzeigen" }, { uid: true }) || [];
      ordner.push(box.path + ":" + uids.length);
      if (nurListe) continue;
      const umzug: Record<string, number[]> = {};
      const merken = (ziel: string, uid: number) => { if (ziel !== box.path) (umzug[ziel] = umzug[ziel] || []).push(uid); };
      for (const uid of uids.slice(-200)) {
        const msg = await client.fetchOne(String(uid), { source: true, envelope: true }, { uid: true });
        if (!msg?.source) continue;
        if (!/@([a-z0-9-]+\.)*kleinanzeigen\.de$/i.test(msg.envelope?.from?.[0]?.address || "")) continue;
        const istChat = /Nutzer-Anfrage|Nachricht|Anfrage zu/i.test(msg.envelope?.subject || "");
        const mid = msg.envelope?.messageId || `uid-${box.path}-${uid}`;
        const da = await sb.from("ka_mail").select("message_id, erledigt").eq("message_id", mid).maybeSingle();
        if (da.data) { if (istChat) merken(da.data.erledigt ? papierkorb : zielOffen, uid); continue; }
        const p = await simpleParser(msg.source);
        const betreff = p.subject || "";
        const von = p.from?.text || "";
        const text = (p.text || "").replace(/\r/g, "").slice(0, 20000);
        if (/Anmeldung|Rechnung|Buchung|Kauf wurde|PRO|Newsletter|Passwort/i.test(betreff) && !/Nachricht|Anfrage/i.test(betreff)) continue;
        const a = auswerten(betreff, text, von);
        const { error } = await sb.from("ka_mail").insert({ message_id: mid, datum: (p.date || new Date()).toISOString(), absender: von,
          antwort_an: p.replyTo?.text || null, betreff, text, ...a });
        if (!error) { neu.push(betreff); if (istChat) merken(zielOffen, uid); }
      }
      for (const [ziel, liste2] of Object.entries(umzug)) {
        try { await client.messageMove(liste2.join(","), ziel, { uid: true }); verschoben.push(`${liste2.length} nach ${ziel}`); } catch (e) { verschoben.push(`Fehler ${ziel}: ${String(e)}`); }
      }
    } finally {
      lock.release();
    }
  }
  await client.logout();
  return new Response(JSON.stringify({ neu: neu.length, betreffe: neu, verschoben, ordner }), { headers: { "content-type": "application/json" } });
});
