# Sorbet C API Wrapper

This directory contains a C API wrapper for Sorbet's LSP functionality, making it accessible from languages like Crystal, Zig, or any language with C FFI support.

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
| macOS    | ⚠️ Broken on Sequoia 15+ | Native build (fails on newer macOS) |
| Windows  | ❌ Not yet supported | Requires MinGW toolchain |

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

## Known Issues

### macOS Sequoia 15+ Build Failure - FIXED ✅

**Error:** `dyld: __DATA_CONST segment missing SG_READ_ONLY flag`

**Cause:** macOS Sequoia (15.x / 26.x) introduced stricter dyld security checks that are incompatible with LLVM 15.x linker output.

**Solution:** Upgrade LLVM from 15.0.7 to 16.0.0+

The fix has been applied to this repository:
- `WORKSPACE`: Updated `llvm_toolchain_15_0_7` → `llvm_toolchain_16_0_0`
- `tools/clang.bzl`: Updated toolchain reference
- `test/pipeline_test.bzl`: Updated ASAN symbolizer path

**Build now works on macOS Sequoia 15.x!**

## Usage Example

See `../crystal/main.cr` for a complete example using the wrapper from Crystal.

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

## Future: Zig Implementation

Currently this wrapper is written in C++ because Sorbet's API is C++-only. A pure Zig implementation would require either:

1. **Hybrid approach**: Minimal C++ bridge + Zig wrapper
2. **Waiting for Sorbet C API**: If Sorbet ever exposes a C API

For now, the C++ wrapper is minimal (~120 lines) and straightforward.
