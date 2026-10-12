-- Update v3.13 (12.10.2026): Fotos je Teiltyp (vom Handy) und Einkäufe über den privaten Kleinanzeigen-Account
alter table teiltyp add column if not exists bild_url text;
insert into storage.buckets (id, name, public) values ('teilbilder', 'teilbilder', true) on conflict (id) do nothing;
drop policy if exists teilbilder_schreiben on storage.objects;
create policy teilbilder_schreiben on storage.objects for insert to authenticated with check (bucket_id = 'teilbilder' and ist_nutzer());
drop policy if exists teilbilder_aendern on storage.objects;
create policy teilbilder_aendern on storage.objects for update to authenticated using (bucket_id = 'teilbilder' and ist_nutzer());
create or replace function teiltyp_bild(p_code text, p_url text) returns void
language plpgsql security definer set search_path = public as $$
begin
  if not ist_nutzer() then raise exception 'Kein Zugriff'; end if;
  update teiltyp set bild_url = p_url where code = p_code;
end $$;
revoke execute on function teiltyp_bild(text, text) from public, anon;
grant execute on function teiltyp_bild(text, text) to authenticated;

-- Einkäufe aus dem privaten Kleinanzeigen-Account: verhandelt -> bezahlt -> erhalten -> gebucht
create table if not exists ka_einkauf (
  id text primary key,
  inserat text,
  titel text,
  verkaeufer text,
  preis numeric(10,2),
  versand numeric(10,2) not null default 0,
  zahlart text,
  bezahlt_am timestamptz,
  status text not null default 'verhandlung' check (status in ('verhandlung', 'bezahlt', 'erhalten', 'gebucht', 'storniert')),
  abholung boolean not null default false,
  einkauf_id uuid references einkauf(id),
  zahlung_id uuid references zahlung(id),
  letzte_nachricht text,
  letzte_am timestamptz,
  notiz text,
  daten jsonb not null default '{}',
  erstellt_am timestamptz not null default now(),
  geaendert_am timestamptz not null default now()
);
alter table ka_einkauf enable row level security;
grant select on ka_einkauf to authenticated;
drop policy if exists app_lesen on ka_einkauf;
create policy app_lesen on ka_einkauf for select to authenticated using (ist_nutzer());
create or replace function ka_einkauf_merken(p jsonb) returns void
language plpgsql security definer set search_path = public as $$
begin
  if not ist_nutzer() then raise exception 'Kein Zugriff'; end if;
  insert into ka_einkauf (id, inserat, titel, verkaeufer, preis, versand, zahlart, bezahlt_am, status, abholung, letzte_nachricht, letzte_am, notiz, daten)
  values (p->>'id', p->>'inserat', p->>'titel', p->>'verkaeufer', (p->>'preis')::numeric, coalesce((p->>'versand')::numeric, 0), p->>'zahlart',
    (p->>'bezahlt_am')::timestamptz, coalesce(p->>'status', 'verhandlung'), coalesce((p->>'abholung')::boolean, false),
    p->>'letzte_nachricht', (p->>'letzte_am')::timestamptz, p->>'notiz', coalesce(p->'daten', '{}'))
  on conflict (id) do update set
    inserat = coalesce(excluded.inserat, ka_einkauf.inserat), titel = coalesce(excluded.titel, ka_einkauf.titel),
    verkaeufer = coalesce(excluded.verkaeufer, ka_einkauf.verkaeufer), preis = coalesce(excluded.preis, ka_einkauf.preis),
    versand = case when p ? 'versand' then excluded.versand else ka_einkauf.versand end,
    zahlart = coalesce(excluded.zahlart, ka_einkauf.zahlart), bezahlt_am = coalesce(ka_einkauf.bezahlt_am, excluded.bezahlt_am),
    status = case when p->>'status' = 'storniert' then 'storniert'
      when array_position(array['verhandlung','bezahlt','erhalten','gebucht'], coalesce(p->>'status', ka_einkauf.status)) > array_position(array['verhandlung','bezahlt','erhalten','gebucht'], ka_einkauf.status)
      then p->>'status' else ka_einkauf.status end,
    abholung = coalesce((p->>'abholung')::boolean, ka_einkauf.abholung),
    letzte_nachricht = coalesce(excluded.letzte_nachricht, ka_einkauf.letzte_nachricht), letzte_am = coalesce(excluded.letzte_am, ka_einkauf.letzte_am),
    notiz = coalesce(excluded.notiz, ka_einkauf.notiz), daten = ka_einkauf.daten || excluded.daten, geaendert_am = now();
end $$;
create or replace function ka_einkauf_status(p_id text, p_status text) returns void
language plpgsql security definer set search_path = public as $$
begin
  if not ist_nutzer() then raise exception 'Kein Zugriff'; end if;
  update ka_einkauf set status = p_status, geaendert_am = now() where id = p_id;
end $$;
revoke execute on function ka_einkauf_merken(jsonb), ka_einkauf_status(text, text) from public, anon;
grant execute on function ka_einkauf_merken(jsonb), ka_einkauf_status(text, text) to authenticated;
do $$ begin begin alter publication supabase_realtime add table ka_einkauf; exception when others then null; end; end $$;
insert into verbindung (name, titel, art, dauerhaft, ok, hinweis, login_url, reihenfolge, geprueft_am) values
  ('kleinanzeigen_privat', 'Kleinanzeigen privat (Einkauf)', 'Chrome am Mac', false, false, 'Noch nicht angemeldet', 'https://www.kleinanzeigen.de/m-einloggen.html', 5, now())
on conflict (name) do nothing;
select count(*) from ka_einkauf;
