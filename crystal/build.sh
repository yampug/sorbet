#!/bin/bash

# Professional build script for libsorbet Crystal CLI
# Suppresses all warnings and creates a clean production build

set -e

CRYSTAL_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
BUILD_DIR="$CRYSTAL_DIR/build"
OUTPUT_DIR="$CRYSTAL_DIR/dist"

# Create directories
mkdir -p "$BUILD_DIR"
mkdir -p "$OUTPUT_DIR"

echo "🔧 Building libsorbet Crystal CLI for production..."

# Build with all warnings suppressed and proper linking
echo "  Compiling main application..."
crystal build main.cr \
  --release \
  --no-debug \
  --link-flags="-L$CRYSTAL_DIR" \
  --stats \
  --progress \
  -o "$BUILD_DIR/main" 2>/dev/null

echo "  Creating distribution package..."
cp "$BUILD_DIR/main" "$OUTPUT_DIR/libsorbet-cli"

# Create version info
VERSION="1.0.0"
echo "$VERSION" > "$OUTPUT_DIR/VERSION"

echo "✅ Build complete!"
echo "   Output: $OUTPUT_DIR/libsorbet-cli"
echo "   Version: $VERSION"
echo "   Size: $(du -h "$OUTPUT_DIR/libsorbet-cli" | cut -f1)"

exit 0