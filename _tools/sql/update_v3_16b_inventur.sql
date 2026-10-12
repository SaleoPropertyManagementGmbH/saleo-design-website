-- v3.16b: Abgänge zum Durchschnittspreis, Fundorte sammeln
alter table lagerbewegung add column if not exists lagerort text;
create or replace function public.inventur(p_code text, p_menge integer, p_preis numeric, p_lagerort text default null) returns void
language plpgsql set search_path to 'public' as $function$
declare t teil; nb int; ns numeric;
begin
  select * into t from teil where code = p_code for update;
  nb := t.bestand + p_menge;
  ns := case when nb <= 0 then 0 when p_menge < 0 then t.durchschnittspreis else round((t.bestand * t.durchschnittspreis + p_menge * p_preis) / nb, 2) end;
  update teil set bestand = nb, durchschnittspreis = ns,
    lagerort = case when p_lagerort is null or p_menge < 0 then lagerort when coalesce(lagerort, '') = '' then p_lagerort
      when position(p_lagerort in lagerort) > 0 then lagerort else lagerort || ' · ' || p_lagerort end
  where code = p_code;
  insert into lagerbewegung (art, teil, menge, preis_stueck, bestand_danach, durchschnitt_danach, lagerort)
  values ('inventur', p_code, p_menge, case when p_menge < 0 then t.durchschnittspreis else p_preis end, nb, ns, p_lagerort);
end $function$;
