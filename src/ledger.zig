const std = @import("std");
const types = @import("types.zig");

pub const max_shards: usize = 64;

pub const LedgerError = error{
    InvalidShardCount,
    InvalidShard,
    InvalidState,
    SecondaryLeaseExists,
};

pub const ShardRecord = struct {
    shard_id: u16,
    state: types.ShardState = .queued,
    attempt: u16 = 0,
    primary_worker: ?u64 = null,
    secondary_worker: ?u64 = null,
    lease_deadline_ns: u64 = 0,
    result_hash: ?u64 = null,
};

pub const ExecutionLedger = struct {
    execution_id: u64,
    shard_count: u16,
    completed_count: u16 = 0,
    state: types.ExecutionState = .collecting,
    shards: [max_shards]ShardRecord,

    pub fn init(execution_id: u64, shard_count: u16) LedgerError!ExecutionLedger {
        if (shard_count == 0 or shard_count > max_shards) return error.InvalidShardCount;

        var ledger = ExecutionLedger{
            .execution_id = execution_id,
            .shard_count = shard_count,
            .shards = undefined,
        };

        var i: usize = 0;
        while (i < shard_count) : (i += 1) {
            ledger.shards[i] = .{ .shard_id = @intCast(i) };
        }
        return ledger;
    }

    pub fn lease(self: *ExecutionLedger, shard_id: u16, worker_id: u64, now_ns: u64, lease_ns: u64) LedgerError!void {
        const shard = try self.get(shard_id);
        if (shard.state != .queued and shard.state != .retry_wait) return error.InvalidState;
        shard.state = .leased;
        shard.attempt += 1;
        shard.primary_worker = worker_id;
        shard.secondary_worker = null;
        shard.lease_deadline_ns = now_ns + lease_ns;
    }

    pub fn speculate(self: *ExecutionLedger, shard_id: u16, worker_id: u64) LedgerError!void {
        const shard = try self.get(shard_id);
        if (shard.state != .leased) return error.InvalidState;
        if (shard.secondary_worker != null) return error.SecondaryLeaseExists;
        if (shard.primary_worker == worker_id) return error.SecondaryLeaseExists;
        shard.secondary_worker = worker_id;
    }

    pub fn complete(self: *ExecutionLedger, shard_id: u16, worker_id: u64, result_hash: u64) LedgerError!types.CompletionOutcome {
        const shard = try self.get(shard_id);
        if (shard.state == .completed) return .duplicate;
        if (shard.state != .leased) return error.InvalidState;
        if (shard.primary_worker != worker_id and shard.secondary_worker != worker_id) return .stale_worker;

        shard.state = .completed;
        shard.result_hash = result_hash;
        shard.primary_worker = null;
        shard.secondary_worker = null;
        self.completed_count += 1;
        if (self.completed_count == self.shard_count) self.state = .completed;
        return .accepted;
    }

    pub fn expireShard(self: *ExecutionLedger, shard_id: u16, now_ns: u64) LedgerError!bool {
        const shard = try self.get(shard_id);
        if (shard.state != .leased or shard.lease_deadline_ns > now_ns) return false;
        shard.state = .retry_wait;
        shard.primary_worker = null;
        shard.secondary_worker = null;
        return true;
    }

    pub fn expireLeases(self: *ExecutionLedger, now_ns: u64) u16 {
        var expired: u16 = 0;
        var i: u16 = 0;
        while (i < self.shard_count) : (i += 1) {
            if (self.expireShard(i, now_ns) catch false) expired += 1;
        }
        return expired;
    }

    pub fn allComplete(self: *const ExecutionLedger) bool {
        return self.state == .completed;
    }

    pub fn shard(self: *const ExecutionLedger, shard_id: u16) LedgerError!*const ShardRecord {
        if (shard_id >= self.shard_count) return error.InvalidShard;
        return &self.shards[shard_id];
    }

    fn get(self: *ExecutionLedger, shard_id: u16) LedgerError!*ShardRecord {
        if (shard_id >= self.shard_count) return error.InvalidShard;
        return &self.shards[shard_id];
    }
};

test "expired lease becomes retryable" {
    var ledger = try ExecutionLedger.init(42, 2);
    try ledger.lease(0, 10, 100, 50);
    try std.testing.expectEqual(@as(u16, 1), ledger.expireLeases(151));
    try std.testing.expectEqual(types.ShardState.retry_wait, (try ledger.shard(0)).state);
    try ledger.lease(0, 11, 152, 50);
    try std.testing.expectEqual(@as(u16, 2), (try ledger.shard(0)).attempt);
}

test "multiple leases expire independently in the same tick" {
    var ledger = try ExecutionLedger.init(99, 2);
    try ledger.lease(0, 10, 0, 100);
    try ledger.lease(1, 20, 0, 100);
    try std.testing.expectEqual(@as(u16, 2), ledger.expireLeases(101));
    try std.testing.expectEqual(types.ShardState.retry_wait, (try ledger.shard(0)).state);
    try std.testing.expectEqual(types.ShardState.retry_wait, (try ledger.shard(1)).state);
}

test "speculative workers use first-valid-result-wins semantics" {
    var ledger = try ExecutionLedger.init(7, 1);
    try ledger.lease(0, 100, 0, 1000);
    try ledger.speculate(0, 200);
    try std.testing.expectEqual(types.CompletionOutcome.accepted, try ledger.complete(0, 200, 999));
    try std.testing.expectEqual(types.CompletionOutcome.duplicate, try ledger.complete(0, 100, 999));
    try std.testing.expect(ledger.allComplete());
}
