-- =====================================================================
--  03_query_analisi.sql – Trasporto pubblico a Napoli 🚌
--  Database: trasporti_napoli.db (SQLite)
--  Giorno tipo: mercoledì 18 ottobre 2023 (vista v_passaggi_giorno_tipo)
--  "Passaggio" = un bus, un treno o una funicolare che si ferma a una fermata
-- =====================================================================


-- =====================================================================
--  0️⃣ CONTROLLI SUI DATI
-- =====================================================================

-- Q0.1 📋 Quante righe ha ogni tabella del GTFS
SELECT 'linee' AS tabella, COUNT(*) AS righe FROM linee
UNION ALL SELECT 'corse', COUNT(*) FROM corse
UNION ALL SELECT 'fermate', COUNT(*) FROM fermate
UNION ALL SELECT 'orari', COUNT(*) FROM orari
UNION ALL SELECT 'giorni di calendario', COUNT(DISTINCT data) FROM calendario;

-- Q0.2 🔍 Corse senza orari e orari con una fermata che non esiste
SELECT (SELECT COUNT(*) FROM corse c WHERE NOT EXISTS (SELECT 1 FROM orari o WHERE o.trip_id = c.trip_id)) AS corse_senza_orari,
       (SELECT COUNT(*) FROM orari o WHERE o.stop_id NOT IN (SELECT stop_id FROM fermate))                AS orari_fermata_sconosciuta,
       (SELECT COUNT(*) FROM fermate WHERE id_quartiere IS NULL)                                         AS fermate_fuori_napoli;

-- Q0.3 📅 Quante corse ci sono ogni giorno della settimana (ottobre 2023)
SELECT k.data,
       CASE strftime('%w', substr(k.data, 1, 4) || '-' || substr(k.data, 5, 2) || '-' || substr(k.data, 7, 2))
            WHEN '0' THEN 'domenica' WHEN '6' THEN 'sabato' ELSE 'feriale' END AS tipo_giorno,
       COUNT(*) AS corse
FROM calendario k
JOIN corse c ON c.service_id = k.service_id
WHERE k.data BETWEEN '20231016' AND '20231022'
GROUP BY k.data
ORDER BY k.data;


-- =====================================================================
--  1️⃣ DOVE CI SONO PIÙ FERMATE E LINEE?
-- =====================================================================

-- Q1.1 🚏 Fermate per quartiere: totale, ogni 10.000 abitanti e ogni km²
SELECT q.quartiere, q.abitanti,
       COUNT(f.stop_id)                                      AS fermate,
       ROUND(COUNT(f.stop_id) * 10000.0 / q.abitanti, 1)     AS fermate_10mila_ab,
       ROUND(COUNT(f.stop_id) / q.area_km2, 1)               AS fermate_km2,
       RANK() OVER (ORDER BY COUNT(f.stop_id) DESC)          AS posizione
FROM quartieri q
LEFT JOIN fermate f ON f.id_quartiere = q.id_quartiere
     AND EXISTS (SELECT 1 FROM v_passaggi_giorno_tipo v WHERE v.stop_id = f.stop_id)
GROUP BY q.id_quartiere
ORDER BY fermate DESC;

-- Q1.2 🔢 Quante linee diverse passano in ogni quartiere
SELECT q.quartiere, COUNT(DISTINCT v.route_id) AS linee,
       GROUP_CONCAT(DISTINCT CASE WHEN v.modo <> 'Bus' THEN v.linea END) AS metro_e_funicolari
FROM quartieri q
LEFT JOIN v_passaggi_giorno_tipo v ON v.id_quartiere = q.id_quartiere
GROUP BY q.id_quartiere
ORDER BY linee DESC;

-- Q1.3 🏛️ Fermate e passaggi per municipalità
SELECT m.nome AS municipalita, SUM(q.abitanti) AS abitanti,
       (SELECT COUNT(DISTINCT v.stop_id) FROM v_passaggi_giorno_tipo v
        JOIN quartieri q2 ON q2.id_quartiere = v.id_quartiere WHERE q2.municipalita = m.municipalita) AS fermate,
       (SELECT COUNT(*) FROM v_passaggi_giorno_tipo v
        JOIN quartieri q2 ON q2.id_quartiere = v.id_quartiere WHERE q2.municipalita = m.municipalita) AS passaggi
FROM municipalita m
JOIN quartieri q ON q.municipalita = m.municipalita
GROUP BY m.municipalita
ORDER BY m.municipalita;


-- =====================================================================
--  2️⃣ QUANTE CORSE? QUANTO SI ASPETTA?
-- =====================================================================

-- Q2.1 🔁 Le 10 linee con più corse nel giorno tipo
SELECT l.linea, l.modo, a.nome AS azienda, COUNT(*) AS corse
FROM corse c
JOIN calendario k ON k.service_id = c.service_id AND k.data = '20231018'
JOIN linee l      ON l.route_id = c.route_id
JOIN aziende a    ON a.agency_id = l.agency_id
GROUP BY l.route_id
ORDER BY corse DESC
LIMIT 10;

-- Q2.2 🧍 Passaggi ogni 1.000 abitanti, per quartiere
SELECT q.quartiere, q.abitanti, COUNT(v.trip_id) AS passaggi,
       ROUND(COUNT(v.trip_id) * 1000.0 / q.abitanti, 1) AS passaggi_1000_ab
FROM quartieri q
LEFT JOIN v_passaggi_giorno_tipo v ON v.id_quartiere = q.id_quartiere
GROUP BY q.id_quartiere
ORDER BY passaggi_1000_ab;

-- Q2.3 🕐 Partenze delle corse per ora del giorno e mezzo di trasporto
WITH partenze AS (
    SELECT v.trip_id, v.modo, v.ora,
           ROW_NUMBER() OVER (PARTITION BY v.trip_id ORDER BY o.stop_sequence) AS n
    FROM v_passaggi_giorno_tipo v
    JOIN orari o ON o.trip_id = v.trip_id AND o.stop_id = v.stop_id
)
SELECT ora,
       SUM(CASE WHEN modo = 'Bus'        THEN 1 ELSE 0 END) AS bus,
       SUM(CASE WHEN modo = 'Metro'      THEN 1 ELSE 0 END) AS metro,
       SUM(CASE WHEN modo = 'Funicolare' THEN 1 ELSE 0 END) AS funicolare
FROM partenze
WHERE n = 1
GROUP BY ora
ORDER BY ora;

-- Q2.4 ⏳ Attesa media tra le 7 e le 9 alle fermate di ogni quartiere (120 minuti ÷ passaggi)
WITH per_fermata AS (
    SELECT stop_id, id_quartiere, COUNT(*) AS passaggi_7_9
    FROM v_passaggi_giorno_tipo
    WHERE partenza >= '07:00:00' AND partenza < '09:00:00' AND id_quartiere IS NOT NULL
    GROUP BY stop_id
)
SELECT q.quartiere, COUNT(*) AS fermate,
       ROUND(AVG(120.0 / passaggi_7_9), 1) AS attesa_media_min,
       SUM(CASE WHEN passaggi_7_9 >= 8 THEN 1 ELSE 0 END) AS fermate_ogni_15_min
FROM per_fermata p
JOIN quartieri q ON q.id_quartiere = p.id_quartiere
GROUP BY q.id_quartiere
ORDER BY attesa_media_min DESC;

-- Q2.5 🌙 Prima e ultima corsa di metro e funicolari
SELECT l.linea, l.nome_lungo, MIN(o.partenza) AS prima_corsa, MAX(o.partenza) AS ultima_corsa, COUNT(DISTINCT c.trip_id) AS corse
FROM orari o
JOIN corse c      ON c.trip_id = o.trip_id
JOIN calendario k ON k.service_id = c.service_id AND k.data = '20231018'
JOIN linee l      ON l.route_id = c.route_id
WHERE l.modo <> 'Bus'
GROUP BY l.route_id
ORDER BY l.modo, l.linea;

-- Q2.6 🔝 Le 10 fermate con più passaggi
SELECT fermata, q.quartiere, COUNT(*) AS passaggi, COUNT(DISTINCT route_id) AS linee
FROM v_passaggi_giorno_tipo v
LEFT JOIN quartieri q ON q.id_quartiere = v.id_quartiere
GROUP BY v.stop_id
ORDER BY passaggi DESC
LIMIT 10;


-- =====================================================================
--  3️⃣ QUANTA STRADA PER ARRIVARE A UNA FERMATA?
-- =====================================================================

-- Q3.1 🚶 Distanza media dalla fermata (pesata sugli abitanti) e % di abitanti entro 300 m
SELECT q.quartiere,
       ROUND(SUM(s.dist_fermata_m * s.abitanti) / SUM(s.abitanti), 0)                         AS distanza_media_m,
       ROUND(SUM(CASE WHEN s.dist_fermata_m <= 300 THEN s.abitanti ELSE 0 END) * 100.0 / SUM(s.abitanti), 1) AS pct_entro_300m,
       SUM(CASE WHEN s.dist_fermata_m > 300 THEN s.abitanti ELSE 0 END)                        AS abitanti_oltre_300m
FROM sezioni s
JOIN quartieri q ON q.id_quartiere = s.id_quartiere
GROUP BY q.id_quartiere
ORDER BY distanza_media_m DESC;

-- Q3.2 📏 Tutta la città: quanti abitanti per fascia di distanza
SELECT CASE WHEN dist_fermata_m < 150 THEN '1) meno di 150 m'
            WHEN dist_fermata_m < 300 THEN '2) 150-300 m'
            WHEN dist_fermata_m < 500 THEN '3) 300-500 m'
            ELSE '4) oltre 500 m' END AS fascia,
       SUM(abitanti) AS abitanti,
       ROUND(SUM(abitanti) * 100.0 / (SELECT SUM(abitanti) FROM sezioni), 1) AS pct
FROM sezioni
GROUP BY fascia
ORDER BY fascia;

-- Q3.3 👵 Gli anziani (65 anni e più): quanti sono a più di 300 m da una fermata
SELECT q.quartiere, SUM(s.over65) AS over65,
       SUM(CASE WHEN s.dist_fermata_m > 300 THEN s.over65 ELSE 0 END) AS over65_oltre_300m,
       ROUND(SUM(CASE WHEN s.dist_fermata_m > 300 THEN s.over65 ELSE 0 END) * 100.0 / SUM(s.over65), 1) AS pct
FROM sezioni s
JOIN quartieri q ON q.id_quartiere = s.id_quartiere
GROUP BY q.id_quartiere
HAVING over65_oltre_300m > 0
ORDER BY over65_oltre_300m DESC
LIMIT 10;


-- =====================================================================
--  4️⃣ METRO E FUNICOLARI: CHI LE HA VICINE?
-- =====================================================================

-- Q4.1 🚇 Stazioni di metro e funicolare in ogni quartiere
SELECT q.quartiere, COUNT(DISTINCT f.nome) AS stazioni,
       GROUP_CONCAT(DISTINCT v.linea) AS linee
FROM quartieri q
LEFT JOIN v_passaggi_giorno_tipo v ON v.id_quartiere = q.id_quartiere AND v.modo <> 'Bus'
LEFT JOIN fermate f ON f.stop_id = v.stop_id
GROUP BY q.id_quartiere
ORDER BY stazioni DESC, q.quartiere;

-- Q4.2 🚶 Abitanti a più di 800 m (circa 10 minuti a piedi) da metro o funicolare
SELECT q.quartiere, q.abitanti,
       SUM(CASE WHEN s.dist_stazione_m > 800 THEN s.abitanti ELSE 0 END) AS abitanti_oltre_800m,
       ROUND(SUM(CASE WHEN s.dist_stazione_m > 800 THEN s.abitanti ELSE 0 END) * 100.0 / q.abitanti, 1) AS pct,
       ROUND(SUM(s.dist_stazione_m * s.abitanti) / SUM(s.abitanti) / 1000, 2) AS km_medi_da_stazione
FROM sezioni s
JOIN quartieri q ON q.id_quartiere = s.id_quartiere
GROUP BY q.id_quartiere
ORDER BY abitanti_oltre_800m DESC;


-- =====================================================================
--  5️⃣ IL QUADRO FINALE
-- =====================================================================

-- Q5.1 🏆 Classifica: abitanti vicini a una fermata, a una fermata frequente e a una stazione
WITH acc AS (
    SELECT id_quartiere,
           SUM(CASE WHEN dist_fermata_m   <= 300 THEN abitanti ELSE 0 END) * 100.0 / SUM(abitanti) AS p_fermata,
           SUM(CASE WHEN dist_frequente_m <= 500 THEN abitanti ELSE 0 END) * 100.0 / SUM(abitanti) AS p_frequente,
           SUM(CASE WHEN dist_stazione_m  <= 800 THEN abitanti ELSE 0 END) * 100.0 / SUM(abitanti) AS p_stazione
    FROM sezioni
    GROUP BY id_quartiere
),
pct AS (
    SELECT id_quartiere, p_fermata, p_frequente, p_stazione,
           (PERCENT_RANK() OVER (ORDER BY p_fermata) + PERCENT_RANK() OVER (ORDER BY p_frequente)
            + PERCENT_RANK() OVER (ORDER BY p_stazione)) / 3 * 100 AS punteggio
    FROM acc
)
SELECT RANK() OVER (ORDER BY punteggio DESC) AS posizione, q.quartiere,
       ROUND(p_fermata, 1) AS pct_fermata_300m, ROUND(p_frequente, 1) AS pct_frequente_500m,
       ROUND(p_stazione, 1) AS pct_stazione_800m, ROUND(punteggio, 0) AS punteggio
FROM pct
JOIN quartieri q ON q.id_quartiere = pct.id_quartiere
ORDER BY posizione;
