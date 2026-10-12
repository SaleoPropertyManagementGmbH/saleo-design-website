-- Update v3.11 (11.10.2026): Verbindungen. Welche Zugänge laufen, welche brauchen eine Anmeldung.
create table if not exists verbindung (
  name text primary key,
  titel text not null,
  art text not null,
  dauerhaft boolean not null default false,
  ok boolean,
  hinweis text,
  login_url text,
  reihenfolge int not null default 0,
  geprueft_am timestamptz
);
alter table verbindung enable row level security;
grant select on verbindung to authenticated;
drop policy if exists app_lesen on verbindung;
create policy app_lesen on verbindung for select to authenticated using (ist_nutzer());
insert into verbindung (name, titel, art, dauerhaft, ok, hinweis, login_url, reihenfolge, geprueft_am) values
  ('app', 'Saleo Design Ops', 'Server', true, true, 'Bleibt angemeldet', null, 1, now()),
  ('paypal', 'PayPal', 'Konnektor', true, true, 'Zahlungen werden automatisch abgeglichen', null, 2, now()),
  ('mailversand', 'Rechnungsversand info@', 'Server', true, true, 'Rechnungen gehen direkt vom Server raus', null, 3, now()),
  ('kleinanzeigen', 'Kleinanzeigen', 'Browser am Mac', false, true, 'Chats werden stündlich gelesen', 'https://www.kleinanzeigen.de/m-einloggen.html', 4, now()),
  ('dpd', 'myDPD Business', 'Browser am Mac', false, true, 'Für Versandlabels', 'https://business.dpd.de', 5, now()),
  ('bank', 'Commerzbank', 'geplant: finAPI', false, null, 'Bis finAPI läuft: Abgleich über DATEV', null, 6, null),
  ('datev', 'DATEV', 'Browser am Mac', false, false, 'Nur einmal nötig: Kundenliste übernehmen. Rechnungen gehen per Upload-Mail.', 'https://duo.apps.datev.de', 7, now())
on conflict (name) do nothing;
create or replace function verbindung_melden(p_name text, p_ok boolean, p_hinweis text default null) returns void
language plpgsql security definer set search_path = public as $$
begin
  if not ist_nutzer() then raise exception 'Kein Zugriff'; end if;
  update verbindung set ok = p_ok, hinweis = coalesce(p_hinweis, hinweis), geprueft_am = now() where name = p_name;
end $$;
revoke execute on function verbindung_melden(text, boolean, text) from public, anon;
grant execute on function verbindung_melden(text, boolean, text) to authenticated;
do $$ begin begin alter publication supabase_realtime add table verbindung; exception when others then null; end; end $$;
select name, ok from verbindung order by reihenfolge;
