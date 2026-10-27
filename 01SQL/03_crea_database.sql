-- =====================================================================
--  01_crea_database.sql – Trasporto pubblico a Napoli 🚌
--  Crea le tabelle del database (SQLite): il GTFS di ANM + quartieri ISTAT.
--  Lo usa 02_carica_dati.py: non serve lanciarlo a mano.
-- =====================================================================

DROP VIEW  IF EXISTS v_passaggi_giorno_tipo;
DROP TABLE IF EXISTS orari;
DROP TABLE IF EXISTS calendario;
DROP TABLE IF EXISTS corse;
DROP TABLE IF EXISTS linee;
DROP TABLE IF EXISTS aziende;
DROP TABLE IF EXISTS sezioni;
DROP TABLE IF EXISTS fermate;
DROP TABLE IF EXISTS quartieri;
DROP TABLE IF EXISTS municipalita;

-- 🏛️ le 10 municipalità
CREATE TABLE municipalita (
    municipalita  INTEGER PRIMARY KEY,
    nome          TEXT NOT NULL                 -- 'Municipalità 1', ...
);

-- 🏘️ i 30 quartieri (ISTAT 2021)
CREATE TABLE quartieri (
    id_quartiere  INTEGER PRIMARY KEY,
    quartiere     TEXT NOT NULL,
    municipalita  INTEGER NOT NULL REFERENCES municipalita (municipalita),
    abitanti      INTEGER NOT NULL,
    area_km2      REAL NOT NULL
);

-- 🚏 le fermate (GTFS stops), con il quartiere in cui si trovano (vuoto = fuori Napoli)
CREATE TABLE fermate (
    stop_id       TEXT PRIMARY KEY,
    nome          TEXT NOT NULL,
    latitudine    REAL NOT NULL,
    longitudine   REAL NOT NULL,
    id_quartiere  INTEGER REFERENCES quartieri (id_quartiere)
);

-- 👪 le sezioni di censimento abitate, con la distanza dalla fermata più vicina (calcolata in Python)
CREATE TABLE sezioni (
    id_sezione        INTEGER PRIMARY KEY,
    id_quartiere      INTEGER NOT NULL REFERENCES quartieri (id_quartiere),
    abitanti          INTEGER NOT NULL,
    over65            INTEGER NOT NULL,
    dist_fermata_m    REAL NOT NULL,          -- fermata qualsiasi con almeno una corsa
    dist_frequente_m  REAL NOT NULL,          -- fermata con almeno 8 passaggi tra le 7 e le 9
    dist_stazione_m   REAL NOT NULL           -- stazione di metro o funicolare
);

-- 🏢 le aziende (ANM e Trenitalia per la Linea 2)
CREATE TABLE aziende (
    agency_id  TEXT PRIMARY KEY,
    nome       TEXT NOT NULL
);

-- 🚌 le linee (GTFS routes)
CREATE TABLE linee (
    route_id    TEXT PRIMARY KEY,
    agency_id   TEXT NOT NULL REFERENCES aziende (agency_id),
    linea       TEXT NOT NULL,                  -- 'R2', '151', 'L1', 'F1' ...
    nome_lungo  TEXT,
    modo        TEXT NOT NULL CHECK (modo IN ('Bus', 'Metro', 'Funicolare'))
);

-- 🔁 le corse (GTFS trips): un viaggio di una linea in un giorno di servizio
CREATE TABLE corse (
    trip_id     TEXT PRIMARY KEY,
    route_id    TEXT NOT NULL REFERENCES linee (route_id),
    service_id  TEXT NOT NULL,
    direzione   INTEGER,
    shape_id    TEXT
);

-- 📅 in quali giorni vale ogni servizio (GTFS calendar_dates)
CREATE TABLE calendario (
    service_id  TEXT NOT NULL,
    data        TEXT NOT NULL,                  -- 'AAAAMMGG'
    PRIMARY KEY (service_id, data)
) WITHOUT ROWID;

-- ⏰ gli orari: una riga per corsa e fermata (GTFS stop_times)
CREATE TABLE orari (
    trip_id        TEXT NOT NULL REFERENCES corse (trip_id),
    stop_sequence  INTEGER NOT NULL,
    stop_id        TEXT NOT NULL REFERENCES fermate (stop_id),
    arrivo         TEXT,                        -- 'HH:MM:SS' (dopo mezzanotte: 24:xx, 25:xx)
    partenza       TEXT,
    PRIMARY KEY (trip_id, stop_sequence)
) WITHOUT ROWID;

CREATE INDEX idx_orari_fermata ON orari (stop_id);
CREATE INDEX idx_corse_servizio ON corse (service_id);
CREATE INDEX idx_fermate_quartiere ON fermate (id_quartiere);

-- 👀 vista comoda: tutti i passaggi del giorno tipo (mercoledì 18/10/2023) con linea, fermata e quartiere
CREATE VIEW v_passaggi_giorno_tipo AS
SELECT o.trip_id, o.stop_id, o.partenza, CAST(substr(o.partenza, 1, 2) AS INTEGER) % 24 AS ora,
       l.route_id, l.linea, l.modo, f.nome AS fermata, f.id_quartiere
FROM orari o
JOIN corse c      ON c.trip_id = o.trip_id
JOIN calendario k ON k.service_id = c.service_id AND k.data = '20231018'
JOIN linee l      ON l.route_id = c.route_id
JOIN fermate f    ON f.stop_id = o.stop_id;
