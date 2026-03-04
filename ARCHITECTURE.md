# Machine Architecture

> Every meaningful layer of abstraction is ours.
> The only external tool is a C compiler — and that's deliberate.

## Layered Model

```
┌─────────────────────────────────────────┐
│  Layer 3: Machine AI                    │
│  Symbolic reasoning over code           │
│  Pattern recognition, system design     │
│  (future — built on VM primitives)      │
├─────────────────────────────────────────┤
│  Layer 2: Machine VM                    │
│  Temporal values, uncertainty, history  │
│  Persistence, reflection, drift         │
│  Written in M → compiled to native      │
├─────────────────────────────────────────┤
│  Layer 1: M Language                    │
│  Bone language. Minimal, explicit.      │
│  Self-hosting compiler + C transpiler   │
│  No hidden behavior. No magic.          │
├─────────────────────────────────────────┤
│  Layer 0: Hardware (x86/ARM)            │
│  via C compiler (gcc/clang)             │
└─────────────────────────────────────────┘
```

Each layer has one job. Complexity lives where it belongs.

## Why This Model

**M stays simple.** M's promise is "what you write is what runs." Adding temporal
types or uncertainty to the language would break that promise. M is the bone —
bones don't think, they hold things up.

**VM owns complexity.** Temporal values, confidence propagation, history tracking —
these are runtime concerns, not language concerns. Just like garbage collection
belongs in a runtime, not in a language specification.

**AI stays replaceable.** The reasoning layer is the most experimental. It must be
free to change without touching the lower layers. VM provides primitives (temporal
memory, reflection, persistence). AI layer decides how to use them.

**Each layer is independently testable.** M has 63/63 compiler tests. VM will have
its own test suite. AI layer tests against VM behavior, not M internals.

## Layer 1: M Language (Complete)

M is a minimal systems language. Self-hosting is proven.

### What M Has
- Types: `i32`, `bool`, `string`, `array`
- Functions with forward declarations
- Control flow: `if/else`, `while`
- String operations: `len`, `char_at`, `substr`, `str_concat`, `str_eq`
- File I/O: `read_file`, `write_file`, `argc`, `argv`
- Multi-file programs: `use "file.m"`
- M-to-C transpiler for native compilation (~48x speedup)

### What M Does NOT Have (By Design)
- No classes, no inheritance, no generics
- No closures, no garbage collector
- No exceptions, no operator overloading
- No temporal types, no uncertainty, no history

These omissions are the point. M is not incomplete — it's minimal.

### Self-Hosting Proof
```
Level 0: C bootstrap        → mc.exe
Level 1: mc.exe (VM)        → transpiles self_codegen.m → self_codegen.c
Level 2: gcc self_codegen.c → mc_native.exe (63/63 tests pass)
Level 3: mc_native.exe      → transpiles self_codegen.m → gen2.c
Level 4: gen1.c == gen2.c   → BYTE-IDENTICAL FIXED POINT
```

### Cross-Language Capability (Phase 2)
M reads C. The entire C bootstrap (6 files, 3500+ lines) has been parsed and
translated to M syntax (3249 lines, 124 functions). Pointer operations remain
as comments — they have no M equivalent and don't need one.

## Layer 2: Machine VM (Next Milestone)

The VM is where Machine becomes more than a compiler.

### Core Concept: Temporal Values

In Machine VM, every value has a past. Assignment doesn't overwrite — it appends.

```
bind x 42           -- x timeline: [42]
bind x 43           -- x timeline: [42, 43]
history x           -- shows both values with timestamps and sources
```

This is the fundamental departure from every conventional VM. Values are not
points — they are trajectories.

### Design Decisions

These questions were identified as critical before any code is written.

#### 1. Time Model: Discrete

Time in Machine VM is **discrete**, measured in ticks (instruction count) and
wall-clock timestamps.

**Rationale:** Continuous time requires floating-point accumulation and brings
complexity that isn't needed. Machine analyzes code, not physics simulations.
Discrete ticks give deterministic replay. Wall-clock timestamps give human context.

**Implementation:**
```
TimePoint = { tick: i32, wall_time: i32, source: string }
```

`tick` increments per instruction executed. `wall_time` is epoch seconds.
`source` tracks what caused this point — "direct", "rebind", "arithmetic", etc.

#### 2. Confidence Model: Heuristic with Deterministic Propagation

Confidence is **not Bayesian**. It's a simple `[0, 100]` integer scale.

**Rationale:** Bayesian inference requires probability distributions and prior
beliefs — heavy machinery for a foundation layer. Machine's uncertainty is
simpler: "how much do I trust this value?"

**Propagation rules:**
- Arithmetic: `confidence(a + b) = min(confidence(a), confidence(b))`
- Comparison: same min-propagation
- Assignment: new value inherits source's confidence
- User can set confidence explicitly: `bind_approx x 42 75`
- Threshold for truthiness: configurable, default 50

**Why integer, not float:** M has `i32`, not `f64`. Integer confidence (0-100)
maps directly to M types. No floating-point edge cases, no epsilon comparisons.

#### 3. Value Propagation: Deterministic

Propagation is **deterministic**, not probabilistic.

**Rationale:** Probabilistic graphs are powerful but opaque. Machine's philosophy
is "what you write is what runs." If `x = a + b` and both have confidence 80,
the result has confidence 80. Always. Deterministic propagation means the user
can predict outcomes without a statistics degree.

**Future extension:** If AI layer needs probabilistic reasoning, it builds that
on top of the deterministic VM primitives. The VM provides data (history,
confidence values), the AI layer interprets it however it wants.

#### 4. IR Execution: VM Interprets Its Own Bytecode Format

The Machine VM **defines and executes its own instruction set**.

**Rationale:** If the VM just ran M bytecode, it would be a glorified M runtime.
The VM needs instructions that M doesn't have — `HISTORY`, `DRIFT`, `REFLECT`,
`FORGET`, `PERSIST`. These are VM-level operations, not language-level.

**Implementation:** M compiles the VM program. The VM (itself compiled from M)
loads and executes bytecode containing temporal opcodes. M never sees these
opcodes — they exist only at the VM layer.

**Bytecode format (Machine VM):**
```
Opcode (1 byte) + operands (variable)

Stack operations:    PUSH_NIL, PUSH_I32, PUSH_BOOL, PUSH_STR, POP
Variable operations: BIND, BIND_APPROX, LOAD
Arithmetic:          ADD, SUB, MUL, DIV, NEG, MOD
Comparison:          EQ, NEQ, LT, GT, LTE, GTE
Logic:               AND, OR, NOT
Control:             JUMP, JUMP_IF_FALSE, CALL, RETURN, HALT, NOP
Temporal:            HISTORY, DRIFT, REFLECT, FORGET, SNAPSHOT
Persistence:         PERSIST, RESTORE
I/O:                 PRINT, PRINT_HISTORY
```

#### 5. State Rollback: Snapshot-Based, Not Full Undo

The VM supports **snapshots**, not continuous undo.

**Rationale:** Full undo (reversing every operation) requires storing inverse
operations or keeping complete state copies at every step. That's expensive and
rarely needed. Snapshots are cheaper and more useful — "save this state, maybe
come back to it."

**Implementation:**
```
SNAPSHOT         -- save current env state
RESTORE          -- restore to last snapshot
PERSIST          -- save to disk (survives process restart)
```

Snapshots are append-only. You can't modify a snapshot. RESTORE doesn't delete
the snapshot — you can restore multiple times. PERSIST writes the full timeline
(not just current values) to disk.

**Why not continuous undo:** Machine's temporal model already preserves history
via timelines. Every `BIND` appends, never overwrites. The full trajectory is
always available. Rollback to a specific tick can be implemented by AI layer
reading the timeline and extracting the value at tick N.

### Opcode Set (Machine VM)

| Category | Opcodes |
|----------|---------|
| Stack | `PUSH_NIL` `PUSH_I32` `PUSH_BOOL` `PUSH_STR` `PUSH_APPROX` `POP` `DUP` |
| Variables | `BIND` `BIND_APPROX` `LOAD` |
| Arithmetic | `ADD` `SUB` `MUL` `DIV` `NEG` `MOD` |
| Comparison | `EQ` `NEQ` `LT` `GT` `LTE` `GTE` |
| Logic | `AND` `OR` `NOT` |
| Control | `JUMP` `JUMP_IF_FALSE` `CALL` `RETURN` `HALT` `NOP` |
| Temporal | `HISTORY` `DRIFT` `REFLECT` `FORGET` `SNAPSHOT` |
| Persistence | `PERSIST` `RESTORE` |
| I/O | `PRINT` `PRINT_HISTORY` `READ_LINE` |

32 opcodes. Clean, flat, no microcode.

### Value Representation in M

The C++ prototype uses `std::variant<monostate, double, bool, string>`. In M:

```m
// Value type tags
fn VAL_NIL() -> i32 { return 0; }
fn VAL_I32() -> i32 { return 1; }
fn VAL_BOOL() -> i32 { return 2; }
fn VAL_STR() -> i32 { return 3; }

// Parallel arrays (M idiom — no structs)
var val_type: array;      // type tag for each value
var val_idata: array;     // integer data (i32 or bool-as-int)
var val_sdata: array;     // string index (into string pool)
var val_confidence: array; // 0-100 integer

// Timeline: each variable maps to an array of value indices
var timeline_vals: array;  // array of arrays (value indices per variable)
var timeline_ticks: array; // array of arrays (tick at each bind)
var timeline_sources: array; // array of arrays (source string index)
```

This is the M way. No structs, no objects — flat arrays with index-based access.
It's explicit, it's transparent, and M can compile it right now.

### Data Structures

#### Environment
Variables map to timelines. Lookup returns the latest entry:
```
env_names: array of string indices     -- variable names
env_timelines: array of array indices  -- each points to a timeline
```

#### Stack
Operand stack for bytecode execution:
```
stack_vals: array       -- value indices
stack_top: i32          -- current stack pointer
```

#### Snapshot Store
```
snapshot_envs: array    -- serialized environment states
snapshot_count: i32
```

### Persistence Format

Binary, big-endian, designed for M's `read_file`/`write_file`:

```
Header:
  [4 bytes] magic "MCHV"
  [4 bytes] version (1)
  [4 bytes] binding count

Per binding:
  [2 bytes] name length
  [N bytes] name
  [1 byte]  forgotten flag
  [4 bytes] timeline length
  Per timeline entry:
    [4 bytes] confidence (0-100)
    [4 bytes] tick
    [4 bytes] wall_time (epoch seconds)
    [2 bytes] source string length
    [N bytes] source string
    [1 byte]  value type tag
    [4 bytes] value data (i32, bool-as-int, or string-length + string)
```

All integers are 32-bit (M's native type). No floating point anywhere.

## Layer 3: Machine AI (Future)

The AI layer uses VM primitives to reason about code.

### What VM Provides to AI
- **Temporal memory:** Read full history of any binding
- **Confidence tracking:** Know how certain each value is
- **Drift detection:** Detect what changed since last checkpoint
- **Reflection:** Inspect VM's own state (binding count, stack depth, etc.)
- **Persistence:** Save and restore analysis state across sessions

### What AI Layer Will Do
- Parse and analyze programs (using M's existing cross-language parsers)
- Build program models (control flow, data flow) stored as temporal values
- Detect patterns across codebases
- Reason about system design
- Eventually: natural language to system design

This layer is the most uncertain. It will be designed when the VM is solid.

## Differences from C++ Prototype

The C++ prototype (`src/`, `include/tohum/`) was a proof-of-concept that validated
the temporal value model. The M rewrite is **not a port** — it's a redesign.

| Aspect | C++ Prototype | M Rewrite |
|--------|--------------|-----------|
| Values | `std::variant` (4 types) | Parallel arrays (4 types) |
| Confidence | `double` (0.0-1.0) | `i32` (0-100) |
| Time | `std::chrono::system_clock` | Tick counter + epoch seconds |
| Persistence | Binary with `fstream` | Binary with `read_file`/`write_file` |
| Names | `std::unordered_map` | Linear search (simple, M-compatible) |
| Strings | `std::string` | M string pool |
| REPL | Interactive CLI | Separate program, not built-in |

The C++ prototype has 34 opcodes (including `PUSH_APPROX` with `f64`). The M
version has 32 — no floating-point opcodes, `PUSH_APPROX` takes `i32` confidence.

## Implementation Plan

### Phase A: Core VM (First)
1. Value representation (parallel arrays, type tags)
2. Bytecode loader (read from file or from memory)
3. Stack machine execution loop
4. Basic opcodes: PUSH, POP, BIND, LOAD, arithmetic, comparison, logic
5. Control flow: JUMP, JUMP_IF_FALSE, CALL, RETURN
6. I/O: PRINT
7. Test suite: at least 30 tests

### Phase B: Temporal (Second)
1. Timeline arrays per variable
2. BIND appends (never overwrites)
3. HISTORY opcode (print full timeline)
4. Tick counter + wall-time tracking
5. Confidence propagation on all arithmetic/comparison
6. BIND_APPROX for explicit confidence setting
7. REFLECT, DRIFT opcodes
8. FORGET opcode (active forgetting)
9. Test suite: at least 20 temporal-specific tests

### Phase C: Persistence (Third)
1. SNAPSHOT opcode (in-memory state save)
2. PERSIST opcode (write to binary file)
3. RESTORE opcode (read from binary file)
4. Binary format as specified above
5. Test: persist, restart, restore, verify timeline continuity

### Phase D: Integration
1. Simple assembler (text → bytecode) for hand-written VM programs
2. Connect to M's cross-language parsers
3. First "real" program: analyze an M source file, build a model, persist it

## What We Don't Build

- No JIT compiler. The VM interprets bytecode. Speed comes from M→C→native for
  the VM itself.
- No garbage collector. M manages memory explicitly.
- No networking. Machine is a local system first.
- No GUI. Text I/O only. Forever.
- No plugin system. If you need to extend Machine, you modify Machine.

## File Organization

```
examples/
  machine_vm.m        -- Machine VM implementation (Phase A-C)
  machine_asm.m       -- Simple assembler for VM bytecode
  self_codegen.m      -- M compiler (existing, unchanged)
  c_lexer.m           -- C tokenizer (existing, unchanged)
  c_parser.m          -- C parser + translator (existing, unchanged)
```

The VM is an M program. It compiles with the same M compiler that compiles
everything else. It transpiles to C and runs as a native executable.

## The Circle

```
M compiles M (self-hosting)
M reads C (cross-language)
M compiles Machine VM (M program → native executable)
Machine VM runs temporal programs (its own bytecode)
Machine VM hosts Machine AI (future)
Machine AI analyzes M, C, and everything else (future)
```

The seed grows into the tree that produces the next seed.
