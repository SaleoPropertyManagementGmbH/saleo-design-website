-- v3.25 (13.10.2026): Aufträge von Hand flexibel: Preis und Name dürfen erst später kommen; jeder Auftrag ist nachträglich änderbar.
create or replace function public.auftrag_von_hand(p jsonb)
 returns uuid language plpgsql security definer set search_path to 'public' as $function$
declare a uuid; m moebel; pr numeric := nullif(p->>'preis', '')::numeric; vk numeric := coalesce(nullif(p->>'versand_kunde', '')::numeric, 0); pos jsonb;
begin
  if not ist_nutzer() then raise exception 'Kein Zugriff'; end if;
  if pr is not null and pr <= 0 then pr := null; end if;
  if nullif(p->>'moebel_id', '') is not null then select * into m from moebel where id = (p->>'moebel_id')::uuid; end if;
  insert into auftrag (status, kanal, inserat, moebel_id, titel, kaeufer_name, kaeufer_kontakt, adresse, versandart, preis, versand_kunde, notiz)
  values ('heiss', coalesce(nullif(p->>'kanal', ''), 'kleinanzeigen'), coalesce(nullif(p->>'inserat', ''), m.inserat), m.id, coalesce(nullif(p->>'titel', ''), m.name, 'Verkauf'),
    nullif(p->>'kunde_name', ''), nullif(p->>'email', ''), case when jsonb_typeof(p->'adresse') = 'object' then p->'adresse' end, coalesce(nullif(p->>'versandart', ''), 'abholung'), pr, vk,
    'Von Hand angelegt' || coalesce(' von ' || nullif(p->>'wer', ''), '') || case when pr is null then '. Preis noch offen.' else '' end)
  returning id into a;
  perform auftrag_status(a, 'heiss');
  if pr is not null and coalesce(p->>'kunde_name', '') <> '' and (coalesce(p->>'email', '') <> '' or jsonb_typeof(p->'adresse') = 'object') then
    pos := jsonb_build_array(jsonb_build_object('text', coalesce(nullif(p->>'titel', ''), m.name, 'USM Haller'), 'menge', 1, 'preis', pr));
    if vk > 0 then pos := pos || jsonb_build_array(jsonb_build_object('text', 'Versandkosten', 'menge', 1, 'preis', vk)); end if;
    perform rechnung_anlegen(a, p->>'kunde_name', case when jsonb_typeof(p->'adresse') = 'object' then p->'adresse' end, nullif(p->>'email', ''), pos, 'differenz', '{ueberweisung,paypal}', null, null, 'von-hand');
  end if;
  return a;
end $function$;

create or replace function public.auftrag_aendern(p_id uuid, p jsonb)
 returns jsonb language plpgsql security definer set search_path to 'public' as $function$
declare a auftrag; r rechnung; pr numeric; vk numeric; alt_pr numeric; alt_vk numeric; pos jsonb; hinweis text := null; neu boolean := false;
begin
  if not ist_nutzer() then raise exception 'Kein Zugriff'; end if;
  select * into a from auftrag where id = p_id for update;
  if a.id is null then raise exception 'Auftrag nicht gefunden'; end if;
  alt_pr := a.preis; alt_vk := a.versand_kunde;
  pr := case when p ? 'preis' then nullif(p->>'preis', '')::numeric else a.preis end;
  vk := case when p ? 'versand_kunde' then coalesce(nullif(p->>'versand_kunde', '')::numeric, 0) else a.versand_kunde end;
  update auftrag set
    titel = coalesce(nullif(p->>'titel', ''), titel),
    preis = pr, versand_kunde = vk,
    versandart = coalesce(nullif(p->>'versandart', ''), versandart),
    kanal = coalesce(nullif(p->>'kanal', ''), kanal),
    kaeufer_name = case when p ? 'kunde_name' then nullif(p->>'kunde_name', '') else kaeufer_name end,
    kaeufer_kontakt = case when p ? 'email' then nullif(p->>'email', '') else kaeufer_kontakt end,
    adresse = case when p ? 'adresse' then (case when jsonb_typeof(p->'adresse') = 'object' and coalesce(p->'adresse'->>'strasse', p->'adresse'->>'plz', p->'adresse'->>'ort', '') <> '' then p->'adresse' else null end) else adresse end,
    inserat = case when p ? 'inserat' then nullif(p->>'inserat', '') else inserat end,
    notiz = case when p ? 'notiz' then nullif(p->>'notiz', '') else notiz end,
    geaendert_am = now()
  where id = p_id returning * into a;
  -- Rechnung mitziehen: Entwurf anpassen, gesendete Rechnung nie anfassen
  select * into r from rechnung where auftrag_id = p_id and status <> 'storniert' order by erstellt_am desc limit 1;
  if r.id is not null and r.status = 'entwurf' and r.gesendet_am is null then
    pos := r.positionen;
    if a.preis is not null and (a.preis is distinct from alt_pr or a.versand_kunde is distinct from alt_vk) and jsonb_array_length(pos) between 1 and 2 then
      pos := jsonb_build_array(jsonb_build_object('text', pos->0->>'text', 'menge', 1, 'preis', a.preis));
      if a.versand_kunde > 0 then pos := pos || jsonb_build_array(jsonb_build_object('text', 'Versandkosten', 'menge', 1, 'preis', a.versand_kunde)); end if;
    end if;
    perform rechnung_aendern(r.id, jsonb_build_object('kunde_name', coalesce(a.kaeufer_name, r.kunde_name), 'kunde_email', case when a.kaeufer_kontakt like '%@%' then a.kaeufer_kontakt else coalesce(r.kunde_email, '') end, 'positionen', pos)
      || case when a.adresse is not null then jsonb_build_object('kunde_adresse', a.adresse) else '{}'::jsonb end);
    hinweis := 'Rechnungsentwurf angepasst';
  elsif r.id is not null then
    hinweis := 'Rechnung ' || r.nummer || ' ist schon gesendet und bleibt unverändert';
  elsif a.preis is not null and coalesce(a.kaeufer_name, '') <> '' and (a.kaeufer_kontakt like '%@%' or a.adresse is not null) then
    pos := jsonb_build_array(jsonb_build_object('text', a.titel, 'menge', 1, 'preis', a.preis));
    if a.versand_kunde > 0 then pos := pos || jsonb_build_array(jsonb_build_object('text', 'Versandkosten', 'menge', 1, 'preis', a.versand_kunde)); end if;
    perform rechnung_anlegen(a.id, a.kaeufer_name, a.adresse, case when a.kaeufer_kontakt like '%@%' then a.kaeufer_kontakt end, pos, 'differenz', '{ueberweisung,paypal}', null, null, 'von-hand');
    hinweis := 'Rechnungsentwurf angelegt'; neu := true;
  end if;
  return jsonb_build_object('ok', true, 'rechnung', hinweis, 'neu', neu);
end $function$;
grant execute on function public.auftrag_aendern(uuid, jsonb) to authenticated;
