# Zig idioms (current)

## Error handling

Error unions `!T`; `try expr` propagates; `expr catch |err| {...}` or `catch default`; `errdefer` cleans up on the error path only. Prefer explicit error sets at API boundaries.

```zig
fn parse(s: []const u8) !u32 { return std.fmt.parseInt(u32, s, 10); }

const n = parse(s) catch |err| switch (err) {
    error.InvalidCharacter => 0,
    else => return err,
};
```

## Allocators — always passed explicitly

```zig
var debug_allocator: std.heap.DebugAllocator(.{}) = .init;   // leak-checking, debug builds
defer _ = debug_allocator.deinit();
const gpa = debug_allocator.allocator();

var arena = std.heap.ArenaAllocator.init(gpa);               // free everything at once
defer arena.deinit();
const a = arena.allocator();
```

`GeneralPurposeAllocator` is now a legacy alias for `DebugAllocator`. In tests use `std.testing.allocator` (auto leak detection). Acquire then immediately `defer x.deinit()`; use `errdefer` for partial-construction rollback.

## Optionals

```zig
const v = maybe orelse default;
if (maybe) |val| { use(val); } else { … }
const forced = maybe.?;   // panics if null
```

## comptime & generics

Type params via `comptime T: type`; duck-typed via `anytype`; `inline for`/`inline while` over comptime-known counts.

```zig
fn Stack(comptime T: type) type {
    return struct {
        items: std.ArrayList(T) = .empty,
        fn push(self: *@This(), alloc: std.mem.Allocator, x: T) !void {
            try self.items.append(alloc, x);
        }
    };
}
fn max(comptime T: type, a: T, b: T) T { return if (a > b) a else b; }
```

## Tagged unions + exhaustive switch

`switch` must cover all cases (or `else`); capture payloads with `|v|`.

```zig
const Shape = union(enum) { circle: f64, rect: struct { w: f64, h: f64 } };
const area = switch (shape) {
    .circle => |r| std.math.pi * r * r,
    .rect => |x| x.w * x.h,
};
```

Labeled switch with `continue :label` for state machines/tokenizers (0.14+).

## Testing

```zig
test "addition" {
    try std.testing.expectEqual(@as(i32, 4), 2 + 2);
}
test "alloc leak-checked" {
    const buf = try std.testing.allocator.alloc(u8, 8);
    defer std.testing.allocator.free(buf);
}
```

Helpers: `expect(bool)`, `expectEqual`, `expectError`, `expectEqualStrings`, `expectEqualSlices`. Run `zig test file.zig` or `zig build test`.

## C interop

Prefer build-system `b.addTranslateC(...)` (0.16) over inline `@cImport`. One-off: `zig translate-c header.h`. ABI: `extern fn` (import), `export fn` (expose), `extern struct`. Zig is also a C/C++ compiler: `zig cc`.

## Naming

functions `camelCase`; types/structs/enums `TitleCase`; vars/fields `snake_case`; constants `snake_case` (or `TitleCase` if the value is a type); files `snake_case.zig` (or `TitleCase.zig` if the file *is* a type). `zig fmt` owns layout.

## Commands

| Command | Use |
|---|---|
| `zig init` | scaffold build.zig, build.zig.zon, src/ |
| `zig build` | build (default install step) |
| `zig build run -- args` | build + run |
| `zig build test` | run test step |
| `zig run f.zig` / `zig test f.zig` | single-file run/test |
| `zig fmt .` / `zig fmt --check .` | format / CI check |
| `zig fetch --save <url>` | add dependency to build.zig.zon |
| `zig build --fetch` | fetch all deps (offline prep) |
| `zig std` | local std-lib docs for THIS install |

Build options: `-Dtarget=<triple>`, `-Doptimize=<Debug\|ReleaseSafe\|ReleaseFast\|ReleaseSmall>` (surfaced by `standardTargetOptions`/`standardOptimizeOption`). Raw compiles: `-target`, `-O`.
