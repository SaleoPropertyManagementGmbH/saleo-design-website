-- v3.24 (13.10.2026): Planung mit Auftrag verknüpfen und Kalkulation setzen (authenticated hat kein UPDATE auf auftrag).
create or replace function public.auftrag_planung_setzen(p_auftrag uuid, p_planung uuid, p_kalkulation jsonb default null, p_ueberschreiben boolean default false)
 returns jsonb language plpgsql security definer set search_path to 'public' as $$
declare a auftrag; k boolean := false;
begin
  if not ist_nutzer() then raise exception 'Kein Zugriff'; end if;
  select * into a from auftrag where id = p_auftrag for update;
  if a.id is null then raise exception 'Auftrag nicht gefunden'; end if;
  if a.planung_id is null and p_planung is not null then update auftrag set planung_id = p_planung, geaendert_am = now() where id = a.id; end if;
  if p_kalkulation is not null and jsonb_typeof(p_kalkulation) = 'array' and jsonb_array_length(p_kalkulation) > 0
     and coalesce(jsonb_array_length(a.teile), 0) = 0 and a.verkauf_id is null and a.moebel_id is null
     and (p_ueberschreiben or coalesce(jsonb_array_length(a.kalkulation), 0) = 0) then
    update auftrag set kalkulation = p_kalkulation, geaendert_am = now() where id = a.id; k := true;
  end if;
  return jsonb_build_object('planung', coalesce(a.planung_id, p_planung), 'kalkulation', k);
end $$;
grant execute on function public.auftrag_planung_setzen(uuid, uuid, jsonb, boolean) to authenticated;
