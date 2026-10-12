-- Update v3.10 (11.10.2026): Kleinanzeigen-Nachrichten aus dem Postfach (rund um die Uhr, ohne Mac)
create table if not exists ka_mail (
  message_id text primary key,
  datum timestamptz not null,
  absender text,
  antwort_an text,
  betreff text,
  text text,
  titel text,
  inserat text,
  partner text,
  email text,
  gesehen boolean not null default false,
  erfasst_am timestamptz not null default now()
);
alter table ka_mail enable row level security;
grant select on ka_mail to authenticated;
drop policy if exists app_lesen on ka_mail;
create policy app_lesen on ka_mail for select to authenticated using (ist_nutzer());
create or replace function ka_mail_gesehen(p_id text) returns void
language plpgsql security definer set search_path = public as $$
begin
  if not ist_nutzer() then raise exception 'Kein Zugriff'; end if;
  update ka_mail set gesehen = true where message_id = p_id;
end $$;
revoke execute on function ka_mail_gesehen(text) from public, anon;
grant execute on function ka_mail_gesehen(text) to authenticated;
do $$ begin
  begin alter publication supabase_realtime add table ka_mail; exception when others then null; end;
  begin alter publication supabase_realtime add table ka_chat; exception when others then null; end;
end $$;
create extension if not exists pg_cron;
create extension if not exists pg_net;
select count(*) from ka_mail;
