# M Language Specification — v0.2

> M: the bone language. Everything above stands on this.

## Philosophy

M is not a general-purpose language. M exists so that Machine can exist
without depending on anything we didn't write. M is minimal, explicit,
and transparent. No hidden behavior. No magic.

## Core Principles

1. **No hidden allocations.** Every byte of memory is explicitly managed.
2. **No implicit conversions.** Types don't silently change.
3. **No exceptions.** Errors are values, returned explicitly.
4. **No runtime.** M compiles to bytecode or native code. No garbage collector.
5. **What you write is what runs.** No optimizer rewrites your intent.

## Types

### Primitive Types

| Type     | Description          |
|----------|----------------------|
| `i32`    | Signed 32-bit integer (default numeric type) |
| `bool`   | `true` or `false`    |
| `string` | Immutable string value |

> Note: M currently operates with these three types. The VM uses 64-bit integers
> internally. Future versions may add `i64`, `f64`, and unsigned types.

### Dynamic Arrays

```m
let arr: array = new_array();
array_push(arr, 42);
let val: i32 = array_get(arr, 0);
let size: i32 = array_len(arr);
```

Arrays hold `i32` values (or string indices). 65536 slots maximum.

## Declarations

### Variables

```m
let x: i32 = 42;           // immutable
var count: i32 = 0;         // mutable
let name: string = "tohum"; // string
let flag: bool = true;      // boolean
```

### Functions

```m
fn add(a: i32, b: i32) -> i32 {
    return a + b;
}

fn greet(name: string) -> i32 {
    print("hello ");
    println(name);
    return 0;
}
```

Forward declarations are supported:

```m
fn helper(x: i32) -> i32;  // forward declaration

fn main() -> i32 {
    return helper(42);
}

fn helper(x: i32) -> i32 {
    return x * 2;
}
```

### Global Variables

```m
var total: i32 = 0;

fn increment() -> i32 {
    total = total + 1;
    return total;
}
```

## Control Flow

```m
if condition {
    // ...
} else if other {
    // ...
} else {
    // ...
}

while condition {
    // ...
}
```

Short-circuit evaluation: `&&` and `||` do not evaluate the right operand if unnecessary.

## Strings

Strings are a built-in type with these operations:

| Function | Signature | Description |
|----------|-----------|-------------|
| `len` | `(string) -> i32` | String length |
| `char_at` | `(string, i32) -> i32` | Character code at index |
| `substr` | `(string, i32, i32) -> string` | Substring (start, length) |
| `str_concat` | `(string, string) -> string` | Concatenate two strings |
| `str_eq` | `(string, string) -> bool` | String equality |
| `int_to_str` | `(i32) -> string` | Integer to string |
| `char_to_str` | `(i32) -> string` | Character code to single-char string |

### Escape Sequences

String literals support escape sequences:

| Escape | Value | Description |
|--------|-------|-------------|
| `\n`   | 10    | Newline |
| `\t`   | 9     | Tab |
| `\r`   | 13    | Carriage return |
| `\\`   | 92    | Backslash |
| `\"`   | 34    | Double quote |
| `\0`   | 0     | Null |

## I/O

| Function | Signature | Description |
|----------|-----------|-------------|
| `print` | `(string) -> void` | Print string (no newline) |
| `println` | `(string) -> void` | Print string with newline |
| `read_file` | `(string) -> string` | Read entire file contents |
| `write_file` | `(string, string) -> i32` | Write string to file |
| `argc` | `() -> i32` | Argument count |
| `argv` | `(i32) -> string` | Get argument by index |

## Multi-file Programs

```m
use "library.m"

fn main() -> i32 {
    // functions from library.m are available here
    return 0;
}
```

The `use` directive includes all declarations from the referenced file.

## Entry Point

```m
fn main() -> i32 {
    // program starts here
    return 0;
}
```

## Compilation

M programs can be:

1. **Bytecode compiled and run** on the M VM
2. **Transpiled to C** and compiled to native executables

```bash
# Bytecode mode (VM)
mc.exe self_codegen.m program.m

# Transpile to C
mc.exe self_codegen.m --emit-c program.m output.c
gcc -O2 -o program output.c
```

## Self-Hosting

M compiles itself. The compiler (`self_codegen.m`, 218 functions) can:

- Parse M source code into AST
- Compile AST to bytecode
- Run bytecode on the VM
- Transpile AST to C source code

The self-hosting proof: the native-compiled compiler reproduces its own
C output byte-identically (fixed point).

## What M Does NOT Have

- No classes, no inheritance, no interfaces
- No generics
- No closures, no lambdas
- No garbage collector
- No exceptions, no try/catch
- No operator overloading
- No macros
- No ternary operator
- No for loops (while is sufficient)
- No null (use 0 or empty string)

## Bootstrap Plan

1. ~~First M compiler written in C (minimal bootstrap)~~ ✓
2. ~~M compiler rewritten in M (self-hosting)~~ ✓
3. ~~Self-hosting proven (byte-identical fixed point)~~ ✓
4. ~~M reads C code (Phase 2)~~ ✓
5. Machine VM written in M — next
6. C bootstrap becomes optional
