#!/bin/bash
# Script to continuously patch Bazel-generated binaries for macOS Sequoia compatibility

BAZEL_DIR="/private/var/tmp/_bazel_bob"

echo "Monitoring for Bazel binaries to patch..."

while true; do
    # Find all generate_ast binaries
    find "$BAZEL_DIR" -name "generate_ast" -type f 2>/dev/null | while read -r binary; do
        # Check if it's already signed
        if ! codesign -v "$binary" 2>/dev/null; then
            echo "Patching: $binary"
            codesign -s - -f "$binary" 2>/dev/null && echo "  ✓ Signed"
        fi
    done

    # Find clang-format binaries too
    find "$BAZEL_DIR" -name "clang-format" -type f -perm +111 2>/dev/null | while read -r binary; do
        if ! codesign -v "$binary" 2>/dev/null; then
            echo "Patching: $binary"
            codesign -s - -f "$binary" 2>/dev/null && echo "  ✓ Signed"
        fi
    done

    sleep 0.5
done
