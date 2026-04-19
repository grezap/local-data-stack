# Case study — `local-data-stack` v0.1.0

> One-page summary for recruiters and interviewers. Full technical depth lives in `README.md` and `docs/adr/`.

## Problem

Every backend project — streaming ingestion, CQRS services, ML inference — needs the same infrastructure substrate to run locally: a broker, a fast analytical store, a cache, and somewhere for metrics / traces / logs to land. Re-provisioning that per project wastes hours and produces inconsistent results across teammates and machines. Shared ad-hoc stacks drift and break.

## Goal

Deliver a **single-command**, **reproducible**, **observable** local data substrate that every subsequent NexusPlatform project can target without modification — on Linux, macOS, or Windows (WSL2).

Success = `git clone && make up` brings nine services to `healthy` in under two minutes, and `make smoke` passes end-to-end.

## Approach

- **Compose v2, one file, profiles for subsets** (ADR-0001). Single source of truth; `docker compose config` in CI catches drift.
- **Kafka in KRaft mode, no ZooKeeper** (ADR-0002). Halves the broker-path container count and aligns with Kafka 4.x's direction.
- **OpenTelemetry Collector as the single telemetry hub** (ADR-0003). Apps emit OTLP only; backend choice (Prometheus / Jaeger / Seq, or later Tempo / Loki) is a config-only change.
- **Dashboards-as-code.** Grafana datasources and dashboards are provisioned from JSON on startup — no click-ops, reviewable in PRs.
- **Pinned image tags + Dependabot** for a reproducible build today and a managed upgrade path.
- **127.0.0.1-only port binding.** Secure-by-default on a laptop; nothing leaks onto the LAN.
- **CI gates every change** with `docker compose config`, a full smoke test, CodeQL, and Trivy image scanning.

## Result

| Metric                                     | Value                                 |
| ------------------------------------------ | ------------------------------------- |
| Services orchestrated                      | 9                                     |
| Cold-start to all-healthy                  | ≈ 90 s (warm cache)                   |
| Footprint (full profile, idle)             | ≈ 3.2 GB RAM, 2 vCPU                  |
| Lines of infra code (compose + configs)    | ~450                                  |
| ADRs                                       | 3 published, 3 more planned           |
| CI quality gates                           | compose-lint, smoke, CodeQL, Trivy    |
| Host-exposed ports                         | 12, all bound to `127.0.0.1`          |

Downstream projects (`streaming-platform`, `cqrs-core`, `ml-inference-api`, …) target this stack unchanged. Changing a backend (e.g. Jaeger → Tempo) requires zero application-code changes.

## What I'd show in an interview

1. **The architecture diagram** (`README.md` §3) — five minutes to explain the decoupling via the OTel hub.
2. **ADR-0003** — the decision to make apps backend-agnostic via OTLP. This is the single highest-leverage choice in the project.
3. **The smoke test script** (`scripts/smoke.sh`) — how I think about "is it actually wired correctly?" as a mechanical, fast check rather than a hope.
4. **CI pipeline** — how quality is defended, not asserted.

## What I'd do next (v0.2.0)

- Kafka JMX → OTel Collector, closing the last gap in unified telemetry.
- Alerting rules + Grafana contact points.
- Evaluate Tempo vs Jaeger v2 for production trace storage.
- Swarm overlay variant (v0.3.0) sharing the same image set.

---

**Repository:** https://github.com/grezap/local-data-stack · **Author:** Greg Zapantis · [LinkedIn](https://www.linkedin.com/in/grigoris-zapantis-1a0638b/)
