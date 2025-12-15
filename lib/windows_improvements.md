# Windows Build Improvement Roadmap

This document outlines technical debt, workarounds, and future improvements identified during the initial Windows port of `libsorbet`. It serves as a guide for hardening the Windows build and achieving full feature parity.

## 1. High Priority: Testing & Stability

### Enable Unit Tests (`doctest`)
-   **Current State**: Unit tests are completely disabled on Windows. The `doctest` library fails to link due to `dllimport`/`dllexport` mismatches (Error `LNK2019`) when built statically with MSVC.
-   **Improvement**:
    -   Investigate `doctest` configuration macros (`DOCTEST_CONFIG_IMPLEMENT_WITH_MAIN`) specifically for Windows static builds.
    -   Alternatively, switch to a purely header-only integration for Windows to bypass linkage complexity.
    -   **Benefit**: Enables automated regression testing without relying on manual E2E scripts.

### Implement Proper Subprocess Support
-   **Current State**: `Subprocess::spawn` is stubbed out to return failure/null in `common/os/common_windows.cc`. Features relying on spawning child processes (e.g., some LSP features or external tool invocations) will silently fail or error out.
-   **Improvement**:
    -   Implement `spawn` using the Windows CreateProcess API.
    -   Map file descriptors correctly to Windows handles for stdin/stdout/stderr redirection.
    -   **Benefit**: Restores full functionality for LSP and tool integrations.

## 2. Medium Priority: Code Maintainability

### Standardize Threading Abstractions
-   **Current State**: The codebase mixes explicit `pthread_t` usage with `std::thread`. We currently shim `pthread` symbols in `common/os/os.h` and provide no-op implementations for thread affinity and priority on Windows.
-   **Improvement**:
    -   Refactor `common/os` to use C++20 `std::jthread` or `std::thread` exclusively, removing the `pthread` dependency entirely.
    -   If thread attributes (priority/affinity) are critical, implement a cross-platform wrapper (e.g., `SorbetThread`) that calls `SetThreadPriority` on Windows and `pthread_setschedparam` on Linux.
    -   **Benefit**: Removes fragile shims and reduces platform-specific code paths.

### Remove Build Script Hacks (`dummy.sh`)
-   **Current State**: `tools/clang.bzl` was patched to bypass proper runfiles handling on Windows because the generated shell scripts failed to locate dependencies.
-   **Improvement**:
    -   Rewrite helper scripts in Python or a platform-agnostic language instead of Bash.
    -   Use Bazel's native runfiles library for C++ (unavailable in older Bazel versions, but standard now) to locate assets reliably on all platforms.
    -   **Benefit**: Cleaner build rules and fewer "magic" patches in `externals.bzl`.

### Clean Up Compilation Warnings
-   **Current State**: `-Werror` (treat warnings as errors) is disabled for Windows to allow the build to pass. We suppress `C4068` (unknown pragma), `C4244` (narrowing conversion), and others.
-   **Improvement**:
    -   Systematically address MSVC warnings.
    -   Replace GCC-specific pragmas (`#pragma GCC diagnostic`) with standard `_Pragma` or `#ifdef _MSC_VER` guards.
    -   Fix implicit narrowing conversions (e.g., `uint64_t` to `uint32_t`) which are flagged aggressively by MSVC.
    -   **Benefit**: Re-enabling `-Werror` prevents code quality regression.

### Modernize File I/O (`std::filesystem`)
-   **Current State**: We migrated to C++20 but still use a custom `dirent_win.h` shim for directory traversal.
-   **Improvement**:
    -   Replace `dirent.h` and POSIX I/O calls with C++17/20 `std::filesystem`.
    -   **Benefit**: Removes platform-specific `win32` API headers and manual resource management.

### Improve Application Robustness (LMDB & Backtraces)
-   **Current State**:
    -   `LMDB` is built with `MDB_USE_ROBUST=0` (no robust mutexes), meaning a crash could leave the database locked indefinitely.
    -   `backtrace.cc` stubs out stack walking, so crashes yield no debug info.
-   **Improvement**:
    -   Investigate Windows-specific robust mutex implementations for LMDB (e.g., named mutexes with `WAIT_ABANDONED`).
    -   Implement `StackWalk64` or `CaptureStackBackTrace` in `common/os/common_windows.cc`.
    -   **Benefit**: Production-grade reliability and debuggability.

### Clean Up External Patches
-   **Current State**: We use fragile `sed` commands in `externals.bzl` to patch Ragel and Protobuf files.
-   **Improvement**:
    -   Upstream fixes to the respective repositories or maintain a clean fork.
    -   Use proper Bazel overlays or toolchains instead of in-place shell patching.
    -   **Benefit**: More resilient builds that don't break on minor dependency updates.

## 3. Low Priority: Feature Parity

### Restore StatsD / Networking
-   **Current State**: StatsD telemetry is disabled via `cc_library` selects. The `StatsD.cc` implementation relies on unnecessary POSIX networking headers (`netdb.h`, `arpa/inet.h`).
-   **Improvement**:
    -   Port `StatsD.cc` to use `Winsock2` on Windows.
    -   Abstract the socket creation/sending logic into `common/os/networking.h`.
    -   **Benefit**: Operational visibility for Windows users.

### Stack Depth Management
-   **Current State**: We blindly increased the stack size to 8MB (`/STACK:8388608`) to prevent crashes during deep AST traversals.
-   **Improvement**:
    -   Investigate iterative algorithms for the deepest traversals in `walker.cc` or `rewriter.cc`.
    -   Implement runtime stack checks to fail gracefully with an error message instead of a hard crash.
    -   **Benefit**: Better stability on memory-constrained systems.

### Macro Hygiene (`VOID`, `Yield`)
-   **Current State**: We `#undef VOID` and `#undef Yield` in `common.h` to fix collisions with `windows.h`. This is brittle if headers are re-ordered.
-   **Improvement**:
    -   Rename `Sorbet::core::Names::VOID` to `VOID_TYPE` or similar.
    -   Rename `Yield` node in the parser to `YieldNode`.
    -   **Benefit**: Eliminates risk of preprocessor collisions and strange syntax errors.
