-- v3.27 (13.10.2026): Social-Bereich mit Website (Metricool) und Kleinanzeigen, Funnel bis zum Kunden, gemeinsamer Strategie-Plan.
alter table social_konto drop constraint if exists social_konto_plattform_check;
alter table social_konto add constraint social_konto_plattform_check check (plattform in ('instagram','tiktok','youtube','facebook','pinterest','linkedin','website','kleinanzeigen'));
alter table social_konto add column if not exists details jsonb; -- Website: {seiten:[{seite,aufrufe}], quellen:[{quelle,besuche}], laender:[{land,besucher}]}
insert into social_konto (plattform, handle, name, url) values ('website','saleo-design.de','Website saleo-design.de','https://saleo-design.de') on conflict (plattform, handle) do nothing;
create table if not exists social_plan (id uuid primary key default gen_random_uuid(), titel text not null, inhalt text, reihenfolge integer not null default 100, geaendert_von text, geaendert_am timestamptz not null default now(), erstellt_am timestamptz not null default now());
alter table social_plan enable row level security;
create policy social_lesen on social_plan for select using (ist_social());
create policy social_schreiben on social_plan for insert with check (ist_social());
create policy social_aendern on social_plan for update using (ist_social()) with check (ist_social());
grant select, insert, update on social_plan to authenticated;
-- social_funnel(p_von, p_bis): nur Anzahl bezahlter Aufträge und Anfragen, keine Beträge (für den Social-Zugang)
-- claude_auftrag: bereich ('alles' | 'social'), von_email; Social-Nutzer sehen nur eigene Einträge (Policy social_eigene)
