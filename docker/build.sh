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

echo ""
echo "=== Done! ==="
echo "Artifact is at: ${OUTPUT_DIR}/"
echo "Copy the entire directory to your CentOS 7.6 intranet machine."
echo "Run with: /path/to/opencode/opencode"
