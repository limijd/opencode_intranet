# Build Guide — OpenCode Intranet

## Prerequisites

- **Docker** (tested with Docker 28.x)
- **Internet access** on the build machine (to pull base images and npm deps)
- ~2GB free disk space for Docker images

## Quick Build

```bash
cd /path/to/opencode_intranet

# One command — builds everything, extracts to output/
./docker/build.sh
```

Or manually:

```bash
# Build Docker image (includes CentOS 7.6 verification)
docker build -f docker/Dockerfile.build -t opencode-builder .

# Extract artifact
mkdir -p output
CONTAINER_ID=$(docker create opencode-builder)
docker cp "${CONTAINER_ID}:/home/testuser/opencode/." output/
docker rm "${CONTAINER_ID}"

ls -lh output/
```

## Build Output

```
output/
├── opencode           2.7KB   Wrapper script (bash)
├── opencode-bin       127MB   Compiled binary (musl ELF x86_64)
└── lib/
    ├── ld-musl-x86_64.so.1   635KB   musl dynamic linker
    ├── libstdc++.so.6         2.6MB   musl-native C++ stdlib
    ├── libgcc_s.so.1          138KB   musl-native GCC runtime
    └── patchelf               171KB   ELF patching tool (musl-linked)
```

Total: ~130MB

## Version Customization

Edit the `OPENCODE_VERSION` in `docker/Dockerfile.build`:

```dockerfile
RUN cd packages/opencode && \
    OPENCODE_VERSION="1.0.0-intranet" \
    bun run script/build.ts --musl --skip-install
```

## Build Details

### Multi-Stage Pipeline

| Stage | Base Image | Purpose |
|-------|-----------|---------|
| 1 - builder | Ubuntu 22.04 | Install Bun, compile musl binary |
| 2 - alpine-libs | Alpine 3.20 | Extract musl-native libraries + patchelf |
| 3 - assembler | Ubuntu 22.04 | Package binary + libs + wrapper |
| 4 - verify | CentOS 7.6.1810 | Verify as non-root user |

### Why musl?

CentOS 7.6 ships glibc 2.17. Bun compiled binaries require glibc 2.25+. The musl target avoids glibc entirely — the binary links against musl libc which we bundle.

### Why patchelf?

The musl binary's ELF interpreter is hardcoded to `/lib/ld-musl-x86_64.so.1`. On CentOS 7.6:
- No musl packages available in yum repos
- No root access to create `/lib/` symlinks

The wrapper script uses patchelf on first run to rewrite the interpreter path to `~/.opencode/lib/ld-musl-x86_64.so.1` (user-writable).

### Why `--ignore-scripts`?

The monorepo includes `electron` (desktop app) whose postinstall script fails in Docker. We only need the `opencode` CLI package — `--ignore-scripts` skips irrelevant postinstall hooks.

## Rebuilding After Upstream Sync

```bash
# 1. Merge upstream
git fetch upstream
git merge upstream/main
# Resolve any conflicts in guarded files

# 2. Rebuild
docker build --no-cache -f docker/Dockerfile.build -t opencode-builder .

# 3. Extract
./docker/build.sh
```

## Troubleshooting

### "Cannot find module" during build

```
error: Cannot find module '@opentui/solid/bun-plugin'
```

The build script must run from `packages/opencode/` directory. The Dockerfile handles this.

### Electron postinstall failure

```
RequestError: unknown certificate verification error
error: postinstall script from "electron" exited with 1
```

Expected. Use `--ignore-scripts` flag (already set in Dockerfile).

### Build takes too long

First build downloads Docker base images + all npm deps. Subsequent builds use Docker cache for unchanged layers. To force full rebuild: `docker build --no-cache ...`

### Docker permission denied

```
permission denied while trying to connect to the Docker daemon socket
```

```bash
sudo usermod -aG docker $USER
# Then log out and back in, or: newgrp docker
```
