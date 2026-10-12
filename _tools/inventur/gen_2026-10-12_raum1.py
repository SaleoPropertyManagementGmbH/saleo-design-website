import json
TYP = "E Beschläge und Montageteile"
Q = "von Samuel beschrieben, Inventur 12.10.2026"
neue_typen = [
 ("HW-HM","Halbmond (Tablarhalter)","SW"),("HW-KLE","Klemme","SW"),
 ("HW-USL","Universalschloss komplett","SW"),
 ("HW-SA","Schloss alte Generation","SW"),("HW-SAK","Knauf alte Generation (nur Knauf)","SW"),
 ("HW-SKA","Schlosskasten alte Generation (Kunststoff)","SW"),("HW-SLA","Schlosslasche alte Generation (Metall)","SW"),
 ("HW-SN","Schloss neue Generation (ohne Schlosskasten)","SW"),("HW-SKN","Schlosskasten neue Generation","SW"),
 ("HW-SKNP","Schlosskasten neue Generation, nur Kunststoffteil","SW"),
 ("HW-SG","Glastürschloss (Paar)","SW"),("HW-SZG","Schließzylinder Glastür","SW"),
 ("HW-SRZ","Rollcontainerschloss, nur Zylinder","SW"),("HW-SR","Rollcontainerschloss komplett","SW"),
 ("HW-SCHL","Schlüssel (Maß = Schlüsselnummer)","CR"),
 ("HW-WV","Wandverankerungsset (18622)","SW"),("HW-BAB","Befestigungsset Schere Typ B (18473)","SW"),
 ("HW-GEA","Glasecke alte Glasvitrine","CR"),("HW-ABS","Ablageschrauben-Set (6 Stück) für Glasplatte","CR"),
 ("HW-WAN","Winkel Ausziehtablar zu Front, neue Generation","SW"),("HW-TWALT","T-Winkel Auszugswanne zu Front, alte Generation","SW"),
 ("HW-MWS","Montagewinkel Scharnier neue Generation (Tür)","SW"),("HW-PSH","Kunststoffteil zwischen Halbmond und Scharnier","SW"),
 ("HW-CEG","Ecke Glastablar neue Generation",None),("HW-CEGS","Ecke mit Scharniernippel (Glastür)",None),
 ("HW-CEGSL","Ecke mit Scharniernippel, einfache Ausführung","CR"),("HW-EKS","Eckenschutz Glastür (ohne Haltefunktion)","SW"),
 ("HW-TK","Trapezkugel","CR"),("HW-AMS","Montagesteg Auszug neue Generation (Maß = Tiefe)","SW"),
 ("HW-FBS","Federbandscharnier neue Generation (ohne Feder)","SW"),
 ("HW-GTS","Garagentor-Scharnier","SW"),("HW-GTB","Befestigungssteg Garagentor-Scharnier (Maß = Seite)","SW"),
 ("HW-GTP","Kunststoffteil Garagentor-Schlitten","SW"),("HW-GTM","Montageschiene Garagentor (Maß = Seite)","SW"),
 ("HW-GTK","Kupplungssteg Garagentor (14983)","SW"),("HW-GTSET","Garagentor-Beschlagset komplett","SW"),
]
# (typ, mass, farbe, zustand, menge, preis, notiz)
P = []
def a(*x): P.append(x)
# USM-Bestellung (neu, EK noch offen)
U = "USM-Bestellung, EK offen"
for t,m,f,n in [("KL","500x175","25",1),("BL","350x175","25",1),("BP","350x175","25",1),("BL","350x250","25",2),("BL","350x250","29",5),
  ("KL","350x350","26",2),("BL","350x350","26",10),("BP","350x350","26",6),("BP","350x100","26",16),("BL","350x350","25",1),
  ("BL","500x350","29",2),("BL","350x250","24",1),("BL","500x350","24",2),("BL","500x350","33",1)]:
    a(t,m,f,"N",n,0,U)
# Raum 1
a("CO",None,None,"G",800,round((400*1.65+400*1.0)/800,2),"ca. 800; 400 zu 1,65 brutto, 400 zu 1,00 (privat)")
a("KU",None,None,"G",180,round((150*2.70+30*4.0)/180,2),"150 ohne Logo zu 2,70, 30 mit Logo zu 4,00")
a("RO","350",None,"G",6,7,None)
a("FU",None,None,"G",150,2,"Fußgröße 23/36 noch offen")
a("HW-HM",None,None,"G",200,0.02,"Schätzung")
a("HW-KLE",None,None,"G",300,0.02,"Schätzung")
a("HW-USL",None,None,"G",23,13,None)
a("HW-GTB","rechts",None,"G",4,5,"Set 22,50 aufgeteilt (Schätzung)")
a("HW-GTS",None,None,"G",3,5,"Set 22,50 aufgeteilt (Schätzung)")
a("HW-GTP",None,None,"G",2,1.25,"Set 22,50 aufgeteilt (Schätzung)")
a("HW-SA",None,None,"G",14,8,None)
a("HW-SA",None,None,"G",4,1,"nachgefunden, max. 1 €")
a("HW-SN",None,None,"G",35,8,None)
a("HW-SKN",None,None,"G",5,4,None)
a("HW-SKA",None,None,"G",27,0.05,"9 + 17 + 1, EK 5 Cent")
a("HW-SKNP",None,None,"G",1,2,None)
a("HW-SG",None,None,"G",2,4,"2 Paar")
a("HW-SRZ",None,None,"G",4,1,"EK geschätzt")
a("HW-SR",None,None,"G",5,5,"1 + 2 Paar")
a("HW-SZG",None,None,"G",2,1,"EK geschätzt")
a("HW-WV",None,None,"N",2,5,"originalverpackt")
a("HW-BAB",None,None,"N",6,3,"originalverpackt")
a("HW-GEA",None,None,"G",25,0.12,"ca. 25 Stück, zusammen 3 €")
a("HW-ABS",None,None,"G",1,2,None)
a("HW-WAN",None,None,"G",28,3,None)
a("HW-TWALT",None,None,"G",26,1.5,None)
a("HW-PSH",None,None,"G",40,0.25,"ca. 40, EK geschätzt")
a("HW-CEG",None,"CR","G",35,3.5,None)
a("HW-CEGS",None,"CR","G",1,3.5,None)
a("HW-CEGSL",None,None,"G",5,1,None)
a("HW-CEG",None,"SW","G",6,1,None)
a("HW-CEGS",None,"SW","G",2,1,None)
a("HW-EKS",None,None,"G",2,0.5,None)
a("HW-TK",None,None,"G",2,0.5,None)
a("HW-SLA",None,None,"G",10,1,None)
a("HW-SAK",None,None,"G",9,0.5,None)
a("HW-AMS","350",None,"G",6,8.5,"4 + 2 schwarz")
a("HW-AMS","500",None,"G",2,8.5,"1 Paar schwarz")
a("HW-GTS",None,None,"G",2,5,"1 Paar, nur Metall, ohne Kunststoffteile")
a("HW-GTP",None,None,"G",2,1.25,"1 Paar")
a("HW-TE500",None,None,"G",2,12.15,"Paare")
a("HW-TE350",None,None,"G",3,12.15,"Paare, dazu 1 einzelnes rechtes")
a("HW-FBS",None,None,"G",2,5,None)
a("HW-BAAT",None,None,"N",1,2,"originalverpackt, 18476")
# Garagentor-Kiste 2, an Kunden verkauft
K = "Garagentor-Kiste, an Kunden verkauft"
a("HW-GTM","rechts",None,"G",4,5,K); a("HW-GTS",None,None,"G",3,5,K); a("HW-GTP",None,None,"G",2,1.25,K)
a("HW-GTSET",None,None,"G",2,22.5,K); a("HW-GTP",None,None,"G",2,1.25,K+", ohne Gegenstück"); a("HW-GTK",None,None,"G",2,2,K)
keys = {"201":1,"202":2,"203":5,"205":2,"207":1,"210":2,"212":2,"214":2,"215":1,"220":2,"225":1,"226":5,"229":1,"230":3,"231":11,
 "241":5,"242":8,"246":6,"251":2,"260":3,"273":2,"248":10,"292":10}
for k,v in keys.items(): a("HW-SCHL",k,None,"G",v,0.25,"Schlüsselnummer "+k)
res = [("Kunde USM-Bestellung (goldgelb)",[("KL","500x175","25","N",1),("BL","350x175","25","N",1),("BP","350x175","25","N",1),("BL","350x250","25","N",2),("BL","350x350","25","N",1)]),
       ("Samuel privat (orange)",[("KL","350x350","26","N",2),("BL","350x350","26","N",10),("BP","350x350","26","N",6),("BP","350x100","26","N",16)]),
       ("Kunde Garagentor-Kiste",[("HW-GTM","rechts",None,"G",4),("HW-GTS",None,None,"G",3),("HW-GTP",None,None,"G",4),("HW-GTSET",None,None,"G",2),("HW-GTK",None,None,"G",2)])]
def q(v): return "null" if v is None else "'"+str(v).replace("'","''")+"'"
sql=["do $$ declare c text; begin"]
for code,bez,f in neue_typen:
    sql.append(f"insert into teiltyp (code, gruppe, bezeichnung, masse, standardfarbe, symmetrisch, mit_generation, quelle_status) values ({q(code)}, {q(TYP)}, {q(bez)}, '{{}}', {q(f)}, false, false, {q(Q)}) on conflict (code) do nothing;")
for t,m,f,z,n,p,no in P:
    sql.append(f"c := teil_code({q(t)}, {q(m)}, {q(f)}, {q(z)}); perform inventur(c, {n}, {p}, 'Raum 1');" + (f" update teil set notiz = concat_ws(' | ', notiz, {q(no)}) where code = c;" if no else ""))
for auf,items in res:
    for t,m,f,z,n in items:
        sql.append(f"perform reserviere({q(auf)}, teil_code({q(t)}, {q(m)}, {q(f)}, {q(z)}), {n});")
sql.append("end $$;")
sql.append("select count(*) teile, sum(bestand) stueck, round(sum(bestand*durchschnittspreis),2) wert from teil where bestand > 0;")
open('/home/claude/saleo-design-ops/inventur/2026-10-12_raum1.sql','w').write("\n".join(sql))
print(len(P), sum(x[4] for x in P), round(sum(x[4]*x[5] for x in P),2))
