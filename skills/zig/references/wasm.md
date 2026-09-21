# Zig → WebAssembly / Cloudflare Workers

Primary target for this project. Two WASM targets:

- **`wasm32-freestanding`** — no OS. This is the Cloudflare Workers / browser / embedding case. Use this.
- **`wasm32-wasi`** — for WASI runtimes (Wasmtime/Wasmer); gives a POSIX-ish layer. Not Workers.

## Export boundary functions

```zig
// src/main.zig — a reactor module (no main), exporting an ABI
export fn add(a: i32, b: i32) i32 {
    return a + b;
}
```

Use only WASM-ABI-friendly types at the boundary (integers, floats, pointers as `usize` offsets into linear memory). Pass buffers as `(ptr, len)` pairs; the host reads/writes the module's linear memory at those offsets.

## CLI build

```bash
# library / object → .wasm (freestanding, smallest)
zig build-lib src/main.zig -target wasm32-freestanding -O ReleaseSmall -dynamic -rdynamic

# WASI executable (non-Workers)
zig build-exe src/main.zig -target wasm32-wasi -O ReleaseSmall
```

`-O ReleaseSmall` matters for Workers — minimize binary size.

## build.zig for a freestanding reactor module

```zig
const target = b.resolveTargetQuery(.{
    .cpu_arch = .wasm32,
    .os_tag = .freestanding,
});

const wasm = b.addExecutable(.{
    .name = "worker",
    .root_module = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = .ReleaseSmall,
    }),
});
wasm.rdynamic = true;       // keep exported symbols
wasm.entry = .disabled;     // reactor module: no _start / main
b.installArtifact(wasm);
```

Or select the target at the CLI: `-Dtarget=wasm32-freestanding -Doptimize=ReleaseSmall`.

## Cloudflare Workers integration

The `.wasm` is the module; load it from a JS/TS Worker via a WASM import and call the exports, or wire it into your existing Worker pipeline. Keep state-crossing minimal — exchange data through linear-memory offsets, not complex types. Pair size discipline (`ReleaseSmall`) with the project's cost-minimization mandate.

After building, verify the artifact exists and exports are present before claiming done (e.g. inspect with `wasm-objdump -x worker.wasm` if available, or load it in the Worker and exercise an export).
