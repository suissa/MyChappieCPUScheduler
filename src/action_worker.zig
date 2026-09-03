const std = @import("std");
const registry_mod = @import("action_registry.zig");
const abi = @import("action_abi.zig");

pub fn main() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var args = try std.process.argsWithAllocator(allocator);
    defer args.deinit();
    _ = args.next() orelse return error.ExpectedProgramName;
    const module_path = args.next() orelse return error.ExpectedModulePath;
    const semantic_id = args.next() orelse return error.ExpectedSemanticId;
    const input_path = args.next() orelse return error.ExpectedInputPath;
    const shard_index_text = args.next() orelse return error.ExpectedShardIndex;
    const shard_count_text = args.next() orelse return error.ExpectedShardCount;
    const output_path = args.next() orelse return error.ExpectedOutputPath;
    const worker_id = args.next() orelse return error.ExpectedWorkerId;
    if (args.next() != null) return error.TooManyArguments;

    const shard_index = try std.fmt.parseInt(u16, shard_index_text, 10);
    const shard_count = try std.fmt.parseInt(u16, shard_count_text, 10);

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
