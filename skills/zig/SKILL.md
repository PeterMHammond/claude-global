---
name: zig
description: Write correct, current-version Zig code. Use whenever authoring, reviewing, debugging, or building Zig (.zig files, build.zig, build.zig.zon), compiling Zig to WebAssembly for Cloudflare Workers, or doing C interop. Zig is pre-1.0 and breaks aggressively between releases — training data is stale and silently wrong on I/O, ArrayList, formatting, build.zig, and async. Triggers on "write Zig", "zig build", "compile to wasm", "build.zig", "zig fmt won't compile", "@cImport", or any Zig task.
---

# Zig

Zig is pre-1.0. **It breaks aggressively every release and your training data is stale.** Code that "looks right" from memory frequently does not compile on current Zig. Do not trust recall for I/O, `ArrayList`, formatting, `build.zig`, `build.zig.zon`, or async — verify.

## Step 1 — Detect the version, always

```bash
zig version
```

Stable lineage: `0.13 → 0.14 → 0.15.x → 0.16.0` (2026-04). Master is `0.17.0-dev`. **This project tracks master/nightly** — the `std.Io` interface is still settling and 0.17 is imminent, so for any I/O, allocator, or `Io`-threaded code, confirm the exact spelling against the live install before committing it:

```bash
zig std                 # opens local std-lib docs for THIS install — source of truth
zig build-exe scratch.zig -fno-emit-bin   # type-check a snippet without running
```

When recall and the installed version disagree, the install wins. Never paste a remembered API into production without `zig build` passing.

## Step 2 — The churn map (what stale training gets wrong)

These are the high-frequency traps. Full OLD→NEW migrations in `references/migration.md` — read it before writing non-trivial code.

| Area | Stale (broken) | Current |
|---|---|---|
| stdout | `std.io.getStdOut().writer()` | buffered `std.Io.Writer` via a File writer + **`flush()`**; on 0.16 thread `init.io` (see migration.md) |
| ArrayList | `.init(alloc)`, `list.append(x)` | unmanaged default: `.empty`, `list.append(alloc, x)`, `list.deinit(alloc)` |
| format `{}` | `{}` auto-calls `format` | `{}` on a type with `format` is a **compile error** — use `{f}`; new sig `fn format(self, writer: *std.Io.Writer) std.Io.Writer.Error!void` |
| usingnamespace | `usingnamespace` | **removed** — conditional decls / switch-on-impl / zero-bit mixin field |
| async | `async`/`await` keywords | **removed** — `io.async(fn, .{...})` + `future.await(io)` |
| build.zig | `addExecutable(.{ .root_source_file=…, .target=…, .optimize=… })` | wrap in `.root_module = b.createModule(.{…})` |
| build.zig.zon | `.name = "str"`, no fingerprint | `.name = .enum_literal`, `.fingerprint` mandatory |
| @Type | `@Type(.{…})` | **removed** (0.16) — `@Int`/`@Struct`/`@Pointer`/… |

## Step 3 — Write idiomatically

Follow current idioms in `references/idioms.md`: error unions + `try`/`catch`/`errdefer`, explicit allocators (`std.heap.DebugAllocator` debug, arena, `std.testing.allocator` in tests), `defer`/`errdefer` after acquisition, optionals via `orelse`/`if (x) |v|`, exhaustive `switch`, generics via `comptime T: type` / `anytype`, tests as `test "name" {}`.

Naming: functions `camelCase`, types `TitleCase`, fields/vars `snake_case`, files `snake_case.zig` (or `TitleCase.zig` if the file *is* a type). `zig fmt` enforces layout — do not hand-fight it.

## Step 4 — WASM / Cloudflare

Primary target for this project. Target `wasm32-freestanding`, `export` boundary functions, `-O ReleaseSmall`, pass data via linear-memory offsets. Full recipe and `build.zig` in `references/wasm.md`.

## Step 5 — Verify before claiming done

Never report Zig as working on memory alone. Run, in order:

```bash
zig fmt .
zig build            # or: zig build-exe / zig test <file>
zig build test
```

Report the actual command output. If it didn't compile, say so.

## References
- `references/migration.md` — every OLD→NEW breaking change with code, + top gotchas
- `references/idioms.md` — current idiomatic patterns, commands, testing
- `references/wasm.md` — WebAssembly + Cloudflare Workers build recipe
- `references/build.md` — `build.zig` and `build.zig.zon` templates
