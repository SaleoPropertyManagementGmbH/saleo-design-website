/* Saleo Design Ops: gemeinsame Verbindung, Anmeldung, Hilfsfunktionen */
const SB_URL = "https://uqcropugtdtrzaumjbby.supabase.co";
const SB_KEY = "sb_publishable_HmAnd_xg6k-R2Nl2VAXecg_d-_OM9Kf";
const sb = supabase.createClient(SB_URL, SB_KEY, { auth: { persistSession: true, autoRefreshToken: true, detectSessionInUrl: true } });
const store = {
  get(k, d = "") { try { return localStorage.getItem(k) ?? d; } catch { return d; } },
  set(k, v) { try { localStorage.setItem(k, v); } catch {} }
};
const DEVICE = (() => { let d = store.get("sdo_dev"); if (!d) { d = Math.random().toString(36).slice(2, 10); store.set("sdo_dev", d); } return d; })();
const WHO = ["Samuel", "Leon"];
const me = () => store.get("sdo_wer");
async function requireSession() {
  const { data } = await sb.auth.getSession();
  if (!data.session) { location.replace("index.html?next=" + encodeURIComponent(location.pathname.split("/").pop() + location.search)); return null; }
  return data.session;
}
async function fetchAll(table, select = "*", mod = q => q) {
  let out = [], from = 0;
  for (;;) {
    const { data, error } = await mod(sb.from(table).select(select)).range(from, from + 999);
    if (error) throw error;
    out = out.concat(data);
    if (data.length < 1000) return out;
    from += 1000;
  }
}
const esc = s => String(s ?? "").replace(/[&<>"']/g, c => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" }[c]));
const eur = n => (Number(n) || 0).toLocaleString("de-DE", { style: "currency", currency: "EUR" });
const when = t => t ? new Date(t).toLocaleString("de-DE", { day: "2-digit", month: "2-digit", year: "2-digit", hour: "2-digit", minute: "2-digit" }) : "";
function whoPicker(onChange) {
  const v = me();
  return `<label class="who">Ich bin <select id="who">${v ? "" : `<option value="">wählen</option>`}${WHO.map(n => `<option${n === v ? " selected" : ""}>${n}</option>`).join("")}</select></label>`;
}
document.addEventListener("change", e => { if (e.target.id === "who") { store.set("sdo_wer", e.target.value); document.dispatchEvent(new CustomEvent("who")); } });
