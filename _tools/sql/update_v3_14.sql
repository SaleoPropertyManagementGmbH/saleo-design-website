-- Update v3.14 (12.10.2026): Marktpreise je Teil (Kleinanzeigen, gebraucht, guter Zustand, brutto je Stück)
-- Marge differenzbesteuert: (Marktpreis - Ø EK) / 1,19
create table if not exists marktpreis (
  typ text not null references teiltyp(code),
  mass text not null default '*',
  preis numeric(10,2) not null,
  spanne text,
  quelle text,
  stand date not null default current_date,
  primary key (typ, mass)
);
alter table marktpreis enable row level security;
grant select on marktpreis to authenticated;
drop policy if exists app_lesen on marktpreis;
create policy app_lesen on marktpreis for select to authenticated using (ist_nutzer());

alter table firma add column if not exists marktpreis_faktor_n numeric not null default 1.25;
alter table firma add column if not exists marktpreis_faktor_s numeric not null default 0.5;

create or replace function marktpreis_fuer(p_typ text, p_mass text, p_zustand text) returns numeric
language sql stable security definer set search_path = public as $$
  with m as (
    select preis, 0 as rang from marktpreis
    where typ = p_typ and (mass = coalesce(p_mass, '*')
      or mass = coalesce(split_part(p_mass, 'x', 2) || 'x' || split_part(p_mass, 'x', 1), '-'))
    union all
    select preis, 1 from marktpreis where typ = p_typ and mass = '*'
    order by rang limit 1
  )
  select round(m.preis * case p_zustand when 'N' then (select marktpreis_faktor_n from firma limit 1)
    when 'S' then (select marktpreis_faktor_s from firma limit 1) else 1 end, 0)
  from m
$$;
grant execute on function marktpreis_fuer(text, text, text) to authenticated;

create or replace function marktpreis_setzen(p_typ text, p_mass text, p_preis numeric, p_quelle text default 'manuell') returns void
language plpgsql security definer set search_path = public as $$
begin
  if not ist_nutzer() then raise exception 'Kein Zugriff'; end if;
  insert into marktpreis (typ, mass, preis, quelle, stand) values (p_typ, coalesce(nullif(p_mass, ''), '*'), p_preis, p_quelle, current_date)
  on conflict (typ, mass) do update set preis = excluded.preis, quelle = excluded.quelle, stand = current_date;
end $$;
revoke execute on function marktpreis_setzen(text, text, numeric, text) from public, anon;
grant execute on function marktpreis_setzen(text, text, numeric, text) to authenticated;

insert into marktpreis (typ, mass, preis, spanne, quelle) values
  ('KU', '*', 3, '3 bis 3,50', 'Kleinanzeigen Okt 2026'),
  ('CO', '*', 2, '1,70 bis 2', 'Kleinanzeigen Okt 2026'),
  ('FU', '*', 4, '1 bis 4', 'Kleinanzeigen Okt 2026'),
  ('RO', '100', 5, '5', 'Kleinanzeigen Okt 2026'),
  ('RO', '175', 8, null, 'geschätzt'),
  ('RO', '250', 10, null, 'geschätzt'),
  ('RO', '350', 12, '10 bis 12', 'Kleinanzeigen Okt 2026'),
  ('RO', '395', 12, null, 'geschätzt wie 350'),
  ('RO', '400', 12, '5 bis 12', 'Kleinanzeigen Okt 2026'),
  ('RO', '500', 14, '10 bis 14', 'Kleinanzeigen Okt 2026'),
  ('RO', '750', 18, '13 bis 19', 'Kleinanzeigen Okt 2026'),
  ('BL', '350x100', 15, '15', 'Kleinanzeigen Okt 2026'),
  ('BL', '350x175', 20, '20', 'Kleinanzeigen Okt 2026'),
  ('BL', '350x250', 25, '20 bis 39', 'Kleinanzeigen Okt 2026'),
  ('BL', '350x350', 30, '26 bis 39', 'Kleinanzeigen und Händler Okt 2026'),
  ('BL', '500x175', 20, '20', 'Kleinanzeigen Okt 2026'),
  ('BL', '500x250', 30, null, 'Kleinanzeigen Okt 2026'),
  ('BL', '500x350', 32, '25 bis 40', 'Kleinanzeigen und Händler Okt 2026'),
  ('BL', '500x395', 32, null, 'geschätzt wie 500x350'),
  ('BL', '500x500', 38, '35 bis 40', 'Kleinanzeigen Okt 2026'),
  ('BL', '750x175', 30, '30', 'Kleinanzeigen Okt 2026'),
  ('BL', '750x250', 40, null, 'Kleinanzeigen Okt 2026'),
  ('BL', '750x350', 45, '40 bis 55', 'Kleinanzeigen Okt 2026'),
  ('BL', '750x500', 50, '30 bis 50', 'Kleinanzeigen Okt 2026'),
  ('BP', '350x100', 20, '20', 'Kleinanzeigen Okt 2026'),
  ('BP', '350x175', 20, '20', 'Kleinanzeigen Okt 2026'),
  ('BP', '350x250', 25, null, 'wie Außentablar'),
  ('BP', '350x350', 30, '30', 'Kleinanzeigen Okt 2026'),
  ('BP', '500x350', 32, null, 'wie Außentablar'),
  ('BP', '750x350', 45, '45 bis 55', 'Kleinanzeigen Okt 2026'),
  ('KL', '350x350', 75, '70 bis 80', 'Kleinanzeigen Okt 2026'),
  ('KL', '500x175', 70, null, 'geschätzt'),
  ('KL', '500x350', 85, '45 bis 90', 'Kleinanzeigen Okt 2026'),
  ('KL', '750x175', 85, null, 'geschätzt'),
  ('KL', '750x250', 95, '109 neu', 'Kleinanzeigen Okt 2026'),
  ('KL', '750x350', 125, '100 bis 139', 'Kleinanzeigen Okt 2026'),
  ('AZ', '500x350', 80, null, 'geschätzt'),
  ('AZ', '500x500', 90, '100', 'Kleinanzeigen Okt 2026'),
  ('AZ', '750x350', 95, '89 bis 119', 'Kleinanzeigen Okt 2026'),
  ('AZ', '750x500', 90, '39 bis 109', 'Kleinanzeigen Okt 2026')
on conflict (typ, mass) do nothing;

create or replace view lager_health as
 select t.code, tt.gruppe, tt.bezeichnung, t.mass, t.farbe, t.zustand, t.generation, t.bestand, t.reserviert,
    t.bestand - t.reserviert - coalesce(v.verbaut, 0) as verfuegbar,
    coalesce(t.mindestbestand, tt.mindestbestand) as mindestbestand,
    t.durchschnittspreis,
    t.bestand::numeric * t.durchschnittspreis as wert,
    t.nur_neu, t.lagerort,
    t.bestand - t.reserviert - coalesce(v.verbaut, 0) < coalesce(t.mindestbestand, tt.mindestbestand, 0) as unter_minimum,
    coalesce(v.verbaut, 0) as verbaut, v.verbaut_in,
    mp.vk as marktpreis,
    t.bestand::numeric * mp.vk as marktwert,
    round(case when mp.vk > t.durchschnittspreis then (mp.vk - t.durchschnittspreis) / 1.19 else mp.vk - t.durchschnittspreis end, 2) as marge_stueck
   from teil t
     join teiltyp tt on tt.code = t.typ
     left join teil_verbaut v on v.teil = t.code
     left join lateral (select marktpreis_fuer(t.typ, t.mass, t.zustand::text) as vk) mp on true;

select code, zustand, bestand, durchschnittspreis, marktpreis, marge_stueck from lager_health where marktpreis is not null order by code;
