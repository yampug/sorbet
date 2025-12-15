# Windows Porting Report: Sorbet C API (Detailed)

This document serves as a comprehensive technical reference for the Windows port of the Sorbet C API (`libsorbet`). It maps specific MSVC/Windows errors to their resolutions.

## 0. Prerequisites & Environment

-   **Bazel Version**: 6.5.0 (Required for specific Windows rule support).
-   **Toolchain**: `clang-format` configuration required adjustments for Windows line endings.
-   **Environment**: MSVC compiler (Visual Studio 2019/2022) with C++20 support.

## 1. Build System & Configuration

### Bazel & MSVC Flags
-   **Stack Overflow**:
    -   *Symptom*: Build succeeds, but [sorbet-orig.exe](file:///c:/repos/sorbet/bazel-bin/main/sorbet-orig.exe) silently exits or crashes immediately on deep AST traversal.
    -   *Fix*: Added `/STACK:8388608` to `linkopts` in [.bazelrc](file:///c:/repos/sorbet/.bazelrc).
-   **C++ Standard**:
    -   *Issue*: `error C2039`, `error C2440` related to designated initializers (`{.field = value}`). MSVC defaults to C++14.
    -   *Fix*: Added `/std:c++20` to `copts`.
-   **Source Encoding**:
    -   *Issue*: `warning C4819`: The file contains a character that cannot be represented in the current code page.
    -   *Fix*: Added `/utf-8` to `copts`.
-   **Strictness**:
    -   *Issue*: `treat_warnings_as_errors` caused build failure on benign MSVC warnings (e.g., `C4068` unknown pragma).
    -   *Fix*: Disabled `-Werror` equivalent flags for Windows config.

## 2. Compilation Errors (MSVC)

### Standard Library Differences
-   **`std::vector<const T>`**:
    -   *Error*: `C2338: The C++ Standard forbids containers of const elements`.
    -   *Context*: `main/lsp/generate_lsp_messages.h` used `std::vector<const Type>`.
    -   *Fix*: Changed to `std::vector<Type>` in generated code (C++ standard compliance).
-   **`winsize` struct undefined**:
    -   *Error*: `error C2079: 'w' uses undefined struct 'winsize'`.
    -   *Context*: [main/options/options.cc](file:///c:/repos/sorbet/main/options/options.cc) uses `sys/ioctl.h` for terminal size.
    -   *Fix*: Guarded code with `#ifndef _WIN32`. MSVC does not have `sys/ioctl.h`.
-   **`spdlog` Sink Mismatch**:
    -   *Error*: `error C2039: 'white': is not a member of ...`.
    -   *Context*: [main/realmain.cc](file:///c:/repos/sorbet/main/realmain.cc) attempted to use `stderr_color_sink_mt` colors directly.
    -   *Fix*: Guarded color setting code with `#ifndef _WIN32` or used compatible `spdlog` macros.

### Syntax & Intrinsics
-   **`__builtin_popcount`**:
    -   *Error*: `C3861: '__builtin_popcount': identifier not found`.
    -   *Fix*: Shimmed in [common/UIntSet.cc](file:///c:/repos/sorbet/common/UIntSet.cc):
        ```cpp
        #if defined(_MSC_VER)
        #include <intrin.h>
        #define __builtin_popcount __popcnt
        #endif
        ```
-   **Designated Initializers**:
    -   *Error*: `error C2440`: 'initializing': cannot convert from 'initializer list' to...
    -   *Context*: Widespread usage in `parser/prism`, plus specific fixes in `core/types/calls.cc`, `namer/namer.cc`, and `packager/VisibilityChecker.cc` which required C++20.
    -   *Fix*: Upgrading to `/std:c++20` resolved this natively.
-   **Variadic Macros**:
    -   *Error*: MSVC preprocessor expansion failure in `ast/treemap/treemap.h`.
    -   *Fix*: Replaced named arguments (`arg_type...`) with `__VA_ARGS__` to support MSVC's standard conformant preprocessor (`/Zc:preprocessor`).

### Platform Macros
-   **`VOID` Collision**:
    -   *Error*: `syntax error` in `core/Names.h`.
    -   *Root Cause*: `windows.h` defines `#define VOID void`, conflicting with `sorbet::core::Names::VOID`.
    -   *Fix*: `#undef VOID` in `common/common.h` after including system headers.
-   **`Yield` Collision**:
    -   *Error*: `syntax error` in generated parser code.
    -   *Root Cause*: `winbase.h` defines `Yield` macro, conflicting with `node.Yield()`.
    -   *Fix*: `#undef Yield` in `common/common.h`.

## 3. Linker Errors

-   **`doctest` Symbols**:
    -   *Error*: `LNK2019: unresolved external symbol ... TestCase::~TestCase`.
    -   *Context*: Default `doctest` configuration on Windows implies `dllimport` but static linking is preferred.
    -   *Status*: **Deferred**. Unit tests are currently blocked. Verification done via E2E script.
-   **`constexpr` Definition**:
    -   *Error*: `LNK2001: unresolved external symbol` for static constexpr members.
    -   *Fix*: Moved definition to `.cc` file or removed `constexpr` where ODR (One Definition Rule) violations occurred.

## 4. Runtime Stability (The Segfault)

### Use-After-Move in `ConstantAssumeType.cc`
-   **Symptoms**:
    -   Build Success.
    -   `sorbet-orig.exe -p state rubygems.rbi` crashes with Access Violation (0xC0000005).
    -   Location: `ConstantAssumeType::run`.
-   **Root Cause**:
    ```cpp
    // MSVC evaluation order caused 'rhs.loc()' to run AFTER 'move(rhs)'
    asgn->rhs = MK::AssumeType(asgn->rhs.loc(), move(asgn->rhs), ...);
    ```
-   **Fix**:
    ```cpp
    auto loc = asgn->rhs.loc(); // Enforce evaluation
    asgn->rhs = MK::AssumeType(loc, move(asgn->rhs), ...);
    ```

## 5. Third-Party Dependencies

-   **LMDB**:
    -   *Issue*: Compilation failure due to missing Robust Mutex APIs on Windows.
    -   *Fix*: `copts = ["-DMDB_USE_ROBUST=0"]` in `lmdb.BUILD`.
-   **Protobuf**:
    -   *Issue*: Invalid include paths in generated C++ (`message.cc`), C#, and Java files. Path length limits exceeded for `java_features.pb.h`.
    -   *Fix*: Patched `externals.bzl`:
        -   Fixed C++ output structure.
        -   Generalized `patch_cmds` for C# and Java include paths.
        -   Shortened output root for `java_features.pb.h` to avoid `MAX_PATH` issues.
-   **Ragel**:
    -   *Issue*: Explicit output path `-o` usage failed in cross-platform rules.
    -   *Fix*: Updated `externals.bzl` to use logic compatible with Windows paths.

## 6. Files & I/O

-   **Directory Traversal**:
    -   *Issue*: `dirent.h` (opendir/readdir) missing.
    -   *Fix*: Added `common/os/dirent_win.h` shim using `FindFirstFile`/`FindNextFile`.
    -   *Issue*: `getpid` and `pid_t` missing.
    -   *Fix*: Typedef `pid_t` to `int` and mapped `getpid` to `_getpid`.
-   **C++ Version Reporting**:
    -   *Issue*: MSVC reports `__cplusplus` as `199711L` by default, confusing version checks.
    -   *Fix*: Added `/Zc:__cplusplus` to `.bazelrc` effectively (via explicit C++20 flag) and ensured `__cplusplus` logic in `common.h` is robust.

## 7. Miscellaneous & One-Off Fixes

-   **Bison / Yacc Flags**:
    -   *Issue*: `bison` command line arguments incompatible with Windows environment in `WORKSPACE`.
    -   *Fix*: Adjusted `BISON_FLAGS` to be platform-neutral or compatible.
-   **Debug Stubs (`backtrace`)**:
    -   *Issue*: `execinfo.h` (backtrace variables) missing on Windows.
    -   *Fix*: Stubbed `sorbet::clean_exit` and `make_backtrace` in `common/os/windows.cc` to do nothing.
-   **JSON Iterator**:
    -   *Issue*: `common/JSON.cc` failed to find `std::ostream_iterator`.
    -   *Fix*: Added `#include <iterator>`.
-   **Variadic Template Macros (`EnforceNoTimer.h`)**:
    -   *Issue*: Expansion error in `ENFORCE_NO_TIMER` macro.
    -   *Fix*: Patched `EnforceNoTimer.h` to correctly handle variadic template arguments on MSVC.
-   **Type Casting (`Trees.h`)**:
    -   *Issue*: `reinterpret_cast` from `uint64_t` to pointer types failed strict casting checks.
    -   *Fix*: Adjusted casting logic to be explicit.
-   **Static Assertions**:
    -   *Issue*: `common.h` contained `static_assert` for structure sizes/alignment that differ on Windows x64.
    -   *Fix*: Disabled specific size checks for `_WIN32` builds.

    -   *Fix*: Disabled specific size checks for `_WIN32` builds.
-   **Architecture Macros (`crypto_hashing`)**:
    -   *Issue*: `common/crypto_hashing` checked for `__x86_64__`, missing MSVC's `_M_X64`.
    -   *Fix*: Added `|| defined(_M_X64)` to architecture checks.
-   **Missing Headers (`cache.h`, `tracing.cc`)**:
    -   *Issue*: `cache.h` missing `<vector>`, `tracing.cc` included `unistd.h` unconditionally.
    -   *Fix*: Added `<vector>` and guarded `unistd.h` with `#ifndef _WIN32`.
-   **Build Flags (`blake2`)**:
    -   *Issue*: `blake2` dependency required tweaks for Windows.
    -   *Fix*: Updated `blake2.BUILD` to select correct sources/flags for Windows.

## 8. Logic & POSIX Shims (Restored)

-   **Timer / Telemetry**:
    -   *Issue*: `Timer.cc` relied on POSIX `clock_gettime`. `StatsD` relied on `netdb.h` and sockets.
    -   *Fix*: Shimmed `Timer` to use Windows `QueryPerformanceCounter`. Disabled `StatsD` via `select` (compiled no-op stub).
-   **Threading (`pthread`)**:
    -   *Issue*: `common/os` heavily relied on `<pthread.h>` which is absent on MSVC.
    -   *Fix*:
        -   Stubbed `pthread_t` and related types in `common/os/os.h`.
        -   Guarded `<pthread.h>` includes in `os.cc` and other files.
        -   Implemented no-op stubs for thread affinity/priority in `windows.cc`.
-   **Subprocesses**:

    -   *Issue*: `Subprocess.cc` relied on `fork`/`exec`.
    -   *Fix*: Stubbed `Subprocess::spawn` to return failure/no-op on Windows to prevent link errors.
-   **Runfiles Support (`dummy.sh`)**:
    -   *Issue*: Bazel's `runfiles` libraries behave differently on Windows, causing `dummy.sh` (helper script) invocation to fail.
    -   *Fix*: Patched `tools/clang.bzl` to avoid strict runfiles checks for this tool on Windows.
    -   *Issue*: `ConstExprStr` header-only definitions caused ODR (One Definition Rule) violations or compilation errors.
    -   *Fix*: Refactored to avoid complex `constexpr` usage in header files.

## 9. Build Logic & Syntax Fixes (Final)

-   **Conditional Build Flags**:
    -   *Issue*: `core/hashing`, `rbs_parser`, and `parser/parser` required platform-specific flags.
    -   *Fix*: Used `select()` in `BUILD` files to apply Windows-specific `copts` only when targeting Windows.
-   **Macro Collisions (`has_member.h`)**:
    -   *Issue*: `has_member.h` macros clashed with MSVC internal definitions.
    -   *Fix*: Renamed or safely wrapped macros to avoid pollution.
-   **Template Constants (`subtyping.cc`)**:
    -   *Issue*: `constexpr` template variables caused linker errors on MSVC.
    -   *Fix*: Replaced with `static const` or inline functions.
-   **Compound Literals**:
    -   *Issue*: C99-style compound literals in `Translator.cc` and `Factory.cc` rejected by MSVC C++.
    -   *Fix*: Replaced with explicit type constructors or standard C++ initialization.
-   **Header Compilation (`TypePtr.h`, `Error.h`)**:
    -   *Issue*: Compilation failures due to include ordering or forward definitions on MSVC.
    -   *Fix*: Adjusted includes and forward declarations.
-   **Manual Macro Inlining (`NameSubstitution.h`)**:
    -   *Issue*: MSVC preprocessor failed to expand recursive macros correctly.
    -   *Fix*: Manually inlined the macro usage to bypass the error.
-   **Struct Visibility (`options.cc`)**:
    -   *Issue*: `Printers` struct visibility issues within `options.cc`.
    -   *Fix*: Resolved by refactoring code and removing unused dependencies during cleanup.
-   **Compiler Attributes (`Exception.h`)**:
    -   *Issue*: `__attribute__((noreturn))` and similar GCC extensions are not supported by MSVC.
    -   *Fix*: Patched `Exception.h` to define `__attribute__(x)` as a no-op macro on declared `_MSC_VER`.

## 10. Verification Status

-   **Build Verification**:
    -   *Status*: **Success**. `sorbet-orig.exe` builds and runs.
    -   *Details*: Validated against `test.rb` and `simple_test.rb`.
-   **Linkage Verification**:
    -   *Status*: **Success**. `libsorbet.dll` is generated and symbols are exported.
    -   *Details*: Confirmed via `dumpbin` and successful execution of the CLI wrapper.

