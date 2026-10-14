"""Kleinanzeigen-Abgleich ohne Guthaben: Daten kommen aus der öffentlichen Unternehmensseite im Browser.

Aufruf: python3 _tools/sync_browser.py BROWSER.json
BROWSER.json:
{"ids": ["<alle aktuell online stehenden Inseratnummern, beide Seiten von kleinanzeigen.de/pro/saleo-group>"],
 "neu": [{"ad_id": "...", "title": "...", "ad_url": "...", "images": ["https://img.kleinanzeigen.de/...?rule=$_59.AUTO"],
          "price": {"amount": 549, "price_type": "FIXED", "negotiable": false}, "created_at": "2026-10-14T14:16:00Z",
          "status": "ACTIVE", "description": "<HTML der Beschreibung>", "details": {"Zustand": "..."}}],
 "preise": {"<ad_id>": 549}}
"neu" nur für Inserate, die noch nicht in ops/data/inserate.json stehen. "preise" optional (aktueller Preis je Inserat).
Neue Inserate werden mit Planer-Vorlage ergänzt, verschwundene als nicht mehr aktiv markiert, wieder aufgetauchte reaktiviert.
Gibt aus, was sich geändert hat; schreibt nur, wenn sich etwas Inhaltliches geändert hat.
"""
import json
import sys
from datetime import datetime, timezone
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from sync_inserate import ZIEL, umwandeln  # noqa: E402


def main():
    b = json.load(open(sys.argv[1]))
    online = {str(i) for i in b.get("ids", [])}
    if len(online) < 5:
        raise SystemExit("Zu wenige Inserate gelesen, Abbruch (Seite nicht richtig geladen?).")
    d = json.load(open(ZIEL))
    jetzt = datetime.now(timezone.utc).isoformat(timespec="seconds")
    alt = {e["id"]: e for e in d["inserate"]}
    neu, weg, wieder, preis = [], [], [], []
    for ad in b.get("neu", []):
        if str(ad["ad_id"]) in alt:
            continue
        e = umwandeln(ad)
        e.update(zuerstGesehen=jetzt, zuletztGesehen=jetzt, aktiv=True, aufrufeVerlauf=[], aufrufe=None, gemerkt=None, anfragen=None)
        d["inserate"].insert(0, e)
        neu.append(f"{e['titel']} ({e['preis']} €)")
    for e in d["inserate"]:
        if e["id"] in online:
            if not e.get("aktiv"):
                e["aktiv"] = True
                wieder.append(e["titel"])
            e["zuletztGesehen"] = jetzt
            p = (b.get("preise") or {}).get(e["id"])
            if p is not None and p != e.get("preis"):
                preis.append(f"{e['titel']}: {e.get('preis')} → {p} €")
                e["preis"] = p
                if e.get("planer") and not e.get("planerManuell"):
                    e["planer"]["price"] = p
        elif e.get("aktiv"):
            e["aktiv"] = False
            weg.append(e["titel"])
    fehlt = online - {e["id"] for e in d["inserate"]}
    d["stand"] = jetzt
    geaendert = bool(neu or weg or wieder or preis)
    if geaendert:
        json.dump(d, open(ZIEL, "w"), ensure_ascii=False, indent=1)
    print(json.dumps({"geaendert": geaendert, "neu": neu, "nicht_mehr_online": weg, "wieder_online": wieder,
                      "preise": preis, "ohne_details": sorted(fehlt), "aktiv": sum(1 for e in d["inserate"] if e.get("aktiv"))},
                     ensure_ascii=False))


if __name__ == "__main__":
    main()
