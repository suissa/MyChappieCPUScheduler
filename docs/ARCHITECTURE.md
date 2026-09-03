# Architecture

## 1. Profile-Guided Durable Distributed Execution

MyChappieCPUScheduler combines several established distributed-computing mechanisms behind a strict ownership boundary:

- profile-guided scheduling;
- hierarchical/two-level scheduling;
- scatter/gather;
- durable task ledger;
- leases and retry;
- straggler mitigation;
- speculative execution;
- idempotent first-result commit.

The local scheduler is intentionally not a cluster scheduler.

```text
Function request
      |
      v
CPUScheduler
  local knowledge only
      |
      +-- local/probe --> local CPU
      |
      +-- offload -----> DistributedSidecar
                              |
                              +--> worker A
                              +--> worker B
                              +--> worker C
                              |
                              +--> retry/speculate
                              +--> gather
                              +--> completion ACK
```

## 2. Why KNOWN/UNKNOWN are knowledge states

`KNOWN` and `UNKNOWN` do not mean cheap/heavy. They mean whether trusted cost evidence exists.

A KNOWN cheap function remains local. A KNOWN heavy function can be offloaded before local execution. An UNKNOWN function must first be measured unless local pressure policy elects to reject execution at a higher layer.

After a successful benchmark/profile observation, an UNKNOWN profile can be promoted to KNOWN by an external profile registry. The scheduler itself does not own persistent benchmark storage.

## 3. P90 threshold

The scheduler consumes a threshold generated from benchmark evidence. The reference helper computes nearest-rank P90.

The benchmark subsystem should measure comparable functions under a normalized environment and publish the threshold plus per-function profile. The scheduler only consumes that evidence.

## 4. Distribution safety

A function is distributable only when its contract says so.

- `offloadable`: the whole function can execute elsewhere.
- `partitionable`: it can be split into independent work shards.
- `checkpointable`: an UNKNOWN in-flight execution can expose remaining work safely.
- `retry_safe`: retry/duplicate execution cannot corrupt semantics.
- `aggregation`: defines how partial results become the final result.

For split execution all of `offloadable + partitionable + retry_safe + aggregation != none` are required.

## 5. Durable ledger

Each execution receives a stable ID and a fixed set of shards. Each shard records state, attempt, primary/secondary lease, deadline and committed result hash.

A lease timeout transitions the shard to `retry_wait`. A later worker can lease it without changing the shard identity.

Speculation adds a secondary worker while the primary lease still exists. Either worker may complete first. The first valid completion commits the shard; later completions are duplicates.

## 6. Outbox semantics

The outbox records domain events emitted by sidecar state transitions. ACK advances the delivery cursor but does not erase core history in v0.1.

A persistent adapter should commit ledger state and outbox append atomically whenever its storage engine permits it.

## 7. Aggregation

The reference core tracks completion and result hashes; it does not interpret arbitrary result payloads. Aggregation is an adapter/typed behavior associated with the function contract.

This prevents the scheduler core from becoming aware of application payloads.

## 8. Future Linux adapter

A Linux implementation can add:

- `perf_event_open` / PMU cycle sampling;
- cgroup v2 CPU accounting;
- eBPF observation;
- CPU affinity/NUMA awareness;
- local pressure sampling;
- process checkpoints for explicitly checkpointable work.

Those measurements feed the same semantic types and do not change the scheduler contract.
