-- Update v3.9 (11.10.2026): Kundenstamm mit Kundennummer (Abgleich mit DATEV), Kundennummer auf jeder Rechnung
create table if not exists kunde (
  id uuid primary key default gen_random_uuid(),
  nummer int unique not null,
  name text not null,
  email text,
  adresse jsonb,
  quelle text not null default 'ops' check (quelle in ('ops', 'datev')),
  erstellt_am timestamptz not null default now()
);
create index if not exists kunde_name_idx on kunde (lower(name));
create index if not exists kunde_email_idx on kunde (lower(email));
alter table kunde enable row level security;
grant select on kunde to authenticated;
drop policy if exists app_lesen on kunde;
create policy app_lesen on kunde for select to authenticated using (ist_nutzer());
alter table rechnung add column if not exists kunde_nr int;
insert into firma (schluessel, wert) values ('kunde_start', '10001') on conflict (schluessel) do nothing;

-- Bestehenden Kunden finden (E-Mail, sonst Name + PLZ, sonst eindeutiger Name), sonst neu anlegen
create or replace function kunde_zuordnen(p_name text, p_email text, p_adresse jsonb) returns int
language plpgsql security definer set search_path = public as $$
declare
  k kunde;
  n int;
begin
  if p_name is null or btrim(p_name) = '' then return null; end if;
  if p_email is not null and p_email <> '' then
    select * into k from kunde where lower(email) = lower(btrim(p_email)) limit 1;
  end if;
  if k.id is null and p_adresse ? 'plz' then
    select * into k from kunde where lower(name) = lower(btrim(p_name)) and adresse->>'plz' = p_adresse->>'plz' limit 1;
  end if;
  if k.id is null and (select count(*) from kunde where lower(name) = lower(btrim(p_name))) = 1 then
    select * into k from kunde where lower(name) = lower(btrim(p_name));
  end if;
  if k.id is not null then
    update kunde set email = coalesce(email, nullif(btrim(p_email), '')), adresse = coalesce(p_adresse, adresse) where id = k.id;
    return k.nummer;
  end if;
  lock table kunde in share row exclusive mode;
  select greatest(coalesce(max(nummer), 0) + 1, (select wert::int from firma where schluessel = 'kunde_start')) into n from kunde;
  insert into kunde (nummer, name, email, adresse) values (n, btrim(p_name), nullif(btrim(p_email), ''), p_adresse);
  return n;
end $$;
revoke execute on function kunde_zuordnen(text, text, jsonb) from public, anon;

create or replace function rechnung_kunde_nr() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if new.kunde_nr is null then new.kunde_nr := kunde_zuordnen(new.kunde_name, new.kunde_email, new.kunde_adresse); end if;
  return new;
end $$;
drop trigger if exists rechnung_kunde_nr on rechnung;
create trigger rechnung_kunde_nr before insert or update of kunde_name, kunde_email, kunde_adresse on rechnung
  for each row execute function rechnung_kunde_nr();

-- Kunden aus DATEV übernehmen: [{"nummer": 10001, "name": "...", "email": "...", "adresse": {...}}]
create or replace function kunden_import(p jsonb) returns int
language plpgsql security definer set search_path = public as $$
declare x jsonb; c int := 0;
begin
  for x in select * from jsonb_array_elements(p) loop
    insert into kunde (nummer, name, email, adresse, quelle)
    values ((x->>'nummer')::int, x->>'name', nullif(x->>'email', ''), x->'adresse', 'datev')
    on conflict (nummer) do update set name = excluded.name, email = coalesce(excluded.email, kunde.email), adresse = coalesce(excluded.adresse, kunde.adresse), quelle = 'datev';
    c := c + 1;
  end loop;
  return c;
end $$;
revoke execute on function kunden_import(jsonb) from public, anon;
select (select count(*) from kunde) kunden;
