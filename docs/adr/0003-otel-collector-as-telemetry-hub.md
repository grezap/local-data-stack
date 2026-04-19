# ADR-0003: OpenTelemetry Collector as the single telemetry hub

- **Status:** Accepted
- **Date:** 2026-04-19
- **Deciders:** Greg Zapantis

## Context

Apps need to emit three signal types — **metrics, traces, logs** — and have them land in three different backends: Prometheus, Jaeger, Seq. The naive wiring is:

```
app ──▶ Prometheus client ──▶ Prometheus
app ──▶ Jaeger client     ──▶ Jaeger
app ──▶ Serilog sink      ──▶ Seq
```

…which couples every app to three vendor-specific SDKs, three endpoints, three auth setups, three retry strategies. Swapping Jaeger for Tempo or Seq for Loki becomes an N-service code change.

## Decision

All application code emits **OTLP only** (gRPC on `:4317` or HTTP on `:4318`) and knows nothing about Prometheus, Jaeger, or Seq. An **OpenTelemetry Collector** (`otel/opentelemetry-collector-contrib`) sits in the middle and fans out:

```
app ──OTLP──▶ otel-collector ──▶ prometheus exporter :8889 (Prom scrapes)
                              ├──▶ otlp/jaeger  (traces)
                              └──▶ otlphttp/seq (logs)
```

The collector is the *only* component that learns backend names. Apps carry exactly one telemetry dependency: the OTLP exporter. Backend changes are a collector-config PR.

## Consequences

### Positive

- **Zero vendor lock-in in app code.** Swap Jaeger → Tempo, Seq → Loki, Prometheus → Mimir by editing `otel-collector-config.yaml`. App binaries are unchanged.
- **Resource enrichment in one place.** `deployment.environment`, `service.namespace`, Kubernetes/Nomad attributes are injected centrally by the `resource` processor.
- **Back-pressure and batching are solved once.** The `memory_limiter` + `batch` processors protect every backend; apps don't re-implement them.
- **Production-path identical.** Same collector config pattern scales from dev (`contrib` binary, one replica) to prod (sidecar/gateway deployment, horizontal scaling).

### Negative / mitigations

- **One more container to operate.** *Mitigation:* collector has a `health_check` extension and self-metrics on `:8888`; dashboards panel watches its throughput.
- **OTLP-logs in some SDKs is newer than mature Prometheus/Serilog pipelines.** *Mitigation:* .NET 10 + OpenTelemetry 1.10 has stable OTLP logs; we pin versions project-side.
- **Extra network hop** (~0.1 ms on localhost) versus direct exporters. Accepted — the decoupling value dwarfs the cost.

## Alternatives considered

- **Direct exporters per signal.** Rejected: N×M coupling, as above.
- **Fluent Bit + Prometheus remote-write + Jaeger direct.** Rejected: three tools to operate instead of one; fragmented config.
- **Vector.** Good logs/metrics story, weaker traces ecosystem, not OTel-native.

## Links

- [OpenTelemetry Collector — Architecture](https://opentelemetry.io/docs/collector/architecture/)
- [OTLP specification](https://github.com/open-telemetry/opentelemetry-specification/blob/main/specification/protocol/otlp.md)
- ADR-0001 (compose-first) — provides the host for this collector.
