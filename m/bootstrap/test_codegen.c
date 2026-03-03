/*
 * test_codegen.c — End-to-end: M source → parse → compile → run → check result
 *
 * This is the real test. If this works, M programs run.
 */

#include "parser.h"
#include "codegen.h"
#include "vm.h"
#include <stdio.h>
#include <string.h>

static int tests_run = 0;
static int tests_passed = 0;

static void check(int condition, const char *name) {
    tests_run++;
    if (condition) {
        tests_passed++;
    } else {
        printf("  FAIL: %s\n", name);
    }
}

/* Run M source, return result of main() */
static Val run_program(const char *source, int *ok) {
    Parser p;
    parser_init(&p, source);
    Program *prog = parser_parse(&p);
    if (parser_had_error(&p)) {
        printf("    parse error: %s\n", parser_error(&p));
        *ok = 0;
        Val v = {0};
        return v;
    }

    Compiler c;
    compiler_init(&c);
    if (compiler_compile(&c, prog) != 0) {
        printf("    compile error: %s\n", compiler_error(&c));
        *ok = 0;
        Val v = {0};
        return v;
    }

    VM vm;
    vm_init(&vm, compiler_module(&c));
    VMResult r = vm_run(&vm, "main");
    if (r == VM_ERROR) {
        printf("    runtime error: %s\n", vm_error(&vm));
        *ok = 0;
        Val v = {0};
        return v;
    }

    *ok = 1;
    return vm_result(&vm);
}

/* ── Tests ─────────────────────────────────────────── */

static void test_return_int(void) {
    int ok;
    Val v = run_program("fn main() -> i32 { return 42; }", &ok);
    check(ok, "return_int: runs");
    check(v.type == VAL_INT && v.i == 42, "return_int: value 42");
}

static void test_return_zero(void) {
    int ok;
    Val v = run_program("fn main() -> i32 { return 0; }", &ok);
    check(ok, "return_zero: runs");
    check(v.type == VAL_INT && v.i == 0, "return_zero: value 0");
}

static void test_arithmetic(void) {
    int ok;
    Val v = run_program(
        "fn main() -> i32 {\n"
        "    let a: i32 = 10;\n"
        "    let b: i32 = 3;\n"
        "    return a + b;\n"
        "}", &ok);
    check(ok, "arith: runs");
    check(v.type == VAL_INT && v.i == 13, "arith: 10+3=13");
}

static void test_arithmetic_complex(void) {
    int ok;
    Val v = run_program(
        "fn main() -> i32 {\n"
        "    let x: i32 = 2 + 3 * 4;\n"
        "    return x;\n"
        "}", &ok);
    check(ok, "arith_complex: runs");
    check(v.type == VAL_INT && v.i == 14, "arith_complex: 2+3*4=14");
}

static void test_subtraction(void) {
    int ok;
    Val v = run_program(
        "fn main() -> i32 {\n"
        "    return 100 - 58;\n"
        "}", &ok);
    check(ok, "sub: runs");
    check(v.type == VAL_INT && v.i == 42, "sub: 100-58=42");
}

static void test_division(void) {
    int ok;
    Val v = run_program(
        "fn main() -> i32 {\n"
        "    return 84 / 2;\n"
        "}", &ok);
    check(ok, "div: runs");
    check(v.type == VAL_INT && v.i == 42, "div: 84/2=42");
}

static void test_modulo(void) {
    int ok;
    Val v = run_program(
        "fn main() -> i32 {\n"
        "    return 17 % 5;\n"
        "}", &ok);
    check(ok, "mod: runs");
    check(v.type == VAL_INT && v.i == 2, "mod: 17%5=2");
}

static void test_negation(void) {
    int ok;
    Val v = run_program(
        "fn main() -> i32 {\n"
        "    let x: i32 = 42;\n"
        "    return -x;\n"
        "}", &ok);
    check(ok, "neg: runs");
    check(v.type == VAL_INT && v.i == -42, "neg: -42");
}

static void test_if_true(void) {
    int ok;
    Val v = run_program(
        "fn main() -> i32 {\n"
        "    if true {\n"
        "        return 1;\n"
        "    }\n"
        "    return 0;\n"
        "}", &ok);
    check(ok, "if_true: runs");
    check(v.type == VAL_INT && v.i == 1, "if_true: returns 1");
}

static void test_if_false(void) {
    int ok;
    Val v = run_program(
        "fn main() -> i32 {\n"
        "    if false {\n"
        "        return 1;\n"
        "    }\n"
        "    return 0;\n"
        "}", &ok);
    check(ok, "if_false: runs");
    check(v.type == VAL_INT && v.i == 0, "if_false: returns 0");
}

static void test_if_else(void) {
    int ok;
    Val v = run_program(
        "fn main() -> i32 {\n"
        "    let x: i32 = 10;\n"
        "    if x > 5 {\n"
        "        return 1;\n"
        "    } else {\n"
        "        return 0;\n"
        "    }\n"
        "}", &ok);
    check(ok, "if_else: runs");
    check(v.type == VAL_INT && v.i == 1, "if_else: 10>5 -> 1");
}

static void test_while_loop(void) {
    int ok;
    Val v = run_program(
        "fn main() -> i32 {\n"
        "    var sum: i32 = 0;\n"
        "    var i: i32 = 1;\n"
        "    while i <= 10 {\n"
        "        sum = sum + i;\n"
        "        i = i + 1;\n"
        "    }\n"
        "    return sum;\n"
        "}", &ok);
    check(ok, "while: runs");
    check(v.type == VAL_INT && v.i == 55, "while: sum 1..10 = 55");
}

static void test_function_call(void) {
    int ok;
    Val v = run_program(
        "fn add(a: i32, b: i32) -> i32 {\n"
        "    return a + b;\n"
        "}\n"
        "fn main() -> i32 {\n"
        "    return add(20, 22);\n"
        "}", &ok);
    check(ok, "call: runs");
    check(v.type == VAL_INT && v.i == 42, "call: add(20,22)=42");
}

static void test_nested_calls(void) {
    int ok;
    Val v = run_program(
        "fn double(x: i32) -> i32 {\n"
        "    return x * 2;\n"
        "}\n"
        "fn main() -> i32 {\n"
        "    return double(double(10)) + 2;\n"
        "}", &ok);
    check(ok, "nested_call: runs");
    check(v.type == VAL_INT && v.i == 42, "nested_call: double(double(10))+2=42");
}

static void test_fibonacci(void) {
    int ok;
    Val v = run_program(
        "fn fib(n: i32) -> i32 {\n"
        "    if n <= 1 {\n"
        "        return n;\n"
        "    }\n"
        "    return fib(n - 1) + fib(n - 2);\n"
        "}\n"
        "fn main() -> i32 {\n"
        "    return fib(10);\n"
        "}", &ok);
    check(ok, "fib: runs");
    check(v.type == VAL_INT && v.i == 55, "fib: fib(10)=55");
}

static void test_boolean_logic(void) {
    int ok;
    Val v = run_program(
        "fn main() -> i32 {\n"
        "    if true && false {\n"
        "        return 1;\n"
        "    }\n"
        "    if true || false {\n"
        "        return 2;\n"
        "    }\n"
        "    return 0;\n"
        "}", &ok);
    check(ok, "logic: runs");
    check(v.type == VAL_INT && v.i == 2, "logic: true||false -> 2");
}

static void test_comparison_ops(void) {
    int ok;
    Val v = run_program(
        "fn main() -> i32 {\n"
        "    var result: i32 = 0;\n"
        "    if 1 == 1 { result = result + 1; }\n"
        "    if 1 != 2 { result = result + 1; }\n"
        "    if 1 < 2  { result = result + 1; }\n"
        "    if 2 > 1  { result = result + 1; }\n"
        "    if 1 <= 1 { result = result + 1; }\n"
        "    if 1 >= 1 { result = result + 1; }\n"
        "    return result;\n"
        "}", &ok);
    check(ok, "cmp: runs");
    check(v.type == VAL_INT && v.i == 6, "cmp: all 6 pass");
}

static void test_float_arithmetic(void) {
    int ok;
    Val v = run_program(
        "fn main() -> f64 {\n"
        "    let x: f64 = 3.14;\n"
        "    let y: f64 = 2.0;\n"
        "    return x * y;\n"
        "}", &ok);
    check(ok, "float: runs");
    check(v.type == VAL_FLOAT && v.f > 6.27 && v.f < 6.29, "float: 3.14*2=~6.28");
}

static void test_multiple_locals(void) {
    int ok;
    Val v = run_program(
        "fn main() -> i32 {\n"
        "    let a: i32 = 1;\n"
        "    let b: i32 = 2;\n"
        "    let c: i32 = 3;\n"
        "    let d: i32 = 4;\n"
        "    let e: i32 = 5;\n"
        "    return a + b + c + d + e;\n"
        "}", &ok);
    check(ok, "locals: runs");
    check(v.type == VAL_INT && v.i == 15, "locals: 1+2+3+4+5=15");
}

static void test_scope(void) {
    int ok;
    Val v = run_program(
        "fn main() -> i32 {\n"
        "    let x: i32 = 10;\n"
        "    if true {\n"
        "        let y: i32 = 20;\n"
        "        return x + y;\n"
        "    }\n"
        "    return x;\n"
        "}", &ok);
    check(ok, "scope: runs");
    check(v.type == VAL_INT && v.i == 30, "scope: x+y=30");
}

static void test_builtin_len(void) {
    int ok;
    Val v = run_program(
        "fn main() -> i32 {\n"
        "    return len(\"hello\");\n"
        "}", &ok);
    check(ok, "len: runs");
    check(v.type == VAL_INT && v.i == 5, "len: len(\"hello\")=5");
}

static void test_builtin_len_empty(void) {
    int ok;
    Val v = run_program(
        "fn main() -> i32 {\n"
        "    return len(\"\");\n"
        "}", &ok);
    check(ok, "len_empty: runs");
    check(v.type == VAL_INT && v.i == 0, "len_empty: len(\"\")=0");
}

static void test_builtin_char_at(void) {
    int ok;
    Val v = run_program(
        "fn main() -> i32 {\n"
        "    return char_at(\"ABC\", 0);\n"
        "}", &ok);
    check(ok, "char_at: runs");
    check(v.type == VAL_INT && v.i == 65, "char_at: char_at(\"ABC\",0)=65 ('A')");
}

static void test_builtin_char_at_mid(void) {
    int ok;
    Val v = run_program(
        "fn main() -> i32 {\n"
        "    return char_at(\"Machine\", 3);\n"
        "}", &ok);
    check(ok, "char_at_mid: runs");
    check(v.type == VAL_INT && v.i == 104, "char_at_mid: char_at(\"Machine\",3)=104 ('h')");
}

static void test_string_scan(void) {
    int ok;
    Val v = run_program(
        "fn is_digit(c: i32) -> bool {\n"
        "    return c >= 48 && c <= 57;\n"
        "}\n"
        "fn count_digits(s: string) -> i32 {\n"
        "    var count: i32 = 0;\n"
        "    var i: i32 = 0;\n"
        "    while i < len(s) {\n"
        "        if is_digit(char_at(s, i)) {\n"
        "            count = count + 1;\n"
        "        }\n"
        "        i = i + 1;\n"
        "    }\n"
        "    return count;\n"
        "}\n"
        "fn main() -> i32 {\n"
        "    return count_digits(\"abc123def45\");\n"
        "}", &ok);
    check(ok, "string_scan: runs");
    check(v.type == VAL_INT && v.i == 5, "string_scan: 5 digits in \"abc123def45\"");
}

static void test_print_output(void) {
    /* Test that print/println produce correct output */
    Parser p;
    parser_init(&p,
        "fn main() -> i32 {\n"
        "    print(\"hello \");\n"
        "    println(42);\n"
        "    return 0;\n"
        "}");
    Program *prog = parser_parse(&p);
    Compiler c;
    compiler_init(&c);
    compiler_compile(&c, prog);
    VM vm;
    vm_init(&vm, compiler_module(&c));
    vm_run(&vm, "main");
    check(vm.output_len > 0, "print_output: has output");
    check(memcmp(vm.output, "hello 42\n", 9) == 0, "print_output: \"hello 42\\n\"");
}

static void test_builtin_substr(void) {
    int ok;
    Val v = run_program(
        "fn main() -> i32 {\n"
        "    let s: string = substr(\"Machine\", 0, 4);\n"
        "    return len(s);\n"
        "}", &ok);
    check(ok, "substr: runs");
    check(v.type == VAL_INT && v.i == 4, "substr: len(substr(\"Machine\",0,4))=4");
}

static void test_builtin_substr_content(void) {
    /* Check that substr extracts the right characters */
    Parser p;
    parser_init(&p,
        "fn main() -> i32 {\n"
        "    let s: string = substr(\"Machine\", 2, 3);\n"
        "    print(s);\n"
        "    return 0;\n"
        "}");
    Program *prog = parser_parse(&p);
    Compiler c;
    compiler_init(&c);
    compiler_compile(&c, prog);
    VM vm;
    vm_init(&vm, compiler_module(&c));
    vm_run(&vm, "main");
    check(vm.output_len == 3, "substr_content: 3 chars");
    check(memcmp(vm.output, "chi", 3) == 0, "substr_content: \"chi\"");
}

static void test_builtin_str_concat(void) {
    Parser p;
    parser_init(&p,
        "fn main() -> i32 {\n"
        "    let s: string = str_concat(\"hello \", \"world\");\n"
        "    print(s);\n"
        "    return len(s);\n"
        "}");
    Program *prog = parser_parse(&p);
    Compiler c;
    compiler_init(&c);
    compiler_compile(&c, prog);
    VM vm;
    vm_init(&vm, compiler_module(&c));
    vm_run(&vm, "main");
    check(memcmp(vm.output, "hello world", 11) == 0, "str_concat: \"hello world\"");
    Val v = vm_result(&vm);
    check(v.type == VAL_INT && v.i == 11, "str_concat: len=11");
}

static void test_builtin_int_to_str(void) {
    Parser p;
    parser_init(&p,
        "fn main() -> i32 {\n"
        "    let s: string = int_to_str(42);\n"
        "    print(s);\n"
        "    return len(s);\n"
        "}");
    Program *prog = parser_parse(&p);
    Compiler c;
    compiler_init(&c);
    compiler_compile(&c, prog);
    VM vm;
    vm_init(&vm, compiler_module(&c));
    vm_run(&vm, "main");
    check(memcmp(vm.output, "42", 2) == 0, "int_to_str: \"42\"");
    Val v = vm_result(&vm);
    check(v.type == VAL_INT && v.i == 2, "int_to_str: len=2");
}

static void test_builtin_str_eq(void) {
    int ok;
    Val v = run_program(
        "fn main() -> i32 {\n"
        "    var result: i32 = 0;\n"
        "    if str_eq(\"abc\", \"abc\") { result = result + 1; }\n"
        "    if !str_eq(\"abc\", \"xyz\") { result = result + 1; }\n"
        "    if !str_eq(\"ab\", \"abc\") { result = result + 1; }\n"
        "    return result;\n"
        "}", &ok);
    check(ok, "str_eq: runs");
    check(v.type == VAL_INT && v.i == 3, "str_eq: all 3 checks pass");
}

static void test_tokenizer_in_m(void) {
    /* The real test: can M tokenize a string? */
    int ok;
    Val v = run_program(
        "fn is_space(c: i32) -> bool {\n"
        "    return c == 32 || c == 10 || c == 9;\n"
        "}\n"
        "fn is_alpha(c: i32) -> bool {\n"
        "    if c >= 65 && c <= 90 { return true; }\n"
        "    if c >= 97 && c <= 122 { return true; }\n"
        "    return c == 95;\n"
        "}\n"
        "fn is_digit(c: i32) -> bool {\n"
        "    return c >= 48 && c <= 57;\n"
        "}\n"
        "fn count_tokens(src: string) -> i32 {\n"
        "    var tokens: i32 = 0;\n"
        "    var i: i32 = 0;\n"
        "    while i < len(src) {\n"
        "        let c: i32 = char_at(src, i);\n"
        "        if is_space(c) {\n"
        "            i = i + 1;\n"
        "        } else if is_digit(c) {\n"
        "            tokens = tokens + 1;\n"
        "            while i < len(src) && is_digit(char_at(src, i)) {\n"
        "                i = i + 1;\n"
        "            }\n"
        "        } else if is_alpha(c) {\n"
        "            tokens = tokens + 1;\n"
        "            while i < len(src) && is_alpha(char_at(src, i)) {\n"
        "                i = i + 1;\n"
        "            }\n"
        "        } else {\n"
        "            tokens = tokens + 1;\n"
        "            i = i + 1;\n"
        "        }\n"
        "    }\n"
        "    return tokens;\n"
        "}\n"
        "fn main() -> i32 {\n"
        "    return count_tokens(\"let x = 42 + y\");\n"
        "}", &ok);
    check(ok, "tokenizer: runs");
    /* "let" "x" "=" "42" "+" "y" = 6 tokens */
    check(v.type == VAL_INT && v.i == 6, "tokenizer: 6 tokens in \"let x = 42 + y\"");
}

static void test_escape_sequences(void) {
    /* Test that \n in string is actual newline */
    Parser p;
    parser_init(&p,
        "fn main() -> i32 {\n"
        "    print(\"a\\nb\");\n"
        "    return 0;\n"
        "}");
    Program *prog = parser_parse(&p);
    Compiler c;
    compiler_init(&c);
    compiler_compile(&c, prog);
    VM vm;
    vm_init(&vm, compiler_module(&c));
    vm_run(&vm, "main");
    check(vm.output_len == 3, "escape: 3 chars (a + newline + b)");
    check(vm.output[0] == 'a' && vm.output[1] == '\n' && vm.output[2] == 'b',
          "escape: a\\nb");
}

static void test_escape_tab(void) {
    Parser p;
    parser_init(&p,
        "fn main() -> i32 {\n"
        "    print(\"x\\ty\");\n"
        "    return 0;\n"
        "}");
    Program *prog = parser_parse(&p);
    Compiler c;
    compiler_init(&c);
    compiler_compile(&c, prog);
    VM vm;
    vm_init(&vm, compiler_module(&c));
    vm_run(&vm, "main");
    check(vm.output[1] == '\t', "escape_tab: x\\ty");
}

static void test_char_to_str(void) {
    Parser p;
    parser_init(&p,
        "fn main() -> i32 {\n"
        "    let s: string = char_to_str(65);\n"
        "    print(s);\n"
        "    return len(s);\n"
        "}");
    Program *prog = parser_parse(&p);
    Compiler c;
    compiler_init(&c);
    compiler_compile(&c, prog);
    VM vm;
    vm_init(&vm, compiler_module(&c));
    vm_run(&vm, "main");
    check(vm.output[0] == 'A', "char_to_str: 65 -> 'A'");
    Val v = vm_result(&vm);
    check(v.type == VAL_INT && v.i == 1, "char_to_str: len=1");
}

static void test_short_circuit_and(void) {
    /* Verify && short-circuits: second operand not evaluated if first is false */
    int ok;
    Val v = run_program(
        "fn boom() -> bool {\n"
        "    // If this runs, char_at will crash on out-of-bounds\n"
        "    let x: i32 = char_at(\"\", 0);\n"
        "    return true;\n"
        "}\n"
        "fn main() -> i32 {\n"
        "    if false && boom() {\n"
        "        return 1;\n"
        "    }\n"
        "    return 42;\n"
        "}", &ok);
    check(ok, "short_circuit_and: runs without crash");
    check(v.type == VAL_INT && v.i == 42, "short_circuit_and: 42");
}

static void test_short_circuit_or(void) {
    int ok;
    Val v = run_program(
        "fn boom() -> bool {\n"
        "    let x: i32 = char_at(\"\", 0);\n"
        "    return false;\n"
        "}\n"
        "fn main() -> i32 {\n"
        "    if true || boom() {\n"
        "        return 42;\n"
        "    }\n"
        "    return 0;\n"
        "}", &ok);
    check(ok, "short_circuit_or: runs without crash");
    check(v.type == VAL_INT && v.i == 42, "short_circuit_or: 42");
}

static void test_array_basic(void) {
    int ok;
    Val v = run_program(
        "fn main() -> i32 {\n"
        "    var arr: i32 = array_new(0);\n"
        "    array_push(arr, 10);\n"
        "    array_push(arr, 20);\n"
        "    array_push(arr, 30);\n"
        "    return array_len(arr);\n"
        "}", &ok);
    check(ok, "array_basic: runs");
    check(v.type == VAL_INT && v.i == 3, "array_basic: len=3");
}

static void test_array_get(void) {
    int ok;
    Val v = run_program(
        "fn main() -> i32 {\n"
        "    var arr: i32 = array_new(0);\n"
        "    array_push(arr, 42);\n"
        "    array_push(arr, 99);\n"
        "    return array_get(arr, 0);\n"
        "}", &ok);
    check(ok, "array_get: runs");
    check(v.type == VAL_INT && v.i == 42, "array_get: arr[0]=42");
}

static void test_array_set(void) {
    int ok;
    Val v = run_program(
        "fn main() -> i32 {\n"
        "    var arr: i32 = array_new(0);\n"
        "    array_push(arr, 1);\n"
        "    array_push(arr, 2);\n"
        "    array_set(arr, 0, 100);\n"
        "    return array_get(arr, 0) + array_get(arr, 1);\n"
        "}", &ok);
    check(ok, "array_set: runs");
    check(v.type == VAL_INT && v.i == 102, "array_set: 100+2=102");
}

static void test_array_loop(void) {
    int ok;
    Val v = run_program(
        "fn main() -> i32 {\n"
        "    var arr: i32 = array_new(0);\n"
        "    var i: i32 = 0;\n"
        "    while i < 10 {\n"
        "        array_push(arr, i * i);\n"
        "        i = i + 1;\n"
        "    }\n"
        "    var sum: i32 = 0;\n"
        "    i = 0;\n"
        "    while i < array_len(arr) {\n"
        "        sum = sum + array_get(arr, i);\n"
        "        i = i + 1;\n"
        "    }\n"
        "    return sum;\n"
        "}", &ok);
    check(ok, "array_loop: runs");
    /* 0+1+4+9+16+25+36+49+64+81 = 285 */
    check(v.type == VAL_INT && v.i == 285, "array_loop: sum of squares 0..9 = 285");
}

static void test_array_of_strings(void) {
    Parser p;
    parser_init(&p,
        "fn main() -> i32 {\n"
        "    var words: i32 = array_new(0);\n"
        "    array_push(words, \"hello\");\n"
        "    array_push(words, \" \");\n"
        "    array_push(words, \"world\");\n"
        "    var i: i32 = 0;\n"
        "    while i < array_len(words) {\n"
        "        print(array_get(words, i));\n"
        "        i = i + 1;\n"
        "    }\n"
        "    return array_len(words);\n"
        "}");
    Program *prog = parser_parse(&p);
    Compiler c;
    compiler_init(&c);
    compiler_compile(&c, prog);
    VM vm;
    vm_init(&vm, compiler_module(&c));
    vm_run(&vm, "main");
    check(memcmp(vm.output, "hello world", 11) == 0, "array_strings: \"hello world\"");
    Val v = vm_result(&vm);
    check(v.type == VAL_INT && v.i == 3, "array_strings: len=3");
}

static void test_global_var_init(void) {
    int ok;
    Val v = run_program(
        "var g: i32 = 42;\n"
        "fn main() -> i32 { return g; }", &ok);
    check(ok, "global_var_init: runs");
    check(v.type == VAL_INT && v.i == 42, "global_var_init: value 42");
}

static void test_global_var_mutation(void) {
    int ok;
    Val v = run_program(
        "var counter: i32 = 0;\n"
        "fn inc() -> i32 { counter = counter + 1; return counter; }\n"
        "fn main() -> i32 { inc(); inc(); inc(); return counter; }", &ok);
    check(ok, "global_var_mutation: runs");
    check(v.type == VAL_INT && v.i == 3, "global_var_mutation: value 3");
}

static void test_global_var_default(void) {
    int ok;
    Val v = run_program(
        "var x: i32;\n"
        "fn main() -> i32 { x = 99; return x; }", &ok);
    check(ok, "global_var_default: runs");
    check(v.type == VAL_INT && v.i == 99, "global_var_default: value 99");
}

static void test_forward_call(void) {
    int ok;
    Val v = run_program(
        "fn a() -> i32 { return b(); }\n"
        "fn b() -> i32 { return 77; }\n"
        "fn main() -> i32 { return a(); }", &ok);
    check(ok, "forward_call: runs");
    check(v.type == VAL_INT && v.i == 77, "forward_call: value 77");
}

static void test_mutual_recursion(void) {
    int ok;
    Val v = run_program(
        "fn is_even(n: i32) -> bool {\n"
        "    if n == 0 { return true; }\n"
        "    return is_odd(n - 1);\n"
        "}\n"
        "fn is_odd(n: i32) -> bool {\n"
        "    if n == 0 { return false; }\n"
        "    return is_even(n - 1);\n"
        "}\n"
        "fn main() -> i32 {\n"
        "    if is_even(10) { return 1; }\n"
        "    return 0;\n"
        "}", &ok);
    check(ok, "mutual_recursion: runs");
    check(v.type == VAL_INT && v.i == 1, "mutual_recursion: 10 is even");
}

/* ── Main ──────────────────────────────────────────── */

int main(void) {
    printf("M end-to-end tests (source -> parse -> compile -> run)\n");

    test_return_int();
    test_return_zero();
    test_arithmetic();
    test_arithmetic_complex();
    test_subtraction();
    test_division();
    test_modulo();
    test_negation();
    test_if_true();
    test_if_false();
    test_if_else();
    test_while_loop();
    test_function_call();
    test_nested_calls();
    test_fibonacci();
    test_boolean_logic();
    test_comparison_ops();
    test_float_arithmetic();
    test_multiple_locals();
    test_scope();

    test_builtin_len();
    test_builtin_len_empty();
    test_builtin_char_at();
    test_builtin_char_at_mid();
    test_string_scan();
    test_print_output();
    test_builtin_substr();
    test_builtin_substr_content();
    test_builtin_str_concat();
    test_builtin_int_to_str();
    test_builtin_str_eq();
    test_tokenizer_in_m();
    test_escape_sequences();
    test_escape_tab();
    test_char_to_str();
    test_short_circuit_and();
    test_short_circuit_or();
    test_array_basic();
    test_array_get();
    test_array_set();
    test_array_loop();
    test_array_of_strings();

    test_global_var_init();
    test_global_var_mutation();
    test_global_var_default();
    test_forward_call();
    test_mutual_recursion();

    printf("\n%d/%d tests passed\n", tests_passed, tests_run);
    return tests_passed == tests_run ? 0 : 1;
}
