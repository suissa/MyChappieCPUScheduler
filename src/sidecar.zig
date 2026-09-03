const std = @import("std");
const ledger_mod = @import("ledger.zig");
const outbox_mod = @import("outbox.zig");
const types = @import("types.zig");

pub const SidecarError = ledger_mod.LedgerError || outbox_mod.OutboxError;

pub const CompletionAck = struct {
    outcome: types.CompletionOutcome,
    execution_completed: bool,
    outbox_sequence: ?u64 = null,
};

pub const DistributedSidecar = struct {
    ledger: ledger_mod.ExecutionLedger,
    outbox: outbox_mod.Outbox = .{},

    pub fn init(execution_id: u64, shard_count: u16) SidecarError!DistributedSidecar {
        var sidecar = DistributedSidecar{
            .ledger = try ledger_mod.ExecutionLedger.init(execution_id, shard_count),
        };
        _ = try sidecar.outbox.append(.{
            .sequence = 0,
            .kind = .execution_submitted,
            .execution_id = execution_id,
        });
        return sidecar;
    }

    pub fn leaseShard(self: *DistributedSidecar, shard_id: u16, worker_id: u64, now_ns: u64, lease_ns: u64) SidecarError!void {
        try self.ledger.lease(shard_id, worker_id, now_ns, lease_ns);
        const attempt = (try self.ledger.shard(shard_id)).attempt;
        _ = try self.outbox.append(.{
            .sequence = 0,
            .kind = .shard_leased,
            .execution_id = self.ledger.execution_id,
            .shard_id = shard_id,
            .worker_id = worker_id,
            .attempt = attempt,
        });
    }

    pub fn speculate(self: *DistributedSidecar, shard_id: u16, worker_id: u64) SidecarError!void {
        try self.ledger.speculate(shard_id, worker_id);
        const attempt = (try self.ledger.shard(shard_id)).attempt;
        _ = try self.outbox.append(.{
            .sequence = 0,
            .kind = .shard_speculated,
            .execution_id = self.ledger.execution_id,
            .shard_id = shard_id,
            .worker_id = worker_id,
            .attempt = attempt,
        });
    }

    pub fn completeShard(self: *DistributedSidecar, shard_id: u16, worker_id: u64, result_hash: u64) SidecarError!CompletionAck {
        const outcome = try self.ledger.complete(shard_id, worker_id, result_hash);
        if (outcome != .accepted) return .{ .outcome = outcome, .execution_completed = self.ledger.allComplete() };

        const sequence = try self.outbox.append(.{
            .sequence = 0,
            .kind = .shard_completed,
            .execution_id = self.ledger.execution_id,
            .shard_id = shard_id,
            .worker_id = worker_id,
            .attempt = (try self.ledger.shard(shard_id)).attempt,
        });

        if (self.ledger.allComplete()) {
            _ = try self.outbox.append(.{
                .sequence = 0,
                .kind = .execution_completed,
                .execution_id = self.ledger.execution_id,
            });
        }

        return .{
            .outcome = outcome,
            .execution_completed = self.ledger.allComplete(),
            .outbox_sequence = sequence,
        };
    }

    pub fn expireAndRequestRetries(self: *DistributedSidecar, now_ns: u64) SidecarError!u16 {
        var expired: u16 = 0;
        var i: u16 = 0;
        while (i < self.ledger.shard_count) : (i += 1) {
            const before = (try self.ledger.shard(i)).state;
            if (before != .leased) continue;
            const deadline = (try self.ledger.shard(i)).lease_deadline_ns;
            if (deadline > now_ns) continue;

            _ = self.ledger.expireLeases(now_ns);
            if ((try self.ledger.shard(i)).state == .retry_wait) {
                expired += 1;
                _ = try self.outbox.append(.{
                    .sequence = 0,
                    .kind = .shard_retry_requested,
                    .execution_id = self.ledger.execution_id,
                    .shard_id = i,
                    .attempt = (try self.ledger.shard(i)).attempt,
                });
            }
        }
        return expired;
    }
};

test "sidecar retries a missing worker and gathers completion" {
    var sidecar = try DistributedSidecar.init(77, 2);
    try sidecar.leaseShard(0, 10, 0, 100);
    try sidecar.leaseShard(1, 20, 0, 100);

    _ = try sidecar.completeShard(0, 10, 111);
    try std.testing.expectEqual(@as(u16, 1), try sidecar.expireAndRequestRetries(101));

    try sidecar.leaseShard(1, 30, 102, 100);
    const ack = try sidecar.completeShard(1, 30, 222);
    try std.testing.expect(ack.execution_completed);
    try std.testing.expect(sidecar.outbox.pendingCount() >= 6);
}
