-- DPD-Preisliste (myDPD national, Stand 2026/04, Preise netto) und Versandpreis für Kunden (Faktor 2 auf DPD netto, dann 19 % USt)
create table if not exists dpd_tarif (bis_kg numeric primary key, preis numeric not null, produkt text not null default 'classic');
alter table dpd_tarif enable row level security;
drop policy if exists dpd_tarif_lesen on dpd_tarif;
create policy dpd_tarif_lesen on dpd_tarif for select to authenticated using (ist_nutzer());
grant select on dpd_tarif to authenticated;
insert into dpd_tarif (bis_kg, preis) values (3,3.40),(5,3.80),(10,4.40),(15,4.90),(20,5.10),(25,5.40),(31.5,5.70)
  on conflict (bis_kg) do update set preis = excluded.preis;
insert into firma (schluessel, wert) values ('dpd_maut','0.35'),('dpd_sicherheit','0.15'),('dpd_nc','7.00'),('dpd_insel','15.00'),('dpd_uebergroesse','43.00'),('versand_faktor','2')
  on conflict (schluessel) do update set wert = excluded.wert;

-- p_pakete: [{kg, l, b, h}] mit Bruttogewicht je Paket in kg und Maßen in cm; p_plz optional für den Inselzuschlag
create or replace function dpd_versandpreis(p_pakete jsonb, p_plz text default null)
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare x jsonb; kg numeric; l numeric; b numeric; h numeric; s numeric[]; band numeric; preis numeric; nc boolean; ueber boolean;
  maut numeric; sich numeric; ncz numeric; insel numeric; uebz numeric; faktor numeric; summe numeric := 0; liste jsonb := '[]'; ist_insel boolean;
begin
  if not ist_nutzer() then raise exception 'Kein Zugriff'; end if;
  select coalesce(max(wert) filter (where schluessel='dpd_maut'),'0.35')::numeric, coalesce(max(wert) filter (where schluessel='dpd_sicherheit'),'0.15')::numeric,
         coalesce(max(wert) filter (where schluessel='dpd_nc'),'7')::numeric, coalesce(max(wert) filter (where schluessel='dpd_insel'),'15')::numeric,
         coalesce(max(wert) filter (where schluessel='dpd_uebergroesse'),'43')::numeric, coalesce(max(wert) filter (where schluessel='versand_faktor'),'2')::numeric
    into maut, sich, ncz, insel, uebz, faktor from firma;
  ist_insel := coalesce(p_plz,'') ~ '^(18565|27498|27499|83256|2584[67]|25849|25859|25863|25869|2593[0-3]|25929|2594[0-2]|25938|25939|2594[6-9]|2595[2-5]|2596[1-9]|25970|25980|2598[56]|2598[89]|25990|2599[2-4]|2599[6-9]|26465|26474|26486|26548|26571|26579|26757)$';
  for x in select * from jsonb_array_elements(coalesce(p_pakete,'[]')) loop
    kg := coalesce((x->>'kg')::numeric, 0);
    s := array(select v from unnest(array[coalesce((x->>'l')::numeric,0), coalesce((x->>'b')::numeric,0), coalesce((x->>'h')::numeric,0)]) v order by v desc);
    l := s[1]; b := s[2]; h := s[3];
    select t.bis_kg, t.preis into band, preis from dpd_tarif t where t.bis_kg >= kg order by t.bis_kg limit 1;
    ueber := band is null or l > 175 or (l + 2*b + 2*h) > 300;
    if band is null then select t.bis_kg, t.preis into band, preis from dpd_tarif t order by t.bis_kg desc limit 1; end if;
    nc := not ueber and (l > 120 or b > 60 or h > 60 or l*b*h/1000 > 150);
    preis := preis + maut + sich + case when nc then ncz else 0 end + case when ueber then uebz else 0 end + case when ist_insel then insel else 0 end;
    summe := summe + preis;
    liste := liste || jsonb_build_object('kg', kg, 'masse', l||' × '||b||' × '||h, 'bis_kg', band, 'nc', nc, 'uebergroesse', ueber, 'dpd_netto', round(preis, 2));
  end loop;
  return jsonb_build_object('pakete', liste, 'anzahl', jsonb_array_length(liste), 'dpd_netto', round(summe, 2), 'kunde_netto', round(summe * faktor, 2),
    'kunde_brutto', round(summe * faktor * 1.19, 2), 'insel', ist_insel, 'hinweis', 'Energiezuschlag und Emergency Fuel Surcharge von DPD sind variabel und nicht enthalten');
end $$;
grant execute on function dpd_versandpreis(jsonb, text) to authenticated;

-- auftrag_aendern nimmt zusätzlich versand_eigen (DPD netto) und paket (jsonb) an; sonst unverändert (live in der DB angelegt am 13.10.2026)

-- steuer_bericht (13.10.2026): Versand bei § 25a regulär mit 19 % (Steuerberater), Positionen „Versand…“/„Lieferung…“ aus der Rechnung,
-- nicht Teil der Differenz; Summe versand_brutto, versand_netto, ust_versand, in netto_regel/ust_regel enthalten (live in der DB)
