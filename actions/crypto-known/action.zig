const abi = @import("action_abi");
const common = @import("crypto_common");

const semantic_id = "Crypto.IteratedSha256.Known";
const rounds: u32 = 4_000;
const default_shards: u16 = 4;

const descriptor = abi.ActionDescriptor{
    .abi_version = abi.abi_version,
    .semantic_id_ptr = semantic_id.ptr,
    .semantic_id_len = semantic_id.len,
    .schema_hash = [_]u8{0x32} ** abi.hash_len,
    .artifact_hash = [_]u8{0x42} ** abi.hash_len,
    .flags = abi.Flag.offloadable | abi.Flag.partitionable | abi.Flag.checkpointable | abi.Flag.retry_safe | abi.Flag.custom_aggregation,
    .cost_knowledge = .known,
    .estimated_cycles = 4_000_000,
    .default_shards = default_shards,
    .max_output_len = common.digest_len,
};

export fn allas_action_descriptor() callconv(.c) *const abi.ActionDescriptor {
    return &descriptor;
}

export fn allas_action_execute(input_ptr: [*]const u8, input_len: usize, output_ptr: [*]u8, output_capacity: usize) callconv(.c) abi.ActionCallResult {
    return common.executeFull(input_ptr[0..input_len], rounds, default_shards, output_ptr[0..output_capacity]);
}

export fn allas_action_execute_shard(input_ptr: [*]const u8, input_len: usize, shard_index: u16, shard_count: u16, output_ptr: [*]u8, output_capacity: usize) callconv(.c) abi.ActionCallResult {
    return common.executeShard(input_ptr[0..input_len], shard_index, shard_count, rounds, output_ptr[0..output_capacity]);
}

export fn allas_action_aggregate(partials_ptr: [*]const u8, partials_len: usize, partial_count: u16, output_ptr: [*]u8, output_capacity: usize) callconv(.c) abi.ActionCallResult {
    return common.aggregate(partials_ptr[0..partials_len], partial_count, output_ptr[0..output_capacity]);
}
