-- ─────────────────────────────────────────────────────────────────────────────
--  NexusPlatform · ClickHouse bootstrap
-- ─────────────────────────────────────────────────────────────────────────────
--  Executed once, at container first-start, by the clickhouse-server entrypoint.
--  Idempotent: every statement uses IF NOT EXISTS.
--
--  Schema layout:
--    nexus.events       — fat append-only event log (trace-like records)
--    nexus.events_5m    — 5-min rollup MV for fast dashboards
-- ─────────────────────────────────────────────────────────────────────────────

CREATE DATABASE IF NOT EXISTS nexus;

CREATE TABLE IF NOT EXISTS nexus.events
(
    event_time    DateTime64(3, 'UTC') CODEC(DoubleDelta, ZSTD(3)),
    service       LowCardinality(String),
    event_type    LowCardinality(String),
    severity      Enum8('trace'=1,'debug'=2,'info'=3,'warn'=4,'error'=5,'fatal'=6),
    trace_id      String CODEC(ZSTD(3)),
    span_id       String CODEC(ZSTD(3)),
    attributes    Map(LowCardinality(String), String) CODEC(ZSTD(3)),
    message       String CODEC(ZSTD(3))
)
ENGINE = MergeTree
PARTITION BY toYYYYMMDD(event_time)
ORDER BY (service, event_type, event_time)
TTL toDateTime(event_time) + INTERVAL 30 DAY
SETTINGS index_granularity = 8192;

CREATE TABLE IF NOT EXISTS nexus.events_5m
(
    bucket_start  DateTime('UTC'),
    service       LowCardinality(String),
    event_type    LowCardinality(String),
    severity      Enum8('trace'=1,'debug'=2,'info'=3,'warn'=4,'error'=5,'fatal'=6),
    count         UInt64
)
ENGINE = SummingMergeTree
PARTITION BY toYYYYMM(bucket_start)
ORDER BY (service, event_type, severity, bucket_start)
TTL bucket_start + INTERVAL 180 DAY;

CREATE MATERIALIZED VIEW IF NOT EXISTS nexus.events_5m_mv
TO nexus.events_5m AS
SELECT
    toStartOfFiveMinute(event_time) AS bucket_start,
    service,
    event_type,
    severity,
    count() AS count
FROM nexus.events
GROUP BY bucket_start, service, event_type, severity;
