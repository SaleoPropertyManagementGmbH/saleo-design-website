"""Kleinanzeigen-Inserate der Saleo Design UG in ops/data/inserate.json umwandeln.

Aufruf: python3 _tools/sync_inserate.py ROHDATEN.json [AUFRUFE.json]
ROHDATEN.json ist die Antwort von get_kleinanzeigen_seller_ads (Seller 151007875, size 100).
AUFRUFE.json (optional) ist {"AD_ID": aufrufe, ...} aus get_kleinanzeigen_ad mit include_views=true.
Pro Tag wird ein Aufrufe-Stand je Inserat gespeichert, daraus rechnet die App Aufrufe pro Tag.
Bestehende Einträge bleiben erhalten; verschwundene Inserate werden als nicht mehr aktiv markiert.
"""
import itertools
import json
import re
import sys
from datetime import datetime, timezone
from pathlib import Path

ZIEL = Path(__file__).resolve().parent.parent / "ops" / "data" / "inserate.json"
FARBEN = [
    ("stahlblau", "34"), ("enzianblau", "27"), ("olivgrün", "36"), ("olivgruen", "36"), ("anthrazit", "33"),
    ("mittelgrau", "32"), ("lichtgrau", "29"), ("mattsilber", "35"), ("graphitschwarz", "30"), ("reinweiß", "24"),
    ("goldgelb", "25"), ("reinorange", "26"), ("rubinrot", "23"), ("beige", "31"), ("braun", "22"),
    ("schwarz", "30"), ("weiß", "24"), ("weiss", "24"), ("grün", "28"), ("gruen", "28"), ("gelb", "25"),
    ("orange", "26"), ("rot", "23"), ("blau", "27"), ("grau", "32"), ("silber", "35"),
]
MOEBEL = r"sideboard|highboard|lowboard|konsole|nachttisch|couchtisch|beistelltisch|tv[ -]?board|kommode|aktenschrank|regal|anrichte|theke|dekotisch"
TISCH = r"schreibtisch|tablett|laptoptisch|monitorst"
HOEHEN = [175, 250, 350, 395, 500]
BREITEN = [750, 500, 395, 350]
KL = {"750x395", "500x395", "750x350", "500x350", "395x350", "350x350", "750x250", "500x250", "750x175", "500x175"}
AZ = {"750x395", "500x395", "750x350", "500x350", "395x350", "750x250", "500x250", "395x250", "750x175", "500x175", "395x175"}


def text(ad):
    d = ad.get("description") or ""
    d = re.sub(r"<br\s*/?>", "\n", d)
    d = re.sub(r"<[^>]+>", "", d)
    return re.sub(r"[ \t]+", " ", d).strip()


def zahl(rx, s):
    m = re.search(rx, s, re.I)
    return int(m.group(1)) if m else None


def farbe(ad, s):
    m = re.search(r"Farbe[n]?:\s*([^\n(]+)", s)
    quelle = (m.group(1) if m else "") + " " + ad["title"]
    q = quelle.lower()
    for wort, code in FARBEN:
        if wort in q:
            return code
    return None


def zerlege(ziel_mm, rand, masse, strafe, anzahl=1):
    kandidaten = []
    for n in range(1, 6):
        for combo in itertools.combinations_with_replacement(masse, n):
            fehler = abs(sum(combo) + rand - ziel_mm) + sum(strafe(m) for m in combo) + 8 * (n - 1)
            kandidaten.append((fehler, list(combo)))
    kandidaten.sort(key=lambda k: k[0])
    return [k[1] for k in kandidaten[:anzahl]] if anzahl > 1 else kandidaten[0][1]


def raster(reihen, spalten, tiefe, klappen, auszuege, offen):
    felder, uid, y = [], 1, 0
    for h in sorted(reihen, reverse=True):
        x = 0
        for w in spalten:
            felder.append({"id": uid, "x": x, "y": y, "w": w, "h": h, "front": "", "back": "" if offen else "BL", "inside": "",
                           "lock": "U", "gen": "N", "rahmen": False, "openL": False, "openR": False, "col": {}})
            uid += 1
            x += w
        y += h
    for f in felder:
        if auszuege and f"{f['w']}x{f['h']}" in AZ and tiefe >= 350:
            f["front"], f["rahmen"] = "AZ", True
            auszuege -= 1
    for f in sorted(felder, key=lambda f: (f["h"] != 350, f["y"], f["x"])):
        if klappen and not f["front"] and f"{f['w']}x{f['h']}" in KL:
            f["front"] = "KL"
            klappen -= 1
    return felder, klappen, auszuege


def layout(h_cm, b_cm, t_cm, klappen, auszuege, offen):
    spalten = sorted(zerlege(b_cm * 10, 23, BREITEN, lambda m: 0 if m in (750, 500) else 25), reverse=True)
    tiefe = min([250, 350, 500], key=lambda t: abs(t + 23 - t_cm * 10))
    kandidaten = [[350]] if h_cm <= 45 else zerlege(h_cm * 10, 40, HOEHEN, lambda m: 0 if m == 350 else 15, anzahl=8)
    beste = None
    for reihen in kandidaten:
        ergebnis = raster(reihen, spalten, tiefe, klappen, auszuege, offen)
        if beste is None:
            beste = ergebnis
        if not ergebnis[1] and not ergebnis[2]:
            beste = ergebnis
            break
    felder, kl_rest, az_rest = beste
    return felder, tiefe, kl_rest, az_rest


def umwandeln(ad):
    s = text(ad)
    titel = ad["title"]
    lt = (titel + " " + s[:200]).lower()
    h, b, t = zahl(r"H[öo]he:\s*(\d+)", s), zahl(r"Breite:\s*(\d+)", s), zahl(r"Tiefe:\s*(\d+)", s)
    klappen = zahl(r"(\d+)\s*x\s*Klappe", s) or 0
    innen = zahl(r"(\d+)\s*x\s*integrierte\s*Ausz", s) or 0
    auszuege = 0 if innen else (zahl(r"(\d+)\s*x\s*Ausz", s) or 0)
    prospekt = zahl(r"(\d+)\s*x\s*Prospekt", s) or 0
    neupreis = re.search(r"Neupreis\s*([\d.]+)\s*(?:€|Euro)", s)
    preis = ad.get("price") or {}
    zustand_txt = (ad.get("details") or {}).get("Zustand", "")
    zustand = "N" if (zustand_txt == "Neu" or "neuwertig" in s.lower()) else "G"
    art = "teil"
    if re.search(TISCH, lt):
        art = "tisch"
    elif re.search(MOEBEL, lt) and h and b:
        art = "moebel"
    e = {
        "id": ad["ad_id"], "titel": titel, "url": ad.get("ad_url"), "bilder": ad.get("images") or [],
        "preis": preis.get("amount"), "preisTyp": preis.get("price_type"), "vb": bool(preis.get("negotiable")),
        "erstellt": ad.get("created_at"), "status": ad.get("status"), "art": art,
        "farbe": farbe(ad, s), "zustand": zustand, "zustandText": zustand_txt,
        "masse": {"h": h, "b": b, "t": t} if h or b or t else None,
        "klappen": klappen, "auszuege": auszuege, "innenauszuege": innen, "prospekt": prospekt,
        "neupreis": int(neupreis.group(1).replace(".", "")) if neupreis else None,
        "beschreibung": s, "gekuerzt": s.endswith("..."), "planer": None, "hinweis": None,
    }
    if art == "moebel" and b:
        if not t:
            t = 35
            e["hinweis"] = "Tiefe fehlt im Inserat, 35 cm angenommen."
        offen = bool(re.search(r"couchtisch|beistelltisch", lt)) and not klappen and not auszuege
        felder, tiefe, kl_rest, az_rest = layout(h, b, t, klappen, auszuege, offen)
        for f in felder:
            if innen and f["front"] == "KL" and f"{f['w']}x{tiefe}" in {"750x500", "750x350", "500x500", "500x350"}:
                f["inside"] = "AT"
                innen -= 1
        for f in felder:
            if prospekt and not f["front"] and f["w"] in (500, 750) and f["h"] >= 350:
                f["inside"] = "ST"
                prospekt -= 1
        hinweise = [e["hinweis"]] if e["hinweis"] else []
        hinweise.append("Aufbau aus den Maßen im Inserat abgeleitet, bitte prüfen.")
        if kl_rest or az_rest:
            hinweise.append(f"{kl_rest} Klappe(n) und {az_rest} Auszug/Auszüge ließen sich nicht zuordnen.")
        e["hinweis"] = " ".join(hinweise)
        e["planer"] = {"fields": felder, "depth": tiefe, "color": e["farbe"] or "30", "zustand": zustand,
                       "base": "FU", "sides": "" if offen else "BL", "top": "BL", "buyNew": {},
                       "price": e["preis"], "rabatt": 0, "ertragsteuer": 30,
                       "neupreis": str(e["neupreis"]) if e["neupreis"] else ""}
    return e


def main():
    roh = json.load(open(sys.argv[1]))
    ads = roh["data"]["ads"] if "data" in roh else roh["ads"]
    jetzt = datetime.now(timezone.utc).isoformat(timespec="seconds")
    heute = jetzt[:10]
    aufrufe = {str(k): int(v) for k, v in json.load(open(sys.argv[2])).items()} if len(sys.argv) > 2 else {}
    alt = {}
    if ZIEL.exists():
        alt = {e["id"]: e for e in json.load(open(ZIEL))["inserate"]}
    voll = {}
    for f in (Path(__file__).resolve().parent / "ads").glob("*.json"):
        d = json.load(open(f))
        d = d.get("data", {}).get("ad", d)
        voll[str(d["ad_id"])] = d.get("description")
    neu = {}
    for ad in ads:
        if voll.get(ad["ad_id"]):
            ad = {**ad, "description": voll[ad["ad_id"]]}
        e = umwandeln(ad)
        frueher = alt.get(e["id"], {})
        e["zuerstGesehen"] = frueher.get("zuerstGesehen", jetzt)
        e["zuletztGesehen"] = jetzt
        e["aktiv"] = True
        verlauf = [v for v in frueher.get("aufrufeVerlauf", []) if v[0] != heute]
        if e["id"] in aufrufe:
            verlauf.append([heute, aufrufe[e["id"]]])
        e["aufrufeVerlauf"] = verlauf[-120:]
        e["aufrufe"] = verlauf[-1][1] if verlauf else None
        if frueher.get("planerManuell"):
            e["planer"], e["planerManuell"] = frueher["planer"], True
        neu[e["id"]] = e
    for i, e in alt.items():
        if i not in neu:
            e["aktiv"] = False
            e.setdefault("verschwundenAm", jetzt)
            neu[i] = e
    liste = sorted(neu.values(), key=lambda e: (not e["aktiv"], e.get("erstellt") or ""), reverse=False)
    liste.sort(key=lambda e: (not e["aktiv"], -(datetime.fromisoformat((e.get("erstellt") or "1970-01-01T00:00:00+00:00").replace("Z", "+00:00")).timestamp())))
    ZIEL.parent.mkdir(parents=True, exist_ok=True)
    json.dump({"stand": jetzt, "quelle": "https://www.kleinanzeigen.de/pro/saleo-group", "sellerId": "151007875",
               "inserate": liste}, open(ZIEL, "w"), ensure_ascii=False, indent=1)
    aktiv = [e for e in liste if e["aktiv"]]
    print(f"{len(aktiv)} aktiv, {len(liste) - len(aktiv)} verschwunden, "
          f"{sum(1 for e in aktiv if e['planer'])} mit Planer-Vorlage, "
          f"{sum(1 for e in aktiv if e['id'] not in alt)} neu")


if __name__ == "__main__":
    main()
