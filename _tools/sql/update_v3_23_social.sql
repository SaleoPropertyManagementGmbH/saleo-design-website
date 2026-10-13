-- v3.23 (13.10.2026): Social Media (Instagram, TikTok) in Saleo Design Ops.
-- Rolle je Nutzer: 'voll' (Samuel, Leon, Automatik) oder 'social' (nur Social-Media-Bereich).
alter table app_nutzer add column if not exists rolle text not null default 'voll';
do $$ begin
  if not exists (select 1 from pg_constraint where conname = 'app_nutzer_rolle_chk') then
    alter table app_nutzer add constraint app_nutzer_rolle_chk check (rolle in ('voll','social'));
  end if;
end $$;

create or replace function public.ist_nutzer() returns boolean language sql stable security definer set search_path to 'public' as $$
  select exists (select 1 from app_nutzer where lower(email) = lower(coalesce(auth.jwt() ->> 'email', '')) and rolle = 'voll')
$$;
create or replace function public.ist_social() returns boolean language sql stable security definer set search_path to 'public' as $$
  select exists (select 1 from app_nutzer where lower(email) = lower(coalesce(auth.jwt() ->> 'email', '')))
$$;
create or replace function public.meine_rolle() returns jsonb language sql stable security definer set search_path to 'public' as $$
  select jsonb_build_object('rolle', rolle, 'name', name) from app_nutzer where lower(email) = lower(coalesce(auth.jwt() ->> 'email', '')) limit 1
$$;
grant execute on function public.ist_social(), public.meine_rolle() to authenticated;

-- Konten (ein Eintrag je Plattform und Account)
create table if not exists social_konto (
  id uuid primary key default gen_random_uuid(),
  plattform text not null check (plattform in ('instagram','tiktok','youtube','facebook','pinterest','linkedin')),
  handle text not null,
  name text,
  url text,
  aktiv boolean not null default true,
  quelle text default 'metricool',
  ext_id text,
  stand timestamptz,
  erstellt_am timestamptz not null default now(),
  unique (plattform, handle)
);
-- Tageswerte je Konto (Follower und Summen des Tages)
create table if not exists social_tag (
  konto_id uuid not null references social_konto(id),
  datum date not null,
  follower integer, follower_neu integer,
  aufrufe integer, reichweite integer, impressionen integer, profilaufrufe integer,
  likes integer, kommentare integer, shares integer, saves integer, link_klicks integer,
  beitraege integer,
  stand timestamptz not null default now(),
  primary key (konto_id, datum)
);
-- Einzelne Beiträge (Reels, TikToks, Posts) mit aktuellem Stand der Zahlen
create table if not exists social_beitrag (
  id uuid primary key default gen_random_uuid(),
  konto_id uuid not null references social_konto(id),
  ext_id text not null,
  typ text,
  titel text,
  link text,
  bild_url text,
  veroeffentlicht_am timestamptz,
  aufrufe integer, reichweite integer, likes integer, kommentare integer, shares integer, saves integer,
  wiedergabe_sek numeric, schnitt_sek numeric, follower_neu integer,
  inserat text, moebel_id uuid,
  notiz text,
  stand timestamptz not null default now(),
  unique (konto_id, ext_id)
);
-- Content-Plan: Ideen bis Veröffentlichung
create table if not exists social_idee (
  id uuid primary key default gen_random_uuid(),
  titel text not null,
  notiz text,
  plattformen text[] not null default '{instagram,tiktok}',
  status text not null default 'idee' check (status in ('idee','geplant','gedreht','online','archiv')),
  geplant_am date,
  beitrag_id uuid references social_beitrag(id),
  inserat text,
  wer text,
  erstellt_am timestamptz not null default now(),
  geaendert_am timestamptz not null default now()
);

alter table social_konto enable row level security;
alter table social_tag enable row level security;
alter table social_beitrag enable row level security;
alter table social_idee enable row level security;
do $$ declare t text; begin
  foreach t in array array['social_konto','social_tag','social_beitrag','social_idee'] loop
    execute format('drop policy if exists social_lesen on %I', t);
    execute format('create policy social_lesen on %I for select using (ist_social())', t);
    execute format('drop policy if exists social_schreiben on %I', t);
    execute format('create policy social_schreiben on %I for insert with check (ist_social())', t);
    execute format('drop policy if exists social_aendern on %I', t);
    execute format('create policy social_aendern on %I for update using (ist_social()) with check (ist_social())', t);
  end loop;
end $$;
grant select, insert, update on social_konto, social_tag, social_beitrag, social_idee to authenticated;

do $$ begin
  begin alter publication supabase_realtime add table social_konto; exception when others then null; end;
  begin alter publication supabase_realtime add table social_tag; exception when others then null; end;
  begin alter publication supabase_realtime add table social_beitrag; exception when others then null; end;
  begin alter publication supabase_realtime add table social_idee; exception when others then null; end;
end $$;

insert into social_konto (plattform, handle, name, url) values
  ('instagram', 'saleo_group', 'Saleo Group', 'https://www.instagram.com/saleo_group/')
on conflict (plattform, handle) do nothing;
