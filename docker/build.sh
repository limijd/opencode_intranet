#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
OUTPUT_DIR="${PROJECT_DIR}/output"

echo "=== OpenCode Intranet Builder ==="
echo "Project: ${PROJECT_DIR}"
echo "Output:  ${OUTPUT_DIR}"

# Build the Docker image (includes verification on CentOS 7.6)
echo ""
echo "=== Building... ==="
docker build \
    -f "${SCRIPT_DIR}/Dockerfile.build" \
    -t opencode-builder \
    "${PROJECT_DIR}" 2>&1 | tee "${SCRIPT_DIR}/build.log"

# Extract artifacts
echo ""
echo "=== Extracting artifacts ==="
rm -rf "${OUTPUT_DIR}"
mkdir -p "${OUTPUT_DIR}"

# Create a temporary container to copy files out
CONTAINER_ID=$(docker create opencode-builder)
docker cp "${CONTAINER_ID}:/opt/opencode/." "${OUTPUT_DIR}/"
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
echo "Copy the entire '${OUTPUT_DIR}/' directory to your CentOS 7.6 intranet machine."
echo "Run with: /path/to/opencode-intranet/opencode"
