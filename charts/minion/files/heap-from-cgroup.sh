#!/usr/bin/env bash
# Copyright 2026 Ronny Trommer <ronny@no42.org>
# SPDX-License-Identifier: Apache-2.0
#
# Derive the Minion heap from the container memory limit, then hand over to the
# image entrypoint. The entrypoint always appends -Xmx${JAVA_MAX_MEM:-2g}, so
# -XX:MaxRAMPercentage never takes effect. Reading memory.max at every start
# lets a container restart pick up a resized limit.
set -euo pipefail

cgroup_file="${CGROUP_MEMORY_MAX:-/sys/fs/cgroup/memory.max}"
max_percent="${HEAP_MAX_PERCENT:-70}"
min_percent="${HEAP_MIN_PERCENT:-25}"

limit="$(cat "$cgroup_file" 2>/dev/null || true)"
if [[ "$limit" =~ ^[0-9]+$ ]]; then
  limit_mib=$(( limit / 1048576 ))
  export JAVA_MAX_MEM="$(( limit_mib * max_percent / 100 ))m"
  export JAVA_MIN_MEM="$(( limit_mib * min_percent / 100 ))m"
  echo "heap-from-cgroup: memory.max=${limit_mib}MiB JAVA_MIN_MEM=${JAVA_MIN_MEM} JAVA_MAX_MEM=${JAVA_MAX_MEM}" >&2
else
  echo "heap-from-cgroup: no numeric memory limit in ${cgroup_file} ('${limit}'), keeping image heap defaults" >&2
fi

exec "${ENTRYPOINT:-/entrypoint.sh}" "$@"
