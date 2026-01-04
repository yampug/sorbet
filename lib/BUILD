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
