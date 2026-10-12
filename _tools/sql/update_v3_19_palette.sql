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
