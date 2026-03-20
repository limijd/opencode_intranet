#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
OUTPUT_DIR="${PROJECT_DIR}/output"

echo "=== OpenCode Intranet Builder ==="
echo "Project: ${PROJECT_DIR}"
echo "Output:  ${OUTPUT_DIR}"

# Build the full image (includes CentOS 7.6 verification)
echo ""
echo "=== Building... ==="
docker build \
    -f "${SCRIPT_DIR}/Dockerfile.build" \
    -t opencode-builder \
    "${PROJECT_DIR}" 2>&1 | tee "${SCRIPT_DIR}/build.log"

# Also build just the assembler stage for clean (un-patched) extraction
echo ""
echo "=== Extracting clean (un-patched) artifacts ==="
docker build \
    -f "${SCRIPT_DIR}/Dockerfile.build" \
    --target assembler \
    -t opencode-assembler \
    "${PROJECT_DIR}" > /dev/null 2>&1

rm -rf "${OUTPUT_DIR}"
mkdir -p "${OUTPUT_DIR}"

# Extract from assembler stage — binary is clean, not yet patchelf'd
CONTAINER_ID=$(docker create opencode-assembler)
docker cp "${CONTAINER_ID}:/package/." "${OUTPUT_DIR}/"
docker rm "${CONTAINER_ID}" > /dev/null

echo ""
echo "=== Package contents ==="
ls -la "${OUTPUT_DIR}/"
ls -la "${OUTPUT_DIR}/lib/"
echo ""
du -sh "${OUTPUT_DIR}/"

# Verify extracted artifacts are clean
echo ""
echo "=== Verifying artifacts ==="
FAIL=0

# 1. Binary must NOT be patchelf'd — interpreter should be default /lib/ld-musl-x86_64.so.1
INTERP=$(readelf -l "${OUTPUT_DIR}/opencode-bin" 2>/dev/null | grep -oP '(?<=interpreter: ).*(?=\])' || true)
if [[ "$INTERP" == "/lib/ld-musl-x86_64.so.1" ]]; then
    echo "OK: interpreter = ${INTERP} (clean, not patched)"
else
    echo "FAIL: interpreter = ${INTERP} (expected /lib/ld-musl-x86_64.so.1 — binary was patched!)"
    FAIL=1
fi

# 2. No .patched marker should exist
if [ -f "${OUTPUT_DIR}/.patched" ]; then
    echo "FAIL: .patched marker found — artifacts came from wrong Docker stage!"
    FAIL=1
else
    echo "OK: no .patched marker"
fi

# 3. Wrapper script must exist and contain OPENCODE_INTRANET=1
if grep -q 'OPENCODE_INTRANET=1' "${OUTPUT_DIR}/opencode" 2>/dev/null; then
    echo "OK: wrapper script present with OPENCODE_INTRANET=1"
else
    echo "FAIL: wrapper script missing or incomplete"
    FAIL=1
fi

# 4. All required libs must exist
for lib in ld-musl-x86_64.so.1 libstdc++.so.6 libgcc_s.so.1 patchelf; do
    if [ -f "${OUTPUT_DIR}/lib/${lib}" ]; then
        echo "OK: lib/${lib}"
    else
        echo "FAIL: lib/${lib} missing"
        FAIL=1
    fi
done

if [ "$FAIL" -ne 0 ]; then
    echo ""
    echo "!!! VERIFICATION FAILED — do NOT deploy this artifact !!!"
    exit 1
fi

echo ""
echo "=== Done! ==="
echo "Artifact is at: ${OUTPUT_DIR}/"
echo "Copy the entire directory to your CentOS 7.6 intranet machine."
echo "Run with: /path/to/opencode/opencode"
