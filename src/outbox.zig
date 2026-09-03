const std = @import("std");

pub const max_events: usize = 128;

pub const EventKind = enum {
    execution_submitted,
    shard_leased,
    shard_retry_requested,
    shard_speculated,
    shard_completed,
    execution_completed,
};

pub const Event = struct {
    sequence: u64,
    kind: EventKind,
    execution_id: u64,
    shard_id: ?u16 = null,
    worker_id: ?u64 = null,
    attempt: u16 = 0,
};

pub const OutboxError = error{OutboxFull};

pub const Outbox = struct {
    events: [max_events]Event = undefined,
    count: usize = 0,
    next_sequence: u64 = 1,
    acknowledged_through: u64 = 0,

    pub fn append(self: *Outbox, event: Event) OutboxError!u64 {
        if (self.count >= max_events) return error.OutboxFull;
        const sequence = self.next_sequence;
        self.next_sequence += 1;
        var stored = event;
        stored.sequence = sequence;
        self.events[self.count] = stored;
        self.count += 1;
        return sequence;
    }

    pub fn acknowledge(self: *Outbox, sequence: u64) void {
        if (sequence > self.acknowledged_through and sequence < self.next_sequence) {
            self.acknowledged_through = sequence;
        }
    }

    pub fn pendingCount(self: *const Outbox) usize {
        var pending: usize = 0;
        var i: usize = 0;
        while (i < self.count) : (i += 1) {
            if (self.events[i].sequence > self.acknowledged_through) pending += 1;
        }
        return pending;
    }
};

test "outbox ACK never deletes history from the core ledger" {
    var outbox = Outbox{};
    const seq = try outbox.append(.{ .sequence = 0, .kind = .execution_submitted, .execution_id = 1 });
    try std.testing.expectEqual(@as(usize, 1), outbox.pendingCount());
    outbox.acknowledge(seq);
    try std.testing.expectEqual(@as(usize, 0), outbox.pendingCount());
    try std.testing.expectEqual(@as(usize, 1), outbox.count);
}
