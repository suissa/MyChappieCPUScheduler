# Implementation Plan

## v0.1 — deterministic core

- [x] Zig 0.16 build.
- [x] KNOWN / UNKNOWN cost knowledge.
- [x] P90 benchmark helper.
- [x] local/probe/offload/split-offload decisions.
- [x] explicit distributability constraints.
- [x] fixed-capacity execution ledger.
- [x] leases and expired-work retry state.
- [x] speculative secondary worker.
- [x] first-valid-result-wins deduplication.
- [x] outbox event model.
- [x] 2flow topology + execution semantics.

## v0.2 — measurement plane

- [ ] Linux CPU-cycle sampler using `perf_event_open`.
- [ ] wall/CPU time and context-switch evidence.
- [ ] cgroup v2 integration.
- [ ] environment fingerprint for benchmark comparability.
- [ ] profile registry persisted by semantic function ID + EvidenceKey.
- [ ] UNKNOWN -> KNOWN promotion policy.

## v0.3 — durable sidecar adapters

- [ ] persistent ledger adapter.
- [ ] persistent outbox adapter.
- [ ] worker registry and capability matching.
- [ ] NATS adapter.
- [ ] QUIC adapter.
- [ ] configurable lease/retry/backoff.
- [ ] straggler detector using benchmark percentile evidence.

## v0.4 — typed partition/reduce

- [ ] partition contract generated from AllasCode schemas.
- [ ] reducer/aggregator interface.
- [ ] deterministic shard input hashes.
- [ ] output/result content hashes.
- [ ] retry-safe effects contract.

## v0.5 — FACoP integration

- [ ] consume BenchmarkResult from FACoP Evidence Passport.
- [ ] generate FunctionCostProfile automatically.
- [ ] compare same-VPS cohorts.
- [ ] invalidate cost profiles when source/toolchain/environment EvidenceKey changes.
- [ ] feed scheduling labels back into the AllasCode semantic graph.
