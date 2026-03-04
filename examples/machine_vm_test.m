// Machine VM test suite — tests for machine_vm.m
// Run: mc.exe self_codegen.m machine_vm_test.m

use "machine_vm.m"

var test_pass: i32 = 0;
var test_fail: i32 = 0;

fn assert_eq(actual: i32, expected: i32, msg: string) -> i32 {
    if actual == expected {
        test_pass = test_pass + 1;
        return 0;
    }
    test_fail = test_fail + 1;
    print("FAIL: ");
    print(msg);
    print(" expected=");
    print(int_to_str(expected));
    print(" actual=");
    println(int_to_str(actual));
    return 1;
}

fn assert_str_eq(actual: string, expected: string, msg: string) -> i32 {
    if str_eq(actual, expected) {
        test_pass = test_pass + 1;
        return 0;
    }
    test_fail = test_fail + 1;
    print("FAIL: ");
    print(msg);
    print(" expected=");
    print(expected);
    print(" actual=");
    println(actual);
    return 1;
}

// ── Value tests ──────────────────────────────────────

fn test_values() -> i32 {
    vm_init();
    let n: i32 = val_nil();
    assert_eq(val_get_type(n), VT_NIL(), "nil type");
    assert_eq(val_get_conf(n), 100, "nil conf");
    let i: i32 = val_i32(42);
    assert_eq(val_get_type(i), VT_I32(), "i32 type");
    assert_eq(val_get_int(i), 42, "i32 val");
    assert_eq(val_get_conf(i), 100, "i32 conf");
    let b: i32 = val_bool(1);
    assert_eq(val_get_type(b), VT_BOOL(), "bool type");
    assert_eq(val_get_int(b), 1, "bool val");
    let s: i32 = val_str("hello");
    assert_eq(val_get_type(s), VT_STR(), "str type");
    assert_str_eq(val_get_str(s), "hello", "str val");
    let a: i32 = val_approx(99, 75);
    assert_eq(val_get_int(a), 99, "approx val");
    assert_eq(val_get_conf(a), 75, "approx conf");
    return 0;
}

fn test_display() -> i32 {
    vm_init();
    let n: i32 = val_nil();
    assert_str_eq(val_display(n), "nil", "display nil");
    let i: i32 = val_i32(42);
    assert_str_eq(val_display(i), "42", "display i32");
    let bt: i32 = val_bool(1);
    assert_str_eq(val_display(bt), "true", "display bool true");
    let bf: i32 = val_bool(0);
    assert_str_eq(val_display(bf), "false", "display bool false");
    let s: i32 = val_str("world");
    assert_str_eq(val_display(s), "\"world\"", "display str");
    let a: i32 = val_approx(10, 70);
    assert_str_eq(val_display(a), "~70% 10", "display approx");
    return 0;
}

fn test_truthy() -> i32 {
    vm_init();
    let n: i32 = val_nil();
    assert_eq(val_is_truthy(n), 0, "nil not truthy");
    let z: i32 = val_i32(0);
    assert_eq(val_is_truthy(z), 0, "0 not truthy");
    let one: i32 = val_i32(1);
    assert_eq(val_is_truthy(one), 1, "1 is truthy");
    let low: i32 = val_approx(42, 30);
    assert_eq(val_is_truthy(low), 0, "low conf not truthy");
    return 0;
}

fn test_confidence() -> i32 {
    vm_init();
    assert_eq(propagate_conf(80, 60), 60, "prop min 80,60");
    assert_eq(propagate_conf(50, 90), 50, "prop min 50,90");
    assert_eq(propagate_conf(100, 100), 100, "prop min 100,100");
    let a: i32 = val_approx(10, 75);
    assert_eq(val_get_conf(a), 75, "approx keeps conf");
    return 0;
}

// ── Timeline tests ───────────────────────────────────

fn test_timeline() -> i32 {
    vm_init();
    let tl: i32 = tl_new();
    assert_eq(tl_length(tl), 0, "new tl empty");
    let v1: i32 = val_i32(10);
    tl_append(tl, v1, 1, "test");
    assert_eq(tl_length(tl), 1, "tl len after 1");
    let v2: i32 = val_i32(20);
    tl_append(tl, v2, 2, "rebind");
    assert_eq(tl_length(tl), 2, "tl len after 2");
    let cur: i32 = tl_current(tl);
    assert_eq(val_get_int(cur), 20, "tl current val");
    let first: i32 = tl_get_val(tl, 0);
    assert_eq(val_get_int(first), 10, "tl first val");
    assert_eq(tl_get_tick(tl, 0), 1, "tl first tick");
    assert_str_eq(tl_get_source(tl, 0), "test", "tl first source");
    assert_eq(tl_get_tick(tl, 1), 2, "tl second tick");
    assert_str_eq(tl_get_source(tl, 1), "rebind", "tl second source");
    return 0;
}

// ── Environment tests ────────────────────────────────

fn test_env() -> i32 {
    vm_init();
    env_bind("x", val_i32(42), 1, "direct");
    let v: i32 = env_load("x");
    assert_eq(val_get_int(v), 42, "env load x");
    assert_eq(env_find("x"), 0, "env find x idx");
    assert_eq(env_find("y"), 0 - 1, "env find y missing");
    env_forget("x");
    let f: i32 = env_load("x");
    assert_eq(val_get_type(f), VT_NIL(), "forgotten returns nil");
    return 0;
}

// ── Execution tests ──────────────────────────────────

fn test_run_basic() -> i32 {
    vm_init();
    code_add(OP_PUSH_I32()); code_add(42);
    code_add(OP_HALT());
    vm_exec();
    assert_eq(vm_halted, 1, "vm halted");
    assert_eq(vm_error, 0, "no error");
    let top: i32 = stack_pop();
    assert_eq(val_get_int(top), 42, "push i32 42");
    return 0;
}

fn test_run_arith() -> i32 {
    vm_init();
    code_add(OP_PUSH_I32()); code_add(10);
    code_add(OP_PUSH_I32()); code_add(20);
    code_add(OP_ADD());
    code_add(OP_HALT());
    vm_exec();
    let r: i32 = stack_pop();
    assert_eq(val_get_int(r), 30, "10+20=30");

    vm_init();
    code_add(OP_PUSH_I32()); code_add(50);
    code_add(OP_PUSH_I32()); code_add(15);
    code_add(OP_SUB());
    code_add(OP_HALT());
    vm_exec();
    let r2: i32 = stack_pop();
    assert_eq(val_get_int(r2), 35, "50-15=35");

    vm_init();
    code_add(OP_PUSH_I32()); code_add(6);
    code_add(OP_PUSH_I32()); code_add(7);
    code_add(OP_MUL());
    code_add(OP_HALT());
    vm_exec();
    let r3: i32 = stack_pop();
    assert_eq(val_get_int(r3), 42, "6*7=42");

    vm_init();
    code_add(OP_PUSH_I32()); code_add(20);
    code_add(OP_PUSH_I32()); code_add(4);
    code_add(OP_DIV());
    code_add(OP_HALT());
    vm_exec();
    let r4: i32 = stack_pop();
    assert_eq(val_get_int(r4), 5, "20/4=5");
    return 0;
}

fn test_run_compare() -> i32 {
    vm_init();
    code_add(OP_PUSH_I32()); code_add(5);
    code_add(OP_PUSH_I32()); code_add(5);
    code_add(OP_EQ());
    code_add(OP_HALT());
    vm_exec();
    let r1: i32 = stack_pop();
    assert_eq(val_get_int(r1), 1, "5==5");

    vm_init();
    code_add(OP_PUSH_I32()); code_add(5);
    code_add(OP_PUSH_I32()); code_add(3);
    code_add(OP_NEQ());
    code_add(OP_HALT());
    vm_exec();
    let r2: i32 = stack_pop();
    assert_eq(val_get_int(r2), 1, "5!=3");

    vm_init();
    code_add(OP_PUSH_I32()); code_add(3);
    code_add(OP_PUSH_I32()); code_add(5);
    code_add(OP_LT());
    code_add(OP_HALT());
    vm_exec();
    let r3: i32 = stack_pop();
    assert_eq(val_get_int(r3), 1, "3<5");

    vm_init();
    code_add(OP_PUSH_I32()); code_add(5);
    code_add(OP_PUSH_I32()); code_add(3);
    code_add(OP_GT());
    code_add(OP_HALT());
    vm_exec();
    let r4: i32 = stack_pop();
    assert_eq(val_get_int(r4), 1, "5>3");

    vm_init();
    code_add(OP_PUSH_I32()); code_add(5);
    code_add(OP_PUSH_I32()); code_add(5);
    code_add(OP_LTE());
    code_add(OP_HALT());
    vm_exec();
    let r5: i32 = stack_pop();
    assert_eq(val_get_int(r5), 1, "5<=5");

    vm_init();
    code_add(OP_PUSH_I32()); code_add(5);
    code_add(OP_PUSH_I32()); code_add(3);
    code_add(OP_GTE());
    code_add(OP_HALT());
    vm_exec();
    let r6: i32 = stack_pop();
    assert_eq(val_get_int(r6), 1, "5>=3");
    return 0;
}

fn test_run_logic() -> i32 {
    vm_init();
    code_add(OP_PUSH_BOOL()); code_add(1);
    code_add(OP_PUSH_BOOL()); code_add(1);
    code_add(OP_AND());
    code_add(OP_HALT());
    vm_exec();
    let r1: i32 = stack_pop();
    assert_eq(val_get_int(r1), 1, "true AND true");

    vm_init();
    code_add(OP_PUSH_BOOL()); code_add(1);
    code_add(OP_PUSH_BOOL()); code_add(0);
    code_add(OP_OR());
    code_add(OP_HALT());
    vm_exec();
    let r2: i32 = stack_pop();
    assert_eq(val_get_int(r2), 1, "true OR false");

    vm_init();
    code_add(OP_PUSH_BOOL()); code_add(1);
    code_add(OP_NOT());
    code_add(OP_HALT());
    vm_exec();
    let r3: i32 = stack_pop();
    assert_eq(val_get_int(r3), 0, "NOT true");
    return 0;
}

fn test_run_bind_load() -> i32 {
    vm_init();
    let nx: i32 = name_add("x");
    code_add(OP_PUSH_I32()); code_add(99);
    code_add(OP_BIND()); code_add(nx);
    code_add(OP_LOAD()); code_add(nx);
    code_add(OP_HALT());
    vm_exec();
    let r: i32 = stack_pop();
    assert_eq(val_get_int(r), 99, "bind+load x");
    return 0;
}

fn test_run_dup() -> i32 {
    vm_init();
    code_add(OP_PUSH_I32()); code_add(77);
    code_add(OP_DUP());
    code_add(OP_HALT());
    vm_exec();
    let a: i32 = stack_pop();
    let b: i32 = stack_pop();
    assert_eq(val_get_int(a), 77, "dup top");
    assert_eq(val_get_int(b), 77, "dup below");
    return 0;
}

fn test_run_neg_mod() -> i32 {
    vm_init();
    code_add(OP_PUSH_I32()); code_add(42);
    code_add(OP_NEG());
    code_add(OP_HALT());
    vm_exec();
    let r1: i32 = stack_pop();
    assert_eq(val_get_int(r1), 0 - 42, "neg 42");

    vm_init();
    code_add(OP_PUSH_I32()); code_add(17);
    code_add(OP_PUSH_I32()); code_add(5);
    code_add(OP_MOD());
    code_add(OP_HALT());
    vm_exec();
    let r2: i32 = stack_pop();
    assert_eq(val_get_int(r2), 2, "17%5=2");
    return 0;
}

fn test_run_jump() -> i32 {
    vm_init();
    code_add(OP_PUSH_I32()); code_add(1);
    code_add(OP_JUMP()); let slot: i32 = code_add(0);
    code_add(OP_PUSH_I32()); code_add(999);
    code_add(OP_PUSH_I32()); code_add(2);
    code_add(OP_HALT());
    // slot at pos 3, ip after = 4, target = 6, offset = 2
    array_set(code, slot, 2);
    vm_exec();
    let top: i32 = stack_pop();
    assert_eq(val_get_int(top), 2, "jump skipped 999");
    let below: i32 = stack_pop();
    assert_eq(val_get_int(below), 1, "jump kept 1");
    return 0;
}

fn test_run_jump_false() -> i32 {
    vm_init();
    code_add(OP_PUSH_BOOL()); code_add(0);
    code_add(OP_JUMP_IF_FALSE()); let slot: i32 = code_add(0);
    code_add(OP_PUSH_I32()); code_add(999);
    code_add(OP_PUSH_I32()); code_add(2);
    code_add(OP_HALT());
    // slot at pos 3, ip after = 4, target = 6, offset = 2
    array_set(code, slot, 2);
    vm_exec();
    let top: i32 = stack_pop();
    assert_eq(val_get_int(top), 2, "jif skipped 999");
    return 0;
}

fn test_run_loop() -> i32 {
    vm_init();
    let nx: i32 = name_add("x");
    code_add(OP_PUSH_I32()); code_add(0);
    code_add(OP_BIND()); code_add(nx);
    // loop_start (addr 4)
    code_add(OP_LOAD()); code_add(nx);
    code_add(OP_PUSH_I32()); code_add(5);
    code_add(OP_LT());
    code_add(OP_JUMP_IF_FALSE()); let exit_slot: i32 = code_add(0);
    // body: x = x + 1
    code_add(OP_LOAD()); code_add(nx);
    code_add(OP_PUSH_I32()); code_add(1);
    code_add(OP_ADD());
    code_add(OP_BIND()); code_add(nx);
    // jump back
    code_add(OP_JUMP()); let back_slot: i32 = code_add(0);
    // exit (addr 20)
    code_add(OP_HALT());
    // exit: slot 11, ip after = 12, target = 20, offset = 8
    array_set(code, exit_slot, 8);
    // back: slot 19, ip after = 20, target = 4, offset = -16
    array_set(code, back_slot, 0 - 16);
    vm_exec();
    let r: i32 = env_load("x");
    assert_eq(val_get_int(r), 5, "loop x=5");
    return 0;
}

fn test_run_string() -> i32 {
    vm_init();
    let ns: i32 = name_add("hello world");
    code_add(OP_PUSH_STR()); code_add(ns);
    code_add(OP_HALT());
    vm_exec();
    let top: i32 = stack_pop();
    assert_str_eq(val_get_str(top), "hello world", "push str");
    return 0;
}

fn test_run_approx() -> i32 {
    vm_init();
    code_add(OP_PUSH_APPROX()); code_add(100); code_add(60);
    code_add(OP_PUSH_APPROX()); code_add(200); code_add(80);
    code_add(OP_ADD());
    code_add(OP_HALT());
    vm_exec();
    let r: i32 = stack_pop();
    assert_eq(val_get_int(r), 300, "approx 100+200");
    assert_eq(val_get_conf(r), 60, "approx conf min(60,80)");
    return 0;
}

fn test_run_timeline() -> i32 {
    vm_init();
    let nx: i32 = name_add("x");
    code_add(OP_PUSH_I32()); code_add(10);
    code_add(OP_BIND()); code_add(nx);
    code_add(OP_PUSH_I32()); code_add(20);
    code_add(OP_BIND()); code_add(nx);
    code_add(OP_PUSH_I32()); code_add(30);
    code_add(OP_BIND()); code_add(nx);
    code_add(OP_HALT());
    vm_exec();
    let cur: i32 = env_load("x");
    assert_eq(val_get_int(cur), 30, "timeline current=30");
    let idx: i32 = env_find("x");
    let tl_id: i32 = array_get(env_tl_ids, idx);
    assert_eq(tl_length(tl_id), 3, "timeline len=3");
    let first: i32 = tl_get_val(tl_id, 0);
    assert_eq(val_get_int(first), 10, "timeline first=10");
    return 0;
}

fn test_run_forget() -> i32 {
    vm_init();
    let nx: i32 = name_add("x");
    code_add(OP_PUSH_I32()); code_add(42);
    code_add(OP_BIND()); code_add(nx);
    code_add(OP_FORGET()); code_add(nx);
    code_add(OP_HALT());
    vm_exec();
    assert_eq(vm_error, 0, "forget no error");
    let idx: i32 = env_find("x");
    assert_eq(array_get(env_forgotten, idx), 1, "x is forgotten");
    return 0;
}

fn test_run_snapshot() -> i32 {
    vm_init();
    let nx: i32 = name_add("x");
    code_add(OP_PUSH_I32()); code_add(10);
    code_add(OP_BIND()); code_add(nx);
    code_add(OP_SNAPSHOT());
    code_add(OP_PUSH_I32()); code_add(99);
    code_add(OP_BIND()); code_add(nx);
    code_add(OP_HALT());
    vm_exec();
    let before: i32 = env_load("x");
    assert_eq(val_get_int(before), 99, "before rollback x=99");
    vm_rollback();
    let after: i32 = env_load("x");
    assert_eq(val_get_int(after), 10, "after rollback x=10");
    return 0;
}

fn test_run_persist() -> i32 {
    vm_init();
    let nx: i32 = name_add("x");
    let ny: i32 = name_add("y");
    code_add(OP_PUSH_I32()); code_add(42);
    code_add(OP_BIND()); code_add(nx);
    code_add(OP_PUSH_APPROX()); code_add(99); code_add(75);
    code_add(OP_BIND()); code_add(ny);
    code_add(OP_HALT());
    vm_exec();
    let data: string = vm_serialize();
    let magic: string = substr(data, 0, 5);
    assert_str_eq(magic, "MCHV1", "persist magic");
    vm_init();
    vm_deserialize(data);
    let rx: i32 = env_load("x");
    assert_eq(val_get_int(rx), 42, "restored x=42");
    let ry: i32 = env_load("y");
    assert_eq(val_get_int(ry), 99, "restored y=99");
    assert_eq(val_get_conf(ry), 75, "restored y conf=75");
    return 0;
}

fn test_run_history() -> i32 {
    vm_init();
    let nx: i32 = name_add("x");
    code_add(OP_PUSH_I32()); code_add(10);
    code_add(OP_BIND()); code_add(nx);
    code_add(OP_PUSH_I32()); code_add(20);
    code_add(OP_BIND()); code_add(nx);
    code_add(OP_HISTORY()); code_add(nx);
    code_add(OP_HALT());
    vm_exec();
    assert_eq(vm_error, 0, "history no error");
    return 0;
}

fn test_run_reflect() -> i32 {
    vm_init();
    let nx: i32 = name_add("x");
    code_add(OP_PUSH_I32()); code_add(42);
    code_add(OP_BIND()); code_add(nx);
    code_add(OP_REFLECT());
    code_add(OP_HALT());
    vm_exec();
    assert_eq(vm_error, 0, "reflect no error");
    return 0;
}

fn test_run_drift() -> i32 {
    vm_init();
    let nx: i32 = name_add("x");
    code_add(OP_PUSH_I32()); code_add(10);
    code_add(OP_BIND()); code_add(nx);
    code_add(OP_PUSH_I32()); code_add(20);
    code_add(OP_BIND()); code_add(nx);
    code_add(OP_DRIFT());
    code_add(OP_HALT());
    vm_exec();
    assert_eq(vm_error, 0, "drift no error");
    return 0;
}

fn test_run_nil_bool() -> i32 {
    vm_init();
    code_add(OP_PUSH_NIL());
    code_add(OP_PUSH_BOOL()); code_add(1);
    code_add(OP_HALT());
    vm_exec();
    let b: i32 = stack_pop();
    assert_eq(val_get_type(b), VT_BOOL(), "push bool type");
    assert_eq(val_get_int(b), 1, "push bool val");
    let n: i32 = stack_pop();
    assert_eq(val_get_type(n), VT_NIL(), "push nil type");
    return 0;
}

fn test_run_pop() -> i32 {
    vm_init();
    code_add(OP_PUSH_I32()); code_add(1);
    code_add(OP_PUSH_I32()); code_add(2);
    code_add(OP_POP());
    code_add(OP_HALT());
    vm_exec();
    let r: i32 = stack_pop();
    assert_eq(val_get_int(r), 1, "pop removed top");
    return 0;
}

fn test_run_div_zero() -> i32 {
    vm_init();
    code_add(OP_PUSH_I32()); code_add(10);
    code_add(OP_PUSH_I32()); code_add(0);
    code_add(OP_DIV());
    code_add(OP_HALT());
    vm_exec();
    assert_eq(vm_error, 1, "div by zero error");
    return 0;
}

fn test_run_bind_approx() -> i32 {
    vm_init();
    let nx: i32 = name_add("x");
    code_add(OP_PUSH_I32()); code_add(42);
    code_add(OP_PUSH_I32()); code_add(65);
    code_add(OP_BIND_APPROX()); code_add(nx);
    code_add(OP_LOAD()); code_add(nx);
    code_add(OP_HALT());
    vm_exec();
    let r: i32 = stack_pop();
    assert_eq(val_get_int(r), 42, "bind_approx val");
    assert_eq(val_get_conf(r), 65, "bind_approx conf");
    return 0;
}

fn test_run_print_hist() -> i32 {
    vm_init();
    let nx: i32 = name_add("x");
    code_add(OP_PUSH_I32()); code_add(1);
    code_add(OP_BIND()); code_add(nx);
    code_add(OP_PUSH_I32()); code_add(2);
    code_add(OP_BIND()); code_add(nx);
    code_add(OP_PRINT_HIST()); code_add(nx);
    code_add(OP_HALT());
    vm_exec();
    assert_eq(vm_error, 0, "print_hist no error");
    return 0;
}

fn test_run_nop() -> i32 {
    vm_init();
    code_add(OP_NOP());
    code_add(OP_PUSH_I32()); code_add(1);
    code_add(OP_NOP());
    code_add(OP_HALT());
    vm_exec();
    let r: i32 = stack_pop();
    assert_eq(val_get_int(r), 1, "nop transparent");
    return 0;
}

// ── Main ─────────────────────────────────────────────

fn main() -> i32 {
    println("=== Machine VM Test Suite ===");

    test_values();
    test_display();
    test_truthy();
    test_confidence();
    test_timeline();
    test_env();
    test_run_basic();
    test_run_arith();
    test_run_compare();
    test_run_logic();
    test_run_bind_load();
    test_run_dup();
    test_run_neg_mod();
    test_run_jump();
    test_run_jump_false();
    test_run_loop();
    test_run_string();
    test_run_approx();
    test_run_timeline();
    test_run_forget();
    test_run_snapshot();
    test_run_persist();
    test_run_history();
    test_run_reflect();
    test_run_drift();
    test_run_nil_bool();
    test_run_pop();
    test_run_div_zero();
    test_run_bind_approx();
    test_run_print_hist();
    test_run_nop();

    println("");
    print("Tests passed: ");
    println(int_to_str(test_pass));
    print("Tests failed: ");
    println(int_to_str(test_fail));

    let total: i32 = test_pass + test_fail;
    print("Total: ");
    print(int_to_str(test_pass));
    print("/");
    println(int_to_str(total));

    if test_fail > 0 {
        println("SOME TESTS FAILED");
        return 1;
    }
    println("ALL TESTS PASSED");
    return 0;
}
