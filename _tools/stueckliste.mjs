// Stückliste für einen Planer-Aufbau berechnen, mit genau der Logik aus ops/planer.html.
// Aufruf: node _tools/stueckliste.mjs PLANER.json  -> gibt JSON [{code,typ,mass,farbe,gen,qty,price}] aus
import fs from "fs";
import path from "path";
import { fileURLToPath } from "url";
const PW = process.env.PLAYWRIGHT_MODULE || "/opt/npm-tools/node_modules/playwright/index.mjs";
const { chromium } = await import(PW);
const ops = path.join(path.dirname(fileURLToPath(import.meta.url)), "..", "ops");
const daten = JSON.parse(fs.readFileSync(process.argv[2], "utf8"));
const FAKE = `window.supabase={createClient(){const q=()=>{const b={select(){return b},order(){return b},range(){return b},limit(){return b},eq(){return b},single(){return b},then(r){return Promise.resolve({data:[],error:null}).then(r)}};return b};
const ch={on(){return ch},subscribe(){return ch}};return{from:q,rpc:async()=>({data:[],error:null}),channel:()=>ch,auth:{getSession:async()=>({data:{session:{user:{email:"x"}}}})}}}};`;
const b = await chromium.launch();
const p = await b.newPage();
await p.route("**/*", r => {
  const u = new URL(r.request().url());
  if (u.hostname === "ops.local") {
    const f = path.join(ops, u.pathname.replace(/^\/ops\//, "") || "planer.html");
    return fs.existsSync(f) ? r.fulfill({ body: fs.readFileSync(f), contentType: f.endsWith(".js") ? "text/javascript" : f.endsWith(".css") ? "text/css" : "text/html" }) : r.fulfill({ status: 404, body: "" });
  }
  if (u.hostname.includes("jsdelivr")) return r.fulfill({ body: FAKE, contentType: "text/javascript" });
  return r.abort();
});
await p.goto("http://ops.local/ops/planer.html");
await p.waitForFunction(() => typeof bom === "function" && typeof LIVE !== "undefined");
await p.waitForTimeout(300);
const rows = await p.evaluate(d => {
  applyData(d); normalize();
  const geo = geometry();
  const msg = messages(geo);
  return { rows: bom(geo).map(r => ({ code: r.code, typ: r.typ, mass: r.mass, farbe: r.farbe, gen: r.gen, qty: r.qty, price: r.price, valid: r.valid, name: partName(r) })), aussen: outer(), hinweise: msg.replace(/<[^>]+>/g, " ").replace(/\s+/g, " ").trim() };
}, daten);
console.log(JSON.stringify(rows));
await b.close();
