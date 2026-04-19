# Changelog

All notable changes to this project are documented in this file.
The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added
- Windows-native developer path: `run.ps1` (PowerShell 7+ task runner) mirroring every `make` verb (`up`, `down`, `nuke`, `restart`, `pull`, `ps`, `logs`, `health`, `urls`, `validate`, `smoke`, `fmt`).
- `scripts/smoke.ps1` — PowerShell end-to-end smoke test equivalent to `scripts/smoke.sh`.
- `.gitattributes` enforcing LF for `*.sh` / YAML / JSON / SQL / Markdown and CRLF for `*.ps1` / `*.bat`, preventing the `bash\r: command not found` trap on cross-platform checkouts.
- README Windows quickstart, execution-policy note, and expanded troubleshooting for Windows-specific issues.
- CONTRIBUTING: cross-platform rules for new scripts and docs.

### Planned
- JMX receiver in OTel Collector for Kafka broker metrics
- Prometheus alerting rules and Grafana contact points
- Tempo evaluation alongside Jaeger v2
- CI matrix adding a `windows-latest` runner exercising `run.ps1 smoke` against Docker Desktop

## [0.1.0] — 2026-04-19

### Added
- Initial nine-service Compose stack: Kafka (KRaft 3.8.1), Schema Registry 7.7.1, ClickHouse 24.8.7.41, Redis 7.4, OTel Collector 0.113.0, Prometheus v3.0.1, Grafana 11.3.0, Jaeger v2.0.0, Seq 2024.3.
- Compose profiles: `minimal`, `streaming`, `analytics`, `observability`, `full`.
- OpenTelemetry Collector configured as a single telemetry hub fanning out to Prometheus / Jaeger / Seq.
- Grafana provisioned with datasources (Prometheus, Jaeger, Seq, ClickHouse) and two starter dashboards.
- ClickHouse bootstrap SQL: `nexus.events` with `SummingMergeTree` 5-minute rollup MV.
- Host ports bound exclusively to `127.0.0.1`.
- `Makefile` contract: `up`, `down`, `nuke`, `ps`, `logs`, `health`, `smoke`, `validate`, `urls`, `fmt`.
- End-to-end smoke test (`scripts/smoke.sh`) exercising every data plane.
- ADRs: 0001 (compose-first topology), 0002 (KRaft over ZooKeeper), 0003 (OTel Collector as single telemetry hub).
- Case study and architecture documents.
- GitHub Actions CI: compose validate, smoke test, CodeQL, Trivy image scan.
- Dependabot configuration for weekly image-tag updates.
- MIT license.

[Unreleased]: https://github.com/grezap/local-data-stack/compare/v0.1.0...HEAD
[0.1.0]: https://github.com/grezap/local-data-stack/releases/tag/v0.1.0
