# Crypto.IteratedSha256.Known

Dynamic Allas Action used to validate the `KNOWN` scheduler mode. Its benchmark-derived cost profile is available before invocation, so `CPUScheduler` may select `split_offload` without executing any shard locally.

The Action is loaded by `semantic_id` through Allas Action ABI v1. It is partitionable, checkpointable and retry-safe. Four independent workers can execute the ordered contiguous byte-range shards and the Action-specific aggregate function reconstructs the deterministic final digest.

The CI Docker scenario verifies that all shards can start in separate containers and that their aggregate equals the result of a full execution of the same content-addressed Action module.
