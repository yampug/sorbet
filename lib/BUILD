# macOS shared library
cc_binary(
    name = "libsorbet.dylib",
    srcs = ["sorbet_c_api.cc"],
    additional_linker_inputs = ["exported.exp"],
    linkshared = True,
    deps = [
        "//main/lsp",
        "//main:realmain",
        "//main/options",
        "//main/pipeline/semantic_extension:interface",
        "@rapidjson",
        "@spdlog",
    ],
    copts = ["-fvisibility=hidden"],
    linkopts = ["-Wl,-exported_symbols_list,$(location exported.exp)"],
    visibility = ["//visibility:public"],
)

# Linux shared library
cc_binary(
    name = "libsorbet.so",
    srcs = ["sorbet_c_api.cc"],
    additional_linker_inputs = ["sorbet.version"],
    linkshared = True,
    deps = [
        "//main/lsp",
        "//main:realmain",
        "//main/options",
        "//main/pipeline/semantic_extension:interface",
        "@rapidjson",
        "@spdlog",
    ],
    copts = ["-fvisibility=hidden"],
    linkopts = ["-Wl,--version-script,$(location sorbet.version)"],
    visibility = ["//visibility:public"],
)

# Windows shared library
cc_binary(
    name = "libsorbet.dll",
    srcs = ["sorbet_c_api.cc"],
    linkshared = True,
    deps = [
        "//main/lsp",
        "//main:realmain",
        "//main/options",
        "//main/pipeline/semantic_extension:interface",
        "@rapidjson",
        "@spdlog",
    ],
    visibility = ["//visibility:public"],
)

# Static library approach: Use cc_library to compile the wrapper
# This creates the C API wrapper as a library that can be extracted
cc_library(
    name = "sorbet_combined",
    srcs = ["sorbet_c_api.cc"],
    linkstatic = True,
    alwayslink = True,
    deps = [
        "//main/lsp",
        "//main:realmain",
        "//main/options",
        "//main/pipeline/semantic_extension:interface",
        "@rapidjson",
        "@spdlog",
    ],
    visibility = ["//visibility:public"],
)

# Optimized static library target
cc_library(
    name = "sorbet_all_static",
    srcs = [
        "sorbet_c_api.cc",
        "sorbet_stubs.cc",
    ],
    linkstatic = True,
    alwayslink = True,
    visibility = ["//visibility:public"],
    deps = [
        "//main:realmain",
        "//main/lsp",
        "//main/options",
        "//main/pipeline/semantic_extension:interface",
        "//main/pipeline/semantic_extension:none",
        "@prism",
        "@rapidjson",
        "@rbs_parser",
        "@spdlog",
    ],
)

# Genrule to create the combined archive (libsorbet.a)
genrule(
    name = "libsorbet_static",
    srcs = [":sorbet_all_static"],
    outs = ["libsorbet.a"],
    tags = ["no-sandbox"],
    cmd = """
        # Enable debug output
        set -e
        # Forced rebuild 2 for getProviders
        
        # Create a temporary directory for extraction
        TEMP_DIR=$$(mktemp -d)
        
        mkdir -p $$TEMP_DIR/obj
        
        # Get the path to the bazel-bin directory relative from the runfiles
        # $(locations :sorbet_all_static) returns the path to libsorbet_all_static.a
        STATIC_LIB_PATH="$(locations :sorbet_all_static)"
        BAZEL_BIN=$$(dirname $$(dirname $$STATIC_LIB_PATH))
        
        # 1. Capture absolute output path
        OUT_PATH="$$PWD/$(location libsorbet.a)"
        
        # 2. Find all archives (internal, external, third_party, etc.)
        # Note: We use -k (keep going) logic implicitly by separate find commands or ignoring errors
        
        # We need a list of all archives. We'll dump them to a file to avoid pipe subshell issues.
        touch archives.txt
        
        # Internal & additional paths
        # Forced rebuild 3 (duplicates)
        find $$BAZEL_BIN/lib $$BAZEL_BIN/main $$BAZEL_BIN/core $$BAZEL_BIN/common $$BAZEL_BIN/cfg \
             $$BAZEL_BIN/namer $$BAZEL_BIN/parser $$BAZEL_BIN/rewriter $$BAZEL_BIN/packager \
             $$BAZEL_BIN/resolver $$BAZEL_BIN/sorbet_version $$BAZEL_BIN/third_party \
             $$BAZEL_BIN/payload $$BAZEL_BIN/ast $$BAZEL_BIN/class_flatten \
             $$BAZEL_BIN/definition_validator $$BAZEL_BIN/hashing $$BAZEL_BIN/infer \
             $$BAZEL_BIN/local_vars $$BAZEL_BIN/proto $$BAZEL_BIN/rbs \
             \\( -name "*.a" -o -name "*.lo" \\) ! -name "libsorbet_combined*" >> archives.txt 2>/dev/null || true
             
        # External paths
        find $$BAZEL_BIN/external \\( -name "*.a" -o -name "*.lo" \\) >> archives.txt 2>/dev/null || true
        
        echo "Check for libnone.a:"
        grep "libnone.a" archives.txt || echo "WARNING: libnone.a NOT FOUND in list"
        
        echo "Found $$(wc -l < archives.txt) archives to process."
        
        # 3. Extract and Rename
        mkdir -p $$TEMP_DIR/all_objs
        counter=0
        
        while IFS= read -r archive; do
            counter=$$((counter + 1))
            # Unique dir for this archive
            extract_dir="$$TEMP_DIR/extract_$$counter"
            mkdir -p "$$extract_dir"
            
            # Resolve to absolute path before cd
            if [[ "$$archive" != /* ]]; then
                archive_abs="$$PWD/$$archive"
            else
                archive_abs="$$archive"
            fi
            
            # Extract
            pushd "$$extract_dir" > /dev/null
            ar -x "$$archive_abs" || echo "Warning: Failed to extract $$archive_abs"
            popd > /dev/null
            
            # Clean up potential mess (sometimes ar extracts garbage or nothing)
            # Rename and move to all_objs
            # We prefix with the counter and simple name to ensure uniqueness and traceability
            base_name=$$(basename "$$archive")
            # Sanitize basename
            safe_name=$$(echo "$$base_name" | sed 's/[^a-zA-Z0-9_]/_/g')
            
            # Find and move objects
            # Use -maxdepth 1 to be safe
            find "$$extract_dir" -maxdepth 1 -name "*.o" -print0 | while IFS= read -r -d '' obj; do
                obj_base=$$(basename "$$obj")
                mv "$$obj" "$$TEMP_DIR/all_objs/$${counter}_$${safe_name}_$${obj_base}"
            done
            
            # Remove extract dir to save space
            rm -rf "$$extract_dir"
            
        done < archives.txt
        
        # 4. Merge
        cd $$TEMP_DIR/all_objs
        
        # Check if we have objects
        # Use find to count, avoiding argument list too long for ls
        obj_count=$$(find . -name "*.o" | wc -l)
        if [ "$$obj_count" -eq 0 ]; then
            echo "❌ Error: No object files extracted!"
            exit 1
        fi
        
        echo "Merging $$obj_count object files into libsorbet.a..."
        
        # Use simple glob expansion. ar supports @file args if needed but glob fits usually.
        ar -rcs "$$OUT_PATH" *.o
        
        echo "✅ Created libsorbet.a at $$OUT_PATH"
        
        # Clean up
        rm -rf $$TEMP_DIR
    """,
    visibility = ["//visibility:public"],
)

genrule(
    name = "libsorbet_static_windows",
    srcs = [":sorbet_all_static"],
    outs = ["libsorbet.lib"],
    tags = ["no-sandbox", "manual"],
    cmd = """
cat <<'EOF' > script.ps1
$$ErrorActionPreference = 'Stop'
try {
    $$srcs = '$(locations :sorbet_all_static)'.Split(' ')
    if ($$srcs.Count -eq 0) { throw 'No sources found' }
    $$firstSrc = $$srcs[0]
    
    # Resolve bazel-bin root
    $$root = (Get-Item $$firstSrc).Directory.Parent.Parent
    Write-Output ("Searching for .lib files in " + $$root.FullName)
    
    $$libs = Get-ChildItem -Path $$root.FullName -Recurse -Filter '*.lib' | Where-Object { $$_.Name -ne 'libsorbet.lib' }
    Write-Output ("Found " + $$libs.Count + " libraries to merge.")
    
    if ($$libs.Count -eq 0) { throw 'No libraries found!' }
    
    $$outPath = '$(location libsorbet.lib)'.Replace('/', '\\')
    New-Item -Path (Split-Path $$outPath) -ItemType Directory -Force | Out-Null
    if (Test-Path $$outPath) { Remove-Item $$outPath }
    
    $$libPaths = $$libs.FullName
    
    # Use response file for safety
    $$rspPath = 'libsorbet.rsp'
    $$rspContent = @("/OUT:$$outPath") + $$libPaths
    Set-Content -Path $$rspPath -Value $$rspContent
    
    Write-Output ("Merging " + $$libs.Count + " libs to " + $$outPath)
    
    # Invoke lib.exe with response file
    # Note: args passed to Start-Process with @file needs care, but direct invocation works usually.
    # lib.exe @libsorbet.rsp
    
    $$p = Start-Process -FilePath "lib.exe" -ArgumentList "@$$rspPath" -Wait -NoNewWindow -PassThru
    if ($$p.ExitCode -ne 0) { throw "lib.exe failed with exit code $$($$p.ExitCode)" }
    
    if (-not (Test-Path $$outPath)) { throw ("Output file not created at " + $$outPath) }
    Write-Output "Done."
} catch {
    Write-Error $$_.Exception.Message
    exit 1
}
EOF
powershell.exe -NoProfile -ExecutionPolicy Bypass -File script.ps1
    """,
    visibility = ["//visibility:public"],
)