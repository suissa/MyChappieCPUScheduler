const std = @import("std");
const registry_mod = @import("action_registry.zig");
const abi = @import("action_abi.zig");

pub fn main() !void {
    var gpa: std.heap.GeneralPurposeAllocator(.{}) = .init;
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);
    if (args.len != 6) return error.ExpectedModuleSemanticIdInputShardCountPrefix;

    const module_path = args[1];
    const semantic_id = args[2];
    const input_path = args[3];
    const shard_count = try std.fmt.parseInt(u16, args[4], 10);
    const prefix = args[5];
    if (shard_count == 0 or shard_count > 16) return error.InvalidShardCount;

    var registry: registry_mod.DynamicActionRegistry = .{};
    defer registry.deinit();
    try registry.load(module_path);
    const action = try registry.find(semantic_id);

    const input_file = try std.fs.cwd().openFile(input_path, .{});
    defer input_file.close();
    var input_buffer: [64 * 1024]u8 = undefined;
    const input_len = try input_file.read(&input_buffer);

    var expected: [abi.hash_len]u8 = undefined;
    const local_result = action.execute(input_buffer[0..input_len], &expected);
    if (local_result.status != .ok) return error.LocalExecutionFailed;

    var partials: [16 * abi.hash_len]u8 = undefined;
    var shard_index: u16 = 0;
    while (shard_index < shard_count) : (shard_index += 1) {
        var path_buffer: [512]u8 = undefined;
        const path = try std.fmt.bufPrint(&path_buffer, "{s}-{d}.bin", .{ prefix, shard_index });
        const file = try std.fs.cwd().openFile(path, .{});
        defer file.close();
        const offset = @as(usize, shard_index) * abi.hash_len;
        const len = try file.read(partials[offset .. offset + abi.hash_len]);
        if (len != abi.hash_len) return error.InvalidPartialLength;
    }

    var aggregate_output: [abi.hash_len]u8 = undefined;
    const aggregate_result = try action.aggregate(partials[0 .. @as(usize, shard_count) * abi.hash_len], shard_count, &aggregate_output);
    if (aggregate_result.status != .ok) return error.AggregationFailed;
    if (!std.mem.eql(u8, &expected, &aggregate_output)) return error.DistributedResultMismatch;

    std.debug.print("distributed verification ok: action={s} shards={d}\n", .{ semantic_id, shard_count });
}
