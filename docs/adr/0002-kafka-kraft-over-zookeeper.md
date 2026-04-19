# ADR-0002: Kafka KRaft mode over ZooKeeper

- **Status:** Accepted
- **Date:** 2026-04-19
- **Deciders:** Greg Zapantis

## Context

Apache Kafka historically required ZooKeeper for metadata consensus. Kafka 3.3 (Oct 2022) promoted **KRaft** — Kafka's self-managed Raft-based metadata quorum — to production-ready. Kafka 3.5 deprecated ZooKeeper; Kafka 4.0 (2025) removed it entirely. As of the pinned image (`apache/kafka:3.8.1`), KRaft is the default and ZooKeeper support is end-of-life.

For the local substrate we must choose one of:

1. **KRaft single-node (combined broker+controller).** One container, ~600 MB RAM.
2. **ZooKeeper + Kafka.** Two containers, ~1 GB RAM, an extra failure surface.
3. **Redpanda.** Kafka-API-compatible, C++, no JVM. Smaller footprint, but diverges from the production target.

## Decision

Run Kafka in **KRaft combined mode** (`KAFKA_PROCESS_ROLES=broker,controller`) as a single node, using the upstream `apache/kafka` image. No ZooKeeper container.

The `CLUSTER_ID` is pinned in `.env.example` so volume re-use across fresh `make up` invocations is deterministic. Regenerating the id requires a `make nuke`.

## Consequences

### Positive

- **50 % fewer containers** for the broker path — one less process to monitor, one less log stream.
- **Alignment with the future.** ZooKeeper is gone in Kafka 4.x; starting ZK-free means zero migration debt.
- **Faster cold start.** KRaft skips the ZK session handshake.
- **Simpler mental model** for interview / demo: "Kafka is one container."

### Negative / mitigations

- **Single-node has no fault tolerance.** Accepted: this is a local dev substrate, not a production HA cluster. The production Kafka deployment (future `streaming-platform` project) uses 3× broker + 3× controller separated roles.
- **KRaft in combined mode is discouraged for production** by the Kafka team. *Mitigation:* explicitly scoped to `profiles: [minimal, streaming, full]` in a dev-only topology; ADR-0006 (future) will document the production split.
- **`apache/kafka` image is newer** than Confluent's `cp-kafka` and has less ecosystem tooling baked in. *Mitigation:* Schema Registry is Confluent-licensed and comes from `cp-schema-registry`; we use the right image for the right job.

## Links

- [KIP-500: Replace ZooKeeper with Self-Managed Metadata Quorum](https://cwiki.apache.org/confluence/display/KAFKA/KIP-500)
- [Kafka 4.0 release notes — ZK removal](https://kafka.apache.org/40/documentation.html)
