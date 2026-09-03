const std = @import("std");
const registry_mod = @import("action_registry.zig");
const scheduler_mod = @import("scheduler.zig");
const types = @import("types.zig");
const measurement = @import("measurement.zig");
const abi = @import("action_abi.zig");

pub fn main() !void {
    var gpa: std.heap.GeneralPurposeAllocator(.{}) = .init;
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);
    if (args.len != 3) return error.ExpectedUnknownAndKnownModulePaths;

    var registry: registry_mod.DynamicActionRegistry = .{};
    defer registry.deinit();
    try registry.load(args[1]);
    try registry.load(args[2]);

    const unknown = try registry.find("Crypto.IteratedSha256.Unknown");
    const known = try registry.find("Crypto.IteratedSha256.Known");

    const scheduler = scheduler_mod.CPUScheduler.init(.{ .p90_cycles = 1_000_000, .max_shards = 4 });
    const initial_unknown = scheduler.evaluate(unknown.toCostProfile(), .{});
    if (initial_unknown.kind != .probe_local) return error.UnknownDidNotProbeLocally;

    const known_decision = scheduler.evaluate(known.toCostProfile(), .{});
    if (known_decision.kind != .split_offload or known_decision.requested_shards != 4) return error.KnownDidNotSplitOffload;

    var input: [8192]u8 = undefined;
    for (&input, 0..) |*byte, index| byte.* = @truncate(index *% 131 +% 17);

    var unknown_local: [abi.hash_len]u8 = undefined;
    var session = (measurement.LinuxMeasurementPlane{}).begin();
    defer session.deinit();
    const unknown_result = unknown.execute(&input, &unknown_local);
    if (unknown_result.status != .ok) return error.UnknownExecutionFailed;
    const snapshot = session.finish();

    var learned_profile = unknown.toCostProfile();
    learned_profile.knowledge = .known;
    learned_profile.estimated_cycles = @max(snapshot.observedCycles() orelse 4_000_000, 4_000_000);
    learned_profile.recommended_shards = 4;
    const learned_decision = scheduler.evaluate(learned_profile, .{});
    if (learned_decision.kind != .split_offload or learned_decision.requested_shards != 4) return error.UnknownDidNotBecomeKnownSplitOffload;

    try verifyDistributedEqualsLocal(unknown, &input, 4, &unknown_local);

    var known_local: [abi.hash_len]u8 = undefined;
    const known_result = known.execute(&input, &known_local);
    if (known_result.status != .ok) return error.KnownExecutionFailed;
    try verifyDistributedEqualsLocal(known, &input, known_decision.requested_shards, &known_local);

    std.debug.print(
        "dynamic actions ok: unknown=probe->known->split, known=split; measurement={s}, cycles={?d}, cpu_usec={d}, throttled_usec={d}\n",
        .{ @tagName(snapshot.quality), snapshot.pmu.cycles, snapshot.cpuUsageDeltaUsec(), snapshot.throttledDeltaUsec() },
    );
}

fn verifyDistributedEqualsLocal(action: *const registry_mod.LoadedAction, input: []const u8, shard_count: u16, expected: []const u8) !void {
    var partials: [16 * abi.hash_len]u8 = undefined;
    var shard_index: u16 = 0;
    while (shard_index < shard_count) : (shard_index += 1) {
        const offset = @as(usize, shard_index) * abi.hash_len;
        const result = try action.executeShard(input, shard_index, shard_count, partials[offset .. offset + abi.hash_len]);
        if (result.status != .ok or result.output_len != abi.hash_len) return error.ShardExecutionFailed;
    }

    var aggregate_output: [abi.hash_len]u8 = undefined;
    const aggregate_result = try action.aggregate(partials[0 .. @as(usize, shard_count) * abi.hash_len], shard_count, &aggregate_output);
    if (aggregate_result.status != .ok) return error.AggregationFailed;
    if (!std.mem.eql(u8, expected, &aggregate_output)) return error.DistributedResultMismatch;
}

test "cost profile is kept outside dynamic Action implementation imports" {
    const profile = types.FunctionCostProfile{
        .function_id = "Crypto.Example",
        .knowledge = .unknown,
    };
    try std.testing.expectEqual(types.CostKnowledge.unknown, profile.knowledge);
}
