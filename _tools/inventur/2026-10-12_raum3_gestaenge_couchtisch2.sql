
-- Inventur 12.10. Raum 3, Gestänge und zweiter Couchtisch (Plaud 19:10)
do $$
declare x record; c text; p numeric; ort text := 'Raum 3, Paletten'; m uuid;
begin
  for x in select * from (values
    -- Leiter 4 × 35/35 (eine Ebene), 2 Füße
    ('KU',null,'CR',10,'zusammengebaut: Leiter 4 × 35 × 35'),('RO','350','CR',13,'zusammengebaut: Leiter'),('CO',null,'CR',26,null),('FU',null,'SW',2,null),
    -- Gestell 35 × 50, zwei Ebenen übereinander
    ('KU',null,'CR',12,'zusammengebaut: Gestell 35 × 50, 2 Fächer hoch'),('RO','350','CR',14,null),('RO','500','CR',6,null),('CO',null,'CR',40,null),
    -- Gestell 35 × 35, drei Ebenen, + 8 Connectoren, 2 Füße
    ('KU',null,'CR',16,'zusammengebaut: Gestell 35 × 35, 3 Fächer hoch'),('RO','350','CR',28,null),('CO',null,'CR',64,null),('FU',null,'SW',2,null),
    -- einzelner Rahmen 35 × 35 (eine Ebene), ein Rohr mit Sticker
    ('KU',null,'CR',4,null),('RO','350','CR',4,'1 mit USM-Sticker'),('CO',null,'CR',8,null)
  ) v(typ, mass, farbe, n, notiz) loop
    c := teil_code(x.typ, x.mass, x.farbe, 'G');
    select durchschnittspreis into p from teil where code = c;
    perform inventur(c, x.n, coalesce(nullif(p, 0), 0), ort);
    if x.notiz is not null then update teil set notiz = concat_ws(' · ', notiz, x.notiz) where code = c; end if;
  end loop;
  -- zweiter Couchtisch 75 × 50, mittelgraue Schwerlasttablare auf Schwerlastrahmen, nur 2 Füße, Zustand schlecht
  m := fertigmoebel_einkauf(p_name => 'Couchtisch 75 × 50 mittelgrau, Schwerlast, 2 Füße', p_preis => 50,
    p_teile => '[{"typ":"KU","farbe":"CR","zustand":"G","menge":8,"wert":3},{"typ":"CO","farbe":"CR","zustand":"G","menge":24,"wert":2},{"typ":"RO","farbe":"CR","mass":"350","zustand":"G","menge":4,"wert":12},{"typ":"RO","farbe":"CR","mass":"500","zustand":"G","menge":4,"wert":14},{"typ":"RO","farbe":"CR","mass":"750","zustand":"G","menge":4,"wert":18},{"typ":"FU","farbe":"SW","zustand":"G","menge":2,"wert":4},{"typ":"BSL","farbe":"32","mass":"750x500","zustand":"S","menge":2,"wert":25},{"typ":"SLR","farbe":"CR","mass":"750x500","zustand":"G","menge":2,"wert":15}]'::jsonb,
    p_farbe => '32', p_zustand => 'G', p_benzin => 0, p_fahrzeug => 0, p_sonstige => 0, p_quelle => 'Inventur Raum 3 (Plaud 12.10.)', p_datum => current_date,
    p_masse => '77 × 39 × 52', p_lagerort => 'Raum 3', p_inserat => null,
    p_daten => '{"fields":[{"id":1,"x":0,"y":0,"w":750,"h":350,"front":"","back":"","inside":"","lock":"U","gen":"N","rahmen":false,"openL":false,"openR":false,"col":{}}],"depth":500,"color":"32","zustand":"G","base":"FU","sides":"","top":"BL","buyNew":{},"price":null,"rabatt":0,"ertragsteuer":30,"neupreis":""}'::jsonb,
    p_notiz => 'EK wie der anthrazitfarbene angenommen (50 €), bitte prüfen. Nur 2 Füße, Zustand schlecht.', p_kategorie => null);
  -- erster Couchtisch hat ebenfalls Schwerlastrahmen
  select id into m from moebel where name like 'Couchtisch 75 × 50 anthrazit%';
  c := teil_code('SLR', '750x500', 'CR', 'G');
  perform inventur(c, 2, 5, 'Büro');
  insert into moebel_teil (moebel_id, teil, menge) values (m, c, 2);
  update moebel set notiz = 'EK ca. 50 €. Oben und unten Schwerlasttablare 75 × 50 anthrazit auf Schwerlastrahmen, schlechter Zustand, Kandidat für Beschichtung.' where id = m;
end $$;
select round(sum(wert)) ek_wert, sum(bestand) stueck from lager_health;
