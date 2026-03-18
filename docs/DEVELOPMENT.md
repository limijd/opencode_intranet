# Development Guide — OpenCode Intranet Fork

## Repository Setup

```bash
git clone git@github.com:limijd/opencode_intranet.git
cd opencode_intranet

# Verify remotes
git remote -v
# origin    git@github.com:limijd/opencode_intranet.git
# upstream  git@github.com:anomalyco/opencode.git

# If upstream remote is missing:
git remote add upstream git@github.com:anomalyco/opencode.git
```

## Branch Strategy

| Branch | Purpose |
|--------|---------|
| `dev` | Main development branch (default) |
| `main` | Stable releases for intranet deployment |

## Making Changes

### Intranet-Specific Changes

All intranet customization follows this pattern:

```typescript
// 1. Import the intranet config
import { INTRANET } from "../intranet/config"

// 2. Add minimal guard (1-2 lines)
if (INTRANET) return          // skip feature
if (INTRANET) return undefined // return empty
if (INTRANET) break           // skip loop iteration
```

**Rules:**
- Keep guards minimal — 1-2 lines, early return
- Never delete upstream code — only add conditional guards
- Concentrate new files in `packages/opencode/src/intranet/`
- Concentrate build files in `docker/`

### Adding a New External Service to Disable

1. Find the external access point in upstream code
2. Add import: `import { INTRANET } from "../intranet/config"`
3. Add guard: `if (INTRANET) return` (or appropriate early exit)
4. Test: rebuild and verify

### Modifying the Build

Build configuration lives in:
- `docker/Dockerfile.build` — Docker pipeline
- `docker/opencode-wrapper.sh` — Runtime wrapper
- `packages/opencode/script/build.ts` — Bun compile (the `--musl` flag)

## Syncing with Upstream

```bash
# 1. Fetch latest upstream
git fetch upstream

# 2. Merge into dev
git checkout dev
git merge upstream/main

# 3. Resolve conflicts
# Most likely conflict files:
#   - packages/opencode/src/flag/flag.ts
#   - packages/opencode/src/provider/provider.ts
#   - packages/opencode/script/build.ts
# Our changes are 1-2 line additions — easy to re-apply

# 4. Test build
docker build --no-cache -f docker/Dockerfile.build -t opencode-builder .

# 5. Push
git push origin dev
```

### Conflict Resolution Tips

Our modifications are always **additions**, never deletions. When resolving:
- Accept upstream changes
- Re-add our `import { INTRANET }` line
- Re-add our `if (INTRANET) ...` guard
- For `flag.ts`: re-add `intranetTruthy()` function and the 3 flag overrides
- For `provider.ts`: re-add the `INTRANET ?` ternary on `BUNDLED_PROVIDERS`

## Currently Guarded Files

Each file has exactly the changes listed:

| File | Import Added | Guard Added |
|------|-------------|-------------|
| `flag/flag.ts` | `import { INTRANET }` | `intranetTruthy()` helper + 3 flag overrides |
| `provider/provider.ts` | `import { INTRANET }` | `BUNDLED_PROVIDERS` ternary (openai-compatible only) |
| `provider/models.ts` | `import { INTRANET }` | `Data()`: skip fetch; `refresh()`: early return |
| `share/share-next.ts` | `import { INTRANET }` | `disabled` const includes `INTRANET` |
| `account/index.ts` | `import { INTRANET }` | 3 functions: `active()`, `config()`, `token()` |
| `installation/index.ts` | `import { INTRANET }` | `latest()`: return current version |
| `file/ripgrep.ts` | `import { INTRANET }` | Skip download, throw error |
| `session/instruction.ts` | `import { INTRANET }` | Skip URL instructions |
| `config/config.ts` | `import { INTRANET }` | Break well-known config loop |
| `server/server.ts` | `import { INTRANET }` | Return 503 for proxy routes |
| `build.ts` | — | `muslFlag` + filter targets |

## Testing Locally

```bash
# Quick test: build and verify
docker build -f docker/Dockerfile.build -t opencode-builder .

# Check the verification output in build log:
# Look for "VERIFY=WORKS" and "PROVIDERS=WORKS"

# Interactive test inside CentOS 7.6:
docker run --rm -it opencode-builder bash
./opencode/opencode providers
./opencode/opencode --help
```

## Debug Build

For diagnosing startup hangs or other issues on the intranet machine:

```bash
# Build debug version (includes strace + diagnostic scripts)
docker build -f docker/Dockerfile.debug -t opencode-debug .

# Extract clean artifacts
docker build -f docker/Dockerfile.debug --target assembler -t opencode-debug-assembler .
mkdir -p output-debug
CONTAINER_ID=$(docker create opencode-debug-assembler)
docker cp "${CONTAINER_ID}:/package/." output-debug/
docker rm "${CONTAINER_ID}"

# Package for transfer
tar -czf opencode-debug.tar.gz -C output-debug .
```

See [DEBUG.md](DEBUG.md) for full debugging procedures and analysis techniques.

## Project Structure

```
opencode_intranet/
├── AGENTS.md                              # Agent conventions (upstream + intranet learnings)
├── docker/                                # ★ Intranet build infrastructure
│   ├── Dockerfile.build                   #   Production multi-stage build
│   ├── Dockerfile.debug                   #   Debug build (strace + diagnostics)
│   ├── Dockerfile.compat-test             #   glibc compatibility test (historical)
│   ├── Dockerfile.musl-test               #   musl approach validation (historical)
│   ├── build.sh                           #   One-command production build
│   ├── build-musl.ts                      #   Standalone musl build (backup)
│   ├── opencode-wrapper.sh               #   Runtime wrapper for CentOS 7.6
│   ├── opencode-debug.sh                 #   Verbose logging wrapper
│   ├── opencode-strace.sh               #   Syscall tracing wrapper
│   └── opencode-trace-startup.sh         #   Phased startup analysis
├── docs/                                  # ★ Intranet documentation
│   ├── ARCHITECTURE.md                    #   System architecture diagram
│   ├── BUILD.md                           #   Build instructions
│   ├── DEBUG.md                           #   Debugging guide (startup hang analysis)
│   ├── DEPLOY.md                          #   Deployment + LLM configuration guide
│   ├── DEVELOPMENT.md                     #   This file
│   └── plans/
│       └── 2026-03-18-opencode-intranet-design.md  # Original design decisions
├── output/                                # ★ Production build artifacts (gitignored)
├── output-debug/                          # ★ Debug build artifacts (gitignored)
├── packages/opencode/
│   ├── script/build.ts                    #   Modified: --musl flag
│   └── src/
│       ├── intranet/                      # ★ Intranet config module
│       │   └── config.ts                  #   OPENCODE_INTRANET + INTRANET_DEBUG
│       ├── flag/flag.ts                   #   Modified: intranetTruthy()
│       ├── provider/provider.ts           #   Modified: BUNDLED_PROVIDERS filter
│       ├── provider/models.ts             #   Modified: skip remote fetch
│       ├── share/share-next.ts            #   Modified: disable sharing
│       ├── account/index.ts               #   Modified: disable account API
│       ├── installation/index.ts          #   Modified: skip update check
│       ├── file/ripgrep.ts                #   Modified: skip rg download
│       ├── session/instruction.ts         #   Modified: skip URL instructions
│       ├── config/config.ts               #   Modified: skip well-known
│       └── server/server.ts               #   Modified: disable proxy
└── ... (upstream files unchanged)
```

Files marked with ★ are intranet-specific additions.
