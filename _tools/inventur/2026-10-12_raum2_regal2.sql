-- Inventur 12.10. Raum 2, Regal 2 (Plaud 17:50, 10 Min.)
insert into teiltyp (code, gruppe, bezeichnung, masse, symmetrisch, mit_generation, quelle_status, hinweis) values
 ('BRC','B Metall- und Glaselemente','Rollcontainer-Tablar (Aussparungen für das Gestell, an das der Schlitten geschraubt wird)', array['500x395'], true, false, 'Samuel 12.10.2026', null)
on conflict (code) do nothing;
insert into marktpreis (typ, mass, preis, quelle) values ('BRC','*',30,'geschätzt') on conflict (typ, mass) do nothing;
update teiltyp set masse = masse || array['250x250','350x250'] where code = 'BK' and not ('250x250' = any(masse));
do $$
declare x record; c text; p numeric; ort text := 'Raum 2, Regal 2';
begin
  for x in select * from (values
    ('BRC','500x395','30','G','N',2,10::numeric,null::text),
    ('BRC','500x395','23','G','N',2,10,null),
    ('BL','395x350','24','G','N',1,10,null),
    ('BL','350x250','30','G','N',5,10,'3 + 2 aus Diktat, bitte prüfen'),
    ('BL','350x150','23','G','N',2,10,null),
    ('BP','350x250','30','G','N',3,10,null),
    ('BK','250x250','30','G','N',2,10,'Außentablar mit Kabeldurchlass, Maß 25 × 25 bitte prüfen'),
    ('BL','500x350','30','G','N',34,17,'3 + 33 diktiert, davon 2 Innentablare abgezogen'),
    ('BL','500x350','29','S','N',1,17,null),
    ('BP','500x350','30','G','N',9,17,'7 + 2 aus den Außentablaren'),
    ('BL','500x350','25','G','N',6,17,'Zustand sehr gut'),
    ('BL','500x350','30','N','N',12,17,null),
    ('BL','500x350','29','G','N',3,17,null),
    ('AT','750x500','30','G','N',7,15,'nur Wanne'),
    ('AT','750x500','24','G','N',3,15,'nur Wanne'),
    ('BSZ','750x350','30','G','N',4,10,'2 mit Schlossschlitz für Einschubtür, 2 zusätzlich mit Kerben für Stopper; Farbe/EK bitte prüfen'),
    ('AT','750x350','30','G','N',5,15,'aus Komplettset neue Gen. 40 €; Farbe bitte prüfen'),
    ('HW-TE350',null,'SW','G','N',10,7.5,null),
    ('HW-AMS','350','SW','G','N',10,5,null),
    ('AT','750x500','29','G','A',1,6,'Komplettset alte Gen. 10 €'),
    ('HW-ASALT',null,'SW','G','N',2,2,'aus Komplettset alte Gen.'),
    ('BL','350x350','29','N','N',6,33,'neu vom Händler, netto'),
    ('BL','350x350','26','G','N',2,15,null),
    ('BL','350x350','30','G','N',18,17,null),
    ('BL','350x350','33','G','N',13,15,null),
    ('BP','350x350','30','G','N',23,15,null),
    ('BL','500x500','33','G','N',2,10,null),
    ('BL','500x500','30','G','N',3,17,null),
    ('BL','500x500','30','N','N',8,17,null),
    ('BL','500x500','32','G','N',1,10,null),
    ('BL','500x500','24','G','N',2,5,'mit weißer Beschichtung'),
    ('BL','750x500','30','N','N',3,17,null),
    ('BPF','750x350','30','N','N',1,17,'mit 2 Kabelauslässen'),
    ('BL','750x350','30','N','N',1,17,null),
    ('KL','750x175','30','S','N',1,20,'große Beule'),
    ('ST','750x350','30','G','N',3,10,'ohne Halbmonde und Klemmen'),
    ('BL','750x350','30','G','N',52,17,null),
    ('BL','750x350','32','G','N',2,17,null),
    ('BL','750x350','29','G','N',18,10,null)
  ) v(typ, mass, farbe, zustand, gen, n, preis, notiz) loop
    c := teil_code(x.typ, x.mass, x.farbe, x.zustand, x.gen);
    select durchschnittspreis into p from teil where code = c;
    perform inventur(c, x.n, coalesce(x.preis, nullif(p, 0), 0), ort);
    if x.notiz is not null then update teil set notiz = concat_ws(' · ', notiz, x.n || '× ' || x.notiz) where code = c; end if;
  end loop;
end $$;
select round(sum(wert)) ek_wert, sum(bestand) stueck, round(sum(marktwert)) markt from lager_health;
