const std = @import("std");
const registry_mod = @import("action_registry.zig");
const abi = @import("action_abi.zig");

pub fn main() !void {
    var gpa: std.heap.GeneralPurposeAllocator(.{}) = .init;
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);
    if (args.len != 8) return error.ExpectedModuleSemanticIdInputShardIndexShardCountOutputWorkerId;

    const module_path = args[1];
    const semantic_id = args[2];
    const input_path = args[3];
    const shard_index = try std.fmt.parseInt(u16, args[4], 10);
    const shard_count = try std.fmt.parseInt(u16, args[5], 10);
    const output_path = args[6];
    const worker_id = args[7];

    var registry: registry_mod.DynamicActionRegistry = .{};
    defer registry.deinit();
    try registry.load(module_path);
    const action = try registry.find(semantic_id);

    const input_file = try std.fs.cwd().openFile(input_path, .{});
    defer input_file.close();
    var input_buffer: [64 * 1024]u8 = undefined;
    const input_len = try input_file.read(&input_buffer);

    var output: [abi.hash_len]u8 = undefined;
    const result = try action.executeShard(input_buffer[0..input_len], shard_index, shard_count, &output);
    if (result.status != .ok or result.output_len != abi.hash_len) return error.ActionShardFailed;

    const output_file = try std.fs.cwd().createFile(output_path, .{ .truncate = true });
    defer output_file.close();
    try output_file.writeAll(output[0..result.output_len]);

    std.debug.print("worker={s} action={s} shard={d}/{d} result=ok\n", .{ worker_id, semantic_id, shard_index, shard_count });
}
