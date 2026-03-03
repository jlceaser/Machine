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

    printf("\n%d/%d tests passed\n", tests_passed, tests_run);
    return tests_passed == tests_run ? 0 : 1;
}
