insert into teiltyp (code, gruppe, bezeichnung, masse, symmetrisch, mit_generation, quelle_status, hinweis)
select 'EIP', gruppe, 'Einschubtür perforiert', masse, symmetrisch, mit_generation, 'von Samuel bestätigt', 'Wie Einschubtür, Front perforiert.' from teiltyp where code = 'EI' on conflict (code) do nothing;
insert into teiltyp (code, gruppe, bezeichnung, masse, symmetrisch, mit_generation, quelle_status, hinweis)
select 'AZP', gruppe, 'Schublade perforiert', masse, symmetrisch, mit_generation, 'von Samuel bestätigt', 'Wie Schublade, Front perforiert.' from teiltyp where code = 'AZ' on conflict (code) do nothing;
update teiltyp set hinweis = 'Klapptür mit perforierter Front.' where code = 'KLP';
insert into marktpreis (typ, mass, preis, quelle) values ('EIP','750x350',135,'geschätzt'),('EIP','500x350',95,'geschätzt') on conflict (typ, mass) do nothing;
do $$
declare m uuid; x record; c text;
begin
  select id into m from moebel where name like 'Sideboard 2×3 mittelgrau%' and lagerort = 'Büro';
  -- weg
  for x in select * from (values ('BL-750x350-32-G', 4), ('KLP-750x350-32-G', 4), ('HW-BAA-SW-G', 4), ('HW-DP-SW-G', 8), ('HW-SC69-SW-G', 8)) v(code, n) loop
    update moebel_teil set menge = menge - x.n where moebel_id = m and teil = x.code;
    delete from moebel_teil where moebel_id = m and teil = x.code and menge <= 0;
    perform inventur(x.code, -x.n, 0, null);
  end loop;
  -- dazu
  for x in select * from (values ('BSZ', '750x350', '32', 4, 22.11), ('EIP', '750x350', '32', 4, 61.41), ('HW-EFP', null, 'SW', 8, 0.30), ('HW-EH', null, 'SW', 8, 0.30), ('HW-EZS', null, 'SW', 4, 0.30), ('HW-KS', null, '32', 8, 0.30)) v(typ, mass, farbe, n, p) loop
    c := teil_code(x.typ, x.mass, x.farbe, 'G');
    perform inventur(c, x.n, x.p, 'Büro');
    if exists (select 1 from moebel_teil where moebel_id = m and teil = c) then update moebel_teil set menge = menge + x.n where moebel_id = m and teil = c;
    else insert into moebel_teil (moebel_id, teil, menge) values (m, c, x.n); end if;
  end loop;
  update moebel set name = 'Sideboard 2×3 mittelgrau, 2 Auszüge, 4 perforierte Einschubtüren',
    notiz = 'Obere zwei Reihen: perforierte Einschubtüren. Oberste Reihe ohne Rückwand. Je Seite Taschenablage aus 2 Rohren 100 und 1 Rohr 350.',
    daten = jsonb_set(daten, '{fields}', (select jsonb_agg(case when f->>'front' in ('KL','KLP') then f || '{"front":"EI","perf":true}'::jsonb else f end) from jsonb_array_elements(daten->'fields') f))
  where id = m;
end $$;
select mt.teil, mt.menge from moebel_teil mt join moebel m on m.id = mt.moebel_id where m.name like 'Sideboard 2×3 mittelgrau%' order by 1;
