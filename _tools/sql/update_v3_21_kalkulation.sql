-- v3.21 (12.10.2026): Kalkulation für Aufträge ohne Lagerabbuchung (z. B. Möbel, die nie im Lager gezählt waren).
-- auftrag.kalkulation = [{text, teil, menge, preis}] nur zur Rechnung, bucht NIE etwas aus. Wareneinsatz fällt darauf zurück.
alter table auftrag add column if not exists kalkulation jsonb;

create or replace view auftrag_uebersicht as
 WITH w AS (
         SELECT mt.moebel_id, sum(mt.menge::numeric * t.durchschnittspreis) AS wert, sum(mt.menge)::integer AS teile
           FROM moebel_teil mt JOIN teil t ON t.code = mt.teil GROUP BY mt.moebel_id
        ), wt AS (
         SELECT a.id AS auftrag_id, sum(((x.value ->> 'menge')::numeric) * t.durchschnittspreis) AS wert, sum((x.value ->> 'menge')::integer)::integer AS teile
           FROM auftrag a CROSS JOIN LATERAL jsonb_array_elements(COALESCE(a.teile, '[]'::jsonb)) x(value)
             JOIN teil t ON t.code = (x.value ->> 'teil') GROUP BY a.id
        ), wk AS (
         SELECT a.id AS auftrag_id, round(sum(((x.value ->> 'menge')::numeric) * ((x.value ->> 'preis')::numeric)), 2) AS wert
           FROM auftrag a CROSS JOIN LATERAL jsonb_array_elements(COALESCE(a.kalkulation, '[]'::jsonb)) x(value) GROUP BY a.id
        ), re AS (
         SELECT DISTINCT ON (rechnung.auftrag_id) rechnung.id, rechnung.nummer, rechnung.auftrag_id, rechnung.status, rechnung.brutto, rechnung.besteuerung, rechnung.ust
           FROM rechnung WHERE rechnung.status <> 'storniert' ORDER BY rechnung.auftrag_id, rechnung.erstellt_am DESC
        ), b AS (
         SELECT a.id, a.status, a.kanal, a.inserat, a.moebel_id, a.titel, a.kaeufer_name, a.kaeufer_kontakt, a.adresse, a.versandart, a.preis,
            a.versand_kunde, a.versand_eigen, a.zahlart, a.zahlung_id, a.bezahlt_am, a.sicherheit, a.zuordnung, a.chat_auszug, a.paket,
            a.sendungsnummer, a.label_url, a.verkauf_id, a.freigabe_von, a.freigabe_am, a.notiz, a.erstellt_am, a.geaendert_am, a.teile, a.kalkulation,
            m.name AS moebel_name, m.lagerort, m.masse AS moebel_masse,
            COALESCE(mv.wareneinsatz, w.wert, wt.wert, wk.wert) AS wareneinsatz,
            COALESCE(w.teile, wt.teile) AS teile_anzahl,
            COALESCE(re.brutto, COALESCE(a.preis, 0::numeric) + a.versand_kunde) AS erloes,
            COALESCE(z.gebuehr, 0::numeric) AS zahlung_gebuehr, z.betrag AS zahlung_betrag, z.absender AS zahlung_absender, z.quelle AS zahlung_quelle, z.art AS zahlung_art,
            re.id AS rechnung_id, re.nummer AS rechnung_nummer, re.status AS rechnung_status, re.brutto AS rechnung_brutto, re.besteuerung, re.ust AS re_ust
           FROM auftrag a
             LEFT JOIN moebel m ON m.id = a.moebel_id
             LEFT JOIN w ON w.moebel_id = a.moebel_id
             LEFT JOIN wt ON wt.auftrag_id = a.id
             LEFT JOIN wk ON wk.auftrag_id = a.id
             LEFT JOIN marge_je_verkauf mv ON mv.id = a.verkauf_id
             LEFT JOIN zahlung z ON z.id = a.zahlung_id
             LEFT JOIN re ON re.auftrag_id = a.id
        )
 SELECT id, status, kanal, inserat, moebel_id, titel, kaeufer_name, kaeufer_kontakt, adresse, versandart, preis, versand_kunde, versand_eigen, zahlart,
    zahlung_id, bezahlt_am, sicherheit, zuordnung, chat_auszug, paket, sendungsnummer, label_url, verkauf_id, freigabe_von, freigabe_am, notiz,
    erstellt_am, geaendert_am, moebel_name, lagerort, moebel_masse, wareneinsatz, teile_anzahl AS teile, erloes, zahlung_gebuehr,
    round(erloes - versand_eigen - zahlung_gebuehr - COALESCE(wareneinsatz, 0::numeric) -
        CASE WHEN besteuerung = 'regel' THEN re_ust ELSE GREATEST(0::numeric, erloes - COALESCE(wareneinsatz, 0::numeric)) * 0.19 / 1.19 END, 2) AS gewinn_vor_steuern,
    zahlung_betrag, zahlung_absender, zahlung_quelle, zahlung_art, rechnung_id, rechnung_nummer, rechnung_status, rechnung_brutto, besteuerung,
    teile AS teile_liste, verkauf_id IS NOT NULL AS verkauft, kalkulation
   FROM b;
