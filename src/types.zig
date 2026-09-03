pub const CostKnowledge = enum {
    unknown,
    known,
};

pub const ComputeClass = enum {
    normal,
    heavy,
    extreme,
};

pub const AggregationStrategy = enum {
    none,
    concatenate,
    sum,
    custom,
};

pub const ScheduleKind = enum {
    local,
    probe_local,
    offload,
    split_offload,
};

pub const ScheduleReason = enum {
    below_threshold,
    unknown_cost,
    local_pressure,
    known_heavy_cost,
    not_offloadable,
    not_retry_safe,
};

pub const FunctionCostProfile = struct {
    function_id: []const u8,
    knowledge: CostKnowledge,
    estimated_cycles: u64 = 0,
    offloadable: bool = false,
    partitionable: bool = false,
    checkpointable: bool = false,
    retry_safe: bool = false,
    aggregation: AggregationStrategy = .none,
    recommended_shards: u16 = 1,

    pub fn splitSafe(self: FunctionCostProfile) bool {
        return self.offloadable and self.partitionable and self.retry_safe and self.aggregation != .none;
    }
};

pub const LocalPressure = struct {
    cpu_percent: u8 = 0,
    runnable_tasks: u16 = 0,
};

pub const ScheduleDecision = struct {
    kind: ScheduleKind,
    reason: ScheduleReason,
    requested_shards: u16 = 1,
    predicted_cycles: u64 = 0,
};

pub const ProbeDecision = enum {
    continue_local,
    request_sidecar,
    finish_local_and_learn,
};

pub const ShardState = enum {
    queued,
    leased,
    retry_wait,
    completed,
};

pub const CompletionOutcome = enum {
    accepted,
    duplicate,
    stale_worker,
};

pub const ExecutionState = enum {
    collecting,
    completed,
};
