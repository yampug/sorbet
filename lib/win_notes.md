# Windows Compatibility Notes for macOS Developers

## Executive Summary
Recent changes merged from macOS (specifically dependency downgrades in `third_party/externals.bzl` and disabling `WORKSPACE` in `.bazelrc`) **broke the Windows build**. 

To restore Windows functionality (Bazel 8 + MSVC), we had to revert these changes locally. This document outlines the constraints and recommendations to maintain cross-platform stability.

## Critical Windows Requirements

### 1. Dependency Versions
The Windows build, running on Bazel 8.4.2, requires newer versions of specific rules to function correctly. The downgrades introduced cause fatal `load` errors and missing definitions (`ProtoInfo`).

| Dependency | Required (Windows) | macOS Downgrade (Broken) | Failure Symptom on Windows |
| :--- | :--- | :--- | :--- |
| **`rules_java`** | **9.3.0** | 7.11.1 | `cannot load '@@rules_java//java:rules_java_deps.bzl'` |
| **`rules_python`** | **1.7.0** | 0.27.0 | Incompatible with Bazel 8 strictness |
| **`com_google_protobuf`** | **v29.1** | v3.27.0 | `name 'ProtoInfo' is not defined` (Starlark error) |

**Impact**: These older versions rely on deprecated Bazel 6/7 features or internal paths that have been removed or reorganized in Bazel 8, or they lack support for the strictly distinct compilation modes required by MSVC.

### 2. Bazel Configuration (`.bazelrc`)
Windows compilation relies on the `WORKSPACE` file for external dependency definitions.

*   **Requirement**: `common --enable_workspace` must be **enabled** (uncommented).
*   **Issue**: It was commented out (`# common --enable_workspace`). Since `common --noenable_bzlmod` is set, disabling WORKSPACE leaves Bazel with *no* way to load dependencies.

## Fixes Applied (Local Reverts)
To fix the Windows build, verified in `//main:sorbet-orig` and `//lib:libsorbet.dll`, we reverted:
*   `rules_java` -> `9.3.0`
*   `rules_python` -> `1.7.0`
*   `com_google_protobuf` -> `v29.1`
*   Uncommented `common --enable_workspace` in `.bazelrc`.

## Recommendations

To avoid breaking Windows support in future merges:

1.  **Harmonize on Newer versions (Recommended)**:
    *   Upgrade the macOS environment to support `rules_java` 9.3.0, `rules_python` 1.7.0, and `protobuf` 29.1. These versions are generally backward compatible or require minimal changes (e.g., `ProtoInfo` migration) which are already handled in the Windows branch.
    
2.  **Explicit Verification**:
    *   Before merging changes to `externals.bzl`, please verify against a Bazel 8 / Windows Environment, or ping the Windows maintainer.

3.  **Use `select()` or patched Bzl files (Advanced)**:
    *   If macOS *strictly* requires older versions (e.g. for a legacy XCode toolchain), we might need to conditionally load dependencies, though this is difficult with `http_archive` in `WORKSPACE`. Moving to `bzlmod` (MODULE.bazel) would make version selection and overrides significantly easier and robust across platforms.

## Current Status
The Windows branch is currently "pinned" to the newer versions to remain functional. Merging `main` without addressing these version conflicts will repeatedly break the Windows build.
