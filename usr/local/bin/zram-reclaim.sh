#!/bin/bash
RECLAIM_AMOUNT="100M"
INTERVAL=3
TARGET="/sys/fs/cgroup/memory.reclaim"
if [ ! -w "$TARGET" ]; then
    logger -t zram-reclaim "ERROR: $TARGET not writable"
    exit 1
fi
logger -t zram-reclaim "Started"
echo 3 > /proc/sys/vm/drop_caches 2>/dev/null
while true; do
    echo "$RECLAIM_AMOUNT" > "$TARGET" 2>/dev/null
    sleep "$INTERVAL"
done
