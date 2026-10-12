-- Inventur 12.10. Raum 2, Regal links (Plaud 17:03, 25 Min.)
update teiltyp set masse = array_append(masse, '395x100') where code = 'AZ' and not ('395x100' = any(masse));
update teiltyp set masse = array_append(masse, '350x150') where code = 'GA' and not ('350x150' = any(masse));
update teiltyp set masse = array_append(masse, '750x500') where code = 'BSZ' and not ('750x500' = any(masse));
update teiltyp set masse = array_append(masse, '350') where code = 'HR' and not ('350' = any(masse));
insert into teiltyp (code, gruppe, bezeichnung, masse, symmetrisch, mit_generation, quelle_status, hinweis) values
 ('BVS','B Metall- und Glaselemente','Metallelement verkürzt, Schwerlast (unter Ausziehtablar, Aussparungen für Schienen)', array['750x500','750x350','500x500','500x350'], true, false, 'Samuel 12.10.2026', null),
 ('RCS','C Einbauten','Rollcontainer-Schlitten (wird im Rahmen eingehängt, Schublade läuft darauf)', '{}', false, false, 'Samuel 12.10.2026', null),
 ('RBU','A Gestell','Buffetrohr (Maß = Länge)', array['350','500','750'], false, false, 'Samuel 12.10.2026', 'Buffetrohre später genauer klären.')
on conflict (code) do nothing;
insert into marktpreis (typ, mass, preis, quelle) values ('BVS','*',40,'geschätzt'),('RCS','*',15,'geschätzt'),('RBU','*',15,'geschätzt'),('RS','*',12,'wie Rohr'),('GT','*',60,'geschätzt'),('ZG','*',35,'geschätzt'),('GA','*',35,'geschätzt'),('EI','*',150,'geschätzt'),('KL','*',85,'geschätzt'),('AZ','*',70,'geschätzt')
on conflict (typ, mass) do nothing;
do $$
declare x record; c text; p numeric; ort text := 'Raum 2, Regal links';
begin
  for x in select * from (values
    -- Rollcontainer-Schubladen 39,5 × 50, EK offen
    ('AZ','395x175','23','G',1,null::numeric,'Rollcontainer-Schublade'),
    ('AZ','395x250','32','G',2,null,'Rollcontainer-Schublade'),
    ('AZ','395x100','24','G',1,null,'Rollcontainer-Schublade'),
    ('AZ','395x100','30','G',1,null,'Rollcontainer-Schublade, Schloss nachrüstbar'),
    ('AZ','395x175','30','G',4,null,'Rollcontainer-Schublade'),
    ('AZ','395x250','24','N',1,null,'frisch beschichtet, Schloss nachrüstbar'),
    ('AZ','395x350','30','G',1,null,'Rollcontainer-Schublade'),
    ('AZ','395x175','24','N',1,null,'frisch beschichtet, Schloss nachrüstbar'),
    -- Scheren
    ('HW-SC69',null,'SW','G',6,10,'Scharnier/Schere neue Generation'),
    ('HW-SCALT',null,'SW','G',6,10,'Liftomat, 3 links, 3 rechts; EK bitte bestätigen'),
    -- Tablare, je 10 €
    ('BVS','750x500','30','G',8,10,'verkürzt, Schwerlast, unter Ausziehtablar'),
    ('BSL','750x350','30','G',3,10,null),
    ('BV','750x500','30','G',2,10,'verkürzt, nicht Schwerlast'),
    ('BSL','750x500','33','G',6,10,null),
    ('BL','750x500','30','G',8,10,null),
    ('BL','750x250','30','G',4,10,null),
    ('BSZ','750x500','30','G',1,10,'Schlitzlöcher für Einschubtür von oben'),
    ('BV','750x500','29','G',2,10,'verkürzt für Unterauszug'),
    ('BL','750x500','29','G',5,10,null),
    ('BL','750x500','24','S',2,10,'eigentlich schwarz, weiß übersprüht'),
    -- Hängeregisterkörbe
    ('HR','350','30','G',5,2,'Hängeregisterkorb 35er'),
    ('HR','350','30','G',1,2.5,'Hängeregisterkorb 35er mit Rollen'),
    -- Glas
    ('ZG','750x350','GL','G',1,10,null),
    ('ZG','500x350','GL','G',1,10,null),
    ('GA','500x500','GL','G',1,20,'mit Chromecken'),
    ('GA','350x250','GL','G',1,10,'ohne Chromecken'),
    ('GA','350x150','GL','G',1,10,'ohne Chromecken'),
    ('HW-CEGS',null,'CR','G',1,null,'von zerbrochener Glastür 50 × 35'),
    ('HW-SCHL','239','CR','G',3,0.25,'Schlüsselnummer 239'),
    -- Schwerlastrahmen
    ('SLR','750x500','CR','G',3,5,'fertig verschraubt'),
    -- Rohre
    ('RO','750','CR','S',36,5,'Tonne, aufbereitbar'),
    ('RO','750','CR','G',9,5,'mit USM-Sticker'),
    ('RS','750','CR','G',2,5,'mit USM-Sticker'),
    ('RO','500','CR','G',10,5,'mit USM-Sticker'),
    ('RO','350','CR','G',4,5,'mit USM-Sticker'),
    ('RO','250','CR','G',4,5,'mit USM-Sticker'),
    ('RO','395','CR','G',1,5,'mit USM-Sticker'),
    ('RO','250','CR','G',22,5,null)
  ) v(typ, mass, farbe, zustand, n, preis, notiz) loop
    c := teil_code(x.typ, x.mass, x.farbe, x.zustand);
    select durchschnittspreis into p from teil where code = c;
    perform inventur(c, x.n, coalesce(x.preis, nullif(p, 0), 0), ort);
    if x.notiz is not null then update teil set notiz = concat_ws(' · ', notiz, x.n || '× ' || x.notiz) where code = c; end if;
  end loop;
end $$;
select round(sum(wert)) ek_wert, sum(bestand) stueck from lager_health;
