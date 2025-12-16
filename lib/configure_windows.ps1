# Configure Windows Environment for Sorbet Build
# This script applies local overrides required for building on Windows with Bazel 8.

$ErrorActionPreference = "Stop"

Write-Host "Configuring generic Sorbet build environment for Windows..."

# 1. Update .bazelversion
Write-Host "1. Setting .bazelversion to 8.4.2..."
"8.4.2" | Set-Content -Path ".bazelversion" -Force

# 2. Update .bazelrc (Enable WORKSPACE)
Write-Host "2. Enabling WORKSPACE in .bazelrc..."
$bazelrc = Get-Content ".bazelrc" -Raw
if ($bazelrc -match "# common --enable_workspace") {
    $bazelrc = $bazelrc -replace "# common --enable_workspace", "common --enable_workspace"
    Set-Content -Path ".bazelrc" -Value $bazelrc -NoNewline
    Write-Host "   Enabled 'common --enable_workspace'."
} else {
    Write-Host "   'common --enable_workspace' already enabled or not found."
}

# 3. Update third_party/externals.bzl
Write-Host "3. Overriding dependencies in third_party/externals.bzl..."
$externalsPath = "third_party/externals.bzl"
$externals = Get-Content $externalsPath -Raw

# Helper to assist with replacement
function Replace-Block($content, $startMarker, $replacement) {
    # Simple regex replace for the known blocks based on the marker
    # This is fragile but sufficient for this specific file structure
    if ($content -match $startMarker) {
        return $content -replace "$startMarker[\s\S]*?\}\)", $replacement
    }
    return $content
}

# Rules Java 9.3.0
$rulesJavaBlock = @"
    http_archive(
        name = "rules_java",
        urls = ["https://github.com/bazelbuild/rules_java/releases/download/9.3.0/rules_java-9.3.0.tar.gz"],
        sha256 = "6ef26d4f978e8b4cf5ce1d47532d70cb62cd18431227a1c8007c8f7843243c06",
    )
"@

# Rules Python 1.7.0
$rulesPythonBlock = @"
    http_archive(
        name = "rules_python",
        url = "https://github.com/bazelbuild/rules_python/releases/download/1.7.0/rules_python-1.7.0.tar.gz",
        sha256 = "f609f341d6e9090b981b3f45324d05a819fd7a5a56434f849c761971ce2c47da",
        strip_prefix = "rules_python-1.7.0",
    )
"@

# Protobuf v29.1
$protobufBlock = @"
    http_archive(
        name = "com_google_protobuf",
        url = "https://github.com/protocolbuffers/protobuf/releases/download/v29.1/protobuf-29.1.tar.gz",
        sha256 = "3d32940e975c4ad9b8ba69640e78f5527075bae33ca2890275bf26b853c0962c",
        strip_prefix = "protobuf-29.1",
    )
"@

# We use more robust regexes to target the specific blocks
# Replace rules_java
$externals = $externals -replace '(?ms)http_archive\s*\(\s*name = "rules_java".*?\)', $rulesJavaBlock
# Replace rules_python
$externals = $externals -replace '(?ms)http_archive\s*\(\s*name = "rules_python".*?\)', $rulesPythonBlock
# Replace com_google_protobuf
$externals = $externals -replace '(?ms)http_archive\s*\(\s*name = "com_google_protobuf".*?\)', $protobufBlock

Set-Content -Path $externalsPath -Value $externals -NoNewline
Write-Host "   Dependencies updated."

# 4. Skip Worktree
Write-Host "4. Ignoring local changes to prevent checking them in..."
git update-index --skip-worktree .bazelversion
git update-index --skip-worktree .bazelrc
git update-index --skip-worktree third_party/externals.bzl
# Ignore checksums just in case
git update-index --skip-worktree .bazelversion_checksums/darwin-arm64
git update-index --skip-worktree .bazelversion_checksums/darwin-x86_64
git update-index --skip-worktree .bazelversion_checksums/linux-arm64
git update-index --skip-worktree .bazelversion_checksums/linux-x86_64

Write-Host "Done. Your environment is configured for Windows build."
Write-Host "To revert changes/track files again, use: git update-index --no-skip-worktree <file>"
