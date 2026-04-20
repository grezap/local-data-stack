<#
.SYNOPSIS
    NexusPlatform :: local-data-stack :: end-to-end smoke test (PowerShell)

.DESCRIPTION
    Windows-native equivalent of scripts/smoke.sh. Asserts the stack is wired
    correctly by exercising every data plane:

      1. Kafka        -- create topic, produce, consume one message
      2. Schema Reg   -- register an Avro schema, list subjects
      3. ClickHouse   -- insert one row, read it back
      4. Redis        -- SET / GET round-trip
      5. OTel         -- POST one log via OTLP/HTTP
      6. Prometheus   -- /-/healthy + query API
      7. Grafana      -- /api/health returns "ok"
      8. Jaeger       -- UI reachable (HTTP 200)
      9. Seq          -- /api returns 200

    Exits with a non-zero code on the first failure. Safe to re-run.

    Pure ASCII so this parses under Windows PowerShell 5.1 (ANSI-default)
    as well as PowerShell 7+.

.NOTES
    Requires: PowerShell 5.1+, Docker Desktop running the full-profile stack.
    Run:   .\scripts\smoke.ps1     or     .\run.ps1 smoke
#>
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
# PS 7.2+ only; safe no-op on earlier versions.
try { $PSNativeCommandUseErrorActionPreference = $false } catch { }

# --- helpers ---------------------------------------------------------------

function Write-Bold { param([string]$Msg) Write-Host $Msg -ForegroundColor Cyan }
function Write-Pass { param([string]$Msg) Write-Host "  [PASS] $Msg" -ForegroundColor Green }
function Write-Fail {
    param([string]$Msg)
    Write-Host "  [FAIL] $Msg" -ForegroundColor Red
    exit 1
}

function Invoke-Http {
    param([string]$Method = 'GET', [string]$Url, $Body = $null, [string]$ContentType = 'application/json')
    try {
        if ($null -ne $Body) {
            return Invoke-WebRequest -Method $Method -Uri $Url -Body $Body `
                    -ContentType $ContentType -UseBasicParsing -TimeoutSec 10
        } else {
            return Invoke-WebRequest -Method $Method -Uri $Url -UseBasicParsing -TimeoutSec 10
        }
    } catch {
        return $_.Exception.Response
    }
}

$Kafka = 'nexus-kafka'
$CH    = 'nexus-clickhouse'
$Rd    = 'nexus-redis'
$ChPwd = if ($env:CLICKHOUSE_PASSWORD) { $env:CLICKHOUSE_PASSWORD } else { 'nexus-dev' }

# --- 1. Kafka --------------------------------------------------------------
Write-Bold "1. Kafka  -- topic + produce + consume"
docker exec $Kafka /opt/kafka/bin/kafka-topics.sh `
    --bootstrap-server kafka:9092 --create --if-not-exists `
    --topic smoke --partitions 1 --replication-factor 1 | Out-Null
if ($LASTEXITCODE -ne 0) { Write-Fail "could not create topic" }

$msg = "smoke-$([DateTimeOffset]::UtcNow.ToUnixTimeSeconds())"
$msg | docker exec -i $Kafka /opt/kafka/bin/kafka-console-producer.sh `
    --bootstrap-server kafka:9092 --topic smoke | Out-Null
if ($LASTEXITCODE -ne 0) { Write-Fail "produce failed" }

$out = docker exec $Kafka timeout 8 /opt/kafka/bin/kafka-console-consumer.sh `
    --bootstrap-server kafka:9092 --topic smoke --from-beginning --max-messages 1 2>$null
if ($out -match '^smoke-') { Write-Pass "kafka round-trip ($out)" } else { Write-Fail "kafka round-trip" }

# --- 2. Schema Registry ----------------------------------------------------
Write-Bold "2. Schema Registry  -- register + list"
$schemaBody = '{"schema":"{\"type\":\"record\",\"name\":\"Smoke\",\"fields\":[{\"name\":\"id\",\"type\":\"string\"}]}"}'
$r = Invoke-Http -Method POST `
        -Url 'http://127.0.0.1:8081/subjects/smoke-value/versions' `
        -Body $schemaBody `
        -ContentType 'application/vnd.schemaregistry.v1+json'
if ($r.StatusCode -ne 200) { Write-Fail "register schema (status $($r.StatusCode))" }

$list = (Invoke-Http -Url 'http://127.0.0.1:8081/subjects').Content
if ($list -match 'smoke-value') { Write-Pass "schema registered" } else { Write-Fail "schema registry" }

# --- 3. ClickHouse ---------------------------------------------------------
Write-Bold "3. ClickHouse  -- insert + select"
$ins = @"
INSERT INTO nexus.events (event_time, service, event_type, severity, trace_id, span_id, attributes, message)
VALUES (now64(3,'UTC'), 'smoke', 'ping', 'info', '', '', map(), 'hello')
"@
docker exec $CH clickhouse-client -u nexus --password $ChPwd -q $ins
if ($LASTEXITCODE -ne 0) { Write-Fail "clickhouse insert" }

$n = docker exec $CH clickhouse-client -u nexus --password $ChPwd `
        -q "SELECT count() FROM nexus.events WHERE service='smoke'"
if ([int]$n -ge 1) { Write-Pass "clickhouse insert+select ($n rows)" } else { Write-Fail "clickhouse" }

# --- 4. Redis --------------------------------------------------------------
Write-Bold "4. Redis  -- SET / GET"
$v = "v-$([DateTimeOffset]::UtcNow.ToUnixTimeSeconds())"
docker exec $Rd redis-cli SET smoke:k $v | Out-Null
$got = docker exec $Rd redis-cli GET smoke:k
if ($got -eq $v) { Write-Pass "redis round-trip" } else { Write-Fail "redis (expected $v got $got)" }

# --- 5. OTel Collector -----------------------------------------------------
Write-Bold "5. OTel Collector  -- OTLP/HTTP log"
$ts = ([DateTimeOffset]::UtcNow.ToUnixTimeSeconds()).ToString() + "000000000"
$otlp = @"
{"resourceLogs":[{"resource":{"attributes":[{"key":"service.name","value":{"stringValue":"smoke"}}]},"scopeLogs":[{"logRecords":[{"timeUnixNano":"$ts","severityText":"INFO","body":{"stringValue":"smoke-log"}}]}]}]}
"@
$r = Invoke-Http -Method POST -Url 'http://127.0.0.1:4318/v1/logs' -Body $otlp
if ($r.StatusCode -in 200,202) { Write-Pass "OTLP/HTTP accepted" } else { Write-Fail "OTLP ingest (status $($r.StatusCode))" }

# --- 6. Prometheus ---------------------------------------------------------
Write-Bold "6. Prometheus  -- health + query"
$h = (Invoke-Http -Url 'http://127.0.0.1:9090/-/healthy').Content
if ($h -match 'Healthy') { Write-Pass "prom healthy" } else { Write-Fail "prom health" }

$q = (Invoke-Http -Url 'http://127.0.0.1:9090/api/v1/query?query=up').Content
if ($q -match '"status":"success"') { Write-Pass "prom query API" } else { Write-Fail "prom query" }

# --- 7. Grafana ------------------------------------------------------------
Write-Bold "7. Grafana  -- /api/health"
$gh = (Invoke-Http -Url 'http://127.0.0.1:3000/api/health').Content
if ($gh -match '"database"\s*:\s*"ok"') { Write-Pass "grafana ok" } else { Write-Fail "grafana" }

# --- 8. Jaeger -------------------------------------------------------------
Write-Bold "8. Jaeger UI"
$jr = Invoke-Http -Url 'http://127.0.0.1:16686/'
if ($jr.StatusCode -eq 200) { Write-Pass "jaeger UI 200" } else { Write-Fail "jaeger (status $($jr.StatusCode))" }

# --- 9. Seq ----------------------------------------------------------------
Write-Bold "9. Seq"
$sr = Invoke-Http -Url 'http://127.0.0.1:5341/api'
if ($sr.StatusCode -eq 200) { Write-Pass "seq API 200" } else { Write-Fail "seq (status $($sr.StatusCode))" }

Write-Host ""
Write-Host "[OK] all smoke checks passed" -ForegroundColor Green
