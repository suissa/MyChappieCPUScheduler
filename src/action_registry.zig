const std = @import("std");
const abi = @import("action_abi.zig");
const types = @import("types.zig");

pub const max_modules: usize = 32;

pub const RegistryError = error{
    RegistryFull,
    DuplicateSemanticId,
    MissingDescriptorSymbol,
    MissingExecuteSymbol,
    MissingShardSymbol,
    MissingAggregateSymbol,
    UnsupportedAbiVersion,
    InvalidDescriptor,
    ActionNotFound,
};

pub const LoadedAction = struct {
    lib: std.DynLib,
    descriptor: *const abi.ActionDescriptor,
    execute_fn: abi.ExecuteFn,
    execute_shard_fn: ?abi.ExecuteShardFn,
    aggregate_fn: ?abi.AggregateFn,

    pub fn semanticId(self: *const LoadedAction) []const u8 {
        return abi.semanticId(self.descriptor);
    }

    pub fn toCostProfile(self: *const LoadedAction) types.FunctionCostProfile {
        return .{
            .function_id = self.semanticId(),
            .knowledge = switch (self.descriptor.cost_knowledge) {
                .unknown => .unknown,
                .known => .known,
            },
            .estimated_cycles = self.descriptor.estimated_cycles,
            .offloadable = abi.hasFlag(self.descriptor, abi.Flag.offloadable),
            .partitionable = abi.hasFlag(self.descriptor, abi.Flag.partitionable),
            .checkpointable = abi.hasFlag(self.descriptor, abi.Flag.checkpointable),
            .retry_safe = abi.hasFlag(self.descriptor, abi.Flag.retry_safe),
            .aggregation = if (abi.hasFlag(self.descriptor, abi.Flag.custom_aggregation)) .custom else .none,
            .recommended_shards = if (self.descriptor.default_shards == 0) 1 else self.descriptor.default_shards,
        };
    }

    pub fn execute(self: *const LoadedAction, input: []const u8, output: []u8) abi.ActionCallResult {
        return self.execute_fn(input.ptr, input.len, output.ptr, output.len);
    }

    pub fn executeShard(self: *const LoadedAction, input: []const u8, shard_index: u16, shard_count: u16, output: []u8) !abi.ActionCallResult {
        const function = self.execute_shard_fn orelse return error.MissingShardSymbol;
        return function(input.ptr, input.len, shard_index, shard_count, output.ptr, output.len);
    }

    pub fn aggregate(self: *const LoadedAction, partials: []const u8, partial_count: u16, output: []u8) !abi.ActionCallResult {
        const function = self.aggregate_fn orelse return error.MissingAggregateSymbol;
        return function(partials.ptr, partials.len, partial_count, output.ptr, output.len);
    }
};

pub const DynamicActionRegistry = struct {
    modules: [max_modules]LoadedAction = undefined,
    len: usize = 0,

    pub fn deinit(self: *DynamicActionRegistry) void {
        var i: usize = 0;
        while (i < self.len) : (i += 1) self.modules[i].lib.close();
        self.len = 0;
    }

    pub fn load(self: *DynamicActionRegistry, path: []const u8) !void {
        if (self.len >= max_modules) return error.RegistryFull;

        var lib = try std.DynLib.open(path);
        errdefer lib.close();

        const descriptor_fn = lib.lookup(abi.DescriptorFn, "allas_action_descriptor") orelse return error.MissingDescriptorSymbol;
        const descriptor = descriptor_fn();
        if (descriptor.abi_version != abi.abi_version) return error.UnsupportedAbiVersion;
        if (descriptor.semantic_id_len == 0 or descriptor.default_shards == 0 or descriptor.max_output_len == 0) return error.InvalidDescriptor;

        const execute_fn = lib.lookup(abi.ExecuteFn, "allas_action_execute") orelse return error.MissingExecuteSymbol;
        const execute_shard_fn = lib.lookup(abi.ExecuteShardFn, "allas_action_execute_shard");
        const aggregate_fn = lib.lookup(abi.AggregateFn, "allas_action_aggregate");

        if (abi.hasFlag(descriptor, abi.Flag.partitionable) and execute_shard_fn == null) return error.MissingShardSymbol;
        if (abi.hasFlag(descriptor, abi.Flag.custom_aggregation) and aggregate_fn == null) return error.MissingAggregateSymbol;

        if (self.find(abi.semanticId(descriptor))) |_| return error.DuplicateSemanticId else |_| {}

        self.modules[self.len] = .{
            .lib = lib,
            .descriptor = descriptor,
            .execute_fn = execute_fn,
            .execute_shard_fn = execute_shard_fn,
            .aggregate_fn = aggregate_fn,
        };
        self.len += 1;
    }

    pub fn find(self: *DynamicActionRegistry, semantic_id: []const u8) RegistryError!*LoadedAction {
        var i: usize = 0;
        while (i < self.len) : (i += 1) {
            if (std.mem.eql(u8, self.modules[i].semanticId(), semantic_id)) return &self.modules[i];
        }
        return error.ActionNotFound;
    }
};
