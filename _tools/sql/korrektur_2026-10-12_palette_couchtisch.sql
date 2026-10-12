-- Korrektur 12.10.2026 (Samuel 19:25): Preise Beschichter-Palette, zweiter Couchtisch 100 €, rote 50 × 17,5 gesamt 2, „Tür 50 × 75“ war ein 75 × 50 Tablar
do $$
declare x record; m uuid; c text; ort_hw text := 'Raum 3, an den Türen auf der Beschichter-Palette';
begin
  -- Palette: Türen 40 € je Stück; die 10 alten 75 × 35 hatten Schloss, Schlosskasten und Lasche dran: 34 + 4 + 1 + 1
  for x in select * from (values
    ('KL-750x350-SO-S-A', 34::numeric), ('KL-750x350-SO-S', 40), ('KL-500x350-SO-S', 40), ('KL-500x350-SO-S-A', 40),
    ('BL-750x350-SO-S', 12.5), ('BL-350x350-SO-S', 12.5), ('BL-500x350-SO-S', 12.5), ('BSL-750x500-SO-S', 12.5)
  ) v(code, preis) loop
    update teil set durchschnittspreis = x.preis where code = x.code;
    update lagerbewegung set preis_stueck = x.preis, durchschnitt_danach = x.preis where teil = x.code and art = 'inventur' and coalesce(preis_stueck, 0) = 0;
  end loop;
  perform inventur(teil_code('HW-SA', null, 'SW', 'G', 'N'), 10, 4, ort_hw);
  perform inventur(teil_code('HW-SKA', null, 'SW', 'G', 'N'), 10, 1, ort_hw);
  perform inventur(teil_code('HW-SLA', null, 'SW', 'G', 'N'), 10, 1, ort_hw);
  update teil set notiz = replace(notiz, '(eine als 50 × 75 diktiert)', '') where code = 'KL-750x350-SO-S';
  -- „Tür 50 × 75“ gab es nicht: die letzten beiden Teile auf der Palette waren 75 × 50 Tablare
  perform inventur('KL-750x350-SO-S', -1, 0, null);
  perform inventur('BSL-750x500-SO-S', 1, 12.5, 'Raum 3, Palette Beschichter');
  update teil set notiz = concat_ws(' · ', notiz, '2 × 75 × 50 Tablar ganz hinten auf der Palette') where code = 'BSL-750x500-SO-S';
  -- rote 50 × 17,5: insgesamt 2
  perform inventur('BL-500x175-23-G', -2, 0, null);
  -- zweiter Couchtisch: EK 100 € statt 50 €, die zusätzlichen 50 € gleich verteilt wie beim Einkauf
  select m2.id into m from moebel m2 where m2.name like 'Couchtisch 75 × 50 mittelgrau%';
  for x in select l.teil, sum(l.menge * l.preis_stueck) extra from lagerbewegung l join moebel mm on mm.einkauf_id = l.beleg_id where mm.id = m group by l.teil loop
    update teil set durchschnittspreis = round(durchschnittspreis + x.extra / nullif(bestand, 0), 2) where code = x.teil;
  end loop;
  update einkauf e set notiz = replace(e.notiz, 'EK wie der anthrazitfarbene angenommen (50 €), bitte prüfen.', 'EK 100 €.') from moebel mm where mm.id = m and e.id = mm.einkauf_id;
  update moebel set notiz = replace(notiz, 'EK wie der anthrazitfarbene angenommen (50 €), bitte prüfen.', 'EK 100 €.') where id = m;
end $$;
select round(sum(wert)) ek_wert, sum(bestand) stueck from lager_health;
select code, bestand, durchschnittspreis from teil where lagerort like '%Beschichter%' and bestand > 0 order by code;
select round(sum(mt.menge * t.durchschnittspreis), 2) couchtisch2_wert from moebel_teil mt join teil t on t.code = mt.teil join moebel m on m.id = mt.moebel_id where m.name like 'Couchtisch 75 × 50 mittelgrau%';
