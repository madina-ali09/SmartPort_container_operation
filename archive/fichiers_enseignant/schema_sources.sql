-- SQLite starter schema generated for the student project
PRAGMA foreign_keys = ON;

DROP TABLE IF EXISTS customers;
CREATE TABLE customers (
    customer_id TEXT,
    customer_name TEXT,
    group_code TEXT,
    customer_type TEXT
);

DROP TABLE IF EXISTS vessel_calls;
CREATE TABLE vessel_calls (
    vessel_id TEXT,
    vessel_name TEXT,
    vessel_type TEXT,
    service_code TEXT
);

DROP TABLE IF EXISTS container_events;
CREATE TABLE container_events (
    event_id INTEGER,
    container_id TEXT,
    customer_id TEXT,
    vessel_id TEXT,
    event_type TEXT,
    event_ts TEXT,
    yard_area TEXT,
    freight_status TEXT,
    gross_weight_kg REAL
);

DROP TABLE IF EXISTS yard_moves;
CREATE TABLE yard_moves (
    move_id INTEGER,
    container_id TEXT,
    move_ts TEXT,
    from_area TEXT,
    to_area TEXT,
    equipment_id TEXT
);

DROP TABLE IF EXISTS equipment;
CREATE TABLE equipment (
    equipment_id TEXT,
    equipment_type TEXT,
    home_area TEXT
);
