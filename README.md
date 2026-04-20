# local-data-stack

> **A reproducible, observable, single-host data + streaming + observability substrate — the local-development foundation for every NexusPlatform project.**

![status](https://img.shields.io/badge/status-v0.1.0-blue)
![license](https://img.shields.io/badge/license-MIT-green)
![compose](https://img.shields.io/badge/docker--compose-v2-informational)
![platform](https://img.shields.io/badge/platform-linux%20%7C%20macos%20%7C%20windows--wsl2-lightgrey)

One `make up` brings up Kafka (KRaft), Schema Registry, ClickHouse, Redis, Prometheus, Grafana, Jaeger v2, Seq, and an OpenTelemetry Collector acting as the single telemetry hub. Every application project in the NexusPlatform portfolio targets this stack unchanged.

---

## Table of contents

1. [Why this exists](#why-this-exists)
2. [What's inside](#whats-inside)
3. [Architecture](#architecture)
4. [Quick start](#quick-start)
5. [Profiles — start only what you need](#profiles)
6. [URLs & credentials](#urls--credentials)
7. [Smoke test](#smoke-test)
8. [Configuration](#configuration)
9. [Design decisions (ADRs)](#design-decisions)
10. [Operating the stack](#operating-the-stack)
11. [Troubleshooting](#troubleshooting)
12. [Roadmap](#roadmap)
13. [Contributing](#contributing)
14. [License](#license)

---

## Why this exists

Every serious backend project I build — streaming ingestion, CQRS services, ML inference APIs — needs the same substrate: a broker, a fast analytical DB, a cache, and a place for metrics/traces/logs to land. Re-provisioning that per-project is wasted motion; sharing one ad-hoc stack is fragile.

`local-data-stack` is the opinionated, pinned, observable substrate. It is:

- **Reproducible.** Image tags are pinned; `.env.example` documents every knob; `docker compose config` is green in CI.
- **Observable by default.** Apps emit OTLP; the collector fans out to Prometheus / Jaeger / Seq. Grafana comes up with provisioned datasources and dashboards.
- **Secure-by-default for a workstation.** All host ports bind to `127.0.0.1` so nothing leaks onto the LAN.
- **Profile-aware.** Need just Kafka + ClickHouse? `make up P=minimal`. The full kitchen is opt-in.

## What's inside

| Service                  | Image                                      | Purpose                              | Host port              |
| ------------------------ | ------------------------------------------ | ------------------------------------ | ---------------------- |
| **Kafka**                | `apache/kafka:3.8.1` (KRaft, no ZK)        | Event streaming                      | `9094` (EXTERNAL)      |
| **Schema Registry**      | `confluentinc/cp-schema-registry:7.7.1`    | Avro/JSON/Proto schema governance    | `8081`                 |
| **ClickHouse**           | `clickhouse/clickhouse-server:24.8.7.41`   | Columnar analytics                   | `8123` HTTP, `9000` TCP|
| **Redis**                | `redis:7.4-alpine`                         | Cache / transient state              | `6379`                 |
| **OTel Collector**       | `otel/opentelemetry-collector-contrib:0.113.0` | Single telemetry hub             | `4317` gRPC, `4318` HTTP |
| **Prometheus**           | `prom/prometheus:v3.0.1`                   | Metrics TSDB                         | `9090`                 |
| **Grafana**              | `grafana/grafana:11.3.0`                   | Dashboards (provisioned)             | `3000`                 |
| **Jaeger**               | `jaegertracing/jaeger:2.0.0` (v2, OTel-native) | Trace storage & UI              | `16686`                |
| **Seq**                  | `datalust/seq:2024.3`                      | Structured log store & UI            | `5341`                 |

All images are pinned. Dependabot proposes version bumps weekly (see `.github/dependabot.yml`).

## Architecture

```
            ┌─────────────────────────────────────────────────────┐
            │                     your app                        │
            └──────────────────────┬──────────────────────────────┘
                                   │ OTLP (gRPC :4317 / HTTP :4318)
                                   ▼
            ┌─────────────────────────────────────────────────────┐
            │             OpenTelemetry Collector                 │
            │   receivers: otlp   processors: batch, resource     │
            └───────┬───────────────┬───────────────┬─────────────┘
           metrics │         traces│            logs│
                   ▼               ▼                ▼
            ┌───────────┐    ┌──────────┐    ┌──────────┐
            │Prometheus │    │ Jaeger 2 │    │   Seq    │
            └─────┬─────┘    └────┬─────┘    └────┬─────┘
                  └──────┬────────┴────────┬──────┘
                         ▼                 ▼
                    ┌─────────┐      ┌─────────────┐
                    │ Grafana │◀────▶│  your eyes  │
                    └─────────┘      └─────────────┘

            ┌────────────┐   ┌────────────────┐   ┌────────┐
            │   Kafka    │──▶│ Schema Registry│   │ Redis  │
            └────────────┘   └────────────────┘   └────────┘
                  ▲
                  └─── producers / consumers (your apps)

            ┌────────────┐
            │ ClickHouse │◀── analytics queries, Grafana panels
            └────────────┘
```

See [`docs/architecture.md`](docs/architecture.md) for the long form.

## Quick start

**Requirements:**

- Docker Desktop ≥ 4.33 (or Docker Engine 27+ on Linux)
- One of:
  - **Linux / macOS / WSL2 / Git Bash:** `make`, `bash`, `curl`, `jq`
  - **Windows PowerShell 7+:** no extra tooling — use `run.ps1` instead of `make`

### Linux · macOS · WSL2 · Git Bash

```bash
git clone https://github.com/grezap/local-data-stack.git
cd local-data-stack
cp compose/.env.example compose/.env   # optional; defaults work
make up
make health
make urls
```

### Windows 11 (native PowerShell 7+)

```powershell
git clone https://github.com/grezap/local-data-stack.git
cd local-data-stack
Copy-Item compose\.env.example compose\.env   # optional; defaults work
.\run.ps1 up
.\run.ps1 health
.\run.ps1 urls
```

> If PowerShell blocks the script, unblock once with:
> `Set-ExecutionPolicy -Scope CurrentUser -ExecutionPolicy RemoteSigned`
> or per-file: `Unblock-File .\run.ps1, .\scripts\smoke.ps1`.
>
> **Prefer PowerShell 7+** (install: `winget install --id Microsoft.PowerShell`). The scripts also work on Windows PowerShell 5.1, but PS 7 reads UTF-8 without BOM natively and has better error handling.

Expected on either path: nine containers reporting `healthy` within ~30 s on a warm image cache.

## Profiles

Compose profiles let you subset the stack. Pass `P=<profile>` to `make up`:

| Profile         | Services                                                                                     | When to use                       |
| --------------- | -------------------------------------------------------------------------------------------- | --------------------------------- |
| `minimal`       | kafka, clickhouse, redis                                                                     | tight laptop / single-feature dev |
| `streaming`     | kafka, schema-registry                                                                       | producer/consumer work            |
| `analytics`     | clickhouse, redis                                                                            | DB / query / modeling             |
| `observability` | otel-collector, prometheus, grafana, jaeger, seq                                             | observability experiments         |
| `full` *(default)* | everything                                                                                 | normal development                |

## URLs & credentials

| UI              | URL                              | Default creds          |
| --------------- | -------------------------------- | ---------------------- |
| Grafana         | http://127.0.0.1:3000            | `admin` / `admin`      |
| Prometheus      | http://127.0.0.1:9090            | —                      |
| Jaeger          | http://127.0.0.1:16686           | —                      |
| Seq             | http://127.0.0.1:5341            | first-run wizard       |
| ClickHouse HTTP | http://127.0.0.1:8123            | `nexus` / `nexus-dev`  |
| Schema Registry | http://127.0.0.1:8081            | —                      |

> ⚠ **These defaults are for local development only.** See [`docs/security.md`](docs/security.md) before exposing any port off `127.0.0.1`.

## Smoke test

`make smoke` runs `scripts/smoke.sh`, which exercises each data plane end-to-end: produces & consumes a Kafka message, registers an Avro schema, inserts & reads a ClickHouse row, round-trips Redis, pushes a log via OTLP/HTTP, and confirms every UI is reachable. CI runs this on every push.

## Configuration

Everything tunable lives in [`compose/.env.example`](compose/.env.example). Copy to `compose/.env` and edit. No other file needs changing for normal use.

| Variable                       | Default              | Notes                                       |
| ------------------------------ | -------------------- | ------------------------------------------- |
| `KAFKA_VERSION`                | `3.8.1`              | Apache Kafka image tag                      |
| `CLICKHOUSE_PASSWORD`          | `nexus-dev`          | User `nexus` password                       |
| `GRAFANA_ADMIN_PASSWORD`       | `admin`              | Change before any demo                      |
| `SEQ_ADMIN_PASSWORD_HASH`      | *(empty)*            | Generate with `docker run datalust/seq config hash` |

## Design decisions

Every non-obvious choice is justified in an ADR. See [`docs/adr/`](docs/adr/):

- [ADR-0001 — Compose-first topology for the local substrate](docs/adr/0001-compose-first-topology.md)
- [ADR-0002 — Kafka KRaft over ZooKeeper](docs/adr/0002-kafka-kraft-over-zookeeper.md)
- [ADR-0003 — OpenTelemetry Collector as the single telemetry hub](docs/adr/0003-otel-collector-as-telemetry-hub.md)

## Operating the stack

The `Makefile` (POSIX shells) and `run.ps1` (PowerShell 7+) expose the **same verbs** so the developer contract is identical across platforms.

| Task                       | POSIX (make)              | Windows (PowerShell)                       |
| -------------------------- | ------------------------- | ------------------------------------------ |
| Start full stack           | `make up`                 | `.\run.ps1 up`                             |
| Start a profile            | `make up P=streaming`     | `.\run.ps1 up -Profile streaming`          |
| Stop (keep data)           | `make down`               | `.\run.ps1 down`                           |
| Stop **and** wipe volumes  | `make nuke` *(destructive)* | `.\run.ps1 nuke` *(prompts for confirm)* |
| Show container state       | `make ps`                 | `.\run.ps1 ps`                             |
| Tail all logs              | `make logs`               | `.\run.ps1 logs`                           |
| Tail one service           | `make logs S=kafka`       | `.\run.ps1 logs -Service kafka`            |
| Probe every healthcheck    | `make health`             | `.\run.ps1 health`                         |
| Lint compose file          | `make validate`           | `.\run.ps1 validate`                       |
| End-to-end smoke test      | `make smoke`              | `.\run.ps1 smoke`                          |
| Print all UI URLs          | `make urls`               | `.\run.ps1 urls`                           |

## Troubleshooting

**Kafka container keeps restarting.** The KRaft storage dir was initialized with a different `CLUSTER_ID`. Run `make nuke` or delete the `nexus-kafka-data` volume, then `make up`.

**Grafana datasource "Seq" shows red.** Seq's OpenSearch-compatible endpoint is lazy; hit the Seq UI once to finish first-run. Then refresh Grafana's datasource test.

**ClickHouse init SQL didn't run.** It only runs on *first* container start against an empty volume. To rerun: `make nuke && make up`.

**Port already in use (e.g. `Bind for 0.0.0.0:3000 failed: port is already allocated`).** Another process on the host owns that port. Two fixes:

1. **Override the host-side port** in `compose/.env`. Every service's host port is parameterized — see `compose/.env.example` for the full list:
   ```
   GRAFANA_PORT=3001
   PROMETHEUS_PORT=9091
   JAEGER_UI_PORT=16687
   ```
   Then `make down && make up` (or `.\run.ps1 down; .\run.ps1 up`).

2. **Find and stop the squatter.** On Windows: `Get-NetTCPConnection -LocalPort 3000 | Select OwningProcess,State` then `Get-Process -Id <pid>`. On Linux/macOS: `lsof -i :3000` or `sudo ss -lptn 'sport = :3000'`. Common culprits: another Grafana, `node` dev server, a leftover stopped container (`docker ps -a | grep 3000`).

**Windows: `run.ps1 : File cannot be loaded because running scripts is disabled`.** One-time fix:
`Set-ExecutionPolicy -Scope CurrentUser -ExecutionPolicy RemoteSigned`. Per-file: `Unblock-File .\run.ps1`.

**Windows: `docker : The term 'docker' is not recognized`.** Docker Desktop is not installed or not on `PATH`. Install from docker.com, reboot, and ensure WSL2 integration is enabled in Docker Desktop → Settings → Resources → WSL Integration.

**Windows: `bash\r: No such file or directory` when running `smoke.sh` in WSL.** The shell script was checked out with CRLF line endings. Fix: `git config --global core.autocrlf input` then `git checkout -- scripts/smoke.sh`. The repo's `.gitattributes` forces LF on `*.sh` — you should only see this if you bypassed it.

**Windows PS 5.1: `Missing argument in parameter list` when running `.\run.ps1`.** Windows PowerShell 5.1 reads `.ps1` files as ANSI (cp1252) unless they have a UTF-8 BOM. The shipped scripts are pure ASCII to avoid this entirely — if you see this, it means the file was modified and non-ASCII characters (em-dash, box drawing, smart quotes) were introduced. Fix: keep `run.ps1` and `scripts/smoke.ps1` ASCII-only, or switch to PowerShell 7 (`winget install --id Microsoft.PowerShell`).

## Roadmap

| Version | Scope                                                                                 |
| ------- | ------------------------------------------------------------------------------------- |
| v0.1.0  | ✅ Core nine-service stack, profiles, OTel hub, smoke test, CI                         |
| v0.2.0  | JMX receiver for Kafka metrics, alerting rules, Loki (optional), Tempo evaluation     |
| v0.3.0  | Swarm overlay (multi-host), mTLS between services, secrets via Docker secrets         |
| v1.0.0  | Nomad + Consul deployment variant, Packer VM image, Terraform stand-up on vSphere     |

## Contributing

PRs welcome. See [`CONTRIBUTING.md`](CONTRIBUTING.md). Every change runs `make validate` and `make smoke` in CI before merge.

## License

[MIT](LICENSE) © 2026 Greg Zapantis

---

**Part of the [NexusPlatform](https://github.com/grezap/portfolio-index) portfolio.**
Questions? gzapas@gmail.com · [LinkedIn](https://www.linkedin.com/in/grigoris-zapantis-1a0638b/)
