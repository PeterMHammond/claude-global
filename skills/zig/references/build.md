# build.zig and build.zig.zon templates

Current (0.16). The breaking points: `root_module` is required on artifacts; `.name` in zon is an **enum literal**; `.fingerprint` is mandatory. On master/0.17-dev confirm with `zig std` / `zig init`.

## build.zig — minimal exe + run + test

```zig
const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const exe = b.addExecutable(.{
        .name = "app",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    b.installArtifact(exe);

    const run = b.addRunArtifact(exe);
    if (b.args) |args| run.addArgs(args);
    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run.step);

    const unit_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    const run_tests = b.addRunArtifact(unit_tests);
    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_tests.step);
}
```

## Depending on a package; exposing your own module

```zig
// consume a dependency declared in build.zig.zon
const dep = b.dependency("somepkg", .{ .target = target, .optimize = optimize });
exe.root_module.addImport("somepkg", dep.module("somepkg"));

// expose your library module to consumers
const mymod = b.addModule("mylib", .{ .root_source_file = b.path("src/root.zig") });

// inline imports when creating a module:
//   .imports = &.{ .{ .name = "c", .module = translate_c.createModule() } }
```

## build.zig.zon

```zig
.{
    .name = .myproject,                 // ENUM LITERAL (dot-prefixed); ≤32 bytes, no "zig" prefix
    .version = "0.1.0",
    .fingerprint = 0x1234567890abcdef,  // auto-generated ONCE by `zig init`; NEVER edit
    .minimum_zig_version = "0.16.0",    // advisory
    .dependencies = .{
        .somepkg = .{
            .url = "https://example.com/pkg.tar.gz",
            .hash = "...",              // source of truth (packages resolve by hash, not URL)
            // .lazy = true,            // defer fetch until used
            // .path = "../somepkg",    // OR a local path instead of url+hash
        },
    },
    .paths = .{ "build.zig", "build.zig.zon", "src", "" },  // required; "" = project root
}
```

Add deps with `zig fetch --save <url>` (keys the table by the package's own `name`). Fetched deps land in a visible `zig-pkg/` at project root (0.16). `zig build --fetch` pre-fetches recursively for offline builds.
