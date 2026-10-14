alter table auftrag add column if not exists archiviert_am timestamptz;
alter table auftrag add column if not exists archiviert_von text;
alter table auftrag add column if not exists archiv_auto boolean not null default true;

create or replace function auftrag_fertig(a auftrag) returns boolean language sql stable set search_path to 'public' as $$
  select a.bezahlt_am is not null
    and a.status not in ('heiss', 'storniert')
    and (a.versandart <> 'dpd' or a.status in ('label', 'versendet', 'abgeholt'))
    and not exists (select 1 from rechnung r where r.auftrag_id = a.id and r.status = 'entwurf')
$$;

create or replace function auftrag_archiv_auto() returns trigger language plpgsql set search_path to 'public' as $$
begin
  if new.archiviert_am is null and new.archiv_auto and auftrag_fertig(new) then
    new.archiviert_am := now();
    new.archiviert_von := 'Automatik';
  end if;
  return new;
end $$;

create or replace trigger auftrag_archiv before insert or update on auftrag
  for each row execute function auftrag_archiv_auto();

create or replace function rechnung_archiv_anstoss() returns trigger language plpgsql set search_path to 'public' as $$
begin
  if new.auftrag_id is not null and new.status is distinct from coalesce(old.status, '') then
    update auftrag set geaendert_am = geaendert_am where id = new.auftrag_id and archiviert_am is null;
  end if;
  return new;
end $$;

create or replace trigger rechnung_archiv after insert or update of status on rechnung
  for each row execute function rechnung_archiv_anstoss();

create or replace function auftrag_archivieren(p_id uuid, p_wer text default null) returns void
language plpgsql security definer set search_path to 'public' as $$
begin
  if not ist_nutzer() then raise exception 'Kein Zugriff'; end if;
  update auftrag set archiviert_am = now(), archiviert_von = coalesce(p_wer, 'von Hand'), geaendert_am = now() where id = p_id;
  if not found then raise exception 'Auftrag nicht gefunden'; end if;
end $$;

create or replace function auftrag_reaktivieren(p_id uuid) returns void
language plpgsql security definer set search_path to 'public' as $$
begin
  if not ist_nutzer() then raise exception 'Kein Zugriff'; end if;
  update auftrag set archiviert_am = null, archiviert_von = null, archiv_auto = false, geaendert_am = now() where id = p_id;
end $$;

grant execute on function auftrag_archivieren(uuid, text), auftrag_reaktivieren(uuid) to authenticated;

update auftrag set geaendert_am = geaendert_am where archiviert_am is null;

do $v$
declare d text := pg_get_viewdef('auftrag_uebersicht'::regclass);
begin
  d := replace(d, 'a.planung_id,', 'a.planung_id, a.archiviert_am, a.archiviert_von,');
  d := replace(d, E'planung_id\n   FROM b', E'planung_id, archiviert_am, archiviert_von\n   FROM b');
  execute 'create or replace view auftrag_uebersicht as ' || d;
end $v$;
