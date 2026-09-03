const std = @import("std");
const cpu = @import("root.zig");

pub fn main() !void {
    const scheduler = cpu.CPUScheduler.init(.{
        .p90_cycles = 1_000_000,
        .overload_cpu_percent = 85,
        .max_shards = 8,
    });

    const profile = cpu.types.FunctionCostProfile{
        .function_id = "Example.ImageTransform",
        .knowledge = .known,
        .estimated_cycles = 2_700_000,
        .offloadable = true,
        .partitionable = true,
        .checkpointable = true,
        .retry_safe = true,
        .aggregation = .concatenate,
    };

    const decision = scheduler.evaluate(profile, .{ .cpu_percent = 35 });
    std.debug.print("function={s} decision={s} shards={d} predicted_cycles={d}\n", .{
        profile.function_id,
        @tagName(decision.kind),
        decision.requested_shards,
        decision.predicted_cycles,
    });

    if (decision.kind == .split_offload or decision.kind == .offload) {
        var sidecar = try cpu.DistributedSidecar.init(1, decision.requested_shards);
        var shard_id: u16 = 0;
        while (shard_id < decision.requested_shards) : (shard_id += 1) {
            try sidecar.leaseShard(shard_id, 1000 + shard_id, 0, 1_000_000);
            _ = try sidecar.completeShard(shard_id, 1000 + shard_id, 10_000 + shard_id);
        }
        std.debug.print("sidecar_completed={} pending_outbox_events={d}\n", .{
            sidecar.ledger.allComplete(),
            sidecar.outbox.pendingCount(),
        });
    }
}
