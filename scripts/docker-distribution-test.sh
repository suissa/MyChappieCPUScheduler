#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

COMPOSE=(docker compose -f docker-compose.test.yml)
rm -rf .dist-test
mkdir -p .dist-test
dd if=/dev/zero of=.dist-test/input.bin bs=8192 count=1 status=none

zig build

UNKNOWN_HOST_LIB="zig-out/lib/liballas_crypto_unknown.so"
KNOWN_HOST_LIB="zig-out/lib/liballas_crypto_known.so"
UNKNOWN_CONTAINER_LIB="/app/lib/liballas_crypto_unknown.so"
KNOWN_CONTAINER_LIB="/app/lib/liballas_crypto_known.so"

# UNKNOWN: shard 0 is the local probe; the remaining shards execute remotely.
./zig-out/bin/action-worker "$UNKNOWN_HOST_LIB" Crypto.IteratedSha256.Unknown .dist-test/input.bin 0 4 .dist-test/unknown-0.bin local-probe

"${COMPOSE[@]}" run --rm worker /app/bin/action-worker "$UNKNOWN_CONTAINER_LIB" Crypto.IteratedSha256.Unknown /work/input.bin 1 4 /work/unknown-1.bin remote-unknown-1 &
pid_unknown_1=$!
"${COMPOSE[@]}" run --rm worker /app/bin/action-worker "$UNKNOWN_CONTAINER_LIB" Crypto.IteratedSha256.Unknown /work/input.bin 2 4 /work/unknown-2.bin remote-unknown-2 &
pid_unknown_2=$!
"${COMPOSE[@]}" run --rm worker /app/bin/action-worker "$UNKNOWN_CONTAINER_LIB" Crypto.IteratedSha256.Unknown /work/input.bin 3 4 /work/unknown-3.bin remote-unknown-3 &
pid_unknown_3=$!
wait "$pid_unknown_1"
wait "$pid_unknown_2"
wait "$pid_unknown_3"

./zig-out/bin/distributed-verifier "$UNKNOWN_HOST_LIB" Crypto.IteratedSha256.Unknown .dist-test/input.bin 4 .dist-test/unknown

# KNOWN: all shards are sent directly to independent worker containers.
pids=()
for shard in 0 1 2 3; do
  "${COMPOSE[@]}" run --rm worker /app/bin/action-worker "$KNOWN_CONTAINER_LIB" Crypto.IteratedSha256.Known /work/input.bin "$shard" 4 "/work/known-${shard}.bin" "remote-known-${shard}" &
  pids+=("$!")
done
for pid in "${pids[@]}"; do
  wait "$pid"
done

./zig-out/bin/distributed-verifier "$KNOWN_HOST_LIB" Crypto.IteratedSha256.Known .dist-test/input.bin 4 .dist-test/known

echo "Docker distribution validation passed for UNKNOWN and KNOWN modes."
