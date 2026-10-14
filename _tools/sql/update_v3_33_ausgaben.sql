-- v3.33: Kategorie und Buchungstext je Ausgabe (für Steuerberater), RPC zahlung_kategorie
alter table zahlung add column if not exists kategorie text;
alter table zahlung add column if not exists buchungstext text;
-- Funktion zahlung_kategorie(p_id, p_kategorie, p_text, p_wer): setzt Kategorie/Text, Nicht-Wareneinkauf -> status ignoriert
