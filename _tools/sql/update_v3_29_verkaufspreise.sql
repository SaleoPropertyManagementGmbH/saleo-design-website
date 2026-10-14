-- 14.10.2026: Verkaufspreise (Tabelle marktpreis) als feste Grundlage für Angebote
-- Preise von Leon festgelegt und aus eigenen Inseraten übernommen; RPC verkaufspreis_setzen(typ, mass, preis, wer) für die App
create or replace function verkaufspreis_setzen(p_typ text, p_mass text, p_preis numeric, p_wer text default null)
returns void language plpgsql security definer set search_path = public as $$
begin
  if not ist_nutzer() then raise exception 'Kein Zugriff'; end if;
  if p_preis is null or p_preis < 0 then raise exception 'Preis fehlt'; end if;
  insert into marktpreis (typ, mass, preis, quelle, stand) values (p_typ, coalesce(nullif(p_mass, ''), '*'), round(p_preis, 2), 'Festgelegt' || coalesce(' von ' || nullif(p_wer, ''), ''), current_date)
  on conflict (typ, mass) do update set preis = excluded.preis, quelle = excluded.quelle, stand = excluded.stand;
end $$;
grant execute on function verkaufspreis_setzen(text, text, numeric, text) to authenticated;
