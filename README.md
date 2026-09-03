# MyChappieCPUScheduler

A Zig 0.16 implementation of **Profile-Guided Durable Distributed Execution (PGDDE)** for AllasCode/MyChappie.

The runtime separates four responsibilities:

```text
DynamicActionRegistry
  = discovers atomic Actions by semantic_id
  = opens content-addressed dynamic modules through Allas Action ABI v1
  = runtime never @imports atomic Actions

LinuxMeasurementPlane
  = observes local Action execution
  = perf_event_open/PMU + cgroup v2
  = produces full / partial / timing-only evidence

CPUScheduler
  = local compute governance
  = consumes ActionDescriptor + CostProfile + local pressure
  = decides local / probe / offload / split-offload

DistributedSidecar
  = durable distributed execution
  = owns workers, shards, leases, retries, speculation and aggregation
  = returns completion/ACK information to the local scheduler boundary
```

`CPUScheduler` does not know `.so` paths, remote server topology, transports, retry destinations or result aggregation.

## Dynamic atomic Actions

Atomic Actions are independent dynamic modules. A module exports the stable C calling-convention **Allas Action ABI v1**:

```text
allas_action_descriptor
allas_action_execute
allas_action_execute_shard   # when partitionable
allas_action_aggregate       # when custom aggregation is declared
```

The descriptor carries ABI version, `semantic_id`, schema hash, artifact hash, distribution flags and optional known cost evidence. `DynamicActionRegistry` resolves the module; the scheduler only receives the normalized cost/distribution profile.

The reference crypto Actions are:

- `Crypto.IteratedSha256.Unknown` — begins as a measured local probe and can become known after measurement;
- `Crypto.IteratedSha256.Known` — publishes a known cost high enough to select direct `split_offload` before local execution.

Both partition the input into ordered byte ranges, produce 32-byte shard digests and deterministically aggregate those partials.

## Linux Measurement Plane

On Linux, an Action probe is observed through:

- `perf_event_open`: CPU cycles, instructions, cache misses and branch misses;
- cgroup v2: `cpu.stat`, current/peak memory, OOM events, CPU pressure and memory pressure;
- monotonic elapsed time.

PMU access can be restricted by kernel policy or container permissions. That does not fail the Action: evidence degrades to `partial` (cgroup/timing) or `timing_only` and explicitly records the available surface.

## KNOWN and UNKNOWN

Every schedulable Action has an independent `CostKnowledge` state.

- `unknown`: no trusted benchmark exists yet. Execution starts as a locally metered probe. If it crosses the compute threshold, remaining work may be handed to the sidecar only when checkpointable/offloadable. Otherwise the current run finishes locally and its measurement becomes knowledge for the next run.
- `known`: benchmark evidence predicts CPU cost before execution, so expensive work can be distributed without first running locally.

The default heavy-compute boundary is the **P90 of benchmarked Action costs**. Cost alone never grants distribution permission:

```text
expensive
+ offloadable
+ retry_safe
+ partitionable
+ aggregation strategy
= split distributed candidate
```

## Durable sidecar

```text
Execution
  -> shard plan
  -> worker leases
  -> partial results
  -> expired-lease retry
  -> optional speculative duplicate for stragglers
  -> first valid result wins per shard
  -> gather
  -> Action aggregate
  -> completion ACK
```

The core uses fixed-capacity ledger/outbox structures on its scheduling path. In-memory state is only the reference persistence adapter; the durable boundary is `ExecutionLedger + outbox`.

## Local multi-server simulation

`docker-compose.test.yml` uses multiple isolated worker containers on one host. Every worker loads the same Action `.so` dynamically.

```bash
zig build test
zig build action-test
bash scripts/docker-distribution-test.sh
```

The Docker gate validates:

- UNKNOWN: local probe shard + remote remaining shards;
- KNOWN: all shards begin directly in remote containers;
- distributed aggregate equals full execution of the exact same Action module.

Sidecar unit tests independently validate lease expiry/retry, multiple simultaneous expirations, speculation and duplicate-result idempotency.

## Layout

```text
src/
  action_abi.zig
  action_registry.zig
  measurement.zig
  scheduler.zig
  ledger.zig
  outbox.zig
  sidecar.zig
  action_demo.zig
  action_worker.zig
  distributed_verify.zig

actions/
  crypto-unknown/
    README.md
    manifest.yml
    config.yml
    schema.yml
    action.zig
  crypto-known/
    README.md
    manifest.yml
    config.yml
    schema.yml
    action.zig

flows/cpu-scheduler.2flow
manifest.yml
config.yml
schema.yml
docker-compose.test.yml
```

## Core invariant

> Atomic Actions are runtime-loaded modules. `CPUScheduler` governs only local compute. `LinuxMeasurementPlane` observes local execution. `DistributedSidecar` owns placement, retry, redistribution, speculative execution, gathering and completion.
