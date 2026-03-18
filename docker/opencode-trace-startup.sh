#!/bin/bash
# OpenCode startup trace — timestamps each phase to find the bottleneck
# Usage: ./opencode-trace-startup [opencode args...]
set -euo pipefail

DIR="$(cd "$(dirname "$0")" && pwd)"
BIN="$DIR/opencode-bin"
MUSL_DIR="$HOME/.opencode/lib"
LOG="/tmp/opencode-startup-$$.log"

export OPENCODE_INTRANET=1
export LD_LIBRARY_PATH="${MUSL_DIR}:$DIR/lib${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"

# Ensure binary is patched
"$DIR/opencode" --version > /dev/null 2>&1

ts() { date '+%H:%M:%S.%N'; }

echo "=== OpenCode Startup Trace ===" | tee "$LOG"
echo "Log: $LOG" | tee -a "$LOG"
echo "" | tee -a "$LOG"

# Phase 1: DNS resolution test
echo "[$(ts)] Phase 1: DNS resolution tests" | tee -a "$LOG"
for host in $(hostname) localhost; do
    START=$(date +%s%N)
    getent hosts "$host" > /dev/null 2>&1 || true
    END=$(date +%s%N)
    MS=$(( (END - START) / 1000000 ))
    echo "  $host: ${MS}ms" | tee -a "$LOG"
done

# Also test what happens when resolving an unreachable host
echo "  Unreachable DNS test (models.dev):" | tee -a "$LOG"
START=$(date +%s%N)
getent hosts models.dev > /dev/null 2>&1 || true
END=$(date +%s%N)
MS=$(( (END - START) / 1000000 ))
echo "    models.dev: ${MS}ms" | tee -a "$LOG"

# Phase 2: Filesystem checks
echo "[$(ts)] Phase 2: Filesystem" | tee -a "$LOG"
echo "  HOME=$HOME" | tee -a "$LOG"
echo "  XDG_CONFIG_HOME=${XDG_CONFIG_HOME:-not set}" | tee -a "$LOG"
echo "  XDG_DATA_HOME=${XDG_DATA_HOME:-not set}" | tee -a "$LOG"
ls -la "$HOME/.config/opencode/" 2>/dev/null | tee -a "$LOG" || echo "  No config dir" | tee -a "$LOG"
ls -la "$HOME/.local/share/opencode/" 2>/dev/null | tee -a "$LOG" || echo "  No data dir" | tee -a "$LOG"

# Phase 3: Test non-interactive commands with timing
echo "" | tee -a "$LOG"
echo "[$(ts)] Phase 3: Command timing" | tee -a "$LOG"

for cmd in "--version" "providers" "providers list"; do
    echo "  Testing: opencode $cmd" | tee -a "$LOG"
    START=$(date +%s%N)
    timeout 30 "$BIN" $cmd > /dev/null 2>&1 || true
    END=$(date +%s%N)
    MS=$(( (END - START) / 1000000 ))
    echo "    Duration: ${MS}ms" | tee -a "$LOG"
done

# Phase 4: strace quick snapshot (first 5 seconds)
echo "" | tee -a "$LOG"
echo "[$(ts)] Phase 4: Quick strace (5 sec snapshot of TUI startup)" | tee -a "$LOG"
STRACE_LOG="/tmp/opencode-strace-quick-$$.log"

if [ -x "$DIR/debug/strace" ]; then
    "$DIR/lib/ld-musl-x86_64.so.1" --library-path "$MUSL_DIR:$DIR/lib" \
        "$DIR/debug/strace" \
        -f -tt -s 128 \
        -e trace=connect,socket,epoll_pwait,getaddrinfo,open,openat \
        -o "$STRACE_LOG" \
        timeout 5 "$BIN" 2>/dev/null || true

    echo "  Strace log: $STRACE_LOG" | tee -a "$LOG"

    # Analyze
    echo "" | tee -a "$LOG"
    echo "=== Strace Analysis ===" | tee -a "$LOG"

    echo "  Connect attempts:" | tee -a "$LOG"
    grep "connect(" "$STRACE_LOG" 2>/dev/null | grep -v "ENOENT" | head -10 | tee -a "$LOG" || echo "    none" | tee -a "$LOG"

    echo "" | tee -a "$LOG"
    echo "  Socket creations:" | tee -a "$LOG"
    grep "socket(" "$STRACE_LOG" 2>/dev/null | head -10 | tee -a "$LOG" || echo "    none" | tee -a "$LOG"

    echo "" | tee -a "$LOG"
    echo "  Long epoll waits (>1sec):" | tee -a "$LOG"
    # Find epoll_pwait calls and calculate durations
    grep "epoll_pwait\|epoll_wait" "$STRACE_LOG" 2>/dev/null | head -10 | tee -a "$LOG" || echo "    none" | tee -a "$LOG"

    echo "" | tee -a "$LOG"
    echo "  Files opened:" | tee -a "$LOG"
    grep -oP 'open(at)?\([^,]*"[^"]*"' "$STRACE_LOG" 2>/dev/null | \
        grep -v "/proc\|/sys\|/dev\|node_modules\|\.so" | \
        sort -u | head -20 | tee -a "$LOG" || echo "    none" | tee -a "$LOG"
else
    echo "  strace not available in debug/" | tee -a "$LOG"
fi

echo "" | tee -a "$LOG"
echo "[$(ts)] Phase 5: Done" | tee -a "$LOG"
echo "" | tee -a "$LOG"
echo "=== Full logs ===" | tee -a "$LOG"
echo "  Startup trace: $LOG" | tee -a "$LOG"
echo "  Strace: $STRACE_LOG" | tee -a "$LOG"
echo "" | tee -a "$LOG"
echo "=== Recommended next steps ===" | tee -a "$LOG"
echo "  1. If DNS is slow: check /etc/resolv.conf, add 'options timeout:1 attempts:1'" | tee -a "$LOG"
echo "  2. If connect() shows external IPs: grep the IP to find which module" | tee -a "$LOG"
echo "  3. If epoll_pwait hangs: run ./opencode-strace to get full trace" | tee -a "$LOG"
echo "  4. For full debug logging: ./opencode-debug" | tee -a "$LOG"
