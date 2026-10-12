-- Update v3.19 (12.10.2026): Palette Beschichter. Was auf der Palette liegt, wird gesammelt; Zielfarbe und Kundenauftrag pro Teil zuordnen; volle Palette abgeben.
insert into firma (schluessel, wert) values ('palette_kapazitaet', '60') on conflict (schluessel) do nothing;

create or replace function palette_beschichtung() returns uuid
language plpgsql security definer set search_path = public as $$
declare b uuid;
begin
  if not ist_nutzer() then raise exception 'Kein Zugriff'; end if;
  select id into b from beschichtung where status = 'sammeln' and notiz = 'Palette Beschichter' order by erstellt_am limit 1;
  if b is null then
    insert into beschichtung (art, beschichter, preis_blech, notiz)
    values ('lager', (select wert from firma where schluessel = 'beschichter'), (select wert::numeric from firma where schluessel = 'beschichtung_preis_blech'), 'Palette Beschichter')
    returning id into b;
  end if;
  return b;
end $$;

create or replace function palette_zuordnen(p_teil text, p_menge int, p_zielfarbe text, p_auftrag uuid default null) returns uuid
language plpgsql security definer set search_path = public as $$
declare b uuid; frei int; pid uuid; k text;
begin
  if not ist_nutzer() then raise exception 'Kein Zugriff'; end if;
  if coalesce(p_menge, 0) <= 0 then raise exception 'Anzahl fehlt'; end if;
  b := palette_beschichtung();
  select t.bestand - coalesce((select sum(menge) from beschichtung_position where beschichtung_id = b and teil = p_teil), 0) into frei from teil t where t.code = p_teil;
  if frei is null then raise exception 'Teil % unbekannt', p_teil; end if;
  if p_menge > frei then raise exception 'Nur noch % Stück frei', frei; end if;
  select coalesce(kaeufer_name, titel) into k from auftrag where id = p_auftrag;
  select id into pid from beschichtung_position where beschichtung_id = b and teil = p_teil and zielfarbe is not distinct from nullif(p_zielfarbe, '') and auftrag_id is not distinct from p_auftrag;
  if pid is not null then
    update beschichtung_position set menge = menge + p_menge where id = pid;
  else
    insert into beschichtung_position (beschichtung_id, teil, bezeichnung, menge, zielfarbe, zweck, auftrag_id, kunde)
    values (b, p_teil, (select concat_ws(' ', ty.bezeichnung, replace(t.mass, 'x', ' × ')) from teil t join teiltyp ty on ty.code = t.typ where t.code = p_teil),
      p_menge, nullif(p_zielfarbe, ''), case when p_auftrag is null then 'lager' else 'auftrag' end, p_auftrag, k)
    returning id into pid;
  end if;
  return pid;
end $$;

create or replace function palette_zuordnung_loeschen(p_pos uuid) returns void
language plpgsql security definer set search_path = public as $$
begin
  if not ist_nutzer() then raise exception 'Kein Zugriff'; end if;
  delete from beschichtung_position p using beschichtung b where p.id = p_pos and b.id = p.beschichtung_id and b.status = 'sammeln';
end $$;

-- Palette abgeben: Rest ohne Zuordnung kommt mit, Farbe wird dann bei Rückkehr gewählt
create or replace function palette_abgeben() returns uuid
language plpgsql security definer set search_path = public as $$
declare b uuid; x record;
begin
  if not ist_nutzer() then raise exception 'Kein Zugriff'; end if;
  b := palette_beschichtung();
  for x in select t.code, t.bestand - coalesce((select sum(menge) from beschichtung_position where beschichtung_id = b and teil = t.code), 0) rest
    from teil t where t.lagerort like '%Palette Beschichter%' and t.bestand > 0 loop
    if x.rest > 0 then perform palette_zuordnen(x.code, x.rest::int, null::text, null::uuid); end if;
  end loop;
  if not exists (select 1 from beschichtung_position where beschichtung_id = b) then raise exception 'Palette ist leer'; end if;
  perform beschichtung_abgeben(b);
  update beschichtung set notiz = 'Palette Beschichter, abgegeben' where id = b;
  update teil set lagerort = nullif(trim(both ' ·' from replace(replace(lagerort, ' · Raum 3, Palette Beschichter', ''), 'Raum 3, Palette Beschichter', '')), '')
    where lagerort like '%Palette Beschichter%' and bestand = 0;
  return b;
end $$;

revoke execute on function palette_beschichtung(), palette_zuordnen(text, int, text, uuid), palette_zuordnung_loeschen(uuid), palette_abgeben() from public, anon;
grant execute on function palette_beschichtung(), palette_zuordnen(text, int, text, uuid), palette_zuordnung_loeschen(uuid), palette_abgeben() to authenticated;

-- v3.19b: Menge einer Zuordnung ändern (0 = zurück auf die Palette)
create or replace function palette_menge(p_pos uuid, p_menge int) returns void
language plpgsql security definer set search_path = public as $$
begin
  if not ist_nutzer() then raise exception 'Kein Zugriff'; end if;
  if coalesce(p_menge, 0) <= 0 then
    delete from beschichtung_position p using beschichtung b where p.id = p_pos and b.id = p.beschichtung_id and b.status = 'sammeln';
  else
    update beschichtung_position p set menge = p_menge from beschichtung b where p.id = p_pos and b.id = p.beschichtung_id and b.status = 'sammeln';
  end if;
end $$;
revoke execute on function palette_menge(uuid, int) from public, anon;
grant execute on function palette_menge(uuid, int) to authenticated;
-- v3.19d (12.10.2026): Palette finalisieren, Übersicht per E-Mail an den Beschichter; Sonderfarben mit RAL
insert into firma (schluessel, wert) values ('beschichter_email', 'alfeo.felgenundpulverwerk@gmx.de')
  on conflict (schluessel) do update set wert = excluded.wert;
alter table beschichtung add column if not exists gesendet_am timestamptz;
alter table beschichtung add column if not exists gesendet_an text;
alter table beschichtung add column if not exists gesendet_von text;

create or replace view beschichtung_uebersicht as
SELECT b.id, b.nummer, b.status, b.art, b.kunde, b.auftrag_id, b.beschichter, b.preis_blech, b.kosten_netto, b.abgegeben_am, b.zurueck_am, b.notiz, b.erstellt_am,
  COALESCE(sum(p.menge), 0::bigint)::integer AS bleche,
  COALESCE(b.kosten_netto, COALESCE(sum(p.menge), 0::bigint)::numeric * b.preis_blech) AS kosten_erwartet,
  COALESCE(jsonb_agg(jsonb_build_object('id', p.id, 'zweck', p.zweck, 'kunde', COALESCE(p.kunde, a.kaeufer_name), 'teil', p.teil,
    'bezeichnung', COALESCE(p.bezeichnung, (tt.bezeichnung || ' '::text) || replace(t.mass, 'x'::text, ' × '::text)), 'menge', p.menge, 'von', t.farbe,
    'zielfarbe', p.zielfarbe, 'ziel_teil', p.ziel_teil, 'auftrag_id', p.auftrag_id)) FILTER (WHERE p.id IS NOT NULL), '[]'::jsonb) AS positionen,
  b.gesendet_am, b.gesendet_an, b.gesendet_von
FROM beschichtung b LEFT JOIN beschichtung_position p ON p.beschichtung_id = b.id LEFT JOIN teil t ON t.code = p.teil
  LEFT JOIN teiltyp tt ON tt.code = t.typ LEFT JOIN auftrag a ON a.id = p.auftrag_id GROUP BY b.id;
grant select on beschichtung_uebersicht to authenticated;

create or replace function palette_gesendet(p_an text, p_wer text default null) returns uuid
language plpgsql security definer set search_path = public as $$
declare b uuid;
begin
  if not ist_nutzer() then raise exception 'Kein Zugriff'; end if;
  b := palette_beschichtung();
  update beschichtung set gesendet_am = now(), gesendet_an = p_an, gesendet_von = p_wer where id = b;
  return b;
end $$;
revoke execute on function palette_gesendet(text, text) from public, anon;
grant execute on function palette_gesendet(text, text) to authenticated;

drop function if exists farbe_sonder_anlegen(text, text);
create or replace function farbe_sonder_anlegen(p_name text, p_hex text, p_ral text default null) returns text
language plpgsql security definer set search_path = public as $$
declare c text; n int; r text := nullif(trim(regexp_replace(coalesce(p_ral, ''), '^\s*(RAL)?\s*', '', 'i')), '');
begin
  if not ist_nutzer() then raise exception 'Kein Zugriff'; end if;
  if coalesce(trim(p_name), '') = '' then raise exception 'Name fehlt'; end if;
  if r is not null then r := 'RAL ' || r; end if;
  select code into c from farbe where lower(name) = lower(trim(p_name));
  if c is not null then update farbe set hex = coalesce(nullif(p_hex, ''), hex), ral = coalesce(r, ral) where code = c; return c; end if;
  select coalesce(max(substr(code, 2)::int), 0) + 1 into n from farbe where code ~ '^X[0-9]+$';
  c := 'X' || n;
  insert into farbe (code, name, hex, ral, sonder, sortierung) values (c, trim(p_name), nullif(p_hex, ''), r, true, 100 + n);
  return c;
end $$;
revoke execute on function farbe_sonder_anlegen(text, text, text) from public, anon;
grant execute on function farbe_sonder_anlegen(text, text, text) to authenticated;
select (select wert from firma where schluessel = 'beschichter_email') mail, (select count(*) from beschichtung_uebersicht) v;

-- v3.19c: Sonderfarben
alter table farbe add column if not exists hex text;
alter table farbe add column if not exists sonder boolean not null default false;
update farbe set hex = '#c9ccd0' where code = 'CR' and hex is null;
insert into farbe (code, name, hex, sonder, sortierung) select 'X1', 'Burgunder', '#6b1e2e', true, 101 where not exists (select 1 from farbe where code = 'X1');

-- v3.19e: Teil aus der Kandidatenliste auf die Palette legen
create or replace function palette_hinzufuegen(p_teil text) returns void
language plpgsql security definer set search_path = public as $$
begin
  if not ist_nutzer() then raise exception 'Kein Zugriff'; end if;
  update teil set lagerort = case when coalesce(lagerort, '') = '' then 'Raum 3, Palette Beschichter' when lagerort like '%Palette Beschichter%' then lagerort else lagerort || ' · Raum 3, Palette Beschichter' end where code = p_teil and bestand > 0;
  if not found then raise exception 'Teil % nicht im Lager', p_teil; end if;
end $$;
revoke execute on function palette_hinzufuegen(text) from public, anon;
grant execute on function palette_hinzufuegen(text) to authenticated;
