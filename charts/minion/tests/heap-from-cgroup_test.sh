#!/usr/bin/env bash
# Copyright 2026 Ronny Trommer <ronny@no42.org>
# SPDX-License-Identifier: Apache-2.0
set -euo pipefail

here="$(cd "$(dirname "$0")" && pwd)"
script="$here/../files/heap-from-cgroup.sh"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

cat > "$tmp/entrypoint" <<'EOF'
#!/usr/bin/env bash
echo "JAVA_MIN_MEM=${JAVA_MIN_MEM:-unset} JAVA_MAX_MEM=${JAVA_MAX_MEM:-unset} ARGS=$*"
EOF
chmod +x "$tmp/entrypoint"

fail=0
# check <name> <memory.max content or MISSING> <extra env or -> <expected stdout>
check() {
  local name="$1" content="$2" extra="$3" want="$4" file="$tmp/memory.max" got
  rm -f "$file"
  [[ "$content" == MISSING ]] || printf '%s\n' "$content" > "$file"
  local -a envs=(CGROUP_MEMORY_MAX="$file" ENTRYPOINT="$tmp/entrypoint")
  if [[ "$extra" != - ]]; then
    local -a more
    read -r -a more <<< "$extra"
    envs+=("${more[@]}")
  fi
  got="$(env -u JAVA_MIN_MEM -u JAVA_MAX_MEM "${envs[@]}" bash "$script" -f 2>"$tmp/stderr")" \
    || got="<exit $?: $(tr '\n' ' ' < "$tmp/stderr")>"
  if [[ "$got" == "$want" ]]; then echo "ok   $name"; else echo "FAIL $name: got '$got' want '$want'"; fail=1; fi
}

check "2 GiB limit, default percents" 2147483648 - "JAVA_MIN_MEM=512m JAVA_MAX_MEM=1433m ARGS=-f"
check "4 GiB limit, custom percents" 4294967296 "HEAP_MAX_PERCENT=50 HEAP_MIN_PERCENT=10" "JAVA_MIN_MEM=409m JAVA_MAX_MEM=2048m ARGS=-f"
check "cgroup-derived value wins over operator JAVA_MAX_MEM" 2147483648 "JAVA_MAX_MEM=4g" "JAVA_MIN_MEM=512m JAVA_MAX_MEM=1433m ARGS=-f"
check "no limit keeps image defaults" max - "JAVA_MIN_MEM=unset JAVA_MAX_MEM=unset ARGS=-f"
check "missing cgroup file keeps image defaults" MISSING - "JAVA_MIN_MEM=unset JAVA_MAX_MEM=unset ARGS=-f"

exit "$fail"
