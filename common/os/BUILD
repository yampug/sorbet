cc_library(
    name = "os",
    srcs = [
        "os.h",
        "os.cc",
    ] + select({
        "@platforms//os:osx": ["mac.cc"],
        "@platforms//cpu:wasm32": ["emscripten.cc"],
        "@bazel_tools//src/conditions:host_windows": ["windows.cc"],
        "//conditions:default": ["linux.cc"],
    }),
    hdrs = [
        "os.h",
    ],
    linkstatic = select({
        "//tools/config:linkshared": 0,
        "//conditions:default": 1,
    }),
    visibility = ["//visibility:public"],
    deps = [
        "@com_google_absl//absl/debugging:symbolize",
        "@spdlog",
    ],
)
