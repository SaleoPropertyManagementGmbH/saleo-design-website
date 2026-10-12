-- v3.20 (12.10.2026): Betrieb ohne Mac. Postfach-Abruf per pg_cron alle 5 Minuten, Auftrag von Hand.
create table if not exists intern_schluessel (name text primary key, wert text not null);
alter table intern_schluessel enable row level security;
revoke all on intern_schluessel from anon, authenticated;
insert into intern_schluessel (name, wert) values ('cron', encode(gen_random_bytes(24), 'hex')) on conflict (name) do nothing;
grant select on intern_schluessel to service_role;
grant select, insert, update on ka_mail to service_role;
grant select on firma to service_role;
select cron.schedule('postfach-lesen', '*/5 * * * *', $c$select net.http_post(url := 'https://uqcropugtdtrzaumjbby.supabase.co/functions/v1/postfach-lesen', headers := jsonb_build_object('Content-Type','application/json','x-cron-key',(select wert from public.intern_schluessel where name='cron')), body := '{}'::jsonb, timeout_milliseconds := 120000)$c$);
-- auftrag_von_hand(p jsonb): siehe Datenbank (Auftrag + Rechnungsentwurf aus dem Formular in der App)

-- v3.20b: Chat-Mails sortieren und aufräumen
alter table ka_mail add column if not exists erledigt boolean not null default false;
alter table ka_mail add column if not exists ordner text;
grant update on ka_mail to service_role;
-- Trigger ka_mail_abschluss auf auftrag: versendet/abgeholt/storniert markiert die Chat-Mails zum Inserat als erledigt
-- ka_chat_beenden(p_inserat, p_partner, p_grund): kein Deal, Mails als erledigt markieren
-- Der Postfach-Abruf verschiebt laufende Chats nach 02_VERKAUF/Kleinanzeigen/Offene Chats und erledigte in den Papierkorb
