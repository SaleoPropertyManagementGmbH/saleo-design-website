"""PayPal-Umsätze (Antwort von list_transactions als JSON) in SQL für die Tabelle zahlung umwandeln.

Aufruf: python3 _tools/paypal_zahlungen.py umsaetze.json > zahlungen.sql
Übernommen werden Zahlungen (Ereigniscodes T00xx): Eingänge sind Verkäufe, Ausgänge meist Einkäufe.
Aufladungen vom Bankkonto (T0300), Rückhalte und deren Freigaben (T11xx, T15xx) bleiben draußen.
Art: Waren und Dienstleistungen (mit Käuferschutz, protection_eligibility 01 oder Gebühr) oder Freunde und Familie.
"""
import json
import sys


def q(v):
    return "null" if v is None else "'" + str(v).replace("'", "''") + "'"


def main():
    d = json.load(open(sys.argv[1]))
    rows = []
    for t in d.get("transaction_details", []):
        i = t["transaction_info"]
        betrag = float(i["transaction_amount"]["value"])
        code = i.get("transaction_event_code", "")
        if betrag == 0 or not code.startswith("T00") or i.get("transaction_status") not in ("S", "P"):
            continue
        richtung = "ein" if betrag > 0 else "aus"
        betrag = abs(betrag)
        gebuehr = abs(float((i.get("fee_amount") or {}).get("value", 0)))
        art = ("waren" if i.get("protection_eligibility") == "01" or gebuehr > 0 else "freunde") if richtung == "ein" else None
        p = t.get("payer_info") or {}
        name = (p.get("payer_name") or {}).get("alternate_full_name") or " ".join(
            x for x in [(p.get("payer_name") or {}).get("given_name"), (p.get("payer_name") or {}).get("surname")] if x) or None
        rows.append(f"({q('paypal')}, {q(i['transaction_id'])}, {q(richtung)}, {q(art)}, {betrag:.2f}, {gebuehr:.2f}, {q(i['transaction_amount']['currency_code'])}, "
                    f"{q(i['transaction_initiation_date'])}::timestamptz, {q(name)}, {q(p.get('email_address'))}, "
                    f"{q(i.get('transaction_note') or i.get('transaction_subject'))}, {q(json.dumps(t, ensure_ascii=False))}::jsonb)")
    if not rows:
        print("-- keine neuen Zahlungen")
        return
    print("insert into zahlung (quelle, ext_id, richtung, art, betrag, gebuehr, waehrung, zeitpunkt, absender, absender_mail, nachricht, roh) values")
    print(",\n".join(rows))
    print("on conflict (quelle, ext_id) do nothing;")


if __name__ == "__main__":
    main()
