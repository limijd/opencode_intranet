#!/bin/bash
# OpenCode Intranet wrapper — fully user-level, no root required.
#
# The musl binary needs: ld-musl-x86_64.so.1 (as ELF interpreter at a fixed path),
# libc.musl-x86_64.so.1 (same file, different name), libstdc++.so.6, libgcc_s.so.1.
# On first run, copies libs to ~/.opencode/lib/ and uses patchelf to rewrite the
# binary's ELF interpreter to that path.
set -euo pipefail

DIR="$(cd "$(dirname "$0")" && pwd)"
BIN="$DIR/opencode-bin"
MARKER="$DIR/.patched"
MUSL_DIR="$HOME/.opencode/lib"

export OPENCODE_INTRANET=1
export LD_LIBRARY_PATH="${MUSL_DIR}:$DIR/lib${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"

# Ensure UTF-8 locale for box-drawing characters (CentOS 7.6 may default to non-UTF-8)
case "${LANG:-}" in
    *.[Uu][Tt][Ff]-8|*.[Uu][Tt][Ff]8) ;; # Already UTF-8
    *)
        if locale -a 2>/dev/null | grep -qi '^en_US\.utf-\?8$'; then
            export LANG="en_US.UTF-8"
        elif locale -a 2>/dev/null | grep -qi '^C\.utf-\?8$'; then
            export LANG="C.UTF-8"
        else
            export LANG="en_US.UTF-8"
        fi
        ;;
esac
export LC_ALL="${LANG}"

# Ensure 256-color terminal for proper TUI rendering
case "${TERM:-}" in
    *-256color|xterm-kitty) ;; # Already good
    xterm) export TERM="xterm-256color" ;;
esac

if [ ! -f "$MARKER" ]; then
    echo "OpenCode: first run setup..." >&2

    # Copy musl libs to stable user path
    mkdir -p "$MUSL_DIR"
    cp -f "$DIR/lib/ld-musl-x86_64.so.1" "$MUSL_DIR/"
    cp -f "$DIR/lib/libstdc++.so.6"      "$MUSL_DIR/"
    cp -f "$DIR/lib/libgcc_s.so.1"       "$MUSL_DIR/"
    # libc.musl-x86_64.so.1 is the same file as ld-musl (musl uses one binary for both)
    ln -sf ld-musl-x86_64.so.1 "$MUSL_DIR/libc.musl-x86_64.so.1"
    chmod +x "$MUSL_DIR/ld-musl-x86_64.so.1"

    # Try /lib symlink first (works in Docker or with root)
    if [ ! -f /lib/ld-musl-x86_64.so.1 ]; then
        ln -sf "$MUSL_DIR/ld-musl-x86_64.so.1" /lib/ld-musl-x86_64.so.1 2>/dev/null || true
    fi

    if [ -f /lib/ld-musl-x86_64.so.1 ]; then
        touch "$MARKER"
    else
        # No /lib access — use patchelf to rewrite ELF interpreter path
        PATCHELF="$DIR/lib/patchelf"
        MUSL_LINKER="$MUSL_DIR/ld-musl-x86_64.so.1"

        # Backup before patching
        cp -f "$BIN" "$BIN.orig"

        # Run patchelf via musl linker (patchelf itself is musl-linked)
        "$DIR/lib/ld-musl-x86_64.so.1" --library-path "$DIR/lib" "$PATCHELF" \
            --set-interpreter "$MUSL_LINKER" \
            "$BIN" 2>/dev/null

        # Test patched binary
        if "$BIN" --version >/dev/null 2>&1; then
            rm -f "$BIN.orig"
            touch "$MARKER"
            echo "OpenCode: setup complete." >&2
        else
            # Patched binary broken — restore and use fallback
            mv -f "$BIN.orig" "$BIN"
            echo "Warning: patchelf failed, using ld-musl fallback." >&2
            echo "fallback" > "$MARKER"
        fi
    fi
fi

# Fallback mode: invoke via musl linker directly (--version/--help show Bun help)
if [ -f "$MARKER" ] && grep -q "fallback" "$MARKER" 2>/dev/null; then
    exec "$DIR/lib/ld-musl-x86_64.so.1" --library-path "$MUSL_DIR:$DIR/lib" "$BIN" "$@"
fi

exec "$BIN" "$@"
