-- v3.32: Kaufart, Sonderanfertigung und Gewährleistungs-Zustimmung je Auftrag; Rechnung übernimmt sie automatisch
alter table auftrag add column if not exists kaufart text;
alter table auftrag add column if not exists sonderanfertigung text;
alter table auftrag add column if not exists gewaehr_1jahr boolean not null default false;
alter table auftrag add column if not exists recht_quelle text;
alter table auftrag add constraint auftrag_kaufart_chk check (kaufart is null or kaufart in ('fernabsatz','vor_ort','gewerblich'));

create or replace function auftrag_widerruf(a auftrag) returns text language sql immutable as $$
  select case
    when a.kaufart in ('vor_ort','gewerblich') then a.kaufart
    when nullif(trim(coalesce(a.sonderanfertigung,'')),'') is not null then 'sonder'
    else 'fernabsatz' end
$$;

create or replace function rechnung_recht_von_auftrag() returns trigger language plpgsql as $$
declare a auftrag;
begin
  if new.auftrag_id is null then return new; end if;
  select * into a from auftrag where id = new.auftrag_id;
  if not found then return new; end if;
  if a.kaufart is null and nullif(trim(coalesce(a.sonderanfertigung,'')),'') is null and not a.gewaehr_1jahr then return new; end if;
  new.widerruf := auftrag_widerruf(a);
  new.widerruf_teile := case when new.widerruf = 'sonder' then a.sonderanfertigung else coalesce(new.widerruf_teile,'') end;
  new.gewaehr_1jahr := a.gewaehr_1jahr;
  return new;
end $$;
create trigger rechnung_recht before insert on rechnung for each row execute function rechnung_recht_von_auftrag();

create or replace function auftrag_recht_sync() returns trigger language plpgsql security definer set search_path = public as $$
begin
  if (new.kaufart is distinct from old.kaufart) or (new.sonderanfertigung is distinct from old.sonderanfertigung) or (new.gewaehr_1jahr is distinct from old.gewaehr_1jahr) then
    update rechnung r set widerruf = auftrag_widerruf(new),
      widerruf_teile = case when auftrag_widerruf(new) = 'sonder' then new.sonderanfertigung else '' end,
      gewaehr_1jahr = new.gewaehr_1jahr
    where r.auftrag_id = new.id and r.status = 'entwurf';
  end if;
  return new;
end $$;
create trigger auftrag_recht after update on auftrag for each row execute function auftrag_recht_sync();

create or replace function auftrag_rechtliches(p_id uuid, p_kaufart text default null, p_sonder text default null, p_gewaehr boolean default null, p_wer text default null)
returns auftrag language plpgsql security definer set search_path = public as $$
declare a auftrag;
begin
  if not ist_nutzer() then raise exception 'nicht erlaubt'; end if;
  update auftrag set
    kaufart = case when p_kaufart is null then kaufart when p_kaufart = '' then null else p_kaufart end,
    sonderanfertigung = case when p_sonder is null then sonderanfertigung else nullif(trim(p_sonder),'') end,
    gewaehr_1jahr = coalesce(p_gewaehr, gewaehr_1jahr),
    recht_quelle = coalesce(p_wer, recht_quelle),
    geaendert_am = now()
  where id = p_id returning * into a;
  if not found then raise exception 'Auftrag nicht gefunden'; end if;
  return a;
end $$;
grant execute on function auftrag_rechtliches(uuid,text,text,boolean,text) to authenticated;

do $$ declare d text; begin
  d := pg_get_viewdef('auftrag_uebersicht'::regclass, true);
  if position('kaufart' in d) = 0 then
    d := replace(d, 'a.archiviert_von', 'a.archiviert_von, a.kaufart, a.sonderanfertigung, a.gewaehr_1jahr, a.recht_quelle');
    d := regexp_replace(d, 'archiviert_von\s+FROM b', 'archiviert_von, kaufart, sonderanfertigung, gewaehr_1jahr, recht_quelle FROM b');
    execute 'create or replace view auftrag_uebersicht as ' || d;
  end if;
end $$;
