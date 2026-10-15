-- v3.34 Social: Trend-Ideen mit Quelle und Diskussion je Idee
alter table social_idee add column if not exists trend text;
alter table social_idee add column if not exists quelle text;

create table if not exists social_idee_kommentar (
  id uuid primary key default gen_random_uuid(),
  idee_id uuid not null references social_idee(id),
  text text not null,
  wer text,
  erstellt_am timestamptz not null default now()
);
create index if not exists social_idee_kommentar_idee on social_idee_kommentar(idee_id, erstellt_am);
alter table social_idee_kommentar enable row level security;
do $$ begin
  if not exists (select 1 from pg_policies where tablename = 'social_idee_kommentar' and policyname = 'social_lesen') then
    create policy social_lesen on social_idee_kommentar for select using (ist_social());
    create policy social_schreiben on social_idee_kommentar for insert with check (ist_social());
  end if;
  if not exists (select 1 from pg_publication_tables where pubname = 'supabase_realtime' and tablename = 'social_idee_kommentar') then
    alter publication supabase_realtime add table social_idee_kommentar;
  end if;
end $$;
