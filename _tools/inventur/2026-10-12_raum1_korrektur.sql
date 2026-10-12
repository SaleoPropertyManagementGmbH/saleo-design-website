do $$
declare c text; m uuid;
begin
  -- 1. Netto-Einkaufspreise der USM-Bestellung
  update teil t set durchschnittspreis = v.p, notiz = replace(t.notiz, 'USM-Bestellung, EK offen', 'USM-Bestellung (netto)')
  from (values ('KL-500x175-25-N',78.02),('BL-350x175-25-N',29.33),('BP-350x175-25-N',29.33),('BL-350x250-25-N',29.78),('BL-350x250-29-N',29.78),
    ('KL-350x350-26-N',63.15),('BL-350x350-26-N',29.78),('BP-350x350-26-N',29.78),('BP-350x100-26-N',27.64),('BL-350x250-24-N',29.78),
    ('BL-500x350-24-N',34.43),('BL-500x350-33-N',34.43),('BL-500x350-29-N',34.43)) v(code, p)
  where t.code = v.code;
  update lagerbewegung l set preis_stueck = t.durchschnittspreis, durchschnitt_danach = t.durchschnittspreis
  from teil t where l.teil = t.code and l.art = 'inventur' and l.preis_stueck = 0 and t.notiz like '%USM-Bestellung (netto)%';
  -- goldgelbes Tablar ist 500 x 350, nicht 350 x 350
  perform inventur('BL-350x350-25-N', -1, 0, null);
  update teil set reserviert = 0, notiz = 'Korrektur: war 500 x 350' where code = 'BL-350x350-25-N';
  c := teil_code('BL', '500x350', '25', 'N'); perform inventur(c, 1, 34.43, 'Raum 1');
  update teil set reserviert = reserviert + 1, notiz = 'USM-Bestellung (netto)' where code = c;
  update reservierung set teil = c where teil = 'BL-350x350-25-N' and not aufgeloest;
  -- 2. zwei neue Tablare 750 x 350 schwarz
  c := teil_code('BL', '750x350', '30', 'N'); perform inventur(c, 2, 17, 'Raum 1');
  -- 3. Nivellierfüße sind 36 mm
  perform inventur('FU-SW-G', -150, 2, null);
  c := teil_code('FU', '36', null, 'G'); perform inventur(c, 150, 2, 'Raum 1');
  -- 4. Montagewinkel Scharnier neue Generation: ca. 37 Sets (je 2 Winkel + 2 Kunststoffteile)
  c := teil_code('HW-MWS', null, null, 'G'); perform inventur(c, 37, 2.5, 'Raum 1');
  update teil set notiz = 'ca. 35 bis 40 Sets, je 2 Winkel zu 1 € + 2 Kunststoffteile zu 0,25 €' where code = c;
  -- 8. Connectoren netto: 400 zu 1,65 brutto = 1,39 netto, 400 zu 1,00 privat
  update teil set durchschnittspreis = 1.19, notiz = 'ca. 800; 400 zu 1,39 netto, 400 zu 1,00 (privat)' where code = 'CO-CR-G';
  -- 7. Gestelle und Rollcontainer: Teile einbuchen und als zusammengebaut festhalten
  perform inventur('KU-CR-G', 32, 2.92, 'Raum 1');
  c := teil_code('RO', '500', null, 'G'); perform inventur(c, 18, 7, 'Raum 1');
  perform inventur('RO-350-CR-G', 22, 7, 'Raum 1');
  c := teil_code('RO', '395', null, 'G'); perform inventur(c, 6, 7, 'Raum 1');
  perform inventur('CO-CR-G', 2, 1.19, 'Raum 1');
  c := teil_code('AZ', '500x350', '23', 'G'); perform inventur(c, 1, 0, 'Raum 1'); update teil set notiz = 'EK offen' where code = c;
  c := teil_code('BL', '500x395', '23', 'G'); perform inventur(c, 2, 0, 'Raum 1'); update teil set notiz = 'EK offen' where code = c;
  m := fertigmoebel_anlegen('Leergestell 3 Fächer 50 × 35, 35 hoch', '{}'::jsonb,
    '[{"teil":"KU-CR-G","menge":16},{"teil":"RO-500-CR-G","menge":12},{"teil":"RO-350-CR-G","menge":16}]'::jsonb,
    '153 × 37 × 37', 'CR', 'G', 'Raum 1', null, null, 'Nur Gestell, ohne Tablare');
  m := fertigmoebel_anlegen('Einzelrahmen 50 × 35', '{}'::jsonb,
    '[{"teil":"KU-CR-G","menge":4},{"teil":"RO-500-CR-G","menge":2},{"teil":"RO-350-CR-G","menge":2},{"teil":"CO-CR-G","menge":2}]'::jsonb,
    null, 'CR', 'G', 'Raum 1', null, null, 'Mit 2 Connectoren');
  m := fertigmoebel_anlegen('Rollcontainer rot 50 × 40, zerlegt', '{}'::jsonb,
    '[{"teil":"KU-CR-G","menge":12},{"teil":"RO-500-CR-G","menge":4},{"teil":"RO-395-CR-G","menge":6},{"teil":"RO-350-CR-G","menge":4},{"teil":"AZ-500x350-23-G","menge":1},{"teil":"BL-500x395-23-G","menge":2}]'::jsonb,
    null, '23', 'G', 'Raum 1', null, null, 'Unvollständig: Rohre 50er für den oberen Rahmen fehlen, zweite Schublade fehlt. 2 Auszüge vorhanden.');
end $$;
select count(*) teile, sum(bestand) stueck, round(sum(bestand*durchschnittspreis),2) wert from teil where bestand > 0;
