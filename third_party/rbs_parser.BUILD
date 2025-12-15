cc_library(
    name = "rbs_parser",
    srcs = glob(["src/**/*.c"]),
    hdrs = glob(["include/**/*.h"]),
    copts = select({
        "@platforms//os:windows": [],
        "//conditions:default": [
            "-Wno-error=missing-field-initializers",
            "-Wno-error=implicit-fallthrough",
        ],
    }),
    includes = ["include"],
    linkstatic = select({
        "@com_stripe_ruby_typer//tools/config:linkshared": 0,
        "//conditions:default": 1,
    }),
    visibility = ["//visibility:public"],
)
