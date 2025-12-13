#!/bin/bash

# Run all specs in the crystal directory
# Usage: ./spec.sh [spec_file]

set -e

CRYSTAL_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
cd "$CRYSTAL_DIR"

# Check if crystal is installed
if ! command -v crystal &> /dev/null; then
    echo "Error: Crystal is not installed. Please install Crystal first."
    echo "Installation instructions: https://crystal-lang.org/install/"
    exit 1
fi

# Check if task is installed
if ! command -v task &> /dev/null; then
    echo "Error: Task is not installed. Please install Task first."
    echo "Installation: brew install go-task/tap/go-task"
    exit 1
fi

# Run specs
if [ $# -eq 0 ]; then
    echo "Running all specs..."
    task spec
else
    echo "Running specific spec: $1"
    crystal spec "$1"
fi

echo "Specs completed."