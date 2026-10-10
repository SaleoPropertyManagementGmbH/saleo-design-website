"""Fertig gekauftes USM-Möbel in Einzelteile umrechnen und als SQL für Supabase ausgeben.

Aufruf: python3 _tools/fertigmoebel.py ANGABEN.json > buchung.sql
ANGABEN.json, Beispiel:
{"name": "Sideboard 2x1 schwarz", "h": 74, "b": 153, "t": 37, "klappen": 2, "auszuege": 0, "innenauszuege": 0,
 "offen": false, "farbe": "30", "zustand": "G", "preis": 900, "benzin": 30, "fahrzeug": 0, "sonstige": 0,
 "quelle": "Kleinanzeigen, Verkäufer Hamburg", "datum": "2026-10-10", "lagerort": "R1", "inserat": null,
 "fields": null, "depth": null, "base": "FU", "notiz": null}
Wird "fields" (Planer-Felder) mitgegeben, gilt genau dieser Aufbau statt der Ableitung aus den Maßen.
"""
import json
import subprocess
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from sync_inserate import layout  # noqa: E402

FARBE = {"24", "29", "35", "32", "33", "30", "34", "27", "28", "36", "25", "26", "23", "22", "31"}


def q(v):
    return "null" if v is None else "'" + str(v).replace("'", "''") + "'"


def main():
    a = json.load(open(sys.argv[1]))
    if a.get("farbe") not in FARBE:
        raise SystemExit(f"Unbekannte Farbe {a.get('farbe')}")
    zustand = a.get("zustand", "G").upper()
    hinweise = []
    if a.get("fields"):
        felder, tiefe = a["fields"], a.get("depth") or 350
    else:
        felder, tiefe, kl_rest, az_rest = layout(a["h"], a["b"], a["t"], a.get("klappen", 0), a.get("auszuege", 0), a.get("offen", False))
        innen = a.get("innenauszuege", 0)
        for f in felder:
            if innen and f["front"] == "KL" and f"{f['w']}x{tiefe}" in {"750x500", "750x350", "500x500", "500x350"}:
                f["inside"], innen = "AT", innen - 1
        if kl_rest or az_rest:
            hinweise.append(f"{kl_rest} Klappe(n), {az_rest} Auszug/Auszüge nicht zuordenbar")
    offen = a.get("offen", False)
    daten = {"fields": felder, "depth": tiefe, "color": a["farbe"], "zustand": zustand, "base": a.get("base", "FU"),
             "sides": "" if offen else "BL", "top": "BL", "buyNew": {}, "price": a.get("verkaufspreis"), "rabatt": 0,
             "ertragsteuer": 30, "neupreis": ""}
    tmp = Path("/tmp/fm_planer.json")
    tmp.write_text(json.dumps(daten))
    out = subprocess.run(["node", str(Path(__file__).resolve().parent / "stueckliste.mjs"), str(tmp)], capture_output=True, text=True, check=True)
    erg = json.loads(out.stdout)
    rows = erg["rows"]
    ungueltig = [r["code"] for r in rows if not r["valid"]]
    if ungueltig:
        raise SystemExit("Ungültige Maße im Aufbau: " + ", ".join(ungueltig))
    teile = []
    for r in rows:
        typ = "HW-" + r["mass"] if r["typ"] == "HW" else "HW-KS" if r["typ"] == "KS" else r["typ"]
        mass = "" if r["typ"] in ("HW", "KS") else r["mass"]
        e = {"typ": typ, "farbe": r["farbe"], "zustand": zustand, "menge": r["qty"], "wert": round(r["price"], 2)}
        if mass:
            e["mass"] = mass
        if r["gen"] == "A":
            e["gen"] = "A"
        teile.append(e)
    o = erg["aussen"]
    masse = f"{round(o['w'] / 10)} × {round(o['h'] / 10)} × {round(o['d'] / 10)}"
    daten["_inserat"] = a.get("inserat")
    daten["_version"] = 6
    print(f"-- Fertigmöbel: {a['name']} · {len(rows)} Positionen, {sum(r['qty'] for r in rows)} Teile · außen {masse} cm")
    if hinweise or erg["hinweise"]:
        print("-- Hinweise: " + "; ".join(hinweise + [erg["hinweise"]]))
    print("select fertigmoebel_einkauf(")
    print(f"  p_name => {q(a['name'])}, p_preis => {a['preis']}, p_teile => {q(json.dumps(teile, ensure_ascii=False))}::jsonb,")
    print(f"  p_farbe => {q(a['farbe'])}, p_zustand => {q(zustand)}, p_benzin => {a.get('benzin', 0)}, p_fahrzeug => {a.get('fahrzeug', 0)}, p_sonstige => {a.get('sonstige', 0)},")
    print(f"  p_quelle => {q(a.get('quelle'))}, p_datum => {q(a.get('datum')) + '::date' if a.get('datum') else 'current_date'}, p_masse => {q(masse)},")
    print(f"  p_lagerort => {q(a.get('lagerort'))}, p_inserat => {q(a.get('inserat'))}, p_daten => {q(json.dumps(daten, ensure_ascii=False))}::jsonb,")
    print(f"  p_notiz => {q(a.get('notiz'))}, p_kategorie => {q(a.get('kategorie'))}) as moebel_id;")


if __name__ == "__main__":
    main()
