# Platform-Specific Build Configuration

This document explains how to configure the Sorbet build for different platforms.

## Overview

Due to toolchain compatibility constraints, macOS and Windows require different Bazel versions and dependency versions:

| Platform | Bazel Version | Reason |
|----------|--------------|--------|
| **macOS** | 6.5.0 | LLVM toolchain fork (`sorbet/bazel-toolchain`) is not yet compatible with Bazel 8 |
| **Windows** | 8.4.2 | Required for MSVC toolchain and newer dependency versions |

## Default Configuration (macOS)

The repository is configured by default for macOS development:

- **Bazel**: 6.5.0 (`.bazelversion`)
- **rules_java**: 7.11.1
- **rules_python**: 0.27.0
- **protobuf**: v3.27.0
- **`.bazelrc`**: `--enable_workspace` is commented out (not supported in Bazel 6.5.0)

## Windows Development Setup

Windows developers need to override the following files locally:

### 1. Update `.bazelversion`
```bash
echo "8.4.2" > .bazelversion
```

### 2. Update `.bazelversion_checksums/`

Create or update these files with Bazel 8.4.2 checksums:

**`.bazelversion_checksums/darwin-arm64`:**
```
0718099b4c505d286d8e24be33ac0a830dfa50c31ef3b68c013edce1aa059de5
```

**`.bazelversion_checksums/darwin-x86_64`:**
```
ce73346274c379f77880db8bd8b9c8569885fe56f19386173760949da9078df0
```

**`.bazelversion_checksums/linux-arm64`:**
```
58e6042fc54f3bf5704452b579f575ae935817d4b842a76123f05fae6b1f9a83
```

**`.bazelversion_checksums/linux-x86_64`:**
```
4dc8e99dfa802e252dac176d08201fd15c542ae78c448c8a89974b6f387c282c
```

### 3. Update `.bazelrc`

Uncomment the `--enable_workspace` flag:

```python
# Disable Bzlmod to use WORKSPACE instead
common --noenable_bzlmod
common --enable_workspace  # Uncomment this line for Windows
```

### 4. Update `third_party/externals.bzl`

Update these three dependencies:

**rules_java** (line ~18-24):
```python
http_archive(
    name = "rules_java",
    urls = ["https://github.com/bazelbuild/rules_java/releases/download/9.3.0/rules_java-9.3.0.tar.gz"],
    sha256 = "6ef26d4f978e8b4cf5ce1d47532d70cb62cd18431227a1c8007c8f7843243c06",
)
```

**rules_python** (line ~26-33):
```python
http_archive(
    name = "rules_python",
    url = "https://github.com/bazelbuild/rules_python/releases/download/1.7.0/rules_python-1.7.0.tar.gz",
    sha256 = "f609f341d6e9090b981b3f45324d05a819fd7a5a56434f849c761971ce2c47da",
    strip_prefix = "rules_python-1.7.0",
)
```

**protobuf** (line ~102-112):
```python
http_archive(
    name = "com_google_protobuf",
    url = "https://github.com/protocolbuffers/protobuf/releases/download/v29.1/protobuf-29.1.tar.gz",
    sha256 = "3d32940e975c4ad9b8ba69640e78f5527075bae33ca2890275bf26b853c0962c",
    strip_prefix = "protobuf-29.1",
)
```

### 5. Git Configuration

**Important**: Do NOT commit these Windows-specific changes to the main repository. Add them to `.git/info/exclude` or use:

```bash
# Ignore local Windows overrides
git update-index --skip-worktree .bazelversion
git update-index --skip-worktree .bazelrc
git update-index --skip-worktree third_party/externals.bzl
git update-index --skip-worktree .bazelversion_checksums/darwin-arm64
git update-index --skip-worktree .bazelversion_checksums/darwin-x86_64
git update-index --skip-worktree .bazelversion_checksums/linux-arm64
git update-index --skip-worktree .bazelversion_checksums/linux-x86_64
```

To restore tracking:
```bash
git update-index --no-skip-worktree <file>
```

## Why Platform-Specific Versions?

### macOS Constraint
The macOS LLVM toolchain (`sorbet/bazel-toolchain`) is a fork of `bazel-contrib/toolchains_llvm` with Sorbet-specific customizations. This fork is based on an older version that predates Bazel 8 support. Upgrading requires:

1. Merging upstream changes from `toolchains_llvm` v1.6.0+
2. Resolving API changes (e.g., `fastbuild_compile_flags` removal)
3. Testing cross-compilation scenarios

### Windows Requirement
Windows uses MSVC toolchain which works natively with Bazel 8. The newer dependency versions (rules_java 9.3.0, rules_python 1.7.0, protobuf 29.1) are required for:

- Bazel 8 compatibility fixes
- MSVC-specific compilation requirements
- Proper path length handling on Windows

## Future Direction

**Option 1: Update macOS toolchain** (recommended long-term)
- Fork and update `sorbet/bazel-toolchain` to support Bazel 8
- Harmonize all platforms on Bazel 8.4.2+

**Option 2: Migrate to Bzlmod**
- Modern dependency management
- Better cross-platform version resolution
- Requires significant migration effort

## Testing

### macOS
```bash
bazel --version  # Should show 6.5.0
bazel build //lib:libsorbet.dylib
bazel test //...
```

### Windows
```bash
bazel --version  # Should show 8.4.2
bazel build //lib:libsorbet.dll
bazel test //...
```

## Troubleshooting

### "Unrecognized option: --enable_workspace" (macOS)
Make sure `--enable_workspace` is commented out in `.bazelrc` and you're using Bazel 6.5.0.

### "ProtoInfo is not defined" (Windows)
Make sure you've updated protobuf to v29.1 in `externals.bzl`.

### "Repository '@compatibility_proxy' could not be resolved" (Windows)
Make sure you've updated rules_java to 9.3.0 in `externals.bzl`.

### llvm-ar errors (macOS on Bazel 8)
You're using Bazel 8 on macOS. Downgrade to Bazel 6.5.0 or wait for toolchain update.
