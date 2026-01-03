#!/bin/bash

# Run Crystal specs with libsorbet
# This script sets up the environment properly for linking

set -e

CRYSTAL_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
REPO_ROOT=$(cd "$CRYSTAL_DIR/.." && pwd)

# Export library path
export MACOSX_DEPLOYMENT_TARGET=15.0
export DYLD_LIBRARY_PATH="$CRYSTAL_DIR:$DYLD_LIBRARY_PATH"
export LD_LIBRARY_PATH="$CRYSTAL_DIR:$LD_LIBRARY_PATH"

# Run the specs with proper linker flags
echo "Running Crystal specs with libsorbet..."
crystal spec "$@" --link-flags="-L$CRYSTAL_DIR"

echo "Specs completed."
