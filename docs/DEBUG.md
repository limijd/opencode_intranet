# Debugging Guide — OpenCode Intranet

## Known Issue: TUI Startup Hangs (Hours)

On intranet CentOS 7.6 machines, OpenCode may hang for **hours** before the TUI appears.
The process is alive (not crashed) and stuck in `epoll_pwait()`.

### Root Cause Analysis

The hang is caused by **network requests timing out** in code paths that run during startup.
Even with `OPENCODE_INTRANET=1`, there may be residual network calls that block.

Possible culprits (ordered by likelihood):

| Suspect | Timeout | Why it hangs |
|---------|---------|--------------|
| TCP connect to unreachable host | 2-3 min per attempt, multiple retries = hours | Some module tries to connect to an external service; TCP SYN gets no RST (firewalled, not rejected) |
| DNS resolution | 5-30s per name × retries | `/etc/resolv.conf` points to unreachable nameserver |
| SQLite database migration | Minutes on slow NFS/Lustre | First-run DB migration on network filesystem |
| Effect runtime HTTP client init | Variable | The Effect-based HTTP client may attempt connections during setup |
| models.dev refresh race | 10s timeout + retries | Module-level `refresh()` may race with flag initialization |

### Debug Build

Build the debug version (includes strace + diagnostic scripts):

```bash
# On internet-connected build machine:
docker build -f docker/Dockerfile.debug -t opencode-debug .

# Extract clean artifacts:
docker build -f docker/Dockerfile.debug --target assembler -t opencode-debug-assembler .
mkdir -p output-debug
CONTAINER_ID=$(docker create opencode-debug-assembler)
docker cp "${CONTAINER_ID}:/package/." output-debug/
docker rm "${CONTAINER_ID}"

# Package for transfer:
tar -czf opencode-debug.tar.gz -C output-debug .
```

### Debug Package Contents

```
output-debug/
├── opencode                  # Normal wrapper (with OPENCODE_INTRANET=1)
├── opencode-bin              # Compiled binary
├── opencode-debug            # Verbose logging wrapper
├── opencode-strace           # Syscall tracing wrapper
├── opencode-trace-startup    # Phased startup analysis
├── debug/
│   └── strace                # Static strace binary (musl-linked)
└── lib/
    ├── ld-musl-x86_64.so.1
    ├── libc.musl-x86_64.so.1 -> ld-musl-x86_64.so.1
    ├── libstdc++.so.6
    ├── libgcc_s.so.1
    └── patchelf
```

### Step-by-Step Debugging on Intranet Machine

**Best first step: built-in startup instrumentation (no strace needed)**

```bash
# 1. Run with debug timestamps — this is the PRIMARY debug tool
OPENCODE_INTRANET_DEBUG=1 ./opencode 2>/tmp/dbg.log &

# 2. Watch the timestamps in real-time
tail -f /tmp/dbg.log

# Output looks like:
# [dbg +0ms] intranet/config loaded
# [dbg +285ms] index: imports done
# [dbg +293ms] index: middleware start (Log.init)
# [dbg +301ms] index: Log.init done, checking DB migration
# [dbg +308ms] index: middleware done
# [dbg +313ms] thread: creating worker
# [dbg +400ms] thread: worker created, getting prompt input
# [dbg +410ms] thread: Instance.provide (TuiConfig) start
# [dbg +500ms] instance.boot: start /path/to/project
# [dbg +510ms] instance.boot: project resolved
# [dbg +520ms] instance.boot: init start
# [dbg +530ms] bootstrap: start
# [dbg +540ms] bootstrap: Plugin.init start
# ...
# THE HANG IS BETWEEN THE LAST LINE AND THE NEXT EXPECTED LINE

# 3. Kill it after seeing where it hangs
kill %1
```

**All instrumented phases:**

| Timestamp label | What it means |
|-----------------|---------------|
| `intranet/config loaded` | Module system started |
| `index: imports done` | All top-level imports resolved |
| `index: middleware start` | yargs middleware (Log.init, DB check) |
| `index: DB migration starting` | First-run SQLite migration |
| `index: middleware done` | Ready to dispatch command |
| `thread: creating worker` | Bun Worker thread being spawned |
| `thread: Instance.provide start` | Project instance initialization |
| `instance.boot: start` | Project directory resolution |
| `instance.boot: project resolved` | Git/project detection done |
| `instance.boot: init start` | InstanceBootstrap beginning |
| `bootstrap: Plugin.init start/done` | Plugin loading |
| `bootstrap: ShareNext.init done` | Share initialization (disabled in intranet) |
| `bootstrap: Format.init done` | Code formatter init |
| `bootstrap: LSP.init done` | Language server init |
| `bootstrap: FileWatcher done` | File watcher init |
| `bootstrap: Vcs.init done` | Git/VCS init |
| `config.state: start` | Config loading |
| `config.state: auth loaded` | Auth entries read |
| `provider.state: Config.get start/done` | Provider config |
| `provider.state: ModelsDev.get start/done` | Model catalog loading |
| `models.Data: loaded from snapshot` | Model data source |
| `thread: launching TUI` | TUI render starting |
| `worker: event stream started` | SSE event loop running |

**If the gap is between two specific labels**, that tells you exactly which function is hanging.

**Other diagnostic tools:**

```bash
# Quick DNS test (rule out DNS — but multi-hour hang is NOT DNS)
time getent hosts $(hostname)
time getent hosts localhost

# strace NOTE: system strace may not work with patchelf'd musl binary.
# If strace fails with "libdw.so" or symbol errors, use the built-in
# debug timestamps above instead — they are MORE useful than strace
# for this problem anyway.

# Verbose app logging (all internal logs to stderr)
./opencode --print-logs --log-level DEBUG 2>/tmp/verbose.log &
tail -f /tmp/verbose.log
```

### Interpreting strace Output

```bash
# Find what the process is waiting on:
grep -E "epoll_pwait|poll|select" /tmp/opencode-strace-*.log | tail -20

# Find all network connections attempted:
grep "connect(" /tmp/opencode-strace-*.log | grep "sin_addr\|sin6_addr"

# Find all DNS-related syscalls:
grep -i "resolv\|hosts\|getaddr" /tmp/opencode-strace-*.log

# Find file opens (look for config files, DB):
grep "openat.*opencode" /tmp/opencode-strace-*.log

# Timeline: first 50 lines vs last 50 lines (see where time is spent)
head -50 /tmp/opencode-strace-*.log   # startup
tail -50 /tmp/opencode-strace-*.log   # where it hangs
```

### Common Fixes

#### Fix 1: DNS Timeout (if DNS is slow)

```bash
# Check current DNS config
cat /etc/resolv.conf

# If you can edit it (or ask admin):
# Add at top: options timeout:1 attempts:1
# This reduces DNS timeout from 5s×2 to 1s×1

# Alternative: set hostname resolution locally
echo "127.0.0.1 $(hostname)" >> /etc/hosts  # needs root
```

#### Fix 2: Block all external network (if strace shows external connects)

```bash
# Find the IP being connected to
grep "connect(" /tmp/opencode-strace-*.log | grep -oP 'sin_addr=inet_addr\("\K[^"]+' | sort -u

# If you see external IPs, you can:
# Option A: iptables rule (needs root)
sudo iptables -A OUTPUT -d <external-ip> -j REJECT

# Option B: null-route (needs root)
sudo ip route add blackhole <external-ip>/32

# Option C: find and fix the code path (see "Finding Unguarded Network Calls" below)
```

#### Fix 3: Slow filesystem (if DB migration is slow)

```bash
# Check if data dir is on NFS/Lustre
df -h ~/.local/share/

# If on slow network filesystem, use local storage:
export XDG_DATA_HOME=/tmp/$USER/opencode-data
mkdir -p "$XDG_DATA_HOME"
./opencode
```

#### Fix 4: Environment variable overrides

```bash
# Nuclear option: disable everything that might network
export OPENCODE_INTRANET=1
export OPENCODE_DISABLE_MODELS_FETCH=1
export OPENCODE_DISABLE_AUTOUPDATE=1
export OPENCODE_DISABLE_LSP_DOWNLOAD=1
export OPENCODE_DISABLE_SHARE=1
export OPENCODE_DISABLE_DEFAULT_PLUGINS=1
export NODE_OPTIONS="--dns-result-order=ipv4first"
./opencode
```

### Finding Unguarded Network Calls

If strace reveals an external connection, trace it back to the code:

```bash
# 1. Find the IP from strace
# e.g., connect(5, {sa_family=AF_INET, sin_port=htons(443), sin_addr=inet_addr("104.18.0.1")}, 16) = -1

# 2. Reverse-lookup the IP
nslookup 104.18.0.1    # or: dig -x 104.18.0.1

# 3. Search codebase for that domain
cd /path/to/opencode_intranet
grep -r "thedomain.com" packages/opencode/src/

# 4. Add INTRANET guard:
#    import { INTRANET } from "../intranet/config"
#    if (INTRANET) return
```

### Debug Environment Variables

| Variable | Effect |
|----------|--------|
| `OPENCODE_INTRANET=1` | Disable all external network (set by wrapper) |
| `OPENCODE_INTRANET_DEBUG=1` | Startup timing logs to stderr |
| `OPENCODE_DISABLE_MODELS_FETCH=1` | Skip models.dev fetch |
| `OPENCODE_DISABLE_AUTOUPDATE=1` | Skip version check |
| `OPENCODE_DISABLE_LSP_DOWNLOAD=1` | Skip LSP binary downloads |
| `OPENCODE_DISABLE_SHARE=1` | Disable sharing |
| `OPENCODE_DISABLE_DEFAULT_PLUGINS=1` | Skip plugin loading |
| `NODE_DEBUG=net,dns,tls,http` | Node.js network debug logging |
| `DEBUG=*` | Enable all debug logging |

### Multi-Hour Hang Analysis

If the hang is **hours** (not seconds/minutes), it's NOT DNS (DNS timeout is 5-30s).
The most likely causes for multi-hour hangs:

1. **TCP connect to firewalled host**: When a firewall drops packets silently (no RST),
   TCP retransmits with exponential backoff. Default Linux TCP timeout is ~2 minutes
   per attempt. With multiple connection attempts or retries, this can add up to hours.

2. **Multiple sequential timeouts**: If the code tries service A (timeout 2min),
   then service B (timeout 2min), then service C, etc. — these add up.

3. **Effect runtime retry logic**: The Effect library has built-in retry with backoff.
   Some operations may retry many times before giving up.

To identify which:

```bash
# Run strace in background, attach after the hang starts
./opencode-strace &
sleep 5
# Now watch the strace log in real-time:
tail -f /tmp/opencode-strace-*.log
# You'll see the epoll_pwait calls and which fd they wait on.
# Then look back in the log for what connect() created that fd.
```

### Reporting Findings

After debugging, update this section with your findings so future developers benefit.
Key info to record:
- What IP/hostname was being connected to
- Which source file initiated the connection
- How it was fixed (guard added, config changed, etc.)
