-- Update v3.18 (12.10.2026): Aufträge an Claude direkt aus der Ops-App (für Leon und Samuel)
create table if not exists claude_auftrag (
  id uuid primary key default gen_random_uuid(),
  text text not null,
  von text,
  status text not null default 'offen' check (status in ('offen', 'in_arbeit', 'rueckfrage', 'erledigt', 'abgelehnt')),
  antwort text,
  bezug_auftrag uuid references auftrag(id),
  erstellt_am timestamptz not null default now(),
  geaendert_am timestamptz not null default now()
);
alter table claude_auftrag enable row level security;
grant select on claude_auftrag to authenticated;
drop policy if exists app_lesen on claude_auftrag;
create policy app_lesen on claude_auftrag for select to authenticated using (ist_nutzer());
create or replace function claude_auftrag_neu(p_text text, p_von text, p_bezug uuid default null) returns uuid
language plpgsql security definer set search_path = public as $$
declare i uuid;
begin
  if not ist_nutzer() then raise exception 'Kein Zugriff'; end if;
  if coalesce(trim(p_text), '') = '' then raise exception 'Bitte kurz schreiben, was zu tun ist'; end if;
  insert into claude_auftrag (text, von, bezug_auftrag) values (trim(p_text), p_von, p_bezug) returning id into i;
  return i;
end $$;
create or replace function claude_auftrag_antwort(p_id uuid, p_status text, p_antwort text) returns void
language plpgsql security definer set search_path = public as $$
begin
  if not ist_nutzer() then raise exception 'Kein Zugriff'; end if;
  update claude_auftrag set status = p_status, antwort = p_antwort, geaendert_am = now() where id = p_id;
end $$;
revoke execute on function claude_auftrag_neu(text, text, uuid), claude_auftrag_antwort(uuid, text, text) from public, anon;
grant execute on function claude_auftrag_neu(text, text, uuid), claude_auftrag_antwort(uuid, text, text) to authenticated;
do $$ begin begin alter publication supabase_realtime add table claude_auftrag; exception when others then null; end; end $$;
select count(*) from claude_auftrag;
