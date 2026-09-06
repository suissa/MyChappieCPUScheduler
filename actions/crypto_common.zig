const std = @import("std");
const abi = @import("action_abi");

const Sha256 = std.crypto.hash.sha2.Sha256;
pub const digest_len: usize = Sha256.digest_length;
pub const max_shards: u16 = 16;

pub fn executeFull(input: []const u8, rounds: u32, shard_count: u16, output: []u8) abi.ActionCallResult {
    if (output.len < digest_len) return .{ .status = .output_too_small, .output_len = digest_len };
    if (shard_count == 0 or shard_count > max_shards) return .{ .status = .invalid_shard, .output_len = 0 };

    var partials: [max_shards * digest_len]u8 = undefined;
    var shard_index: u16 = 0;
    while (shard_index < shard_count) : (shard_index += 1) {
        const offset = @as(usize, shard_index) * digest_len;
        hashShard(input, shard_index, shard_count, rounds, partials[offset .. offset + digest_len]) catch {
            return .{ .status = .invalid_shard, .output_len = 0 };
        };
    }
    return aggregate(partials[0 .. @as(usize, shard_count) * digest_len], shard_count, output);
}

pub fn executeShard(input: []const u8, shard_index: u16, shard_count: u16, rounds: u32, output: []u8) abi.ActionCallResult {
    if (output.len < digest_len) return .{ .status = .output_too_small, .output_len = digest_len };
    hashShard(input, shard_index, shard_count, rounds, output[0..digest_len]) catch {
        return .{ .status = .invalid_shard, .output_len = 0 };
    };
    return .{ .status = .ok, .output_len = digest_len };
}

pub fn aggregate(partials: []const u8, partial_count: u16, output: []u8) abi.ActionCallResult {
    if (partial_count == 0 or partial_count > max_shards) return .{ .status = .invalid_shard, .output_len = 0 };
    if (partials.len != @as(usize, partial_count) * digest_len) return .{ .status = .invalid_input, .output_len = 0 };
    if (output.len < digest_len) return .{ .status = .output_too_small, .output_len = digest_len };
    Sha256.hash(partials, output[0..digest_len], .{});
    return .{ .status = .ok, .output_len = digest_len };
}

fn hashShard(input: []const u8, shard_index: u16, shard_count: u16, rounds: u32, output: []u8) !void {
    if (shard_count == 0 or shard_index >= shard_count) return error.InvalidShard;
    const start = (input.len * @as(usize, shard_index)) / @as(usize, shard_count);
    const end = (input.len * @as(usize, shard_index + 1)) / @as(usize, shard_count);

    var digest: [digest_len]u8 = undefined;
    Sha256.hash(input[start..end], &digest, .{});

    var round: u32 = 0;
    while (round < rounds) : (round += 1) {
        var next: [digest_len]u8 = undefined;
        Sha256.hash(&digest, &next, .{});
        digest = next;
    }
    @memcpy(output[0..digest_len], &digest);
}
