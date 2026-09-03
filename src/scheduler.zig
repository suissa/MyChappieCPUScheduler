const std = @import("std");
const types = @import("types.zig");

pub const SchedulerConfig = struct {
    p90_cycles: u64,
    overload_cpu_percent: u8 = 85,
    max_shards: u16 = 16,
};

pub const CPUScheduler = struct {
    config: SchedulerConfig,

    pub fn init(config: SchedulerConfig) CPUScheduler {
        return .{ .config = config };
    }

    pub fn evaluate(self: CPUScheduler, profile: types.FunctionCostProfile, pressure: types.LocalPressure) types.ScheduleDecision {
        if (profile.knowledge == .unknown) {
            return .{
                .kind = .probe_local,
                .reason = .unknown_cost,
                .predicted_cycles = 0,
            };
        }

        const overloaded = pressure.cpu_percent >= self.config.overload_cpu_percent;
        const expensive = profile.estimated_cycles > self.config.p90_cycles;

        if (!overloaded and !expensive) {
            return .{
                .kind = .local,
                .reason = .below_threshold,
                .predicted_cycles = profile.estimated_cycles,
            };
        }

        if (!profile.offloadable) {
            return .{
                .kind = .local,
                .reason = .not_offloadable,
                .predicted_cycles = profile.estimated_cycles,
            };
        }
        if (!profile.retry_safe) {
            return .{
                .kind = .local,
                .reason = .not_retry_safe,
                .predicted_cycles = profile.estimated_cycles,
            };
        }

        if (profile.splitSafe()) {
            return .{
                .kind = .split_offload,
                .reason = if (overloaded) .local_pressure else .known_heavy_cost,
                .requested_shards = self.recommendedShardCount(profile),
                .predicted_cycles = profile.estimated_cycles,
            };
        }

        return .{
            .kind = .offload,
            .reason = if (overloaded) .local_pressure else .known_heavy_cost,
            .requested_shards = 1,
            .predicted_cycles = profile.estimated_cycles,
        };
    }

    pub fn observeUnknown(self: CPUScheduler, profile: types.FunctionCostProfile, cycles_so_far: u64) types.ProbeDecision {
        if (cycles_so_far <= self.config.p90_cycles) return .continue_local;

        if (profile.offloadable and profile.retry_safe and profile.checkpointable) {
            return .request_sidecar;
        }

        return .finish_local_and_learn;
    }

    fn recommendedShardCount(self: CPUScheduler, profile: types.FunctionCostProfile) u16 {
        if (self.config.p90_cycles == 0) return self.config.max_shards;

        const quotient = profile.estimated_cycles / self.config.p90_cycles;
        const remainder = profile.estimated_cycles % self.config.p90_cycles;
        var computed: u64 = quotient + @intFromBool(remainder != 0);
        if (computed < 2) computed = 2;

        var requested = computed;
        if (profile.recommended_shards > 1 and @as(u64, profile.recommended_shards) > requested) {
            requested = profile.recommended_shards;
        }
        if (requested > self.config.max_shards) requested = self.config.max_shards;
        return @intCast(requested);
    }
};

test "unknown work begins as a local probe" {
    const scheduler = CPUScheduler.init(.{ .p90_cycles = 1_000 });
    const decision = scheduler.evaluate(.{
        .function_id = "Unknown.fn",
        .knowledge = .unknown,
        .offloadable = true,
        .checkpointable = true,
        .retry_safe = true,
    }, .{});
    try std.testing.expectEqual(types.ScheduleKind.probe_local, decision.kind);
}

test "known heavy partitionable work is split without local execution" {
    const scheduler = CPUScheduler.init(.{ .p90_cycles = 1_000, .max_shards = 8 });
    const decision = scheduler.evaluate(.{
        .function_id = "Heavy.fn",
        .knowledge = .known,
        .estimated_cycles = 3_200,
        .offloadable = true,
        .partitionable = true,
        .checkpointable = true,
        .retry_safe = true,
        .aggregation = .sum,
    }, .{});
    try std.testing.expectEqual(types.ScheduleKind.split_offload, decision.kind);
    try std.testing.expectEqual(@as(u16, 4), decision.requested_shards);
}

test "unknown non-checkpointable work learns locally after threshold" {
    const scheduler = CPUScheduler.init(.{ .p90_cycles = 1_000 });
    const profile = types.FunctionCostProfile{
        .function_id = "Opaque.fn",
        .knowledge = .unknown,
        .offloadable = true,
        .retry_safe = true,
        .checkpointable = false,
    };
    try std.testing.expectEqual(types.ProbeDecision.finish_local_and_learn, scheduler.observeUnknown(profile, 1_001));
}
