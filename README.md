# Machine

> *Toprak altinda bir tohum var.*
> *Tohum bilmiyor topragin ustunde ne oldugunu.*
> *Sadece biliyor: yukari dogru bir sey var ve*
> *asagi dogru bir sey var.*

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

### Machine VM — Temporal Computation

A virtual machine where every value has a history, uncertainty is native, and programs can inspect their own state. Written in M — not ported from C++, designed from scratch.

- **Temporal values:** every binding creates a timeline, re-binding appends (never overwrites)
- **Uncertainty:** `bind x ~ 95` creates an approximate value with 70% confidence
- **Confidence propagation:** arithmetic on uncertain values produces uncertain results
- **Snapshot/rollback:** save and restore VM state in memory
- **Persistence:** serialize/deserialize to disk across sessions

### Machine REPL — Interactive Shell

An interactive terminal for temporal computing. Evaluate expressions, bind values, analyze code.

```
$ mc.exe self_codegen.m machine_repl.m

  Machine -Temporal Computing Shell
  Tohum v0.1 | Type 'help' for commands

machine> bind x = 42
  x = 42
machine> bind x = 100
  x -> 100
machine> history x
  x timeline (2 entries):
    [0] 42  (repl)
    [1] 100  (repl)  <- current
machine> x * 2 + 1
  = 201
machine> analyze examples/machine_vm.m
  Analyzed: examples/machine_vm.m
  Functions: 95, Globals: 26, Lines: 1168
  Largest function: vm_exec (411 lines)
machine> calls env_bind
  env_bind calls: env_find, tl_append, sp_store, tl_new, array_push
machine> callers env_find
  Who calls env_find:
    <- env_bind, env_load, env_forget, env_get_timeline, env_is_forgotten, vm_exec
```

### Machine AI — The Mind (in progress)

Machine doesn't just read code — it reasons about it. Built on VM primitives: temporal memory, uncertainty, self-reflection.

**Working today:** analyze → health → suggest → explain → audit → **think**. Machine classifies functions, scores risk, detects patterns, generates suggestions — and now runs autonomous cognition cycles.

**Inner loop (new):** Machine predicts code properties before analyzing, measures prediction error, and decides what to explore next — without human commands. The `think` command runs N autonomous cycles: predict → perceive → measure → decide → act.

**Coming:** deeper self-model, intent understanding, cross-language knowledge transfer.

## Current Status

| Component | Status | Tests |
|-----------|--------|-------|
| M lexer | complete | 347/347 |
| M parser | complete | 6505 tokens, 113 decl, 3891 AST nodes |
| M bytecode compiler | complete | 63/63 |
| M interpreter | complete | 27/27 |
| M → C transpiler | working | ~48x speedup (VM → native) |
| Self-hosting | proven | Byte-identical fixed point, 4 levels |
| C lexer (in M) | complete | 13/13 |
| C parser (in M) | complete | 28/28 |
| C → M translator | working | 6 files, 3249 lines M, 124 functions |
| Machine VM | **working** | 89/89 |
| Machine assembler | **working** | 27/27 |
| Machine REPL | **working** | Interactive shell + expression eval |
| Code analyzer | **working** | 147/147 |
| Machine Mind | **working** | 61/61 |

**Total: 387 tests passing across 5 test suites.**

## Phase 3: Machine Reads Code

Machine can now analyze M source files and represent program structure as temporal knowledge:

```
machine> analyze examples/self_codegen.m
  Functions: 218, Globals: 62, Lines: 3206
  Largest: main (492 lines)

machine> top 3
  1. main          492L  85 calls
  2. vm_run_func   285L  85 calls
  3. gen_expr       55L  14 calls

machine> search env
  env_bind, env_load, env_find, env_forget, env_init ... (12 matches)

machine> stats
  Size distribution:
    small (1-5):    148
    medium (6-20):  50
    large (21-50):  6
    huge (50+):     14
```

Analysis results are temporal — re-analyzing a different file shows drift:

```
machine> analyze examples/machine_vm.m
machine> load _funcs
  _funcs = 95
machine> analyze examples/self_codegen.m
machine> load _funcs
  _funcs = 218
machine> history _funcs
  [0] 95   (analyze)
  [1] 218  (analyze)  <- current
```

Cross-file dependency resolution:
- `ana_resolve_deps()` follows `use` directives recursively
- `ana_who_defines("vm_exec")` → `"examples/machine_vm.m"`
- `ana_external_calls()` identifies cross-file function calls

Diff/change detection:
```
machine> analyze examples/machine_vm.m
machine> analyze examples/machine_asm.m
machine> diff
  Diff: machine_vm.m -> machine_asm.m
  Lines: 1168 -> 829 (-339)
  Functions: 95 -> 38 (-57)
  + New (38): asm_trim, asm_line, asm_run ...
  - Removed (95): OP_NOP, vm_exec, env_bind ...
```

C file analysis — Machine reads C source files too:
```
machine> analyze m/bootstrap/vm.c
  Analyzed: m/bootstrap/vm.c
  Lines: 840, Functions: 21, Dependencies: 5
machine> compare m/bootstrap/vm.c examples/machine_vm.m
  C: vm.c (840 lines, 21 funcs)  ->  M: machine_vm.m (1168 lines, 95 funcs)
  Shared: vm_init (C:6L -> M:32L), vm_run (C:23L -> M:1L)
  C-only: 19 functions  |  M-only: 93 new functions
```

Complexity scoring with uncertainty:
```
machine> complexity 3
  1. vm_exec   ~95 (conf:75%)     411L  72 calls
  2. vm_deserialize  ~90 (conf:75%)  132L  21 calls
  3. vm_serialize  ~49 (conf:90%)   42L  14 calls
```

Code intelligence — Machine reasons about code:
```
machine> health
  Health: 85/100 (Grade A)  conf:80%
  Size distribution:
    small (1-5):    53 (55%)
    medium (6-20):  27 (28%)
    large (21-50):  9 (9%)
    huge (50+):     6 (6%)
  Findings:
    6 huge functions (largest: vm_exec 411L)
    12 unused functions (12%)

machine> hotspots 3
  1. sp_get         8 callers
  2. val_nil        7 callers
  3. env_find       6 callers

machine> unused
  12 functions with no callers:
    vm_snapshot, vm_rollback, vm_serialize ...

machine> summary
  Scale: medium system (95 functions, 1168 lines, 26 globals)
  Architecture: 46 constants, 35 utilities, 5 core, 9 interfaces
  Spine: vm_exec (411L, risk:65), vm_deserialize (132L, risk:60)
  Health: ~85/100 — well-structured

machine> focus vm_exec
  Role: core  Lines: 411  Calls: 72  Callers: 1
  Risk: ~65/100  ! MEDIUM — test after changes
  Called by: vm_run
  Suggestion: SPLIT — 411 lines is too large
  Suggestion: EXTRACT — 72 callees, high fan-out

machine> suggest
  [HIGH] SPLIT vm_exec — 411 lines
  [HIGH] EXTRACT vm_exec — 72 functions, high fan-out
  [LOW] REMOVE vm_snapshot — no callers found
  Total: 16 suggestions (2 high, 2 medium, 12 low)

machine> explain vm_exec
  vm_exec is a core function — central to this file's purpose.
  It is massive (411 lines).
  It depends on 72 other functions: array_get, OP_NOP, OP_HALT and 69 more.
  Pattern: dispatcher — large function routing to many smaller ones.

machine> audit
  1. HEALTH: ~85/100 (conf:80%) [PASS]
  2. SIZE BALANCE: 2 large functions (543 lines, 46%) [WARN]
  3. DEAD CODE: 12 functions (12%) [WARN]
  4. COUPLING: no mutual dependencies [PASS]
  5. HOTSPOTS: no critical hotspots [PASS]
  6. ARCHITECTURE: well-layered [PASS]
  VERDICT: GOOD — minor issues, low risk
```

### Phase 4: Machine Thinks

Machine can now run autonomous cognition cycles — predicting, perceiving, measuring, and deciding without human commands:

```
machine> seed examples/machine_vm.m
machine> seed examples/machine_asm.m
machine> seed examples/machine_analyze.m
machine> think 5

  Machine Mind — 5 cycles
  ─────────────────────
  [1] explore examples/machine_vm.m  error:18%
  [2] explore examples/machine_asm.m  error:73%
  [3] explore examples/machine_analyze.m  error:1%
  [4] repredict examples/machine_asm.m  error:52%
  [5] consolidate

  Competence: ~59% | Files: 3/3 | Predictions: 4

machine> history mind.competence
  mind.competence timeline (6 entries):
    [0] ~50 (conf:30%)  (mind_init)
    [1] ~82 (conf:65%)  (measure)
    [2] ~55 (conf:70%)  (measure)
    [3] ~70 (conf:75%)  (measure)
    [4] ~59 (conf:80%)  (measure)
    [5] ~59 (conf:85%)  (measure)  <- current
```

The inner loop: predict code properties → analyze → measure prediction error → learn → decide next action. Auto-discovers dependencies through `use` directives. Predictions improve as the model accumulates experience.

## Self-Hosting Proof

```
Level 0: C bootstrap        → mc.exe
Level 1: mc.exe (VM)        → transpiles self_codegen.m → self_codegen.c
Level 2: gcc self_codegen.c → mc_native.exe (63/63 tests pass)
Level 3: mc_native.exe      → transpiles self_codegen.m → gen2.c
Level 4: gen1.c == gen2.c   → BYTE-IDENTICAL FIXED POINT
```

## Phase 2: M Reads C

M can read, parse, and translate its own C bootstrap code to M syntax:

```
bytecode.c (153 lines) → 162 lines M    lexer.c  (383 lines) → 577 lines M
parser.c  (1025 lines) → 950 lines M    codegen.c (726 lines) → 616 lines M
vm.c       (785 lines) → 687 lines M    mc.c      (232 lines) → 198 lines M
```

## Building

```bash
# Build from C bootstrap
gcc -O2 -o mc.exe m/bootstrap/mc.c m/bootstrap/lexer.c m/bootstrap/parser.c \
    m/bootstrap/codegen.c m/bootstrap/vm.c m/bootstrap/bytecode.c \
    core/tohum_memory.c -Im/bootstrap -Iinclude

# Or build from generated single-file bootstrap
gcc -O2 -o mc.exe m/generated/self_codegen.c

# Run all tests
./mc.exe examples/self_codegen.m           # M compiler (63 tests)
./mc.exe examples/machine_vm_test.m        # Machine VM (89 tests)
./mc.exe examples/machine_asm.m            # Assembler (27 tests)
./mc.exe examples/machine_analyze_test.m   # Analyzer (112 tests)

# Launch interactive REPL
./mc.exe examples/self_codegen.m examples/machine_repl.m

# Compile and run an M program
./mc.exe examples/self_codegen.m examples/bench_fib.m

# Transpile M to C (native compile)
./mc.exe examples/self_codegen.m --emit-c examples/bench_fib.m output.c
gcc -O2 -o bench output.c
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
m/bootstrap/          C bootstrap compiler (lexer, parser, codegen, vm, bytecode)
m/generated/          Generated artifacts (self_codegen.c, bootstrap_translated.m)
m/spec/               M language specification
examples/
  self_codegen.m        M compiler + transpiler (218 functions, 63/63 tests)
  machine_vm.m          Temporal computation VM (95 functions, 1167 lines)
  machine_vm_test.m     VM test suite (89/89 tests)
  machine_asm.m         Text assembler for VM (27/27 tests)
  machine_repl.m        Interactive temporal computing shell
  machine_mind.m        Autonomous cognition — inner loop (Phase 4)
  machine_mind_test.m   Mind tests (61/61)
  machine_analyze.m     M + C source code analyzer (Phase C)
  machine_analyze_test.m  Analyzer tests (147/147)
  c_lexer.m             C tokenizer written in M (13/13 tests)
  c_parser.m            C parser + translator written in M (28/28 tests)
  self_interp.m         M interpreter written in M (27/27 tests)
  self_parse.m          M parser written in M
core/                 Memory management (tohum_memory.c)
include/              Headers
```

## Roadmap

- [x] M language bootstrap (lexer, parser, codegen, VM)
- [x] Self-hosting (M compiles M, byte-identical fixed point)
- [x] M → C transpiler (native executables)
- [x] C lexer in M (Phase 2)
- [x] C parser in M (structural + expression/statement)
- [x] C → M translator (bootstrap self-translation)
- [x] Machine VM — temporal computation engine (89/89 tests)
- [x] Machine assembler — text-to-bytecode (27/27 tests)
- [x] Machine REPL — interactive temporal computing shell
- [x] Code analyzer — M + C file analysis (147/147 tests)
- [x] Cross-file analysis in REPL (dependencies, where, project)
- [x] C file analysis via temporal VM (C structure extraction)
- [x] Diff/change detection (new/removed/changed functions)
- [x] Complexity scoring with uncertainty
- [x] C vs M structural comparison
- [x] Code intelligence (health scoring, dead code, hotspots)
- [x] Code reasoning (suggest, focus, summary, coupling, explain, audit, map)
- [x] Inner loop — autonomous cognition cycles (predict, perceive, measure, decide)
- [ ] Self-model deepening (the mind inspects its own prediction patterns)
- [ ] Cross-language learning (Python, Rust file analysis)
- [ ] Linux transition

## License

MIT
