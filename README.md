# MyChappieCPUScheduler

A Zig 0.16 implementation of **Profile-Guided Durable Distributed Execution (PGDDE)** for AllasCode/MyChappie.

The project deliberately separates two responsibilities:

```text
CPUScheduler.zig
  = local compute governance
  = knows only the process/function executing on this machine
  = decides local / probe / offload / split-offload

DistributedSidecar
  = durable distributed execution
  = knows workers, shards, leases, retries, speculation and aggregation
  = returns completion/ACK information to the local scheduler boundary
```

The scheduler does **not** know remote server topology, NATS, QUIC, Kafka, retry destinations or result aggregation. Those belong to the sidecar.

## KNOWN and UNKNOWN

Every schedulable function has an independent `CostKnowledge` state.

- `unknown`: no trusted benchmark exists yet. Execution starts as a locally metered probe. If it crosses the compute threshold, remaining work may be handed to the sidecar only when the function is checkpointable/offloadable. Otherwise the current run finishes locally and its measurement becomes knowledge for the next run.
- `known`: benchmark evidence predicts CPU cost before execution, so the scheduler can avoid executing expensive work locally.

The default heavy-compute boundary is the **P90 of benchmarked function costs**. Benchmark cost alone never grants permission to distribute a function.

```text
expensive
+ offloadable
+ retry_safe
+ (partitionable + aggregation strategy, when split)
= distributed candidate
```

## Decisions

The local scheduler returns one of:

- `local`
- `probe_local`
- `offload`
- `split_offload`

For known partitionable work, shard count is derived from `estimated_cycles / p90_threshold` and bounded by configuration.

## Durable sidecar

The sidecar owns the resilient distributed lifecycle:

```text
Execution
  -> shard plan
  -> worker leases
  -> partial results
  -> expired-lease retry
  -> optional speculative duplicate for stragglers
  -> first valid result wins per shard
  -> gather completion
  -> ACK
```

The core uses a fixed-capacity ledger/outbox and no heap allocation on its scheduling path. In-memory state is not claimed to be durable storage: `ExecutionLedger` plus outbox events form the persistence boundary for adapters such as EventStoreDB, BadgerDB, Postgres or JetStream.

## Layout

```text
src/
  root.zig
  types.zig
  benchmark.zig
  scheduler.zig
  ledger.zig
  outbox.zig
  sidecar.zig
  main.zig
flows/cpu-scheduler.2flow
manifest.yml
config.yml
schema.yml
```

## Zig 0.16

This repository targets Zig `0.16.0`.

```bash
zig version
zig build test
zig build run
```

Zig 0.16 is the current stable release as of this implementation.

## Core invariant

> `CPUScheduler` governs only local compute. `DistributedSidecar` owns placement, retry, redistribution, speculative execution, gathering and completion.

See Issue #1 for the bootstrap scope.