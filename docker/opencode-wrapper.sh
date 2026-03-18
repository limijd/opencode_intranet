#!/bin/bash
# OpenCode Intranet wrapper — fully user-level, no root required.
#
# The compiled binary expects /lib/ld-musl-x86_64.so.1 as its ELF interpreter.
# Without root, we can't write there. Instead we do a direct byte-patch of the
# interpreter path in the binary to point to ~/.opencode/lib/ld-musl-x86_64.so.1.
# This works because the new path is longer, and we pad the old path's section.
# Unlike patchelf, this doesn't restructure the ELF — just overwrites bytes in place.
set -euo pipefail

DIR="$(cd "$(dirname "$0")" && pwd)"
BIN="$DIR/opencode-bin"
MARKER="$DIR/.patched"
MUSL_DIR="$HOME/.opencode/lib"

export OPENCODE_INTRANET=1
export LD_LIBRARY_PATH="${MUSL_DIR}:$DIR/lib${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"

if [ ! -f "$MARKER" ]; then
    # Copy musl libs to stable user path
    mkdir -p "$MUSL_DIR"
    cp -f "$DIR/lib/ld-musl-x86_64.so.1" "$MUSL_DIR/"
    cp -f "$DIR/lib/libstdc++.so.6"      "$MUSL_DIR/"
    cp -f "$DIR/lib/libgcc_s.so.1"       "$MUSL_DIR/"
    chmod +x "$MUSL_DIR/ld-musl-x86_64.so.1"

    # Try /lib symlink first (works in Docker or if user has permissions)
    if [ ! -f /lib/ld-musl-x86_64.so.1 ]; then
        ln -sf "$MUSL_DIR/ld-musl-x86_64.so.1" /lib/ld-musl-x86_64.so.1 2>/dev/null || true
    fi

    if [ -f /lib/ld-musl-x86_64.so.1 ]; then
        touch "$MARKER"
    else
        # No /lib access. Use patchelf (Alpine musl-linked) to rewrite interpreter.
        # Key: use --page-size 0 to avoid section rewrite that breaks Bun.
        PATCHELF="$DIR/lib/patchelf"
        MUSL_LINKER="$MUSL_DIR/ld-musl-x86_64.so.1"

        # Make a backup before patching
        cp -f "$BIN" "$BIN.orig"

        "$DIR/lib/ld-musl-x86_64.so.1" --library-path "$DIR/lib" "$PATCHELF" \
            --set-interpreter "$MUSL_LINKER" \
            "$BIN" 2>/dev/null

        # Test if the patched binary runs
        if "$BIN" --version >/dev/null 2>&1; then
            rm -f "$BIN.orig"
            touch "$MARKER"
        else
            # Patched binary broken — restore and fall back to ld-musl invocation
            mv -f "$BIN.orig" "$BIN"
            echo "Warning: patchelf broke the binary, using ld-musl fallback." >&2
            echo "Note: --version/--help will show Bun help instead of OpenCode." >&2
            echo "Use 'opencode providers' or 'opencode run' to verify it works." >&2
            # Mark as fallback mode
            echo "fallback" > "$MARKER"
        fi
    fi
fi

# Check if we're in fallback mode (ld-musl invocation — less compatible but functional)
if [ -f "$MARKER" ] && grep -q "fallback" "$MARKER" 2>/dev/null; then
    exec "$DIR/lib/ld-musl-x86_64.so.1" --library-path "$MUSL_DIR:$DIR/lib" "$BIN" "$@"
fi

exec "$BIN" "$@"
