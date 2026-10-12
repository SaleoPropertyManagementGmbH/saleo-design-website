-- Update v3.12 (12.10.2026): Pulverbeschichtung (Palette mit Lagerteilen, Teilen für Kundenaufträge und Kundenteilen) und Büromöbel
-- Zustand S = schlecht, so nicht verbaubar (nur zum Beschichten). Teile kommen frisch beschichtet als Zustand N (neuwertig) zurück.
-- Kosten je Blech (Tablar, Seite, Rückwand, Front) netto aus firma.beschichtung_preis_blech (Start 16 €).
alter table teil drop constraint if exists teil_zustand_check;
alter table teil add constraint teil_zustand_check check (zustand in ('N', 'G', 'S'));
alter table lagerbewegung drop constraint if exists lagerbewegung_art_check;
alter table lagerbewegung add constraint lagerbewegung_art_check check (art in ('inventur', 'einkauf', 'verkauf', 'korrektur', 'beschichtung'));
insert into firma (schluessel, wert) values
  ('beschichtung_preis_blech', '16'),
  ('beschichtung_grenze_flaeche', '122500'),
  ('beschichter', null)
on conflict (schluessel) do nothing;

create table if not exists beschichtung (
  id uuid primary key default gen_random_uuid(),
  nummer int generated always as identity,
  status text not null default 'sammeln' check (status in ('sammeln', 'beim_beschichter', 'zurueck', 'storniert')),
  art text not null default 'lager' check (art in ('lager', 'kunde')),
  kunde text,
  auftrag_id uuid references auftrag(id),
  beschichter text,
  preis_blech numeric(10,2),
  kosten_netto numeric(10,2),
  abgegeben_am date,
  zurueck_am date,
  notiz text,
  erstellt_am timestamptz not null default now()
);
create table if not exists beschichtung_position (
  id uuid primary key default gen_random_uuid(),
  beschichtung_id uuid not null references beschichtung(id) on delete cascade,
  teil text references teil(code),
  bezeichnung text,
  menge int not null check (menge > 0),
  zielfarbe text references farbe(code),
  zweck text not null default 'lager' check (zweck in ('lager', 'auftrag', 'kundenteil')),
  auftrag_id uuid references auftrag(id),
  kunde text,
  einstand_stueck numeric(10,2),
  ziel_teil text references teil(code)
);
alter table beschichtung_position add column if not exists zweck text not null default 'lager';
alter table beschichtung_position add column if not exists auftrag_id uuid references auftrag(id);
alter table beschichtung_position add column if not exists kunde text;
alter table beschichtung_position alter column zielfarbe drop not null;
alter table beschichtung enable row level security;
alter table beschichtung_position enable row level security;
grant select on beschichtung, beschichtung_position to authenticated;
drop policy if exists app_lesen on beschichtung; create policy app_lesen on beschichtung for select to authenticated using (ist_nutzer());
drop policy if exists app_lesen on beschichtung_position; create policy app_lesen on beschichtung_position for select to authenticated using (ist_nutzer());

-- Lohnt sich das Beschichten? Groß (über 35 × 35): ab mittlerem Zustand. Klein: nur wenn unbrauchbar.
create or replace function beschichtung_lohnt(p_teil text) returns jsonb
language plpgsql stable set search_path = public as $$
declare
  t teil; tt teiltyp; fl int; grenze int; preis numeric; neu numeric;
begin
  select * into t from teil where code = p_teil;
  if not found then return jsonb_build_object('lohnt', false, 'grund', 'Teil unbekannt'); end if;
  select * into tt from teiltyp where code = t.typ;
  if tt.gruppe not in ('B Metall- und Glaselemente', 'C Einbauten', 'D Fronten') or t.farbe in ('GL', 'CR', 'SW') then
    return jsonb_build_object('lohnt', false, 'grund', 'Wird nicht beschichtet');
  end if;
  fl := coalesce(split_part(t.mass, 'x', 1)::int * split_part(t.mass, 'x', 2)::int, 0);
  grenze := (select wert::int from firma where schluessel = 'beschichtung_grenze_flaeche');
  preis := (select wert::numeric from firma where schluessel = 'beschichtung_preis_blech');
  neu := coalesce(t.neupreis, tt.richtwert);
  if fl > grenze then
    return jsonb_build_object('lohnt', true, 'grund', 'Großes Teil: lohnt sich schon bei mittlerem Zustand', 'kosten', preis, 'neupreis', neu);
  end if;
  return jsonb_build_object('lohnt', t.zustand = 'S', 'grund', 'Kleines Teil (bis 35 × 35): nur wenn unbrauchbar', 'kosten', preis, 'neupreis', neu);
end $$;

-- Sammelliste anlegen oder ergänzen. p: {"art":"lager|kunde","kunde":"...","notiz":"...","positionen":[{"teil":"BL-750x350-30-S","menge":3,"zielfarbe":"30"} | {"bezeichnung":"Tablar 750 × 350 (Kundenteil)","menge":2,"zielfarbe":"24"}]}
create or replace function beschichtung_anlegen(p jsonb) returns uuid
language plpgsql security definer set search_path = public as $$
declare b uuid; x jsonb;
begin
  if not ist_nutzer() then raise exception 'Kein Zugriff'; end if;
  insert into beschichtung (art, kunde, auftrag_id, beschichter, preis_blech, notiz)
  values (coalesce(p->>'art', 'lager'), p->>'kunde', nullif(p->>'auftrag_id', '')::uuid,
    coalesce(p->>'beschichter', (select wert from firma where schluessel = 'beschichter')),
    coalesce((p->>'preis_blech')::numeric, (select wert::numeric from firma where schluessel = 'beschichtung_preis_blech')), p->>'notiz')
  returning id into b;
  for x in select * from jsonb_array_elements(p->'positionen') loop
    insert into beschichtung_position (beschichtung_id, teil, bezeichnung, menge, zielfarbe, zweck, auftrag_id, kunde)
    values (b, nullif(x->>'teil', ''), x->>'bezeichnung', (x->>'menge')::int, nullif(x->>'zielfarbe', ''),
      coalesce(x->>'zweck', case when nullif(x->>'teil', '') is null then 'kundenteil' when x->>'auftrag_id' is not null then 'auftrag' else 'lager' end),
      nullif(x->>'auftrag_id', '')::uuid, x->>'kunde');
  end loop;
  return b;
end $$;

-- Abgabe beim Beschichter: Lagerteile gehen aus dem Bestand (Einstandspreis wird gemerkt)
create or replace function beschichtung_abgeben(p_id uuid, p_datum date default current_date) returns void
language plpgsql security definer set search_path = public as $$
declare pos beschichtung_position; t teil;
begin
  if not ist_nutzer() then raise exception 'Kein Zugriff'; end if;
  if not exists (select 1 from beschichtung where id = p_id and status = 'sammeln') then raise exception 'Nur gesammelte Aufträge können abgegeben werden'; end if;
  for pos in select * from beschichtung_position where beschichtung_id = p_id and teil is not null loop
    select * into t from teil where code = pos.teil for update;
    if t.bestand - t.reserviert < pos.menge then raise exception 'Zu wenig % im Lager (frei: %)', pos.teil, t.bestand - t.reserviert; end if;
    update teil set bestand = bestand - pos.menge where code = pos.teil;
    update beschichtung_position set einstand_stueck = t.durchschnittspreis where id = pos.id;
    insert into lagerbewegung (art, teil, menge, preis_stueck, bestand_danach, durchschnitt_danach, beleg_id, notiz)
    values ('beschichtung', pos.teil, -pos.menge, t.durchschnittspreis, t.bestand - pos.menge, t.durchschnittspreis, p_id, 'Zum Beschichter');
  end loop;
  update beschichtung set status = 'beim_beschichter', abgegeben_am = p_datum where id = p_id;
end $$;

-- Rückgabe: Lagerteile kommen als neuwertig in der Zielfarbe zurück, Einstand = alter Einstand + Beschichtung
-- p_farben: {"<position_id>": "30", ...} für Positionen, deren Farbe bei der Abgabe noch offen war
create or replace function beschichtung_zurueck(p_id uuid, p_kosten_netto numeric default null, p_datum date default current_date, p_farben jsonb default '{}') returns void
language plpgsql security definer set search_path = public as $$
declare b beschichtung; pos beschichtung_position; t teil; z text; stk numeric; bleche int; ziel teil;
begin
  if not ist_nutzer() then raise exception 'Kein Zugriff'; end if;
  select * into b from beschichtung where id = p_id for update;
  if b.status <> 'beim_beschichter' then raise exception 'Auftrag ist nicht beim Beschichter'; end if;
  select coalesce(sum(menge), 0) into bleche from beschichtung_position where beschichtung_id = p_id;
  stk := case when p_kosten_netto is not null and bleche > 0 then p_kosten_netto / bleche else b.preis_blech end;
  update beschichtung_position bp set zielfarbe = p_farben->>bp.id::text where beschichtung_id = p_id and p_farben ? bp.id::text;
  if exists (select 1 from beschichtung_position where beschichtung_id = p_id and teil is not null and zielfarbe is null) then
    raise exception 'Bei einigen Teilen fehlt noch die neue Farbe';
  end if;
  for pos in select * from beschichtung_position where beschichtung_id = p_id and teil is not null loop
    select * into t from teil where code = pos.teil;
    z := teil_code(t.typ, t.mass, pos.zielfarbe, 'N', t.generation);
    select * into ziel from teil where code = z for update;
    update teil set durchschnittspreis = round((ziel.bestand * ziel.durchschnittspreis + pos.menge * (coalesce(pos.einstand_stueck, 0) + stk)) / (ziel.bestand + pos.menge), 2),
      bestand = bestand + pos.menge where code = z returning * into ziel;
    update beschichtung_position set ziel_teil = z where id = pos.id;
    insert into lagerbewegung (art, teil, menge, preis_stueck, bestand_danach, durchschnitt_danach, beleg_id, notiz)
    values ('beschichtung', z, pos.menge, coalesce(pos.einstand_stueck, 0) + stk, ziel.bestand, ziel.durchschnittspreis, p_id, 'Vom Beschichter zurück');
    if pos.zweck = 'auftrag' and pos.auftrag_id is not null then
      perform reserviere('Auftrag ' || pos.auftrag_id, z, pos.menge);
    end if;
  end loop;
  update beschichtung set status = 'zurueck', zurueck_am = p_datum, kosten_netto = coalesce(p_kosten_netto, bleche * b.preis_blech) where id = p_id;
end $$;

create or replace view beschichtung_uebersicht with (security_invoker = true) as
select b.*, coalesce(sum(p.menge), 0)::int as bleche,
  coalesce(b.kosten_netto, coalesce(sum(p.menge), 0) * b.preis_blech) as kosten_erwartet,
  coalesce(jsonb_agg(jsonb_build_object('id', p.id, 'zweck', p.zweck, 'kunde', coalesce(p.kunde, a.kaeufer_name), 'teil', p.teil, 'bezeichnung', coalesce(p.bezeichnung, tt.bezeichnung || ' ' || replace(t.mass, 'x', ' × ')), 'menge', p.menge,
    'von', t.farbe, 'zielfarbe', p.zielfarbe, 'ziel_teil', p.ziel_teil)) filter (where p.id is not null), '[]') as positionen
from beschichtung b
left join beschichtung_position p on p.beschichtung_id = b.id
left join teil t on t.code = p.teil
left join teiltyp tt on tt.code = t.typ
left join auftrag a on a.id = p.auftrag_id
group by b.id;

-- Kandidaten: alles in Zustand S plus große gebrauchte Bleche
create or replace view beschichtung_kandidat with (security_invoker = true) as
select t.code, t.typ, tt.bezeichnung, t.mass, t.farbe, t.zustand, t.bestand - t.reserviert as frei, beschichtung_lohnt(t.code) as bewertung
from teil t join teiltyp tt on tt.code = t.typ
where t.bestand - t.reserviert > 0 and t.zustand = 'S';

revoke execute on function beschichtung_anlegen(jsonb), beschichtung_abgeben(uuid, date), beschichtung_zurueck(uuid, numeric, date, jsonb) from public, anon;
grant execute on function beschichtung_anlegen(jsonb), beschichtung_abgeben(uuid, date), beschichtung_zurueck(uuid, numeric, date, jsonb) to authenticated;
grant select on beschichtung_uebersicht, beschichtung_kandidat to authenticated;
do $$ begin begin alter publication supabase_realtime add table beschichtung; exception when others then null; end; end $$;

-- Büromöbel: stehen bei uns im Büro, sind aber verkäuflich (Teile zählen als verbaut)
alter table moebel add column if not exists einsatz text not null default 'lager';
alter table moebel drop constraint if exists moebel_einsatz_check;
alter table moebel add constraint moebel_einsatz_check check (einsatz in ('lager', 'buero'));
select count(*) as beschichtungen from beschichtung;
