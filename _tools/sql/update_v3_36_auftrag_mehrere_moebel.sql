-- v3.36 Mehrere Möbel in einem Auftrag (z. B. Lowboard + 2 Beistelltische)
create table if not exists auftrag_moebel (
  id uuid primary key default gen_random_uuid(),
  auftrag_id uuid not null references auftrag(id),
  moebel_id uuid not null references moebel(id),
  preis numeric,
  reihenfolge int not null default 0,
  aktiv boolean not null default true,
  verkauf_id uuid,
  erstellt_am timestamptz not null default now(),
  unique (auftrag_id, moebel_id)
);
alter table auftrag_moebel enable row level security;
do $$ begin
  if not exists (select 1 from pg_policies where tablename = 'auftrag_moebel' and policyname = 'nutzer_lesen') then
    create policy nutzer_lesen on auftrag_moebel for select using (ist_nutzer());
  end if;
end $$;

-- Liste setzen: [{moebel_id, preis}], die Reihenfolge zählt (erstes Möbel = Hauptmöbel des Auftrags)
create or replace function auftrag_moebel_setzen(p_auftrag uuid, p_liste jsonb, p_wer text default null)
returns jsonb language plpgsql security definer set search_path to 'public' as $f$
declare a auftrag; x jsonb; i int := 0; m moebel; summe numeric := 0; alle_preise boolean := true; namen text[] := '{}'; erst uuid; r rechnung; pos jsonb := '[]'::jsonb; hinweis text;
begin
  if not ist_nutzer() then raise exception 'Kein Zugriff'; end if;
  select * into a from auftrag where id = p_auftrag for update;
  if a.id is null then raise exception 'Auftrag nicht gefunden'; end if;
  if a.verkauf_id is not null then raise exception 'Auftrag ist schon verbucht, Möbel können nicht mehr geändert werden'; end if;
  if jsonb_typeof(p_liste) <> 'array' then raise exception 'Liste fehlt'; end if;
  -- entfernte Möbel freigeben
  for m in select mo.* from auftrag_moebel am join moebel mo on mo.id = am.moebel_id
           where am.auftrag_id = p_auftrag and am.aktiv
             and am.moebel_id::text not in (select e->>'moebel_id' from jsonb_array_elements(p_liste) e) loop
    update auftrag_moebel set aktiv = false where auftrag_id = p_auftrag and moebel_id = m.id;
    if m.status = 'reserviert' and not exists (select 1 from auftrag_moebel am2 join auftrag a2 on a2.id = am2.auftrag_id
         where am2.moebel_id = m.id and am2.aktiv and a2.status not in ('storniert') and a2.verkauf_id is null) then
      update moebel set status = 'aufgebaut', geaendert_am = now() where id = m.id;
    end if;
  end loop;
  if a.moebel_id is not null and a.moebel_id::text not in (select e->>'moebel_id' from jsonb_array_elements(p_liste) e) then
    update moebel set status = 'aufgebaut', geaendert_am = now() where id = a.moebel_id and status = 'reserviert'
      and not exists (select 1 from auftrag_moebel am2 join auftrag a2 on a2.id = am2.auftrag_id where am2.moebel_id = a.moebel_id and am2.aktiv and a2.id <> a.id and a2.status <> 'storniert' and a2.verkauf_id is null);
  end if;
  for x in select * from jsonb_array_elements(p_liste) loop
    i := i + 1;
    select * into m from moebel where id = (x->>'moebel_id')::uuid;
    if m.id is null then raise exception 'Möbel % nicht gefunden', x->>'moebel_id'; end if;
    if m.status not in ('aufgebaut', 'reserviert') then raise exception 'Möbel „%“ ist nicht verfügbar (Status %)', m.name, m.status; end if;
    insert into auftrag_moebel (auftrag_id, moebel_id, preis, reihenfolge, aktiv)
    values (p_auftrag, m.id, nullif(x->>'preis', '')::numeric, i, true)
    on conflict (auftrag_id, moebel_id) do update set preis = excluded.preis, reihenfolge = excluded.reihenfolge, aktiv = true;
    if a.status <> 'storniert' then update moebel set status = 'reserviert', geaendert_am = now() where id = m.id and status = 'aufgebaut'; end if;
    if nullif(x->>'preis', '') is null then alle_preise := false; else summe := summe + (x->>'preis')::numeric; end if;
    namen := namen || m.name;
    if i = 1 then erst := m.id; end if;
    pos := pos || jsonb_build_array(jsonb_build_object('text', m.name, 'menge', 1, 'preis', coalesce(nullif(x->>'preis', '')::numeric, 0)));
  end loop;
  update auftrag set moebel_id = erst,
    preis = case when i > 0 and alle_preise then summe else preis end,
    titel = case when i > 1 then array_to_string(namen, ' + ') when i = 1 then coalesce(nullif(titel, ''), namen[1]) else titel end,
    notiz = concat_ws(' · ', notiz, case when p_wer is not null then 'Möbel geändert von ' || p_wer end),
    geaendert_am = now()
  where id = p_auftrag returning * into a;
  -- Rechnungsentwurf: eine Zeile pro Möbel, dazu Versand
  select * into r from rechnung where auftrag_id = p_auftrag and status <> 'storniert' order by erstellt_am desc limit 1;
  if r.id is not null and r.status = 'entwurf' and r.gesendet_am is null and i > 0 and alle_preise then
    if a.versand_kunde > 0 then pos := pos || jsonb_build_array(jsonb_build_object('text', case when a.versandart = 'lieferung' then 'Lieferung' else 'Versandkosten' end, 'menge', 1, 'preis', a.versand_kunde)); end if;
    perform rechnung_aendern(r.id, jsonb_build_object('positionen', pos));
    hinweis := 'Rechnungsentwurf angepasst';
  elsif r.id is not null and r.status <> 'entwurf' then
    hinweis := 'Rechnung ' || r.nummer || ' ist schon gesendet und bleibt unverändert';
  end if;
  return jsonb_build_object('ok', true, 'moebel', i, 'preis', a.preis, 'rechnung', hinweis);
end $f$;

-- Verbuchen: jedes Möbel einzeln verkaufen; Versand und Gebühren hängen am ersten
create or replace function auftrag_verbuchen(p_id uuid, p_teile jsonb default null)
returns uuid language plpgsql set search_path to 'public' as $f$
declare a auftrag; v uuid; v1 uuid; x jsonb; am auftrag_moebel; n int; summe_p numeric; summe_w numeric; anteil numeric; k int := 0; geb numeric;
begin
  select * into a from auftrag where id = p_id for update;
  if a.verkauf_id is not null then return a.verkauf_id; end if;
  geb := coalesce((select gebuehr from zahlung where id = a.zahlung_id), 0);
  select count(*) into n from auftrag_moebel where auftrag_id = p_id and aktiv;
  if n > 0 then
    select sum(preis), sum(coalesce((select sum(mt.menge * t.durchschnittspreis) from moebel_teil mt join teil t on t.code = mt.teil where mt.moebel_id = x2.moebel_id), 0))
      into summe_p, summe_w from auftrag_moebel x2 where auftrag_id = p_id and aktiv;
    for am in select * from auftrag_moebel where auftrag_id = p_id and aktiv order by reihenfolge loop
      k := k + 1;
      -- Preisanteil: eigener Preis, wenn alle Preise da sind und zur Summe passen, sonst nach Materialwert aufgeteilt
      if (select bool_and(preis is not null) from auftrag_moebel where auftrag_id = p_id and aktiv) and summe_p = coalesce(a.preis, summe_p) then
        anteil := am.preis;
      elsif summe_w > 0 then
        anteil := round(coalesce(a.preis, 0) * coalesce((select sum(mt.menge * t.durchschnittspreis) from moebel_teil mt join teil t on t.code = mt.teil where mt.moebel_id = am.moebel_id), 0) / summe_w, 2);
      else
        anteil := round(coalesce(a.preis, 0) / n, 2);
      end if;
      v := fertigmoebel_verkaufen(am.moebel_id, anteil + case when k = 1 then a.versand_kunde else 0 end,
        case when k = 1 then a.versand_eigen + geb else 0 end, a.kanal, 'Auftrag ' || a.id || ' (' || k || '/' || n || ')');
      update auftrag_moebel set verkauf_id = v where id = am.id;
      if k = 1 then v1 := v; end if;
    end loop;
    update auftrag set verkauf_id = v1, geaendert_am = now() where id = p_id;
    return v1;
  end if;
  if a.moebel_id is not null then
    v := fertigmoebel_verkaufen(a.moebel_id, coalesce(a.preis, 0) + a.versand_kunde, a.versand_eigen + geb, a.kanal, 'Auftrag ' || a.id);
  else
    p_teile := coalesce(p_teile, a.teile);
    if p_teile is null or jsonb_array_length(p_teile) = 0 then raise exception 'Ohne Fertigmöbel brauche ich die verkauften Teile'; end if;
    insert into verkauf (kanal, bezeichnung, erloes, eigene_kosten, notiz, kategorie)
    values (a.kanal, a.titel, coalesce(a.preis, 0) + a.versand_kunde, a.versand_eigen + geb, 'Auftrag ' || a.id, kategorie_aus(a.titel)) returning id into v;
    for x in select * from jsonb_array_elements(p_teile) loop
      insert into verkauf_position (verkauf_id, teil, menge) values (v, x->>'teil', (x->>'menge')::int);
    end loop;
    perform buche_verkauf(v);
  end if;
  update auftrag set verkauf_id = v, geaendert_am = now() where id = p_id;
  return v;
end $f$;

-- Status: Reservierung auch für die weiteren Möbel des Auftrags
create or replace function auftrag_status(p_id uuid, p_status text, p_notiz text default null)
returns void language plpgsql set search_path to 'public' as $f$
declare a auftrag;
begin
  update auftrag set status = p_status, geaendert_am = now(), notiz = coalesce(p_notiz, notiz) where id = p_id returning * into a;
  if not found then raise exception 'Auftrag nicht gefunden'; end if;
  if a.moebel_id is null and a.inserat is not null then
    update auftrag set inserat = inserat where id = p_id returning * into a;
  end if;
  if a.verkauf_id is null then
    if p_status = 'heiss' then
      update moebel set status = 'reserviert', geaendert_am = now() where status = 'aufgebaut'
        and (id = a.moebel_id or id in (select moebel_id from auftrag_moebel where auftrag_id = p_id and aktiv));
    elsif p_status = 'storniert' then
      update moebel set status = 'aufgebaut', geaendert_am = now() where status = 'reserviert'
        and (id = a.moebel_id or id in (select moebel_id from auftrag_moebel where auftrag_id = p_id and aktiv));
    end if;
  end if;
  if p_status in ('bezahlt', 'freigegeben', 'label', 'versendet', 'abgeholt') and a.verkauf_id is null then
    if a.moebel_id is not null or exists (select 1 from auftrag_moebel where auftrag_id = p_id and aktiv) or (a.teile is not null and jsonb_array_length(a.teile) > 0) then
      perform auftrag_verbuchen(p_id);
    else
      update auftrag set notiz = concat_ws(' · ', notiz, 'Lager noch nicht ausgebucht: verkaufte Teile fehlen') where id = p_id and coalesce(notiz, '') not like '%Lager noch nicht ausgebucht%';
    end if;
  end if;
end $f$;

-- Kein Abschluss: Auftrag schließen, Reservierungen lösen, ungesendeten Rechnungsentwurf stornieren (nichts wird gelöscht)
create or replace function auftrag_kein_abschluss(p_id uuid, p_wer text default null, p_grund text default null)
returns jsonb language plpgsql security definer set search_path to 'public' as $f$
declare a auftrag; n int;
begin
  if not ist_nutzer() then raise exception 'Kein Zugriff'; end if;
  select * into a from auftrag where id = p_id for update;
  if a.id is null then raise exception 'Auftrag nicht gefunden'; end if;
  if a.verkauf_id is not null or a.bezahlt_am is not null then raise exception 'Auftrag ist schon bezahlt oder verbucht'; end if;
  perform auftrag_status(p_id, 'storniert', concat_ws(' · ', a.notiz, 'Kein Abschluss' || coalesce(' (' || nullif(p_grund, '') || ')', '') || coalesce(', ' || nullif(p_wer, ''), '') || ' am ' || to_char(now() at time zone 'Europe/Berlin', 'DD.MM.YYYY')));
  update auftrag_moebel set aktiv = false where auftrag_id = p_id;
  update rechnung set status = 'storniert' where auftrag_id = p_id and status = 'entwurf' and gesendet_am is null;
  get diagnostics n = row_count;
  update auftrag set archiviert_am = now(), archiviert_von = coalesce(nullif(p_wer, ''), 'App'), geaendert_am = now() where id = p_id;
  return jsonb_build_object('ok', true, 'rechnung_storniert', n);
end $f$;

-- Danach per DO-Block: auftrag_uebersicht um CTE wm (Möbelliste, Materialwert aller Möbel) und Spalte moebel_liste erweitert.
-- Sicherheit: Views auf security_invoker umgestellt (sonst lesbar für jeden angemeldeten Nutzer, auch Social-Rolle)
alter view auftrag_uebersicht set (security_invoker = true);
alter view teil_verbaut set (security_invoker = true);
alter view beschichtung_uebersicht set (security_invoker = true);
alter view lager_health set (security_invoker = true);
