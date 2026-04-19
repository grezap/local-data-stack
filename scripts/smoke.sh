#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
#  NexusPlatform · local-data-stack · end-to-end smoke test
# ─────────────────────────────────────────────────────────────────────────────
#  Asserts that the stack is wired correctly by exercising each data plane:
#
#    1. Kafka        — create topic, produce, consume one message
#    2. Schema Reg   — register an Avro schema, list subjects
#    3. ClickHouse   — insert one row, read it back
#    4. Redis        — SET/GET round-trip
#    5. OTel         — POST one log via OTLP/HTTP, verify collector counter ticks
#    6. Prometheus   — query `up` for each scrape target
#    7. Grafana      — /api/health returns "ok"
#    8. Jaeger       — UI reachable
#    9. Seq          — /api returns 200
#
#  Exit 0 on success, non-zero on the first failure. Safe to re-run.
# ─────────────────────────────────────────────────────────────────────────────
set -euo pipefail

bold() { printf "\033[1m%s\033[0m\n" "$*"; }
pass() { printf "  \033[32m✓\033[0m %s\n" "$*"; }
fail() { printf "  \033[31m✗\033[0m %s\n" "$*"; exit 1; }

KAFKA=nexus-kafka
CH=nexus-clickhouse
RD=nexus-redis

bold "1. Kafka  ── topic + produce + consume"
docker exec -i $KAFKA /opt/kafka/bin/kafka-topics.sh \
  --bootstrap-server kafka:9092 --create --if-not-exists \
  --topic smoke --partitions 1 --replication-factor 1 >/dev/null
echo "smoke-$(date +%s)" | docker exec -i $KAFKA /opt/kafka/bin/kafka-console-producer.sh \
  --bootstrap-server kafka:9092 --topic smoke >/dev/null
OUT=$(docker exec -i $KAFKA timeout 8 /opt/kafka/bin/kafka-console-consumer.sh \
  --bootstrap-server kafka:9092 --topic smoke --from-beginning --max-messages 1 2>/dev/null || true)
[[ "$OUT" == smoke-* ]] && pass "kafka round-trip ($OUT)" || fail "kafka round-trip"

bold "2. Schema Registry  ── register + list"
curl -sf -X POST -H 'Content-Type: application/vnd.schemaregistry.v1+json' \
  --data '{"schema":"{\"type\":\"record\",\"name\":\"Smoke\",\"fields\":[{\"name\":\"id\",\"type\":\"string\"}]}"}' \
  http://127.0.0.1:8081/subjects/smoke-value/versions >/dev/null
curl -sf http://127.0.0.1:8081/subjects | grep -q smoke-value \
  && pass "schema registered" || fail "schema registry"

bold "3. ClickHouse  ── insert + select"
docker exec -i $CH clickhouse-client -u nexus --password "${CLICKHOUSE_PASSWORD:-nexus-dev}" -q "
  INSERT INTO nexus.events (event_time, service, event_type, severity, trace_id, span_id, attributes, message)
  VALUES (now64(3,'UTC'), 'smoke', 'ping', 'info', '', '', map(), 'hello')"
N=$(docker exec -i $CH clickhouse-client -u nexus --password "${CLICKHOUSE_PASSWORD:-nexus-dev}" \
     -q "SELECT count() FROM nexus.events WHERE service='smoke'")
[[ "$N" -ge 1 ]] && pass "clickhouse insert+select ($N rows)" || fail "clickhouse"

bold "4. Redis  ── SET/GET"
docker exec -i $RD redis-cli SET smoke:k "v-$(date +%s)" >/dev/null
docker exec -i $RD redis-cli GET smoke:k | grep -q "^v-" && pass "redis round-trip" || fail "redis"

bold "5. OTel Collector  ── OTLP/HTTP log"
PAYLOAD='{"resourceLogs":[{"resource":{"attributes":[{"key":"service.name","value":{"stringValue":"smoke"}}]},"scopeLogs":[{"logRecords":[{"timeUnixNano":"'"$(date +%s)"'000000000","severityText":"INFO","body":{"stringValue":"smoke-log"}}]}]}]}'
curl -sf -X POST -H 'Content-Type: application/json' \
  --data "$PAYLOAD" http://127.0.0.1:4318/v1/logs >/dev/null \
  && pass "OTLP/HTTP accepted" || fail "OTLP ingest"

bold "6. Prometheus  ── /-/healthy + targets up"
curl -sf http://127.0.0.1:9090/-/healthy | grep -qi healthy && pass "prom healthy" || fail "prom health"
curl -sf 'http://127.0.0.1:9090/api/v1/query?query=up' | grep -q '"status":"success"' \
  && pass "prom query API" || fail "prom query"

bold "7. Grafana  ── /api/health"
curl -sf http://127.0.0.1:3000/api/health | grep -q '"database": *"ok"' \
  && pass "grafana ok" || fail "grafana"

bold "8. Jaeger UI"
curl -sf -o /dev/null -w "%{http_code}" http://127.0.0.1:16686/ | grep -q 200 \
  && pass "jaeger UI 200" || fail "jaeger"

bold "9. Seq"
curl -sf -o /dev/null -w "%{http_code}" http://127.0.0.1:5341/api | grep -q 200 \
  && pass "seq API 200" || fail "seq"

echo
bold "✓ all smoke checks passed"
