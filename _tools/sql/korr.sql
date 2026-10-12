-- Korrektur 12.10.: perforierte Klapptür (KLP) und Couchtisch (EK 50 €, Tablare schlecht)
insert into teiltyp (code, gruppe, bezeichnung, masse, symmetrisch, mit_generation, quelle_status, hinweis)
select 'KLP', gruppe, 'Klapptür perforiert', masse, symmetrisch, mit_generation, 'von Samuel bestätigt', 'Wie Klapptür, Front perforiert. Beschläge wie Klapptür.'
from teiltyp where code = 'KL' on conflict (code) do nothing;
insert into marktpreis (typ, mass, preis, spanne, quelle) values
  ('KLP', '750x350', 135, null, 'geschätzt: Klapptür + 10'), ('KLP', '500x350', 95, null, 'geschätzt: Klapptür + 10'), ('KLP', '350x350', 85, null, 'geschätzt: Klapptür + 10')
on conflict (typ, mass) do nothing;
do $$
declare m uuid; alt text := 'KL-750x350-32-G'; neu text; p numeric; ct uuid; e uuid; s text;
begin
  -- 1. Mittelgraues Sideboard: 4 Klapptüren sind perforiert
  select id into m from moebel where name like 'Sideboard 2×3 mittelgrau%' limit 1;
  neu := teil_code('KLP', '750x350', '32', 'G');
  select durchschnittspreis into p from teil where code = alt;
  update moebel_teil set teil = neu where moebel_id = m and teil = alt;
  perform inventur(neu, 4, p, 'Büro');
  perform inventur(alt, -4, 0, null);
  update moebel set daten = jsonb_set(daten, '{fields}', (select jsonb_agg(case when f->>'front' = 'KL' then jsonb_set(f, '{front}', '"KLP"') else f end) from jsonb_array_elements(daten->'fields') f))
  where id = m;
  -- 2. Couchtisch: EK 50 €, Tablare schlechter Zustand
  select id, einkauf_id into ct, e from moebel where name like 'Couchtisch 75 × 50%' limit 1;
  s := teil_code('BL', '750x500', '33', 'S');
  update moebel_teil set teil = s where moebel_id = ct and teil = 'BL-750x500-33-G';
  perform inventur(s, 2, 3.93, 'Büro');
  perform inventur('BL-750x500-33-G', -2, 0, null);
  update einkauf_position set teil = s where einkauf_id = e and teil = 'BL-750x500-33-G';
  update einkauf_position ep set preis_gesamt = v.w from (values ('KU-CR-G', 3.77), ('CO-CR-G', 7.55), ('RO-350-CR-G', 7.55), ('RO-500-CR-G', 8.81),
    ('RO-750-CR-G', 11.32), ('FU-SW-G', 2.52), ('HW-BS-SW-G', 0.62)) v(t, w) where ep.einkauf_id = e and ep.teil = v.t;
  update einkauf_position set preis_gesamt = 7.86 where einkauf_id = e and teil = s;
  update teil t set durchschnittspreis = round((t.bestand * t.durchschnittspreis + v.w) / t.bestand, 2)
  from (values ('KU-CR-G', 3.77), ('CO-CR-G', 7.55), ('RO-350-CR-G', 7.55), ('RO-500-CR-G', 8.81), ('RO-750-CR-G', 11.32), ('FU-SW-G', 2.52), ('HW-BS-SW-G', 0.62)) v(t, w)
  where t.code = v.t and t.bestand > 0;
  update moebel set farbe = '33', notiz = 'EK 50 € (ca.). Tablare 75 × 50 anthrazit in schlechtem Zustand, Kandidat für Beschichtung.' where id = ct;
end $$;
select code, bestand, durchschnittspreis from teil where code in ('KLP-750x350-32-G','KL-750x350-32-G','BL-750x500-33-S','BL-750x500-33-G','KU-CR-G');
