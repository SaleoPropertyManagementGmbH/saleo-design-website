-- Update v3.8 (11.10.2026): Kleinanzeigen-Chats mitlesen, Rechnung direkt aus dem Chat
create table if not exists ka_chat (
  id text primary key,
  inserat text,
  titel text,
  partner text,
  letzte_nachricht text,
  letzte_am timestamptz,
  status text not null default 'offen' check (status in ('offen', 'deal', 'rechnung', 'erledigt', 'ignoriert')),
  auftrag_id uuid references auftrag(id),
  rechnung_id uuid references rechnung(id),
  daten jsonb not null default '{}',
  notiz text,
  quelle text not null default 'browser',
  geprueft_am timestamptz not null default now(),
  erstellt_am timestamptz not null default now()
);
alter table ka_chat enable row level security;
grant select on ka_chat to authenticated;
drop policy if exists app_lesen on ka_chat;
create policy app_lesen on ka_chat for select to authenticated using (ist_nutzer());

-- Chatstand merken (vom Mitleser). Erledigte Chats behalten ihren Status.
create or replace function ka_chat_merken(p jsonb) returns void
language plpgsql security definer set search_path = public as $$
begin
  if not ist_nutzer() then raise exception 'Kein Zugriff'; end if;
  insert into ka_chat (id, inserat, titel, partner, letzte_nachricht, letzte_am, status, daten, notiz, quelle)
  values (p->>'id', p->>'inserat', p->>'titel', p->>'partner', p->>'letzte_nachricht', (p->>'letzte_am')::timestamptz,
    coalesce(p->>'status', 'offen'), coalesce(p->'daten', '{}'), p->>'notiz', coalesce(p->>'quelle', 'browser'))
  on conflict (id) do update set
    inserat = coalesce(excluded.inserat, ka_chat.inserat),
    titel = coalesce(excluded.titel, ka_chat.titel),
    partner = coalesce(excluded.partner, ka_chat.partner),
    letzte_nachricht = coalesce(excluded.letzte_nachricht, ka_chat.letzte_nachricht),
    letzte_am = coalesce(excluded.letzte_am, ka_chat.letzte_am),
    status = case when ka_chat.status in ('rechnung', 'erledigt', 'ignoriert') then ka_chat.status else coalesce(p->>'status', ka_chat.status) end,
    daten = ka_chat.daten || excluded.daten,
    notiz = coalesce(excluded.notiz, ka_chat.notiz),
    geprueft_am = now();
end $$;

-- Abschluss im Chat erkannt: Auftrag (heiß) und Rechnung anlegen. Einmal je Chat.
create or replace function ka_chat_rechnung(p jsonb) returns uuid
language plpgsql security definer set search_path = public as $$
declare
  a uuid;
  r uuid;
  z text[];
begin
  if not ist_nutzer() then raise exception 'Kein Zugriff'; end if;
  select rechnung_id into r from ka_chat where id = p->>'id';
  if r is not null then return r; end if;
  perform ka_chat_merken(p || '{"status": "deal"}');
  a := nullif(p->>'auftrag_id', '')::uuid;
  if a is null then
    insert into auftrag (status, kanal, inserat, moebel_id, titel, kaeufer_name, kaeufer_kontakt, adresse, versandart, preis, versand_kunde, chat_auszug)
    values ('heiss', 'kleinanzeigen', p->>'inserat', nullif(p->>'moebel_id', '')::uuid, coalesce(p->>'titel', 'Kleinanzeigen-Verkauf'),
      p->>'kunde_name', 'Kleinanzeigen: ' || coalesce(p->>'partner', ''), p->'adresse', coalesce(p->>'versandart', 'dpd'),
      (p->>'preis')::numeric, coalesce((p->>'versand_kunde')::numeric, 0), p->>'chat_auszug')
    returning id into a;
  end if;
  z := coalesce(array(select jsonb_array_elements_text(p->'zahlarten')), '{}');
  if cardinality(z) = 0 then z := '{ueberweisung,paypal}'; end if;
  r := rechnung_anlegen(a, p->>'kunde_name', p->'adresse', p->>'email', p->'positionen',
    coalesce(p->>'besteuerung', 'differenz'), z, null, p->>'hinweis', 'kleinanzeigen-chat');
  update ka_chat set status = 'rechnung', auftrag_id = a, rechnung_id = r, geprueft_am = now() where id = p->>'id';
  return r;
end $$;
revoke execute on function ka_chat_merken(jsonb), ka_chat_rechnung(jsonb) from public, anon;
grant execute on function ka_chat_merken(jsonb), ka_chat_rechnung(jsonb) to authenticated;
select count(*) as chats from ka_chat;
