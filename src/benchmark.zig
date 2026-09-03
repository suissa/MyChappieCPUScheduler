const std = @import("std");
const types = @import("types.zig");

pub const BenchmarkError = error{
    NoSamples,
    InvalidPercentile,
};

pub fn percentileNearestRank(samples: []u64, percentile: u8) BenchmarkError!u64 {
    if (samples.len == 0) return error.NoSamples;
    if (percentile == 0 or percentile > 100) return error.InvalidPercentile;

    var i: usize = 1;
    while (i < samples.len) : (i += 1) {
        const value = samples[i];
        var j = i;
        while (j > 0 and samples[j - 1] > value) : (j -= 1) {
            samples[j] = samples[j - 1];
        }
        samples[j] = value;
    }

    const numerator = @as(usize, percentile) * samples.len;
    const rank = (numerator + 99) / 100;
    return samples[rank - 1];
}

pub fn p90(samples: []u64) BenchmarkError!u64 {
    return percentileNearestRank(samples, 90);
}

pub fn classify(cycles: u64, threshold: u64) types.ComputeClass {
    if (threshold == 0) return .extreme;
    if (cycles <= threshold) return .normal;
    if (cycles / threshold < 2) return .heavy;
    return .extreme;
}

pub fn excessBasisPoints(cycles: u64, threshold: u64) u64 {
    if (threshold == 0 or cycles <= threshold) return 0;
    const excess = cycles - threshold;
    return (excess * 10_000) / threshold;
}

test "P90 selects the nearest-rank threshold" {
    var samples = [_]u64{ 10, 100, 30, 90, 50, 60, 20, 80, 40, 70 };
    try std.testing.expectEqual(@as(u64, 90), try p90(samples[0..]));
}

test "classification separates normal heavy and extreme" {
    try std.testing.expectEqual(types.ComputeClass.normal, classify(100, 100));
    try std.testing.expectEqual(types.ComputeClass.heavy, classify(150, 100));
    try std.testing.expectEqual(types.ComputeClass.extreme, classify(250, 100));
}
