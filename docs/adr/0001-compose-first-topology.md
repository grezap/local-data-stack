# ADR-0001: Compose-first topology for the local substrate

- **Status:** Accepted
- **Date:** 2026-04-19
- **Deciders:** Greg Zapantis
- **Supersedes:** —

## Context

Every NexusPlatform application project (streaming ingester, CQRS service, ML inference API, etc.) needs the same backing services: a broker, a fast analytical DB, a cache, and an observability trio. The local-development substrate must be:

1. **Reproducible** across Linux, macOS, and Windows-WSL2 workstations.
2. **Fast to stand up** — under two minutes on a warm image cache, from `git clone` to running stack.
3. **Operable by one engineer** without cluster expertise.
4. **Promotable** — the same mental model should carry to Swarm / Nomad / Kubernetes later without a rewrite of the app code.

Candidates considered:

| Option                              | Stand-up time | Fidelity to prod | Ops overhead | Single-file truth |
| ----------------------------------- | ------------- | ---------------- | ------------ | ----------------- |
| **Docker Compose v2**               | ~60 s         | medium           | very low     | ✅ yes            |
| Kubernetes (kind / k3d)             | ~5 min        | high             | medium       | ⚠ many manifests  |
| Nomad + Consul (dev agents)         | ~3 min        | high             | medium       | ⚠ many files      |
| Tilt / Skaffold over k8s            | ~5 min        | high             | high         | ⚠ tool-coupled    |
| Raw systemd + local binaries        | —             | low              | high         | ❌                |

## Decision

We adopt **Docker Compose v2** with named profiles as the topology for `local-data-stack` v0.x and v1.x. A single `compose/docker-compose.yml` is the source of truth.

Promotion targets (Swarm stack, Nomad job, Helm chart) will be **derived** from the same service definitions in a later volume, not forked. ADRs for those promotions will reference this one.

## Consequences

### Positive

- One-file truth. Reviewers see the entire topology in a single diff.
- Profiles (`minimal`, `streaming`, `analytics`, `observability`, `full`) give cheap subsets without YAML forking.
- `docker compose config` in CI catches schema drift on every PR.
- YAML anchors (`x-logging`, `x-restart`) eliminate copy-paste drift between services.

### Negative / mitigations

- **No orchestrator-level health semantics** (no readiness-vs-liveness distinction, no restart-budget). *Mitigation:* every service ships a `healthcheck` + `depends_on: { condition: service_healthy }` for ordered start-up.
- **Single-host only.** *Mitigation:* v0.3.0 roadmap adds a Swarm overlay variant sharing the same image set.
- **No built-in secret store.** *Mitigation:* `.env` files are gitignored; production guidance points to Vault (covered in `local-infra-hub`).

## Links

- [Compose spec v2](https://github.com/compose-spec/compose-spec/blob/main/spec.md)
- ADR-0002 (KRaft), ADR-0003 (OTel hub) build on this foundation.
