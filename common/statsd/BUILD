cc_library(
    name = "statsd",
    srcs = select({
        "@platforms//cpu:wasm32": ["statsd-emscripten.cc"],
        "@bazel_tools//src/conditions:host_windows": ["statsd-emscripten.cc"],
        "//conditions:default": ["statsd.cc"],
    }),
    hdrs = [
        "statsd.h",
    ],
    linkstatic = select({
        "//tools/config:linkshared": 0,
        "//conditions:default": 1,
    }),
    visibility = ["//visibility:public"],
    deps = [
        "//common",
        "//core",
        "//sorbet_version",
    ] + select({
        "@platforms//cpu:wasm32": [],
        "@bazel_tools//src/conditions:host_windows": [],
        "//conditions:default": ["@statsd"],
    }),
)
