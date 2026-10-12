import json
B=json.load(open('bom.json'))
MP={'KU':3,'CO':2,'FU':4,'RO':{'100':5,'250':10,'350':12,'500':14,'750':18},'BL':{'350x350':30,'750x350':45,'500x350':32,'500x500':38,'750x500':50,'350x250':25,'500x250':30},
    'BP':{'350x350':30,'500x350':32},'BK':{'500x350':40},'BV':{'750x350':40},'AT':{'750x350':60},'ER':{'750x350':30},'KL':{'750x350':125,'500x350':85,'500x250':75},'AZ':{'750x350':95},'ST':{'500x350':60}}
def wert(typ,mass):
    v=MP.get(typ)
    if isinstance(v,dict): return v.get(mass,20)
    return v if v else 1
def rows(k):
    d={}
    for r in B[k]['rows']: d[r['code']]=dict(typ=r['typ'],mass=r['mass'],farbe=r['farbe'],qty=r['qty'])
    return d
def adj(d,code,delta,typ=None,mass=None,farbe=None):
    if code not in d: d[code]=dict(typ=typ,mass=mass,farbe=farbe,qty=0)
    d[code]['qty']+=delta
    if d[code]['qty']<=0: del d[code]
S={}
d=rows('mg')
adj(d,'RO-100-CR-G',4,'RO','100','CR'); adj(d,'RO-350-CR-G',2); adj(d,'KU-CR-G',4); adj(d,'CO-CR-G',12); S['mg']=d
d=rows('gr1'); adj(d,'BL-500x350-28-G',-1); adj(d,'BL-750x350-28-G',-1); adj(d,'HW-BS-SW-G',-2); S['gr1']=d
d=rows('gr2')
for c in d: d[c]['qty']*=2
for c,n in [('KU-CR-G',-8),('CO-CR-G',-20),('RO-250-CR-G',-2),('RO-350-CR-G',-4),('RO-500-CR-G',-4),('FU-SW-G',-2),('BL-500x250-28-G',-1),('BL-500x350-28-G',-2)]: adj(d,c,n)
S['gr2']=d
for k in ['sw1','sw2','sw3','ct','sw4']: S[k]=rows(k)
d=rows('sw5'); adj(d,'BL-500x350-30-G',-1); adj(d,'BK-500x350-30-G',1,'BK','500x350','30'); adj(d,'BL-500x500-30-G',-1); S['sw5']=d
d=rows('sw6'); adj(d,'BL-500x350-30-G',-2); adj(d,'BP-500x350-30-G',2,'BP','500x350','30'); S['sw6']=d
INFO={
 'mg':('Sideboard 2×3 mittelgrau, 2 Auszüge, 4 perforierte Klappen',1300,'32','150 × 109 × 37','Klappen perforiert (Garagentor-Optik). Oberste Reihe ohne Rückwand. Je Seite Ausleger aus 2 Rohren 100 und 1 Rohr 350 (Taschenablage).'),
 'gr1':('Hochbau grün 1,25 m, unten offenes Gestell 50 hoch, oben 2 Klappen',400,'28','127 × 89 × 37','Unteres Fach 50 hoch nur Gestänge, ohne Böden und Seiten.'),
 'gr2':('Schrank grün doppelseitig 50 × 70, Prospekthalter und Klappen 50 × 25',850,'28','52 × 99 × 72','Zwei Einheiten 50 × 35 Rückwand an Rückwand. Je Seite 2 Schrägtablare (Prospekthalter) und oben Klappe 50 × 25. Aufbau bitte prüfen.'),
 'sw1':('Sideboard schwarz T50, 3 Klappen (2 × 75, 1 × 50)',550,'30','127 × 74 × 52','Über der 50er Klappe nur Deckel.'),
 'sw2':('Sideboard schwarz 2 m, 4 Klappen und 4 offene 25er Fächer',850,'30','202 × 74 × 37','Mitte 4 offene Fächer 25 × 35, ohne Rückwand.'),
 'sw3':('Sideboard schwarz 2×2, 4 Klappen',800,'30','152 × 74 × 37',None),
 'ct':('Couchtisch 75 × 50 anthrazit, offen',0,'33','77 × 39 × 52','EK offen. Böden als Schwerlasttablare.'),
 'sw4':('Regal schwarz 75 × 35, 2 Fächer offen',300,'30','77 × 74 × 37','Seiten mit Innentablaren (gelocht).'),
 'sw5':('Board schwarz 50 × 50 mit Klappe und Rückwand-Aufsatz',280,'30','52 × 74 × 52','Oben nur Rückwand mit Kabeldurchlass, Seiten und Deckel offen.'),
 'sw6':('Regal schwarz 75 × 50, 2 Fächer offen',300,'30','77 × 74 × 52','Links Außentablare, rechts Innentablare.'),
}
q=lambda v:"null" if v is None else "'"+str(v).replace("'","''")+"'"
out=["do $$ declare m uuid; begin"]
summary=[]
for k,(name,preis,farbe,masse,notiz) in INFO.items():
    teile=[]
    for c,e in S[k].items():
        typ=e['typ']; mass=e['mass']
        if c.startswith('HW-KS'): t={'typ':'HW-KS','farbe':e['farbe']}
        elif typ=='HW': t={'typ':'HW-'+mass,'farbe':'SW'}
        else:
            t={'typ':typ,'farbe':e['farbe']}
            if mass: t['mass']=mass
        t.update(zustand='G',menge=e['qty'],wert=wert(typ,mass) if typ!='HW' else 1)
        teile.append(t)
    summary.append((name,preis,sum(t['menge'] for t in teile)))
    daten=json.load(open(f'{k}.json'))
    out.append(f"  m := fertigmoebel_einkauf(p_name => {q(name)}, p_preis => {preis}, p_teile => {q(json.dumps(teile,ensure_ascii=False))}::jsonb, p_farbe => {q(farbe)}, p_zustand => 'G', p_benzin => 0, p_fahrzeug => 0, p_sonstige => 0, p_quelle => 'Inventur Büro (Plaud 12.10.)', p_datum => current_date, p_masse => {q(masse)}, p_lagerort => 'Büro', p_inserat => null, p_daten => {q(json.dumps(daten,ensure_ascii=False))}::jsonb, p_notiz => {q(notiz)}, p_kategorie => null);")
    out.append("  update moebel set einsatz = 'buero' where id = m;")
out.append("end $$;")
out.append("select m.name, m.einsatz, count(mt.*) pos, sum(mt.menge) teile from moebel m left join moebel_teil mt on mt.moebel_id=m.id where m.lagerort='Büro' group by 1,2;")
open('buero.sql','w').write("\n".join(out))
for s in summary: print(s)
