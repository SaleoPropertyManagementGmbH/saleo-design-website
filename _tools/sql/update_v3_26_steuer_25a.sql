-- v3.26 (13.10.2026): Differenzbesteuerung § 25a UStG. Jeder Verkauf (Auftrag) bekommt seine Einkäufe zugeordnet (FIFO je Teil),
-- daraus Differenz je Verkauf, Steuer und Monatsübersicht für den Steuerberater.
-- Einkaufspreis § 25a = an den Verkäufer gezahlter Preis je Stück (ohne eigene Nebenkosten wie Benzin, Fahrzeug, Beschichtung, Palette).

create table if not exists steuer_zuordnung (
  id bigserial primary key,
  auftrag_id uuid not null references auftrag(id),
  teil text not null,
  menge integer not null check (menge > 0),
  charge text,                 -- 'e:<einkauf_position.id>' oder 'i:<lagerbewegung.id>' (Inventur), null = ohne Beleg
  charge_art text not null check (charge_art in ('einkauf','altbestand','ohne_beleg')),
  ek_stueck numeric not null default 0,
  manuell boolean not null default false,
  aktiv boolean not null default true,      -- neu zugeordnet: alte Zeilen bleiben als Verlauf, aktiv = false
  erstellt_am timestamptz not null default now()
);
create index if not exists steuer_zuordnung_auftrag on steuer_zuordnung(auftrag_id);
create index if not exists steuer_zuordnung_charge on steuer_zuordnung(charge);
alter table steuer_zuordnung enable row level security;
drop policy if exists steuer_lesen on steuer_zuordnung;
create policy steuer_lesen on steuer_zuordnung for select using (ist_nutzer());
grant select on steuer_zuordnung to authenticated;

-- Vergleichsschlüssel: Typ, Maß, Generation (Farbe und Zustand egal, weil Teile beschichtet oder aufbereitet werden)
create or replace function public.teil_schluessel(p_code text) returns text language sql stable set search_path to 'public' as $$
  select coalesce(
    (select t.typ || '|' || coalesce(t.mass, '') || '|' || coalesce(t.generation, 'N') from teil t where t.code = p_code),
    case when split_part(p_code, '-', 1) = 'HW' then 'HW-' || split_part(p_code, '-', 2) || '||N'
      else split_part(p_code, '-', 1) || '|' || case when split_part(p_code, '-', 2) ~ '^[0-9]+(x[0-9]+)?$' then split_part(p_code, '-', 2) else '' end
        || '|' || case when p_code like '%-A' then 'A' else 'N' end end)
$$;

-- Alle Einkaufs-Chargen mit Restmenge
create or replace view steuer_charge as
  select 'e:' || p.id::text as charge, p.teil, teil_schluessel(p.teil) as schluessel, e.datum,
    case when e.quelle ilike 'Inventur%' then 'altbestand' else 'einkauf' end as art,
    p.menge, round(coalesce(p.preis_gesamt, 0) / nullif(p.menge, 0), 4) as ek_stueck,
    coalesce(k.verkaeufer, e.quelle) as lieferant, coalesce(k.titel, e.notiz) as beleg, k.inserat
  from einkauf_position p join einkauf e on e.id = p.einkauf_id
  left join lateral (select verkaeufer, titel, inserat from ka_einkauf where einkauf_id = e.id limit 1) k on true
  where p.menge > 0
  union all
  select 'i:' || b.id::text, b.teil, teil_schluessel(b.teil), b.zeitpunkt::date, 'altbestand', b.menge, coalesce(b.preis_stueck, 0),
    'Inventur', 'Altbestand laut Inventur', null
  from lagerbewegung b where b.art = 'inventur' and b.menge > 0;

-- Verkaufte Teile eines Auftrags: Lagerteile, sonst Fertigmöbel, sonst Kalkulation aus dem Planer
create or replace function public.auftrag_teile_steuer(p_auftrag uuid) returns table(teil text, menge integer) language sql stable set search_path to 'public' as $$
  with a as (select * from auftrag where id = p_auftrag),
  roh as (
    select x->>'teil' teil, (x->>'menge')::numeric menge from a, jsonb_array_elements(coalesce(a.teile, '[]'::jsonb)) x where jsonb_array_length(coalesce(a.teile, '[]'::jsonb)) > 0
    union all
    select mt.teil, mt.menge from a join moebel_teil mt on mt.moebel_id = a.moebel_id where jsonb_array_length(coalesce(a.teile, '[]'::jsonb)) = 0
    union all
    select x->>'teil', (x->>'menge')::numeric from a, jsonb_array_elements(coalesce(a.kalkulation, '[]'::jsonb)) x
      where jsonb_array_length(coalesce(a.teile, '[]'::jsonb)) = 0 and a.moebel_id is null and coalesce(x->>'teil', '') <> ''
  )
  select teil, sum(menge)::int from roh where coalesce(teil, '') <> '' and menge > 0 group by teil
$$;

create or replace function public.steuer_zuordnen(p_auftrag uuid, p_neu boolean default false) returns integer
 language plpgsql security definer set search_path to 'public' as $$
declare it record; c record; rest integer; nimm integer; n integer := 0; dp numeric;
begin
  if not ist_nutzer() then raise exception 'Kein Zugriff'; end if;
  if exists (select 1 from steuer_zuordnung where auftrag_id = p_auftrag and aktiv) then
    if not p_neu then return 0; end if;
    update steuer_zuordnung set aktiv = false where auftrag_id = p_auftrag and aktiv and not manuell;
  end if;
  for it in select * from auftrag_teile_steuer(p_auftrag) loop
    rest := it.menge - coalesce((select sum(menge) from steuer_zuordnung where auftrag_id = p_auftrag and teil = it.teil and aktiv), 0);
    for c in
      select ch.*, ch.menge - coalesce((select sum(z.menge) from steuer_zuordnung z where z.charge = ch.charge and z.aktiv), 0) as frei
      from steuer_charge ch where ch.schluessel = teil_schluessel(it.teil)
      order by ch.datum, (ch.teil = it.teil) desc, ch.charge
    loop
      exit when rest <= 0;
      continue when c.frei <= 0;
      nimm := least(rest, c.frei);
      insert into steuer_zuordnung (auftrag_id, teil, menge, charge, charge_art, ek_stueck) values (p_auftrag, it.teil, nimm, c.charge, c.art, c.ek_stueck);
      rest := rest - nimm; n := n + 1;
    end loop;
    if rest > 0 then
      select durchschnittspreis into dp from teil where code = it.teil;
      insert into steuer_zuordnung (auftrag_id, teil, menge, charge, charge_art, ek_stueck) values (p_auftrag, it.teil, rest, null, 'ohne_beleg', coalesce(dp, 0));
      n := n + 1;
    end if;
  end loop;
  return n;
end $$;

-- Alle verkauften Aufträge ohne Zuordnung in zeitlicher Reihenfolge zuordnen (FIFO)
create or replace function public.steuer_zuordnen_offen() returns integer language plpgsql security definer set search_path to 'public' as $$
declare a record; n integer := 0;
begin
  if not ist_nutzer() then raise exception 'Kein Zugriff'; end if;
  for a in select id from auftrag where status in ('bezahlt','freigegeben','label','versendet','abgeholt')
      and not exists (select 1 from steuer_zuordnung z where z.auftrag_id = auftrag.id and z.aktiv)
      order by coalesce(bezahlt_am, erstellt_am) loop
    perform steuer_zuordnen(a.id); n := n + 1;
  end loop;
  return n;
end $$;

create or replace function public.steuer_neu_zuordnen(p_auftrag uuid) returns integer language plpgsql security definer set search_path to 'public' as $$
begin
  if not ist_nutzer() then raise exception 'Kein Zugriff'; end if;
  return steuer_zuordnen(p_auftrag, true);
end $$;

-- Bericht für einen Zeitraum: je Verkauf Verkaufspreis, zugeordnete Einkäufe, Differenz, Steuer
create or replace function public.steuer_bericht(p_von date, p_bis date) returns jsonb language plpgsql security definer set search_path to 'public' as $$
declare res jsonb;
begin
  if not ist_nutzer() then raise exception 'Kein Zugriff'; end if;
  perform steuer_zuordnen_offen();
  with v as (
    select a.id, a.titel, a.kaeufer_name, a.kanal, a.status, r.nummer, r.status as rstatus,
      coalesce(r.lieferdatum, r.datum, a.bezahlt_am::date, a.erstellt_am::date) as datum,
      coalesce(r.besteuerung, 'differenz') as besteuerung,
      coalesce(r.brutto, coalesce(a.preis, 0) + coalesce(a.versand_kunde, 0)) as vk,
      r.ust as r_ust, r.netto as r_netto
    from auftrag a
    left join lateral (select * from rechnung where auftrag_id = a.id and status <> 'storniert' order by erstellt_am desc limit 1) r on true
    where a.status in ('bezahlt','freigegeben','label','versendet','abgeholt')
  ), z as (
    select z.auftrag_id, sum(z.menge * z.ek_stueck) ek,
      sum(z.menge) filter (where z.charge_art = 'ohne_beleg') ohne_beleg,
      sum(z.menge) filter (where z.charge_art = 'altbestand') altbestand,
      jsonb_agg(jsonb_build_object('teil', z.teil, 'menge', z.menge, 'ek_stueck', z.ek_stueck, 'art', z.charge_art, 'charge', z.charge,
        'datum', ch.datum, 'lieferant', ch.lieferant, 'beleg', ch.beleg, 'inserat', ch.inserat) order by z.teil) teile
    from steuer_zuordnung z left join steuer_charge ch on ch.charge = z.charge where z.aktiv group by z.auftrag_id
  ), x as (
    select v.*, coalesce(z.ek, 0) ek, coalesce(z.ohne_beleg, 0) ohne_beleg, coalesce(z.altbestand, 0) altbestand, coalesce(z.teile, '[]'::jsonb) teile,
      v.vk - coalesce(z.ek, 0) as differenz
    from v left join z on z.auftrag_id = v.id where v.datum between p_von and p_bis
  ), y as (
    select x.*,
      case when besteuerung = 'differenz' then round(greatest(differenz, 0) * 19 / 119, 2) else coalesce(r_ust, round(vk * 19 / 119, 2)) end as ust,
      case when besteuerung = 'differenz' then round(greatest(differenz, 0) * 100 / 119, 2) else coalesce(r_netto, round(vk * 100 / 119, 2)) end as bemessung
    from x
  )
  select jsonb_build_object(
    'von', p_von, 'bis', p_bis,
    'summe', jsonb_build_object(
      'verkaeufe', count(*), 'vk', coalesce(sum(vk), 0), 'ek', coalesce(sum(ek), 0),
      'diff_pos', coalesce(sum(greatest(differenz, 0)) filter (where besteuerung = 'differenz'), 0),
      'diff_neg', coalesce(sum(least(differenz, 0)) filter (where besteuerung = 'differenz'), 0),
      'bemessung_25a', coalesce(sum(bemessung) filter (where besteuerung = 'differenz'), 0),
      'ust_25a', coalesce(sum(ust) filter (where besteuerung = 'differenz'), 0),
      'netto_regel', coalesce(sum(bemessung) filter (where besteuerung <> 'differenz'), 0),
      'ust_regel', coalesce(sum(ust) filter (where besteuerung <> 'differenz'), 0),
      'ohne_beleg', coalesce(sum(ohne_beleg), 0), 'altbestand', coalesce(sum(altbestand), 0)),
    'verkaeufe', coalesce(jsonb_agg(to_jsonb(y) - 'r_ust' - 'r_netto' order by datum, nummer), '[]'::jsonb))
  into res from y;
  return res;
end $$;
grant execute on function public.steuer_bericht(date, date), public.steuer_neu_zuordnen(uuid), public.steuer_zuordnen_offen() to authenticated;
alter view steuer_charge set (security_invoker = true);
