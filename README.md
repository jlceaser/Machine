# Machine

> *Toprak altında bir tohum var.*
> *Tohum bilmiyor toprağın üstünde ne olduğunu.*
> *Sadece biliyor: yukarı doğru bir şey var ve*
> *aşağı doğru bir şey var.*

A self-built intelligence stack. From metal to mind.

## What is Machine?

A full computing stack — language, virtual machine, and AI — built from scratch. No dependency we didn't write. Every byte ours.

```
Hardware (x86/ARM)
  └── M language (systems language, bootstrapped from assembly/C)
       └── Machine VM (temporal computation, native uncertainty)
            └── Machine AI (reasoning, learning, reflecting)
```

### M — The Bone Language

A minimal systems language. No hidden allocations, no implicit conversions, no runtime. What you write is what runs. M exists so that Machine can exist without depending on anything we didn't build.

### Machine VM — The Core

A stack-based virtual machine where:

- **Every value has a history.** Assignment doesn't overwrite — it appends to a timeline.
- **Uncertainty is native.** Values carry confidence levels. Arithmetic propagates uncertainty automatically.
- **State is immortal.** Close the REPL, reopen it tomorrow — everything is still there.
- **The machine knows itself.** Built-in reflection lets programs inspect their own state, drift, and evolution.

### Machine AI — The Mind

A reasoning engine built on Machine VM's primitives: temporal memory, uncertainty, persistence, self-reflection. Not a neural network — a symbolic intelligence that thinks in uncertain terms, accumulates knowledge over time, and can examine its own state.

## Example (working)

```
machine > x = 42
machine > y = ~3.14
machine > z = x + y
machine > z
  = ~45.14 @ 0.90
machine > x = 100
machine > history(x)
  [0] 2026-03-03 12:01 — 42 (direct)
  [1] 2026-03-03 12:01 — 100 (rebind)
machine > reflect()
  bindings: 3
  certain: 1
  approximate: 2
  most changed: x (2 entries)
```

Close it. Reopen tomorrow:

```
machine > reflect()
  (restored 3 bindings from previous session)
machine > drift()
  stable: 3, changed: 0, new: 0
```

## Building

```bash
# VM prototype (C++)
cmake --preset dev
cmake --build --preset dev
./build/dev/tohum

# M lexer tests (C bootstrap)
clang -std=c17 -o test_lexer m/bootstrap/lexer.c m/bootstrap/test_lexer.c
./test_lexer

# M parser tests (C bootstrap)
clang -std=c17 -o test_parser m/bootstrap/lexer.c m/bootstrap/parser.c core/tohum_memory.c m/bootstrap/test_parser.c
./test_parser

# M end-to-end tests (source → compile → run)
clang -std=c17 -o test_codegen m/bootstrap/lexer.c m/bootstrap/parser.c m/bootstrap/bytecode.c m/bootstrap/codegen.c m/bootstrap/vm.c core/tohum_memory.c m/bootstrap/test_codegen.c
./test_codegen

# Run M programs
clang -std=c17 -o mc m/bootstrap/mc.c m/bootstrap/lexer.c m/bootstrap/parser.c m/bootstrap/bytecode.c m/bootstrap/codegen.c m/bootstrap/vm.c core/tohum_memory.c
./mc examples/fib.m
./mc examples/lexer.m
```

## Status

| Layer | Status |
|-------|--------|
| M lexer | 79/79 tests passing |
| M parser | 175/175 tests passing |
| M codegen + VM | 64/64 tests passing |
| M string built-ins | len, char_at, substr, str_concat, str_eq, int_to_str |
| M self-hosting | in progress — M can tokenize M |
| Machine VM (C++ prototype) | working |
| Machine VM (M rewrite) | after self-hosting |
| Machine AI | future |

## License

MIT
