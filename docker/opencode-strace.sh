#!/bin/bash
# OpenCode strace mode — trace syscalls to find what's hanging
# Usage: ./opencode-strace [opencode args...]
# Output: strace log in /tmp/opencode-strace-<pid>.log
set -euo pipefail

DIR="$(cd "$(dirname "$0")" && pwd)"
BIN="$DIR/opencode-bin"
MUSL_DIR="$HOME/.opencode/lib"
STRACE="$DIR/debug/strace"
LOG="/tmp/opencode-strace-$$.log"

export OPENCODE_INTRANET=1
export LD_LIBRARY_PATH="${MUSL_DIR}:$DIR/lib${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"

# Ensure binary is patched
"$DIR/opencode" --version > /dev/null 2>&1

echo "=== OpenCode Strace ===" >&2
echo "Strace log: $LOG" >&2
echo "Tracing: network + file + epoll syscalls" >&2
echo "Ctrl+C to stop, then examine $LOG" >&2
echo "" >&2

# strace is Alpine musl-linked, run via our musl linker
"$DIR/lib/ld-musl-x86_64.so.1" --library-path "$MUSL_DIR:$DIR/lib" "$STRACE" \
    -f \
    -e trace=network,connect,socket,bind,sendto,recvfrom,epoll_pwait,epoll_wait,epoll_ctl,poll,select,getaddrinfo,write \
    -e signal=none \
    -tt \
    -s 256 \
    -o "$LOG" \
    "$BIN" "$@"

echo "" >&2
echo "=== Strace complete ===" >&2
echo "Log: $LOG" >&2
echo "Quick analysis:" >&2
echo "  Longest epoll waits:" >&2
grep epoll_pwait "$LOG" 2>/dev/null | tail -5 >&2 || true
echo "  Connect attempts:" >&2
grep -c "connect(" "$LOG" 2>/dev/null >&2 || echo "  0" >&2
echo "  DNS lookups:" >&2
grep -i "getaddrinfo\|dns\|resolv" "$LOG" 2>/dev/null | head -5 >&2 || true
