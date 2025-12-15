def _clang_tool_impl(ctx):
    exec_path = ""
    if ctx.file.tool.short_path.endswith("dummy.sh"):
        exec_path = 'exec "%s" "$@"' % ctx.file.tool.short_path
    else:
        exec_path = 'exec $0.runfiles/%s/%s "$@"' % (
            ctx.workspace_name,
            ctx.file.tool.short_path,
        )

    ctx.actions.write(
        ctx.outputs.executable,
        "\n".join(
            [
                "#!/bin/sh",
                exec_path,
                "",
            ],
        ),
        True,
    )

    return [DefaultInfo(runfiles = ctx.runfiles(files = [ctx.file.tool]))]

_clang_tool = rule(
    _clang_tool_impl,
    attrs = {
        "tool": attr.label(
            allow_single_file = True,
            cfg = "host",
        ),
    },
    executable = True,
)

def clang_tool(name):
    _clang_tool(
        name = name,
        tool = select({
            "@bazel_tools//src/conditions:host_windows": "//tools:dummy.sh",
            "//conditions:default": "@llvm_toolchain_16_0_0//:bin/" + name,
        }),
        visibility = ["//visibility:public"],
    )
