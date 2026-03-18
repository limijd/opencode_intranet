# OpenCode Intranet Fork — Architecture

> Fork of [anomalyco/opencode](https://github.com/anomalyco/opencode) for air-gapped intranet deployment.
> Repo: [limijd/opencode_intranet](https://github.com/limijd/opencode_intranet)

## Overview

```
┌─────────────────────────────────────────────────────────────────────┐
│  Developer Machine (internet access)                                │
│                                                                     │
│  ┌──────────────────────────────────────────────────────────────┐   │
│  │  Docker Build Pipeline                                       │   │
│  │                                                              │   │
│  │  Stage 1: Ubuntu 22.04        Stage 2: Alpine 3.20          │   │
│  │  ┌────────────────────┐       ┌──────────────────────┐      │   │
│  │  │ Bun + source code  │       │ musl libs:           │      │   │
│  │  │ bun build --compile│       │  ld-musl-x86_64.so.1 │      │   │
│  │  │ --target=musl      │       │  libstdc++.so.6      │      │   │
│  │  │                    │       │  libgcc_s.so.1       │      │   │
│  │  │ → opencode-bin     │       │  patchelf            │      │   │
│  │  └────────────────────┘       └──────────────────────┘      │   │
│  │           │                            │                     │   │
│  │           └──────────┬─────────────────┘                     │   │
│  │                      ▼                                       │   │
│  │  Stage 3: Assemble   Stage 4: CentOS 7.6 Verify             │   │
│  │  ┌─────────────────────────────────────────────┐             │   │
│  │  │ opencode (wrapper) + opencode-bin + lib/     │             │   │
│  │  │ Verified as non-root user on CentOS 7.6     │             │   │
│  │  └─────────────────────────────────────────────┘             │   │
│  └──────────────────────────────────────────────────────────────┘   │
│                      │                                              │
│                      ▼  tar / scp / USB                             │
└─────────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────────┐
│  Intranet CentOS 7.6 Machine (no internet)                         │
│                                                                     │
│  ~/opencode/                                                        │
│  ├── opencode          ← wrapper: auto-patchelf on first run        │
│  ├── opencode-bin      ← musl-linked Bun compiled binary            │
│  └── lib/                                                           │
│      ├── ld-musl-x86_64.so.1                                       │
│      ├── libstdc++.so.6                                             │
│      ├── libgcc_s.so.1                                              │
│      └── patchelf                                                   │
│                                                                     │
│  OPENCODE_INTRANET=1  ←──  set by wrapper                          │
│         │                                                           │
│         ▼                                                           │
│  ┌─────────────────────────────────┐    ┌─────────────────────┐     │
│  │  OpenCode CLI/TUI               │───▶│ Internal LLM        │     │
│  │  (only openai-compatible        │    │ (OpenAI-compatible   │     │
│  │   provider enabled)             │    │  /v1/chat/completions│     │
│  │                                 │    │  e.g. vLLM, TGI)    │     │
│  │  All external access disabled:  │    └─────────────────────┘     │
│  │  ✗ models.dev                   │                                │
│  │  ✗ opncd.ai (share)            │                                │
│  │  ✗ GitHub API                   │                                │
│  │  ✗ OAuth / account              │                                │
│  │  ✗ Version updates              │                                │
│  │  ✗ LSP downloads                │                                │
│  │  ✗ app.opencode.ai proxy       │                                │
│  └─────────────────────────────────┘                                │
└─────────────────────────────────────────────────────────────────────┘
```

## Module Map

### Intranet-Specific Code

| Path | Purpose |
|------|---------|
| `packages/opencode/src/intranet/config.ts` | `OPENCODE_INTRANET` env var check |
| `packages/opencode/src/flag/flag.ts` | `intranetTruthy()` forces disable flags on |
| `docker/Dockerfile.build` | Multi-stage Docker build pipeline |
| `docker/opencode-wrapper.sh` | User-level ELF interpreter patchelf wrapper |
| `docker/build.sh` | One-command build + artifact extraction |
| `docker/build-musl.ts` | Standalone musl build script (backup) |
| `packages/opencode/script/build.ts` | Added `--musl` flag to official build |

### Upstream Code with Guards (12 files modified, 1-2 lines each)

| File | What's Disabled |
|------|-----------------|
| `flag/flag.ts` | `DISABLE_AUTOUPDATE`, `DISABLE_LSP_DOWNLOAD`, `DISABLE_MODELS_FETCH` |
| `provider/provider.ts` | Cloud LLM providers (keeps only `openai-compatible`) |
| `provider/models.ts` | models.dev remote fetch + refresh |
| `share/share-next.ts` | Session sharing |
| `account/index.ts` | Account/identity API (returns undefined) |
| `installation/index.ts` | Version update checks |
| `file/ripgrep.ts` | Ripgrep binary download |
| `session/instruction.ts` | Remote URL instruction fetch |
| `config/config.ts` | `.well-known/opencode` remote config |
| `server/server.ts` | `app.opencode.ai` proxy |

## Build Pipeline

```
bun install --ignore-scripts
    │
    ▼
bun run script/build.ts --musl --skip-install
    │
    ├─ Fetch models.dev/api.json (build-time only, baked into binary)
    ├─ Load DB migrations
    ├─ Bun.build({ compile: { target: "bun-linux-x64-musl" } })
    │
    ▼
dist/opencode-linux-x64-musl/bin/opencode  (127MB ELF binary)
    │
    ▼
Assembled with Alpine musl libs + patchelf → ~130MB package
    │
    ▼
Verified on CentOS 7.6 as non-root user
```

## Upstream Sync Strategy

```bash
git remote -v
# origin    git@github.com:limijd/opencode_intranet.git
# upstream  git@github.com:anomalyco/opencode.git

# Periodic sync
git fetch upstream
git merge upstream/main
# Resolve conflicts — most likely in flag.ts or provider.ts
# All intranet guards are 1-2 line additions, merge conflicts are minimal
```

## Key Design Decisions

| Decision | Rationale |
|----------|-----------|
| Runtime disable (not compile-time) | Easier upstream sync, same codebase |
| musl target (not glibc) | CentOS 7.6 has glibc 2.17, Bun needs 2.25+ |
| patchelf (not /lib symlink) | No root required on target machine |
| Bundled libs (not system) | Target machine has no musl packages |
| `--musl` flag in build.ts | Minimal change to upstream build script |
| `intranetTruthy()` in flag.ts | Leverages existing flag system for LSP/models/etc. |
