# Zig migration: OLD (broken on recent) → CURRENT

Verified against 0.16.0 release notes (2026-04) + 0.15.1 notes. On master/0.17-dev the `Io` API is still settling — confirm exact spellings with `zig std`. Every snippet below is the *current* form; the OLD form is what stale training emits.

## I/O — two consecutive overhauls (the #1 source of broken AI Zig)

"Writergate" (0.15) replaced generic `std.io.Writer/Reader` with non-generic `std.Io.Writer/Reader` where **the buffer lives in the interface** and **you must `flush()`**. "I/O as an Interface" / "Juicy Main" (0.16) then made all I/O take an injected `Io` (like the allocator pattern); `std.fs.File/Dir` → `std.Io.File/Dir`.

```zig
// OLD (≤0.14 — BROKEN on 0.15+)
const stdout = std.io.getStdOut().writer();
try stdout.print("Hello {s}\n", .{"world"});
```

```zig
// 0.15 — buffer-in-interface, MUST flush
var buf: [4096]u8 = undefined;
var fw = std.fs.File.stdout().writer(&buf);
const stdout = &fw.interface;          // *std.Io.Writer
try stdout.print("Hello {s}\n", .{"world"});
try stdout.flush();                    // REQUIRED — buffered
```

```zig
// 0.16 — "Juicy Main", Io injected into main
pub fn main(init: std.process.Init) !void {
    const io = init.io;
    var buf: [1024]u8 = undefined;
    var fw: std.Io.File.Writer = .init(.stdout(), io, &buf);
    const stdout = &fw.interface;
    try stdout.print("Hello {s}\n", .{"world"});
    try stdout.flush();
}
```

```zig
// 0.16 simplest one-shot — no buffer management
pub fn main(init: std.process.Init) !void {
    try std.Io.File.stdout().writeStreamingAll(init.io, "Hello, World!\n");
}
```

`std.process.Init` carries `init.gpa`, `init.arena`, `init.io`, `init.environ_map`, CLI args. `std.debug.print` still works with no `Io` for quick debugging (writes to stderr). `Io` impls: `std.Io.Threaded` (default, complete), `std.Io.Evented` (experimental). `std.heap.ThreadSafeAllocator` was **removed**. On 0.16, file/dir ops take `io`: e.g. `file.close(io)`.

## ArrayList — default is now UNMANAGED (0.15)

Default `std.ArrayList(T)` holds no allocator; pass it to every mutating call. Old managed type → `std.ArrayList(T).Managed`.

```zig
// OLD — BROKEN as default on 0.15+
var list = std.ArrayList(i32).init(allocator);
defer list.deinit();
try list.append(42);
```

```zig
// CURRENT — unmanaged default
var list: std.ArrayList(i32) = .empty;          // or .{}
defer list.deinit(allocator);
try list.append(allocator, 42);
try list.appendSlice(allocator, &.{ 1, 2, 3 });
const owned = try list.toOwnedSlice(allocator);
// var list = try std.ArrayList(i32).initCapacity(allocator, 16);
// want stored allocator? var list = std.ArrayList(i32).Managed.init(allocator);
```

Same managed→unmanaged flip is idiomatic for `HashMap`/`ArrayHashMap`.

## Formatting — `{f}` calls `format`; new method signature (0.15)

`{}` no longer auto-calls a type's `format`. Using `{}` on a type that has one is a **compile error** (`specify {f} to call format method, or {any} to skip it`).

```zig
// OLD format method — BROKEN
pub fn format(self: @This(), comptime fmt: []const u8,
              options: std.fmt.FormatOptions, writer: anytype) !void { ... }
```

```zig
// CURRENT — only a *std.Io.Writer; no fmt string, no options, no anytype
const Point = struct {
    x: i32, y: i32,
    pub fn format(self: Point, writer: *std.Io.Writer) std.Io.Writer.Error!void {
        try writer.print("({d}, {d})", .{ self.x, self.y });
    }
};
try stdout.print("{f}\n", .{point});   // {f} invokes .format
```

Specifiers: `{d}` int/float, `{s}` string, `{c}` char, `{x}`/`{X}` hex, `{b}` binary, `{o}` octal, `{any}` catch-all (skips a `format` method), `{f}` calls `format`, `{t}` `@tagName`/`@errorName`, `{?}` optional, `{!}` error union, width/fill `{d:0>5}`. Renames: `fmt.format`→`std.Io.Writer.print`, `fmt.Formatter`→`Alt`, `fmt.FormatOptions`→`Options`, `fmt.bufPrintZ`→`bufPrintSentinel`. Ad-hoc custom format without a method: `std.fmt.Alt`.

## usingnamespace — REMOVED (0.15)

```zig
// conditional decl
pub const foo = if (have_foo) 123 else @compileError("unsupported");
// switch on impl
pub const init = switch (target) { .windows => initWindows, else => initOther };
// mixin via zero-bit field (call foo.counter.increment())
pub const Foo = struct { count: u32 = 0, counter: CounterMixin(Foo) = .{} };
```

## async/await — keywords REMOVED (0.15); concurrency via Io (0.16)

```zig
var future = io.async(work, .{args});   // Io.Future(T)
const result = future.await(io);
// also io.concurrent(...), Io.Group, Io.Batch, future.cancel(io)
```

## build.zig — root_module is required

```zig
// OLD — BROKEN
const exe = b.addExecutable(.{
    .name = "app", .root_source_file = b.path("src/main.zig"),
    .target = target, .optimize = optimize,
});
```

```zig
// CURRENT
const exe = b.addExecutable(.{
    .name = "app",
    .root_module = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target, .optimize = optimize,
    }),
});
```

See `build.md` for the full file. Add a dep's module: `exe.root_module.addImport("pkg", dep.module("pkg"))`.

## build.zig.zon — name is an enum literal, fingerprint mandatory (0.14/0.16)

```zig
.{
    .name = .myproject,                 // ENUM LITERAL, not "string"; ≤32 bytes, no "zig" prefix
    .version = "0.1.0",
    .fingerprint = 0x1234567890abcdef,  // generate ONCE, never edit
    .minimum_zig_version = "0.16.0",
    .dependencies = .{},
    .paths = .{ "build.zig", "build.zig.zon", "src", "" },
}
```

Fetched deps now live in a visible `zig-pkg/` at project root. Add with `zig fetch --save <url>`; offline prep `zig build --fetch`.

## Other language churn

- **`@Type` removed (0.16)** → `@Int(.unsigned, 10)`, `@Tuple`, `@Pointer`, `@Fn`, `@Struct`, `@Union`, `@Enum`.
- **Labeled switch + `continue :label`** (0.14) — jump to another prong; idiomatic for state machines/tokenizers.
- **Decl literals** (0.14) — `.empty`, `.init`, etc. resolve to any decl on the result type.
- **`@cImport` moving to build system (0.16)** — prefer `b.addTranslateC(...)` + `.createModule()` over inline `@cImport`.
- **Forbidden (0.16):** `return &local;` errors; runtime-indexing vectors; pointers inside packed structs/unions (use `usize` + `@ptrFromInt`).
- **`std.crypto.random` → `io.random(&buf)`** (0.16).

## Top 10 gotchas

1. `std.io.getStdOut().writer()` — gone. Buffered `std.Io.Writer` + `flush()`; thread `init.io` on 0.16.
2. Forgetting `flush()` — output silently vanishes (writers are buffered).
3. `ArrayList(T).init(alloc)` + `append(x)` — unmanaged now; pass `alloc` each call, `.empty` to init.
4. `{}` on a type with `format` — compile error; use `{f}`; new `format` sig has no comptime fmt/options/anytype.
5. `usingnamespace` — removed.
6. `async`/`await` keywords — removed; use `io.async` + `future.await(io)`.
7. `addExecutable`/`addTest` with bare `root_source_file`/`target`/`optimize` — wrap in `.root_module`.
8. `build.zig.zon` `.name = "string"` / missing `.fingerprint` — name is an enum literal; fingerprint mandatory.
9. `@Type(...)` — removed; use `@Int`/`@Struct`/`@Pointer`/…
10. `std.fs.File`/`std.fs.Dir` without `io` — migrated to `std.Io.File`/`std.Io.Dir`; ops take `io` on 0.16.
