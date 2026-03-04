# Machine

> *Toprak altında bir tohum var.*
> *Tohum bilmiyor toprağın üstünde ne olduğunu.*
> *Sadece biliyor: yukarı doğru bir şey var ve*
> *aşağı doğru bir şey var.*

A self-built intelligence stack. From metal to mind.

## What is Machine?

A system that understands software languages — starting with itself, then C, then everything else. Not a text processor. A code-aware computing substrate.

```
Hardware (x86/ARM)
  └── M language (bone language, self-hosting, compiles to native)
       └── Machine VM (temporal computation, uncertainty — written in M)
            └── Machine AI (reasoning over code and systems)
```

### M — The Bone Language

A minimal systems language. No hidden allocations, no implicit conversions, no runtime magic. What you write is what runs. M exists so that Machine can exist without depending on anything we didn't build.

**Self-hosting proven:** M compiles itself, transpiles to C, produces native executables. The generated native compiler reproduces itself byte-identically (fixed point).

### Machine VM — The Core (planned)

A virtual machine where every value has a history, uncertainty is native, and programs can inspect their own state. Will be written in M — not ported from C++, designed from scratch.

### Machine AI — The Mind (future)

A reasoning engine built on Machine VM primitives: temporal memory, uncertainty, persistence, self-reflection.

## Current Status

| Component | Status | Detail |
|-----------|--------|--------|
| M lexer | **347/347** tests | Full tokenizer with all operators, keywords, literals |
| M parser | **complete** | 6505 tokens, 113 declarations, 3891 AST nodes (self-parse) |
| M bytecode compiler | **63/63** tests | Compiles M to bytecode, runs on VM |
| M interpreter | **27/27** tests | M interprets M (self_interp.m) |
| M → C transpiler | **working** | AST walk → C source → gcc → native (~48x speedup) |
| Self-hosting | **proven** | Byte-identical fixed point across 4 levels |
| C lexer (in M) | **13/13** tests | M tokenizes C code (32 keywords, 46 operators) |
| C parser (in M) | **28/28** tests | Structural + expression/statement parsing |
| C → M translator | **working** | All 6 bootstrap files translate (3249 lines M, 124 functions) |
| Escape processing | **working** | `\n` → char 10 in bytecode compiler |
| Machine VM (M) | planned | Next milestone |

## Self-Hosting Proof

```
Level 0: C bootstrap        → mc.exe
Level 1: mc.exe (VM)        → transpiles self_codegen.m → self_codegen.c
Level 2: gcc self_codegen.c → mc_native.exe (63/63 tests pass)
Level 3: mc_native.exe      → transpiles self_codegen.m → gen2.c
Level 4: gen1.c == gen2.c   → BYTE-IDENTICAL FIXED POINT
```

## Phase 2: M Reads C

M can now read, parse, and translate its own C bootstrap code to M syntax:

```
bytecode.c (153 lines) → 162 lines M    lexer.c  (383 lines) → 577 lines M
parser.c  (1025 lines) → 950 lines M    codegen.c (726 lines) → 616 lines M
vm.c       (785 lines) → 687 lines M    mc.c      (232 lines) → 198 lines M
```

Pointer operations and `sizeof` remain as comments (no M equivalent). All logic, control flow, and function signatures are fully translated. Ternary operators expand to if/else. Character escape sequences resolve to integer values.

## Building

```bash
# Build from C bootstrap
gcc -O2 -o mc.exe m/bootstrap/mc.c m/bootstrap/lexer.c m/bootstrap/parser.c \
    m/bootstrap/codegen.c m/bootstrap/vm.c m/bootstrap/bytecode.c \
    core/tohum_memory.c -Im/bootstrap -Iinclude

# Or build from generated single-file bootstrap
gcc -O2 -o mc.exe m/generated/self_codegen.c

# Run M compiler test suite (63 tests)
./mc.exe examples/self_codegen.m

# Run C lexer tests (13 tests)
./mc.exe examples/self_codegen.m examples/c_lexer.m

# Run C parser + translator tests (28 tests)
./mc.exe examples/self_codegen.m examples/c_parser.m

# Compile and run an M program
./mc.exe examples/self_codegen.m examples/bench_fib.m

# Transpile M to C
./mc.exe examples/self_codegen.m --emit-c examples/bench_fib.m output.c

# Translate C to M
./mc.exe examples/self_codegen.m examples/c_parser.m --translate path/to/file.c
```

## Example

```m
fn fib(n: i32) -> i32 {
    if n <= 1 { return n; }
    return fib(n - 1) + fib(n - 2);
}

fn main() -> i32 {
    let result: i32 = fib(35);
    print(int_to_str(result));
    println("");
    return 0;
}
```

VM: ~1.7s. Native (via M→C transpiler + gcc): ~0.035s. **~48x speedup.**

## Project Structure

```
m/bootstrap/     C bootstrap compiler (lexer, parser, codegen, vm, bytecode)
m/generated/     Generated artifacts (self_codegen.c, bootstrap_translated.m)
m/spec/          M language specification
examples/        M programs
  self_codegen.m   M compiler + transpiler (218 functions, 63/63 tests)
  c_lexer.m        C tokenizer written in M (13/13 tests)
  c_parser.m       C parser + translator written in M (28/28 tests)
  self_interp.m    M interpreter written in M (27/27 tests)
  self_parse.m     M parser written in M
  bench_fib.m      Fibonacci benchmark
core/            Memory management (tohum_memory.c)
include/         Headers
```

## Roadmap

- [x] M language bootstrap (lexer, parser, codegen, VM)
- [x] Self-hosting (M compiles M, byte-identical fixed point)
- [x] M → C transpiler (native executables)
- [x] C lexer in M (Phase 2)
- [x] C parser in M (structural + expression/statement)
- [x] C → M translator (bootstrap self-translation)
- [x] Escape sequence processing
- [ ] Temporal VM in M
- [ ] Linux transition

## License

MIT
