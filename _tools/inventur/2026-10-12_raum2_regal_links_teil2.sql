-- Inventur 12.10. Raum 2, Regal links, Teil 2 (Antworten Samuel 17:39)
insert into teiltyp (code, gruppe, bezeichnung, masse, symmetrisch, mit_generation, quelle_status, hinweis) values
 ('ROX','A Gestell','Rohr Sondermaß / nicht zuordenbar', '{}', false, false, 'Samuel 12.10.2026', 'Sammelposition für Rohre mit unbekanntem Maß (z. B. zwischen 35 und 40, 60er).')
on conflict (code) do nothing;
insert into marktpreis (typ, mass, preis, quelle) values ('ROX','*',5,'geschätzt'),('GST','*',20,'blucom') on conflict (typ, mass) do nothing;
update teil set durchschnittspreis = 10 where code in ('AZ-395x175-23-G','AZ-395x250-32-G','AZ-395x100-24-G','AZ-395x100-30-G','AZ-395x175-30-G','AZ-395x250-24-N','AZ-395x350-30-G','AZ-395x175-24-N') and durchschnittspreis = 0;
update teil set notiz = replace(notiz, '; EK bitte bestätigen', '') where code = 'HW-SCALT-SW-G';
do $$
declare x record; c text; p numeric; ort text := 'Raum 2, Regal links';
begin
  for x in select * from (values
    ('AT','750x350','30','G',4,30::numeric,'komplette Auszugswanne neue Gen. (Set 40 € inkl. Schienen), Maß bitte prüfen'),
    ('HW-TE350',null,'SW','G',8,5,'aus kompletten Auszugswannen'),
    ('BL','750x500','33','G',1,10,'mit Holz oben als Kratzschutz'),
    ('KL','750x350','24','G',1,20,'weiß, kam mit Universalschloss + Schlosskasten (30 € gesamt)'),
    ('KL','750x350','30','N',4,35,null),
    ('KL','750x350','30','G',6,35,null),
    ('HW-USL',null,'SW','G',4,7.5,'von Klapptüren (Schloss + Kasten = 10 €)'),
    ('HW-SKN',null,'SW','G',4,2.5,'von Klapptüren'),
    ('EI','500x350','24','N',1,65,'Komplettset ca. 82,50 € inkl. Garagen-Beschlagset, flacher Schlosskasten'),
    ('HW-GTSET',null,'SW','G',1,17.5,'zur weißen Einschubtür 50 × 35'),
    ('GT','350x350','GL','G',1,20,'Ecke leicht abgesplittert, mit Knauf und Scharnier-Chromecke'),
    ('GT','500x350','GL','G',1,20,'mit Schloss und schwarz-matter Scharnier-Ecke'),
    ('RCS',null,'SW','G',2,5,null),
    ('GST','750','CR','G',1,14,'Stange 75 + Anbauteile (quer einbaubar)'),
    ('RBU','500','CR','G',2,7,'Buffetrohr mit 35er Aufbau'),
    ('RO','350','CR','G',2,7,'Aufbau auf Buffetrohr'),
    ('CO',null,'CR','G',2,1.19,null),
    ('ROX',null,'CR','G',6,5,'zwischen 35 und 40, Maß unklar'),
    ('RO','250','CR','G',21,5,null),
    ('RS','250','CR','G',10,5,null),
    ('RO','350','CR','G',202,7,null),
    ('RS','350','CR','G',5,7,null),
    ('RO','500','CR','G',76,7,null),
    ('RS','500','CR','G',35,7,null),
    ('KU',null,'CR','G',6,null,'steckten auf 50er Rohren'),
    ('CO',null,'CR','G',6,1.19,null),
    ('RO','750','CR','G',116,7,null),
    ('RS','750','CR','G',30,7,null)
  ) v(typ, mass, farbe, zustand, n, preis, notiz) loop
    c := teil_code(x.typ, x.mass, x.farbe, x.zustand);
    select durchschnittspreis into p from teil where code = c;
    perform inventur(c, x.n, coalesce(x.preis, nullif(p, 0), 0), ort);
    if x.notiz is not null then update teil set notiz = concat_ws(' · ', notiz, x.n || '× ' || x.notiz) where code = c; end if;
  end loop;
end $$;
select round(sum(wert)) ek_wert, sum(bestand) stueck, round(sum(marktwert)) markt from lager_health;
