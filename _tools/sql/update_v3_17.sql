-- Update v3.17 (12.10.2026): Bezahlt = verkauft. Zahlungseingang (PayPal, Bank oder manuell) bucht den Verkauf und nimmt die Teile aus dem Lager.
alter table auftrag add column if not exists teile jsonb;

create or replace function public.auftrag_verbuchen(p_id uuid, p_teile jsonb default null) returns uuid
language plpgsql set search_path to 'public' as $function$
declare a auftrag; v uuid; x jsonb;
begin
  select * into a from auftrag where id = p_id for update;
  if a.verkauf_id is not null then return a.verkauf_id; end if;
  if a.moebel_id is not null then
    v := fertigmoebel_verkaufen(a.moebel_id, coalesce(a.preis, 0) + a.versand_kunde,
      a.versand_eigen + coalesce((select gebuehr from zahlung where id = a.zahlung_id), 0), a.kanal, 'Auftrag ' || a.id);
  else
    p_teile := coalesce(p_teile, a.teile);
    if p_teile is null or jsonb_array_length(p_teile) = 0 then raise exception 'Ohne Fertigmöbel brauche ich die verkauften Teile'; end if;
    insert into verkauf (kanal, bezeichnung, erloes, eigene_kosten, notiz, kategorie)
    values (a.kanal, a.titel, coalesce(a.preis, 0) + a.versand_kunde,
      a.versand_eigen + coalesce((select gebuehr from zahlung where id = a.zahlung_id), 0), 'Auftrag ' || a.id, kategorie_aus(a.titel)) returning id into v;
    for x in select * from jsonb_array_elements(p_teile) loop
      insert into verkauf_position (verkauf_id, teil, menge) values (v, x->>'teil', (x->>'menge')::int);
    end loop;
    perform buche_verkauf(v);
  end if;
  update auftrag set verkauf_id = v, geaendert_am = now() where id = p_id;
  return v;
end $function$;

create or replace function public.auftrag_status(p_id uuid, p_status text, p_notiz text default null) returns void
language plpgsql set search_path to 'public' as $function$
declare a auftrag;
begin
  update auftrag set status = p_status, geaendert_am = now(), notiz = coalesce(p_notiz, notiz) where id = p_id returning * into a;
  if not found then raise exception 'Auftrag nicht gefunden'; end if;
  if a.moebel_id is null and a.inserat is not null then
    update auftrag set inserat = inserat where id = p_id returning * into a;
  end if;
  if a.moebel_id is not null and a.verkauf_id is null then
    if p_status = 'heiss' then
      update moebel set status = 'reserviert', geaendert_am = now() where id = a.moebel_id and status = 'aufgebaut';
    elsif p_status = 'storniert' then
      update moebel set status = 'aufgebaut', geaendert_am = now() where id = a.moebel_id and status = 'reserviert';
    end if;
  end if;
  -- Bezahlt heißt verkauft: ab jetzt ist der Verkauf fix und die Teile gehen aus dem Lager
  if p_status in ('bezahlt', 'freigegeben', 'label', 'versendet', 'abgeholt') and a.verkauf_id is null then
    if a.moebel_id is not null or (a.teile is not null and jsonb_array_length(a.teile) > 0) then
      perform auftrag_verbuchen(p_id);
    else
      update auftrag set notiz = concat_ws(' · ', notiz, 'Lager noch nicht ausgebucht: verkaufte Teile fehlen') where id = p_id and coalesce(notiz, '') not like '%Lager noch nicht ausgebucht%';
    end if;
  end if;
end $function$;

-- Backup: bezahlt per Hand bestätigen
create or replace function auftrag_bezahlt_manuell(p_id uuid, p_wer text default null) returns void
language plpgsql security definer set search_path = public as $$
begin
  if not ist_nutzer() then raise exception 'Kein Zugriff'; end if;
  update auftrag set bezahlt_am = coalesce(bezahlt_am, now()), zuordnung = coalesce(zuordnung, 'manuell bestätigt' || coalesce(' von ' || p_wer, '')), sicherheit = coalesce(sicherheit, 100) where id = p_id;
  perform auftrag_status(p_id, 'bezahlt');
end $$;
revoke execute on function auftrag_bezahlt_manuell(uuid, text) from public, anon;
grant execute on function auftrag_bezahlt_manuell(uuid, text) to authenticated;

-- Übersicht: Wareneinsatz auch für Teile-Verkäufe, Marge in Prozent, verkauft ja/nein
create or replace view auftrag_uebersicht as
 with w as (
   select mt.moebel_id, sum(mt.menge::numeric * t.durchschnittspreis) as wert, sum(mt.menge)::integer as teile
   from moebel_teil mt join teil t on t.code = mt.teil group by mt.moebel_id
 ), wt as (
   select a.id as auftrag_id, sum((x->>'menge')::numeric * t.durchschnittspreis) as wert, sum((x->>'menge')::int)::integer as teile
   from auftrag a cross join lateral jsonb_array_elements(coalesce(a.teile, '[]')) x join teil t on t.code = x->>'teil' group by a.id
 ), re as (
   select distinct on (rechnung.auftrag_id) rechnung.id, rechnung.nummer, rechnung.auftrag_id, rechnung.status, rechnung.datum, rechnung.lieferdatum,
     rechnung.kunde_name, rechnung.kunde_adresse, rechnung.kunde_email, rechnung.positionen, rechnung.besteuerung, rechnung.netto, rechnung.ust, rechnung.brutto,
     rechnung.zahlarten, rechnung.paypal_link, rechnung.hinweis, rechnung.quelle, rechnung.gesendet_von, rechnung.gesendet_am, rechnung.storno_von, rechnung.erstellt_am
   from rechnung where rechnung.status <> 'storniert' order by rechnung.auftrag_id, rechnung.erstellt_am desc
 ), b as (
   select a.*, m.name as moebel_name, m.lagerort, m.masse as moebel_masse,
     coalesce(mv.wareneinsatz, w.wert, wt.wert) as wareneinsatz, coalesce(w.teile, wt.teile) as teile_anzahl,
     coalesce(re.brutto, coalesce(a.preis, 0) + a.versand_kunde) as erloes, coalesce(z.gebuehr, 0) as zahlung_gebuehr,
     z.betrag as zahlung_betrag, z.absender as zahlung_absender, z.quelle as zahlung_quelle, z.art as zahlung_art,
     re.id as rechnung_id, re.nummer as rechnung_nummer, re.status as rechnung_status, re.brutto as rechnung_brutto, re.besteuerung, re.ust as re_ust
   from auftrag a left join moebel m on m.id = a.moebel_id left join w on w.moebel_id = a.moebel_id left join wt on wt.auftrag_id = a.id
     left join marge_je_verkauf mv on mv.id = a.verkauf_id left join zahlung z on z.id = a.zahlung_id left join re on re.auftrag_id = a.id
 )
 select b.id, b.status, b.kanal, b.inserat, b.moebel_id, b.titel, b.kaeufer_name, b.kaeufer_kontakt, b.adresse, b.versandart, b.preis, b.versand_kunde, b.versand_eigen,
   b.zahlart, b.zahlung_id, b.bezahlt_am, b.sicherheit, b.zuordnung, b.chat_auszug, b.paket, b.sendungsnummer, b.label_url, b.verkauf_id, b.freigabe_von, b.freigabe_am,
   b.notiz, b.erstellt_am, b.geaendert_am, b.moebel_name, b.lagerort, b.moebel_masse, b.wareneinsatz, b.teile_anzahl as teile, b.erloes, b.zahlung_gebuehr,
   round(b.erloes - b.versand_eigen - b.zahlung_gebuehr - coalesce(b.wareneinsatz, 0)
     - case when b.besteuerung = 'regel' then b.re_ust else greatest(0, b.erloes - coalesce(b.wareneinsatz, 0)) * 0.19 / 1.19 end, 2) as gewinn_vor_steuern,
   b.zahlung_betrag, b.zahlung_absender, b.zahlung_quelle, b.zahlung_art, b.rechnung_id, b.rechnung_nummer, b.rechnung_status, b.rechnung_brutto, b.besteuerung,
   b.teile as teile_liste, b.verkauf_id is not null as verkauft
 from b;
grant select on auftrag_uebersicht to authenticated;
select count(*) from auftrag_uebersicht;

-- Nachtrag: Chat-Rechnung übernimmt die verkauften Teile, Auftrag reserviert sofort; Teile nachträglich setzen
-- (siehe ka_chat_rechnung mit p->'teile' und auftrag_teile_setzen, live eingespielt 12.10.2026 18:40)
