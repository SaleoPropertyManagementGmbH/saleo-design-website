// Rechnung serverseitig als PDF erzeugen und senden (an Kunde, Blindkopie an DATEV und an das eigene Postfach).
// Für die Cloud-Automatik: läuft ohne Browser und ohne Mac. Zugang: interner Cron-Schlüssel oder angemeldeter Nutzer.
import { createClient } from "npm:@supabase/supabase-js@2.45.4";
import { jsPDF } from "npm:jspdf@2.5.1";
import qrcode from "npm:qrcode-generator@1.4.4";
import { SMTPClient } from "https://deno.land/x/denomailer@1.6.0/mod.ts";

const sb = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!);
const cors = { "Access-Control-Allow-Origin": "*", "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type, x-cron-key", "Access-Control-Allow-Methods": "POST, OPTIONS" };
const antwort = (b: unknown, s = 200) => new Response(JSON.stringify(b), { status: s, headers: { ...cors, "Content-Type": "application/json" } });
let R: any = null, F: Record<string, string> = {}, LOGO: string | null = null;

const eurD = n => (Number(n) || 0).toLocaleString("de-DE", { minimumFractionDigits: 2, maximumFractionDigits: 2 }) + " €";
const datD = d => new Date(d).toLocaleDateString("de-DE", { day: "2-digit", month: "2-digit", year: "numeric" });
const SONDER = "Gebrauchtgegenstände/Sonderregelung. Differenzbesteuerung nach § 25a UStG, die Umsatzsteuer wird nicht gesondert ausgewiesen.";
function faellig() { const d = new Date(R.datum); d.setDate(d.getDate() + Number(F.zahlungsziel_tage || 7)); return d; }
function adresseZeilen() { const a = R.kunde_adresse || {}; return [R.kunde_name, a.zusatz, a.strasse, [a.plz, a.ort].filter(Boolean).join(" "), a.land && a.land !== "DE" ? a.land : ""].filter(Boolean); }
function zahlungText() {
  const z = [];
  if (R.zahlarten.includes("ueberweisung")) z.push(`per Überweisung an Kontoinhaber ${F.kontoinhaber || F.name}, ${F.bank || "Bank"}${F.iban ? ", IBAN " + F.iban : ""}${F.bic ? ", BIC " + F.bic : ""}, Verwendungszweck ${R.nummer}`);
  if (R.zahlarten.includes("paypal")) z.push(R.paypal_link ? `per PayPal über diesen Link: ${R.paypal_link}` : `per PayPal an ${F.paypal}, bitte mit der Rechnungsnummer ${R.nummer} als Nachricht`);
  if (R.zahlarten.includes("bar")) z.push("bar bei Abholung");
  if (R.zahlarten.includes("sumup")) z.push("mit Karte bei Abholung");
  return z;
}
const bezahlt = () => R.status === "bezahlt";
const steuerZeilen = () => [F.steuernummer ? `Steuernummer: ${F.steuernummer}` : "", F.ust_id ? `USt-IdNr.: ${F.ust_id}` : ""].filter(Boolean);
const fussSpalten = () => [[F.name, F.strasse, F.ort], [F.telefon ? `Tel.: ${F.telefon}` : "", F.email, F.web], [...steuerZeilen(), F.register || "", F.geschaeftsfuehrer ? `Geschäftsführer: ${F.geschaeftsfuehrer}` : ""], [F.bank || "", F.kontoinhaber ? `Kontoinhaber: ${F.kontoinhaber}` : "", F.iban ? `IBAN: ${F.iban}` : "", F.bic ? `BIC: ${F.bic}` : ""]].map(c => c.filter(Boolean));
function girocode() {
  if (!F.iban || !F.iban || !R.zahlarten.includes("ueberweisung") || bezahlt()) return null;
  const daten = ["BCD", "002", "1", "SCT", F.bic || "", (F.kontoinhaber || F.name).slice(0, 70), F.iban.replace(/\s/g, ""), "EUR" + Number(R.brutto).toFixed(2), "", "", R.nummer].join("\n");
  const q = qrcode(0, "M"); q.addData(daten); q.make(); return q;
}

function pdf() {
  const d = new jsPDF({ unit: "mm", format: "a4" });
  const L = 20, Rr = 190, AK = [39, 55, 77], HELL = [244, 246, 249];
  const grau = () => d.setTextColor(110, 116, 128), dunkel = () => d.setTextColor(23, 25, 29), weiss = () => d.setTextColor(255), fett = b => d.setFont("helvetica", b ? "bold" : "normal");
  const fuss = () => {
    d.setDrawColor(...AK); d.setLineWidth(0.6); d.line(L, 269, Rr, 269); d.setLineWidth(0.2);
    const X = [0, 38, 76, 118], W = [36, 36, 40, 52]; d.setFontSize(7.5);
    fussSpalten().forEach((col, c) => { let yy = 274; col.forEach((t, i) => { fett(i === 0); i === 0 ? dunkel() : grau(); const z = d.splitTextToSize(String(t), W[c]); d.text(z, L + X[c], yy); yy += z.length * 3.5; }); });
    fett(false);
  };
  const neueSeite = () => { fuss(); d.addPage(); d.setFillColor(...AK); d.rect(0, 0, 210, 3, "F"); return 20; };
  d.setFillColor(...AK); d.rect(0, 0, 210, 3, "F");
  if (LOGO) d.addImage(LOGO, "PNG", L, 12, 46, 23.7); else { d.setFillColor(...AK); d.rect(L, 13, 24, 24, "F"); }
  fett(true); d.setFontSize(24); d.setTextColor(...AK); d.text("RECHNUNG", Rr, 24, { align: "right", charSpace: 1.2 });
  fett(false); d.setFontSize(10.5); grau(); d.text(`Nr. ${R.nummer}`, Rr, 31, { align: "right" });
  d.setFontSize(7.5); grau(); const abs = `${F.name_absender || F.name} · ${F.strasse} · ${F.ort}`; d.text(abs, L, 49); d.setDrawColor(200); d.line(L, 50.3, L + d.getTextWidth(abs), 50.3);
  dunkel(); d.setFontSize(10.5); adresseZeilen().forEach((z, i) => d.text(z, L, 57 + i * 5));
  const meta = [["Rechnungsnummer", R.nummer], ...(R.kunde_nr ? [["Kundennummer", String(R.kunde_nr)]] : []), ["Rechnungsdatum", datD(R.datum)], ["Liefer-/Leistungsdatum", datD(R.lieferdatum || R.datum)], ...(bezahlt() ? [] : [["Zahlbar bis", datD(faellig())]]), ...(steuerZeilen().length ? [] : [["Steuernummer", "beantragt"]])];
  d.setFillColor(...HELL); d.roundedRect(120, 45, 70, meta.length * 5.6 + 7, 2, 2, "F");
  meta.forEach(([k, v], i) => { const yy = 51.5 + i * 5.6; d.setFontSize(8.5); grau(); d.text(k, 125, yy); d.setFontSize(9.5); dunkel(); fett(i === 0); d.text(String(v), 185, yy, { align: "right" }); fett(false); });
  let y = 96;
  const kopfzeile = () => { d.setFillColor(...AK); d.rect(L, y - 5.5, Rr - L, 8.5, "F"); weiss(); fett(true); d.setFontSize(9); d.text("Pos.", L + 3, y); d.text("Beschreibung", L + 15, y); d.text("Menge", 128, y, { align: "right" }); d.text("Einzelpreis", 158, y, { align: "right" }); d.text("Gesamt", Rr - 3, y, { align: "right" }); fett(false); dunkel(); y += 9; };
  kopfzeile(); d.setFontSize(10);
  R.positionen.forEach((p, i) => {
    const zeilen = d.splitTextToSize(p.text, 80);
    if (y + zeilen.length * 5 > 250) { y = neueSeite() + 6; kopfzeile(); d.setFontSize(10); }
    dunkel(); d.text(String(i + 1), L + 3, y); d.text(zeilen, L + 15, y); d.text(String(p.menge), 128, y, { align: "right" }); d.text(eurD(p.preis), 158, y, { align: "right" }); d.text(eurD(p.menge * p.preis), Rr - 3, y, { align: "right" });
    y += zeilen.length * 5 + 2.5; d.setDrawColor(228, 230, 235); d.line(L, y - 3.5, Rr, y - 3.5);
  });
  y += 2; d.setFontSize(10);
  if (R.besteuerung === "regel") { grau(); d.text("Nettobetrag", 124, y); dunkel(); d.text(eurD(R.netto), Rr - 3, y, { align: "right" }); y += 5.5; grau(); d.text("zzgl. 19 % USt", 124, y); dunkel(); d.text(eurD(R.ust), Rr - 3, y, { align: "right" }); y += 3; }
  d.setFillColor(...AK); d.roundedRect(120, y, 70, 11, 1.8, 1.8, "F"); weiss(); fett(true); d.setFontSize(11); d.text("Rechnungsbetrag", 124, y + 7.2); d.text(eurD(R.brutto), Rr - 4, y + 7.2, { align: "right" }); fett(false); dunkel();
  y += 20; d.setFontSize(8.5); grau();
  const absatz = t => { const z = d.splitTextToSize(t, Rr - L); d.text(z, L, y); y += z.length * 4 + 2; };
  if (R.besteuerung === "differenz") absatz(SONDER);
  if (R.hinweis) absatz(R.hinweis);
  if (F.rechnung_hinweis) absatz(F.rechnung_hinweis);
  const qr = girocode(), txtB = qr ? 118 : Rr - L - 10;
  d.setFontSize(9.5);
  const zl = bezahlt() ? [d.splitTextToSize("Der Betrag ist bei uns eingegangen. Vielen Dank!", txtB)] : zahlungText().map(t => d.splitTextToSize("•  " + t, txtB));
  const textH = 7 + zl.reduce((s, z) => s + z.length * 4.4 + 1.5, 0), boxH = Math.max(textH, qr ? 40 : 0) + 8;
  if (y + boxH + 12 > 265) y = neueSeite();
  y += 2; d.setFillColor(...HELL); d.roundedRect(L, y, Rr - L, boxH, 2, 2, "F");
  let ty = y + 8; d.setTextColor(...AK); fett(true); d.setFontSize(10.5); d.text(bezahlt() ? "Bereits bezahlt" : `Bitte zahlen Sie bis zum ${datD(faellig())}`, L + 5, ty); fett(false); dunkel(); d.setFontSize(9.5); ty += 6;
  zl.forEach(z => { d.text(z, L + 5, ty); ty += z.length * 4.4 + 1.5; });
  if (qr) {
    const n = qr.getModuleCount(), g = 30, s = g / n, qx = Rr - 5 - g, qy = y + 4; d.setFillColor(255); d.rect(qx - 1.5, qy - 1.5, g + 3, g + 3, "F"); d.setFillColor(0);
    for (let r = 0; r < n; r++) for (let c = 0; c < n; c++) if (qr.isDark(r, c)) d.rect(qx + c * s, qy + r * s, s, s, "F");
    d.setFontSize(7); grau(); d.text("Mit der Banking-App scannen", qx + g / 2, qy + g + 4.5, { align: "center" });
  }
  y += boxH + 9; d.setFontSize(10.5); d.setTextColor(...AK); fett(true); d.text("Vielen Dank für Ihren Einkauf!", L, y); fett(false);
  fuss();
  return d;
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  try {
    const key = req.headers.get("x-cron-key") || "";
    const soll = (await sb.from("intern_schluessel").select("wert").eq("name", "cron").maybeSingle()).data?.wert;
    const perSchluessel = !!soll && key === soll;
    let erlaubt = perSchluessel, wer = "Automatik";
    if (!erlaubt) {
      const auth = req.headers.get("Authorization") || "";
      const u = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_ANON_KEY") || "sb_publishable_HmAnd_xg6k-R2Nl2VAXecg_d-_OM9Kf", { global: { headers: { Authorization: auth } } });
      erlaubt = !!auth && !!(await u.rpc("ist_nutzer")).data;
    }
    if (!erlaubt) return antwort({ error: "Kein Zugriff" }, 403);
    const body = await req.json();
    // Seit 13.10.2026: Rechnungen gehen nur nach manueller Freigabe in der App raus (angemeldeter Nutzer). Die Automatik darf nur Testmails an das eigene Postfach senden.
    if (perSchluessel && !body.test) return antwort({ error: "Rechnungen werden nur nach Freigabe in der App gesendet" }, 403);
    const { data: r } = await sb.from("rechnung").select("*").eq("id", body.rechnung_id).single();
    if (!r) return antwort({ error: "Rechnung nicht gefunden" }, 404);
    if (r.status === "storniert") return antwort({ error: "Rechnung ist storniert" }, 400);
    if (r.gesendet_am && !body.erneut) return antwort({ ok: true, schon_gesendet: r.gesendet_am });
    const an = (body.an || r.kunde_email || "").trim();
    if (!/^[^@\s]+@[^@\s]+\.[^@\s]+$/.test(an)) return antwort({ error: "E-Mail des Kunden fehlt" }, 400);
    const { data: f } = await sb.from("firma").select("*");
    F = Object.fromEntries((f ?? []).map((x: any) => [x.schluessel, x.wert]));
    R = r;
    if (!R.kunde_adresse) return antwort({ error: "Adresse des Kunden fehlt" }, 400);
    if (!LOGO) { try { const t = await (await fetch("https://saleo-design.de/ops/logo-rechnung.js")).text(); LOGO = (t.match(/"(data:image\/png;base64,[^"]+)"/) || [])[1] || null; } catch (_) { LOGO = null; } }
    const doc = pdf();
    const b64 = doc.output("datauristring").split(",")[1];
    const passwort = Deno.env.get("SMTP_PASSWORT");
    if (!passwort) return antwort({ error: "Postfach-Passwort fehlt" }, 400);
    const text = body.text || `Guten Tag ${R.kunde_name},\n\nanbei erhalten Sie Ihre Rechnung ${R.nummer} über ${eurD(R.brutto)}.${bezahlt() ? "" : ` Bitte zahlen Sie bis zum ${datD(faellig())}, alle Zahlungsmöglichkeiten stehen auf der Rechnung.`}\n\nVielen Dank für Ihren Einkauf und viele Grüße\nIhr Team von Saleo Design`;
    const client = new SMTPClient({ connection: { hostname: F.smtp_host || "smtp.ionos.de", port: Number(F.smtp_port || 465), tls: true, auth: { username: F.smtp_user || F.email, password: passwort } } });
    const bcc = body.test ? [] : [F.datev_rechnungsausgang, F.email].filter(Boolean);
    await client.send({ from: "Saleo Design <" + (F.email || F.smtp_user) + ">", to: body.test ? (F.email || F.smtp_user) : an, bcc, subject: `Ihre Rechnung ${R.nummer} von Saleo Design`, content: text,
      attachments: [{ filename: `Rechnung_${R.nummer}_Saleo_Design.pdf`, content: b64, encoding: "base64", contentType: "application/pdf" }] });
    await client.close();
    if (!body.test) {
      const u = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!);
      await u.from("rechnung").update({ status: R.status === "bezahlt" ? "bezahlt" : "gesendet", gesendet_am: new Date().toISOString(), gesendet_von: body.wer || wer }).eq("id", R.id);
    }
    return antwort({ ok: true, an: body.test ? F.email : an, bcc, nummer: R.nummer });
  } catch (e) {
    return antwort({ error: String((e as Error)?.message ?? e) }, 500);
  }
});
