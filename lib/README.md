# Sorbet C API Wrapper

This directory contains a C API wrapper for Sorbet's LSP functionality, making it accessible from languages like Crystal, or any language with C FFI support.

## Files

- `sorbet_c_api.cc` - C++ wrapper exposing Sorbet LSP as C ABI
- `BUILD` - Bazel build configuration
- `Taskfile.yml` - Build tasks for different platforms
- `Dockerfile` - Docker environment for Linux builds

## Building

### Requirements

- Bazel 6.5+
- Docker (for Linux builds)
- Task (task runner) - `brew install go-task/tap/go-task`

### Supported Platforms

| Platform | Status | Method |
|----------|--------|--------|
| Linux    | ✅ Working | Docker build |
| macOS    | ✅ Working | Native build |
| Windows  | ✅ Working | Native build |

### Build Commands

```bash
cd lib

# Build for Linux (via Docker)
task build:linux

# Attempt macOS build (will fail on macOS Sequoia 15+)
task build:macos

# Build Docker image
task docker:build

# Clean artifacts
task clean
```

## Usage Example

See `../crystal/main.cr` for a complete example using the wrapper from Crystal.

## Running Tests

The Crystal directory contains a comprehensive test suite:

```bash
cd crystal

# Install dependencies
task --list  # Show available tasks

# Run all specs
task spec

# Run specific spec groups
task spec-basic      # Basic functionality tests
task spec-require    # Require resolution tests

# Clean up
task clean
```

The test suite covers:
- Basic session management
- File typechecking
- Error detection and reporting
- Require resolution (require_relative, nested requires, etc.)
- Batch processing and multi-threaded operations
- Memory management and cleanup

### Testing the Build

After building libsorbet, you can test it with the Crystal examples:

```bash
# Build libsorbet first
cd ../lib
task build:macos      # macOS
task build:linux      # Linux

# Test with Crystal
cd ../crystal
crystal build main.cr -L../dist/macos   # macOS
crystal build main.cr -L../dist/linux   # Linux
```
=======

## API

```c
// Opaque state handle
typedef void* SorbetState;

// Initialize Sorbet LSP
SorbetState* sorbet_new(const char* args_json);

// Send LSP message and get response
char* sorbet_send(SorbetState* state, const char* message);

// Free Sorbet state
void sorbet_free(SorbetState* state);
```
