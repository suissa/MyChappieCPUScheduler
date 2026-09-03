const std = @import("std");
const builtin = @import("builtin");

pub const PmuSnapshot = struct {
    cycles: ?u64 = null,
    instructions: ?u64 = null,
    cache_misses: ?u64 = null,
    branch_misses: ?u64 = null,

    pub fn availableCount(self: PmuSnapshot) u8 {
        return @intFromBool(self.cycles != null) +
            @intFromBool(self.instructions != null) +
            @intFromBool(self.cache_misses != null) +
            @intFromBool(self.branch_misses != null);
    }
};

pub const PressureSnapshot = struct {
    some_avg10: f64 = 0,
    total_usec: u64 = 0,
};

pub const CgroupSnapshot = struct {
    available: bool = false,
    cpu_usage_usec: u64 = 0,
    cpu_user_usec: u64 = 0,
    cpu_system_usec: u64 = 0,
    nr_periods: u64 = 0,
    nr_throttled: u64 = 0,
    throttled_usec: u64 = 0,
    memory_current_bytes: u64 = 0,
    memory_peak_bytes: u64 = 0,
    memory_oom: u64 = 0,
    memory_oom_kill: u64 = 0,
    cpu_pressure: PressureSnapshot = .{},
    memory_pressure: PressureSnapshot = .{},
};

pub const MeasurementQuality = enum {
    full,
    partial,
    timing_only,
};

pub const MeasurementSnapshot = struct {
    elapsed_ns: u64,
    pmu: PmuSnapshot,
    cgroup_before: CgroupSnapshot,
    cgroup_after: CgroupSnapshot,
    quality: MeasurementQuality,

    pub fn observedCycles(self: MeasurementSnapshot) ?u64 {
        return self.pmu.cycles;
    }

    pub fn cpuUsageDeltaUsec(self: MeasurementSnapshot) u64 {
        if (!self.cgroup_before.available or !self.cgroup_after.available) return 0;
        return self.cgroup_after.cpu_usage_usec -| self.cgroup_before.cpu_usage_usec;
    }

    pub fn throttledDeltaUsec(self: MeasurementSnapshot) u64 {
        if (!self.cgroup_before.available or !self.cgroup_after.available) return 0;
        return self.cgroup_after.throttled_usec -| self.cgroup_before.throttled_usec;
    }
};

const CounterKind = enum {
    cycles,
    instructions,
    cache_misses,
    branch_misses,
};

const CounterHandle = struct {
    fd: ?std.posix.fd_t = null,
    baseline: ?u64 = null,

    fn close(self: *CounterHandle) void {
        if (self.fd) |fd| std.posix.close(fd);
        self.fd = null;
    }
};

const PmuSession = struct {
    cycles: CounterHandle = .{},
    instructions: CounterHandle = .{},
    cache_misses: CounterHandle = .{},
    branch_misses: CounterHandle = .{},

    fn open() PmuSession {
        if (builtin.os.tag != .linux) return .{};
        return .{
            .cycles = openCounter(.cycles),
            .instructions = openCounter(.instructions),
            .cache_misses = openCounter(.cache_misses),
            .branch_misses = openCounter(.branch_misses),
        };
    }

    fn close(self: *PmuSession) void {
        self.cycles.close();
        self.instructions.close();
        self.cache_misses.close();
        self.branch_misses.close();
    }

    fn sample(self: *const PmuSession) PmuSnapshot {
        return .{
            .cycles = sampleCounter(self.cycles),
            .instructions = sampleCounter(self.instructions),
            .cache_misses = sampleCounter(self.cache_misses),
            .branch_misses = sampleCounter(self.branch_misses),
        };
    }
};

pub const LinuxMeasurementPlane = struct {
    cgroup_root: []const u8 = "/sys/fs/cgroup",

    pub fn begin(self: LinuxMeasurementPlane) MeasurementSession {
        return .{
            .plane = self,
            .timer = std.time.Timer.start() catch null,
            .pmu = PmuSession.open(),
            .cgroup_before = readCgroupSnapshot(self.cgroup_root),
        };
    }
};

pub const MeasurementSession = struct {
    plane: LinuxMeasurementPlane,
    timer: ?std.time.Timer,
    pmu: PmuSession,
    cgroup_before: CgroupSnapshot,
    finished: bool = false,

    pub fn finish(self: *MeasurementSession) MeasurementSnapshot {
        const elapsed_ns = if (self.timer) |*timer| timer.read() else 0;
        const pmu = self.pmu.sample();
        const cgroup_after = readCgroupSnapshot(self.plane.cgroup_root);
        self.finished = true;
        return .{
            .elapsed_ns = elapsed_ns,
            .pmu = pmu,
            .cgroup_before = self.cgroup_before,
            .cgroup_after = cgroup_after,
            .quality = qualityFor(pmu, self.cgroup_before.available and cgroup_after.available),
        };
    }

    pub fn deinit(self: *MeasurementSession) void {
        self.pmu.close();
    }
};

fn qualityFor(pmu: PmuSnapshot, cgroup_available: bool) MeasurementQuality {
    if (pmu.availableCount() == 4 and cgroup_available) return .full;
    if (pmu.availableCount() > 0 or cgroup_available) return .partial;
    return .timing_only;
}

fn perfConfig(kind: CounterKind) std.os.linux.PERF.COUNT.HW {
    return switch (kind) {
        .cycles => .CPU_CYCLES,
        .instructions => .INSTRUCTIONS,
        .cache_misses => .CACHE_MISSES,
        .branch_misses => .BRANCH_MISSES,
    };
}

fn openCounter(kind: CounterKind) CounterHandle {
    if (builtin.os.tag != .linux) return .{};

    var attr: std.os.linux.perf_event_attr = .{
        .type = .HARDWARE,
        .config = @intFromEnum(perfConfig(kind)),
    };
    attr.flags.exclude_hv = true;

    const fd = std.posix.perf_event_open(&attr, 0, -1, -1, 0) catch return .{};
    const baseline = readCounter(fd);
    return .{ .fd = fd, .baseline = baseline };
}

fn readCounter(fd: std.posix.fd_t) ?u64 {
    var value: u64 = 0;
    const bytes = std.mem.asBytes(&value);
    const read_len = std.posix.read(fd, bytes) catch return null;
    if (read_len != @sizeOf(u64)) return null;
    return value;
}

fn sampleCounter(handle: CounterHandle) ?u64 {
    const fd = handle.fd orelse return null;
    const baseline = handle.baseline orelse return null;
    const current = readCounter(fd) orelse return null;
    return current -| baseline;
}

fn readCgroupSnapshot(root: []const u8) CgroupSnapshot {
    if (builtin.os.tag != .linux) return .{};

    var snapshot: CgroupSnapshot = .{};
    var buffer: [4096]u8 = undefined;

    if (readCgroupFile(root, "cpu.stat", &buffer)) |data| {
        snapshot.available = true;
        parseCpuStat(data, &snapshot);
    } else |_| {}

    if (readCgroupFile(root, "memory.current", &buffer)) |data| {
        snapshot.available = true;
        snapshot.memory_current_bytes = parseSingleU64(data) orelse 0;
    } else |_| {}

    if (readCgroupFile(root, "memory.peak", &buffer)) |data| {
        snapshot.memory_peak_bytes = parseSingleU64(data) orelse 0;
    } else |_| {}

    if (readCgroupFile(root, "memory.events", &buffer)) |data| {
        parseMemoryEvents(data, &snapshot);
    } else |_| {}

    if (readCgroupFile(root, "cpu.pressure", &buffer)) |data| {
        snapshot.cpu_pressure = parsePressure(data);
    } else |_| {}

    if (readCgroupFile(root, "memory.pressure", &buffer)) |data| {
        snapshot.memory_pressure = parsePressure(data);
    } else |_| {}

    return snapshot;
}

fn readCgroupFile(root: []const u8, leaf: []const u8, buffer: []u8) ![]const u8 {
    var path_buffer: [512]u8 = undefined;
    const path = try std.fmt.bufPrint(&path_buffer, "{s}/{s}", .{ root, leaf });
    const file = try std.fs.openFileAbsolute(path, .{});
    defer file.close();
    const len = try file.read(buffer);
    return buffer[0..len];
}

fn parseSingleU64(data: []const u8) ?u64 {
    return std.fmt.parseInt(u64, std.mem.trim(u8, data, " \t\r\n"), 10) catch null;
}

fn parseCpuStat(data: []const u8, snapshot: *CgroupSnapshot) void {
    var lines = std.mem.splitScalar(u8, data, '\n');
    while (lines.next()) |line| {
        var fields = std.mem.tokenizeAny(u8, line, " \t");
        const key = fields.next() orelse continue;
        const value_text = fields.next() orelse continue;
        const value = std.fmt.parseInt(u64, value_text, 10) catch continue;
        if (std.mem.eql(u8, key, "usage_usec")) snapshot.cpu_usage_usec = value else if (std.mem.eql(u8, key, "user_usec")) snapshot.cpu_user_usec = value else if (std.mem.eql(u8, key, "system_usec")) snapshot.cpu_system_usec = value else if (std.mem.eql(u8, key, "nr_periods")) snapshot.nr_periods = value else if (std.mem.eql(u8, key, "nr_throttled")) snapshot.nr_throttled = value else if (std.mem.eql(u8, key, "throttled_usec")) snapshot.throttled_usec = value;
    }
}

fn parseMemoryEvents(data: []const u8, snapshot: *CgroupSnapshot) void {
    var lines = std.mem.splitScalar(u8, data, '\n');
    while (lines.next()) |line| {
        var fields = std.mem.tokenizeAny(u8, line, " \t");
        const key = fields.next() orelse continue;
        const value_text = fields.next() orelse continue;
        const value = std.fmt.parseInt(u64, value_text, 10) catch continue;
        if (std.mem.eql(u8, key, "oom")) snapshot.memory_oom = value else if (std.mem.eql(u8, key, "oom_kill")) snapshot.memory_oom_kill = value;
    }
}

fn parsePressure(data: []const u8) PressureSnapshot {
    var lines = std.mem.splitScalar(u8, data, '\n');
    while (lines.next()) |line| {
        var fields = std.mem.tokenizeAny(u8, line, " \t");
        const scope = fields.next() orelse continue;
        if (!std.mem.eql(u8, scope, "some")) continue;

        var result: PressureSnapshot = .{};
        while (fields.next()) |field| {
            if (std.mem.startsWith(u8, field, "avg10=")) {
                result.some_avg10 = std.fmt.parseFloat(f64, field[6..]) catch 0;
            } else if (std.mem.startsWith(u8, field, "total=")) {
                result.total_usec = std.fmt.parseInt(u64, field[6..], 10) catch 0;
            }
        }
        return result;
    }
    return .{};
}

test "cgroup parsers normalize cpu, memory and pressure data" {
    var snapshot: CgroupSnapshot = .{};
    parseCpuStat("usage_usec 120\nuser_usec 80\nsystem_usec 40\nnr_periods 3\nnr_throttled 1\nthrottled_usec 9\n", &snapshot);
    parseMemoryEvents("low 0\noom 2\noom_kill 1\n", &snapshot);
    const pressure = parsePressure("some avg10=0.25 avg60=0.10 avg300=0.02 total=1234\nfull avg10=0.00 avg60=0.00 avg300=0.00 total=0\n");

    try std.testing.expectEqual(@as(u64, 120), snapshot.cpu_usage_usec);
    try std.testing.expectEqual(@as(u64, 9), snapshot.throttled_usec);
    try std.testing.expectEqual(@as(u64, 2), snapshot.memory_oom);
    try std.testing.expectEqual(@as(u64, 1), snapshot.memory_oom_kill);
    try std.testing.expectApproxEqAbs(@as(f64, 0.25), pressure.some_avg10, 0.0001);
    try std.testing.expectEqual(@as(u64, 1234), pressure.total_usec);
}

test "measurement quality degrades without assuming PMU availability" {
    try std.testing.expectEqual(MeasurementQuality.timing_only, qualityFor(.{}, false));
    try std.testing.expectEqual(MeasurementQuality.partial, qualityFor(.{ .cycles = 100 }, false));
    try std.testing.expectEqual(MeasurementQuality.full, qualityFor(.{
        .cycles = 1,
        .instructions = 2,
        .cache_misses = 3,
        .branch_misses = 4,
    }, true));
}
