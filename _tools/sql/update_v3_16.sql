-- Update v3.16 (12.10.2026): Verkauf bucht das Lager automatisch aus; Fundorte sammeln
-- 1. Auftrag findet sein Fertigmöbel über das Inserat
create or replace function auftrag_moebel_finden() returns trigger
language plpgsql set search_path = public as $$
begin
  if new.moebel_id is null and new.inserat is not null then
    select id into new.moebel_id from moebel where inserat = new.inserat and status in ('aufgebaut', 'reserviert') order by erstellt_am limit 1;
  end if;
  return new;
end $$;
drop trigger if exists auftrag_moebel on auftrag;
create trigger auftrag_moebel before insert or update of inserat, moebel_id on auftrag for each row execute function auftrag_moebel_finden();

-- 2. Status "versendet" oder "abgeholt" bucht den Verkauf und nimmt die Teile aus dem Lager
create or replace function public.auftrag_status(p_id uuid, p_status text, p_notiz text default null) returns void
language plpgsql set search_path to 'public' as $function$
declare a auftrag;
begin
  update auftrag set status = p_status, geaendert_am = now(), notiz = coalesce(p_notiz, notiz) where id = p_id returning * into a;
  if not found then raise exception 'Auftrag nicht gefunden'; end if;
  if a.moebel_id is null and a.inserat is not null then
    update auftrag set inserat = inserat where id = p_id returning * into a;
  end if;
  if a.moebel_id is not null then
    if p_status in ('heiss', 'bezahlt', 'freigegeben', 'label') then
      update moebel set status = 'reserviert', geaendert_am = now() where id = a.moebel_id and status = 'aufgebaut';
    elsif p_status = 'storniert' then
      update moebel set status = 'aufgebaut', geaendert_am = now() where id = a.moebel_id and status = 'reserviert';
    end if;
  end if;
  if p_status in ('versendet', 'abgeholt') and a.verkauf_id is null then
    if a.moebel_id is not null then
      perform auftrag_verbuchen(p_id);
    else
      update auftrag set notiz = concat_ws(' · ', notiz, 'Lager noch nicht ausgebucht: kein Fertigmöbel zugeordnet') where id = p_id and coalesce(notiz, '') not like '%Lager noch nicht ausgebucht%';
    end if;
  end if;
end $function$;

-- 3. Inserate den Büro-Möbeln zuordnen (sicher erkannte)
update moebel set inserat = v.ins from (values
  ('Hochbau grün%', '3437083363'), ('Schrank grün doppelseitig%', '3528040054'), ('Sideboard schwarz T50%', '3528031830'),
  ('Sideboard schwarz 2 m%', '3443793606'), ('Sideboard schwarz 2×2%', '3435919216'), ('Regal schwarz 75 × 50%', '3478241354')
) v(n, ins) where moebel.name like v.n and moebel.inserat is null;
select name, inserat from moebel where lagerort = 'Büro' order by name;
