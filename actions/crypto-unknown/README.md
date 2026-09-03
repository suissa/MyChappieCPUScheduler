# Crypto.IteratedSha256.Unknown

Dynamic Allas Action used to validate the `UNKNOWN` scheduler mode. The runtime does not import this implementation; it resolves the compiled shared object by `semantic_id` through Allas Action ABI v1.

The first execution is a measured local probe. `LinuxMeasurementPlane` captures PMU/cgroup evidence and the resulting cost profile can promote later execution to `KNOWN`. The Action is partitionable, checkpointable and retry-safe, so work beyond the local threshold may be delegated to the distributed sidecar.

Each shard hashes a contiguous byte range and performs the configured number of additional SHA-256 rounds. Aggregation is deterministic: concatenate ordered 32-byte partial digests and SHA-256 that byte sequence. Therefore local full execution and distributed execution have the same result contract.
