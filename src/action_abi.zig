pub const abi_version: u32 = 1;
pub const hash_len: usize = 32;

pub const Flag = struct {
    pub const offloadable: u64 = 1 << 0;
    pub const partitionable: u64 = 1 << 1;
    pub const checkpointable: u64 = 1 << 2;
    pub const retry_safe: u64 = 1 << 3;
    pub const custom_aggregation: u64 = 1 << 4;
};

pub const CostKnowledge = enum(u32) {
    unknown = 0,
    known = 1,
};

pub const CallStatus = enum(u32) {
    ok = 0,
    invalid_input = 1,
    output_too_small = 2,
    invalid_shard = 3,
    internal_error = 255,
};

pub const ActionCallResult = extern struct {
    status: CallStatus,
    output_len: usize,
};

pub const ActionDescriptor = extern struct {
    abi_version: u32,
    semantic_id_ptr: [*]const u8,
    semantic_id_len: usize,
    schema_hash: [hash_len]u8,
    artifact_hash: [hash_len]u8,
    flags: u64,
    cost_knowledge: CostKnowledge,
    estimated_cycles: u64,
    default_shards: u16,
    max_output_len: usize,
};

pub const DescriptorFn = *const fn () callconv(.c) *const ActionDescriptor;
pub const ExecuteFn = *const fn (
    input_ptr: [*]const u8,
    input_len: usize,
    output_ptr: [*]u8,
    output_capacity: usize,
) callconv(.c) ActionCallResult;

pub const ExecuteShardFn = *const fn (
    input_ptr: [*]const u8,
    input_len: usize,
    shard_index: u16,
    shard_count: u16,
    output_ptr: [*]u8,
    output_capacity: usize,
) callconv(.c) ActionCallResult;

pub const AggregateFn = *const fn (
    partials_ptr: [*]const u8,
    partials_len: usize,
    partial_count: u16,
    output_ptr: [*]u8,
    output_capacity: usize,
) callconv(.c) ActionCallResult;

pub fn hasFlag(descriptor: *const ActionDescriptor, flag: u64) bool {
    return (descriptor.flags & flag) != 0;
}

pub fn semanticId(descriptor: *const ActionDescriptor) []const u8 {
    return descriptor.semantic_id_ptr[0..descriptor.semantic_id_len];
}
