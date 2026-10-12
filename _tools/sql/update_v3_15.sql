-- Update v3.15 (12.10.2026): verbaute Teile je Möbel mit Menge (für das aufklappbare „verbaut“ im Lager)
create or replace view teil_verbaut as
 select mt.teil, sum(mt.menge)::integer as verbaut, string_agg(distinct m.name, ', ') as verbaut_in,
   jsonb_agg(jsonb_build_object('name', m.name, 'menge', mt.menge, 'id', m.id, 'einsatz', m.einsatz) order by mt.menge desc) as verbaut_liste
 from moebel_teil mt join moebel m on m.id = mt.moebel_id
 where m.status = any (array['aufgebaut', 'reserviert'])
 group by mt.teil;
create or replace view lager_health as
 select t.code, tt.gruppe, tt.bezeichnung, t.mass, t.farbe, t.zustand, t.generation, t.bestand, t.reserviert,
    t.bestand - t.reserviert - coalesce(v.verbaut, 0) as verfuegbar,
    coalesce(t.mindestbestand, tt.mindestbestand) as mindestbestand,
    t.durchschnittspreis,
    t.bestand::numeric * t.durchschnittspreis as wert,
    t.nur_neu, t.lagerort,
    t.bestand - t.reserviert - coalesce(v.verbaut, 0) < coalesce(t.mindestbestand, tt.mindestbestand, 0) as unter_minimum,
    coalesce(v.verbaut, 0) as verbaut, v.verbaut_in,
    mp.vk as marktpreis,
    t.bestand::numeric * mp.vk as marktwert,
    round(case when mp.vk > t.durchschnittspreis then (mp.vk - t.durchschnittspreis) / 1.19 else mp.vk - t.durchschnittspreis end, 2) as marge_stueck,
    v.verbaut_liste
   from teil t
     join teiltyp tt on tt.code = t.typ
     left join teil_verbaut v on v.teil = t.code
     left join lateral (select marktpreis_fuer(t.typ, t.mass, t.zustand::text) as vk) mp on true;
select code, verbaut, jsonb_array_length(verbaut_liste) n from lager_health where code = 'CO-CR-G';
