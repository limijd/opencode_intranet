# OpenCode Intranet Fork Design

**Date**: 2026-03-18
**Repo**: https://github.com/limijd/opencode_intranet
**Upstream**: git@github.com:anomalyco/opencode.git

## Goal

Fork OpenCode for intranet use: connect to internal OpenAI-compatible LLM services, disable all external network access, build a single executable that runs on CentOS 7.6.

## Key Decisions

| Decision | Choice | Rationale |
|----------|--------|-----------|
| Internal LLM API | OpenAI-compatible (`/v1/chat/completions`) | Already supported by upstream `openai-compatible` provider |
| External code disabling | Runtime disable via env var | Easier to maintain long-term sync with upstream |
| Build target | Single executable (linux-x64) | Simplest to distribute to intranet machines |
| Target OS | CentOS 7.6 (glibc 2.17) | Must match production intranet environment |
| Fork strategy | Long-term maintenance, periodic upstream merge | Stay current with upstream improvements |
| Build environment | Docker CentOS 7.6 on developer machine (internet-connected) | Build externally, carry artifact to intranet |

## Architecture

```
opencode_intranet/
├── intranet/                  # All customization code here
│   ├── config.ts              # Runtime switch: OPENCODE_INTRANET=1
│   ├── providers.ts           # Only enable openai-compatible
│   └── patches/               # Minimal patches to upstream code
│
├── docker/                    # CentOS 7.6 build infrastructure
│   ├── Dockerfile.builder     # Build environment (Bun + toolchain)
│   ├── Dockerfile.test        # Clean CentOS 7.6 for validation
│   ├── build.sh               # One-command build script
│   └── export.sh              # Extract artifact from container
│
├── packages/                  # Upstream code (minimal modifications)
│   └── opencode/src/
│       └── ...                # Guard insertions only
│
└── docs/plans/                # This document
```

## Runtime Disable Strategy

Environment variable `OPENCODE_INTRANET=1` controls all feature gates.

### Features to Disable

| Feature | Source Location | Disable Method |
|---------|----------------|----------------|
| Cloud LLM providers (Anthropic, Google, Azure, etc.) | `provider/provider.ts` | Only register `openai-compatible` |
| models.dev remote model list | `provider/models.ts` | Skip remote fetch, use local static JSON |
| Telemetry | TBD (needs code audit) | Disable sending |
| Version update check | `installation/` | Skip check |
| Share functionality | `share/` | Disable |
| OAuth / cloud auth | `auth/` | Disable |
| ACP (Anomaly Control Plane) | `acp/`, `control-plane/` | Disable |
| Account / Identity | `account/`, `identity/` | Disable |

### Implementation Pattern

```typescript
// intranet/config.ts
export const isIntranet = process.env.OPENCODE_INTRANET === "1"

// In upstream files, minimal guard:
import { isIntranet } from "@/intranet/config"
if (isIntranet) return  // skip this feature
```

Each modification point adds only 1-2 lines, minimizing merge conflicts.

## Build Strategy (Verified)

CentOS 7.6 uses glibc 2.17. Compatibility testing confirmed:

- **Plan A (glibc): FAILED** — Bun requires glibc 2.25 (needs `__cxa_thread_atexit_impl`, `quick_exit`, `getrandom`)
- **Plan B (esbuild+Node): Not needed**
- **Plan C (musl): VERIFIED WORKING** — Chosen approach

### Final Build Pipeline

1. **Build stage** (Ubuntu 22.04): `bun build --compile --target=bun-linux-x64-musl`
2. **Libs stage** (Alpine 3.20): Extract musl-native `ld-musl-x86_64.so.1`, `libstdc++.so.6`, `libgcc_s.so.1`
3. **Package**: Binary + 3 libs + wrapper script (~94MB total)
4. **Verify stage** (CentOS 7.6): Run artifact to confirm it works

### Delivery Structure

```
opencode-intranet/
├── lib/
│   ├── ld-musl-x86_64.so.1    # musl dynamic linker
│   ├── libstdc++.so.6          # musl-native C++ stdlib
│   └── libgcc_s.so.1           # musl-native GCC runtime
├── opencode-bin                 # compiled binary (musl-linked)
└── opencode                     # wrapper script (sets up lib path, exec binary)
```

### Wrapper Script

```bash
#!/bin/bash
DIR="$(cd "$(dirname "$0")" && pwd)"
exec "$DIR/lib/ld-musl-x86_64.so.1" --library-path "$DIR/lib" "$DIR/opencode-bin" "$@"
```

## Git Workflow

```bash
# Initial setup
git remote add upstream git@github.com:anomalyco/opencode.git
git remote set-url origin git@github.com:limijd/opencode_intranet.git

# Periodic sync
git fetch upstream
git merge upstream/main  # resolve conflicts in intranet/ changes
```

## Implementation Order

1. **Compatibility verification** (FIRST — blocks everything else)
   - Docker CentOS 7.6: test if Bun binary runs
   - Test `bun build --compile` output on CentOS 7.6
   - Determine Plan A/B/C

2. **Docker build infrastructure**
   - Dockerfile.builder
   - Dockerfile.test
   - build.sh / export.sh

3. **Runtime disable implementation**
   - `intranet/config.ts`
   - Guards in each upstream module
   - Code audit for any other external network calls

4. **Provider configuration**
   - Default config for openai-compatible provider
   - Documentation for intranet users

5. **End-to-end validation**
   - Build in Docker
   - Run on clean CentOS 7.6
   - Connect to OpenAI-compatible endpoint
   - Verify no external network requests
