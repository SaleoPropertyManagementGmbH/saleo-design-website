-- Inventur 12.10. Raum 3, Antworten Samuel 19:08 + Palette Beschichter
update teiltyp set masse = masse || array['750x175'] where code = 'BK' and not ('750x175' = any(masse));
update teiltyp set masse = masse || array['500x225'] where code = 'BL' and not ('500x225' = any(masse));
do $$
declare x record; c text; p numeric; ort text := 'Raum 3, Paletten'; pal text := 'Raum 3, Palette Beschichter';
begin
  for x in select * from (values
    ('KL','750x350','24','N','A',1,45::numeric,'frisch beschichtet'::text,null::text),
    ('KL','500x350','24','G','A',1,15,'mit aufgeschraubtem Griff',null),
    ('KL','750x350','30','N','A',2,40,'frisch beschichtet',null),
    ('KL','750x350','24','G','N',1,30,null,null),
    ('KL','750x350','34','G','N',2,20,null,null),
    ('BL','750x350','30','G','N',2,15,null,null),
    ('AT','750x350','30','G','N',3,15,'einzelne Wanne',null),
    ('BK','750x175','30','G','N',1,17,'Kabelauslass in der Mitte',null),
    ('BV','750x350','30','G','N',1,10,null,null),
    ('BV','750x350','32','G','N',1,10,null,null),
    ('BL','350x250','30','G','A',2,10,null,null),
    ('BL','500x175','23','G','N',2,15,null,null),
    ('BL','500x225','30','G','A',1,10,null,null),
    ('BL','500x225','30','G','N',2,10,null,null),
    ('BV','750x350','32','G','A',1,10,null,null),
    -- Palette Beschichter: Farbe egal (wird neu beschichtet), EK offen
    ('KL','750x350','SO','S','A',10,null,'Palette Beschichter, mit Universalschloss, Schlosskasten, Lasche (aktuell weiß)','P'),
    ('BL','750x350','SO','S','N',7,null,'Palette Beschichter','P'),
    ('BSL','750x500','SO','S','N',1,null,'Palette Beschichter','P'),
    ('KL','750x350','SO','S','N',4,null,'Palette Beschichter (eine als 50 × 75 diktiert)','P'),
    ('BL','350x350','SO','S','N',5,null,'Palette Beschichter','P'),
    ('BL','500x350','SO','S','N',4,null,'Palette Beschichter','P'),
    ('KL','500x350','SO','S','N',1,null,'Palette Beschichter','P'),
    ('KL','500x350','SO','S','A',1,null,'Palette Beschichter','P')
  ) v(typ, mass, farbe, zustand, gen, n, preis, notiz, o) loop
    c := teil_code(x.typ, x.mass, x.farbe, x.zustand, x.gen);
    select durchschnittspreis into p from teil where code = c;
    perform inventur(c, x.n, coalesce(x.preis, nullif(p, 0), 0), case when x.o = 'P' then pal else ort end);
    if x.notiz is not null then update teil set notiz = concat_ws(' · ', notiz, x.n || '× ' || x.notiz) where code = c; end if;
  end loop;
  -- 2 einzelne Wannen waren vorher als lichtgrau gebucht, gehören zu den schwarzen: korrigiert über 3 schwarze oben
end $$;
select round(sum(wert)) ek_wert, sum(bestand) stueck from lager_health;
select code, bestand from teil where lagerort like '%Palette Beschichter%' order by code;
