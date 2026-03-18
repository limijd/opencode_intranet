#!/bin/bash
# OpenCode debug mode — verbose logging + timing
set -euo pipefail

DIR="$(cd "$(dirname "$0")" && pwd)"

export OPENCODE_INTRANET=1

# Enable all debug logging
export DEBUG="*"
export NODE_DEBUG="net,dns,tls,http,https"
export BUN_DEBUG_QUIET_LOGS=0

# Print startup timing
echo "=== OpenCode Debug Launch ===" >&2
echo "Time: $(date '+%Y-%m-%d %H:%M:%S.%N')" >&2
echo "User: $(whoami)" >&2
echo "PWD: $(pwd)" >&2
echo "HOME: $HOME" >&2
echo "OPENCODE_INTRANET: $OPENCODE_INTRANET" >&2
echo "" >&2

# Check DNS - this is often the culprit
echo "=== DNS Check ===" >&2
echo "hostname: $(hostname)" >&2
echo "/etc/resolv.conf:" >&2
cat /etc/resolv.conf 2>/dev/null || echo "(not readable)" >&2
echo "" >&2
echo "Resolving hostname..." >&2
START=$(date +%s%N)
getent hosts $(hostname) 2>&1 || echo "hostname resolution failed" >&2
END=$(date +%s%N)
echo "hostname resolution took: $(( (END - START) / 1000000 ))ms" >&2
echo "" >&2

# Check network interfaces
echo "=== Network ===" >&2
ip addr 2>/dev/null || ifconfig 2>/dev/null || echo "(no network tools)" >&2
echo "" >&2

echo "=== Starting OpenCode with --print-logs ===" >&2
echo "Time: $(date '+%Y-%m-%d %H:%M:%S.%N')" >&2

# Run with verbose logging
exec "$DIR/opencode" --print-logs --log-level DEBUG "$@"
