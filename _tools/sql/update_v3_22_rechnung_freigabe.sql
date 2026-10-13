-- v3.22 (13.10.2026): Rechnungen nur nach manueller Freigabe; Entwürfe in der App änderbar; Rechnungsfirma Saleo Design UG.
create or replace function public.rechnung_aendern(p_id uuid, p jsonb)
 returns jsonb language plpgsql security definer set search_path to 'public' as $$
declare r rechnung; pos jsonb; summe numeric; best text;
begin
  if not ist_nutzer() then raise exception 'Kein Zugriff'; end if;
  select * into r from rechnung where id = p_id for update;
  if r.id is null then raise exception 'Rechnung nicht gefunden'; end if;
  if r.status <> 'entwurf' or r.gesendet_am is not null then raise exception 'Nur Entwürfe können geändert werden'; end if;
  pos := coalesce(p->'positionen', r.positionen);
  if jsonb_typeof(pos) <> 'array' or jsonb_array_length(pos) = 0 then raise exception 'Mindestens eine Position nötig'; end if;
  best := coalesce(p->>'besteuerung', r.besteuerung);
  select sum((x->>'menge')::numeric * (x->>'preis')::numeric) into summe from jsonb_array_elements(pos) x;
  update rechnung set
    kunde_name = coalesce(p->>'kunde_name', kunde_name),
    kunde_email = case when p ? 'kunde_email' then nullif(p->>'kunde_email','') else kunde_email end,
    kunde_adresse = coalesce(p->'kunde_adresse', kunde_adresse),
    positionen = pos, besteuerung = best,
    hinweis = case when p ? 'hinweis' then nullif(p->>'hinweis','') else hinweis end,
    lieferdatum = case when p ? 'lieferdatum' then nullif(p->>'lieferdatum','')::date else lieferdatum end,
    zahlarten = case when p ? 'zahlarten' then array(select jsonb_array_elements_text(p->'zahlarten')) else zahlarten end,
    netto = case when best = 'regel' then round(summe, 2) end,
    ust = case when best = 'regel' then round(summe * 0.19, 2) else 0 end,
    brutto = case when best = 'regel' then round(summe * 1.19, 2) else round(summe, 2) end
  where id = p_id;
  return (select to_jsonb(x) from rechnung x where id = p_id);
end $$;
grant execute on function public.rechnung_aendern(uuid, jsonb) to authenticated;

insert into firma (schluessel, wert) values
 ('name','Saleo Design UG (haftungsbeschränkt)'), ('name_absender','Saleo Design UG (haftungsbeschränkt)'),
 ('register','Amtsgericht Wiesbaden, HRB 37027'), ('geschaeftsfuehrer','Samuel Lewis Seel, Leon Nikolas Nessler'),
 ('kontoinhaber','Saleo Group'),
 ('rechnung_hinweis','Es gelten unsere AGB sowie die Widerrufsbelehrung und die Hinweise zur Gewährleistung aus unserem Angebot auf Kleinanzeigen.')
on conflict (schluessel) do update set wert = excluded.wert;
