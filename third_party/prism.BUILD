cc_library(
    name = "prism",
    srcs = glob(["src/**/*.c"]),
    hdrs = glob(["include/**/*.h"]),
    copts = select({
        "@platforms//os:windows": [],
        "//conditions:default": ["-Wno-implicit-fallthrough"],
    }),
    includes = ["include"],
    visibility = ["//visibility:public"],
)
