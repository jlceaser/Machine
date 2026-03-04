// Machine VM — Temporal computation engine written in M
// Every value has a history. Uncertainty is native.
// Written in M, compiled to native via M→C transpiler.
//
// Phase A: Core VM — value representation, bytecode, stack machine
// Phase B: Temporal — timelines, confidence, history/reflect/drift
// Phase C: Persistence — snapshot, persist, restore

// ── Opcodes ──────────────────────────────────────────

fn OP_NOP() -> i32         { return 0; }
fn OP_HALT() -> i32        { return 1; }

// Stack
fn OP_PUSH_NIL() -> i32    { return 2; }
fn OP_PUSH_I32() -> i32    { return 3; }
fn OP_PUSH_BOOL() -> i32   { return 4; }
fn OP_PUSH_STR() -> i32    { return 5; }
fn OP_PUSH_APPROX() -> i32 { return 6; }
fn OP_POP() -> i32         { return 7; }
fn OP_DUP() -> i32         { return 8; }

// Variables
fn OP_BIND() -> i32        { return 10; }
fn OP_BIND_APPROX() -> i32 { return 11; }
fn OP_LOAD() -> i32        { return 12; }

// Arithmetic
fn OP_ADD() -> i32         { return 20; }
fn OP_SUB() -> i32         { return 21; }
fn OP_MUL() -> i32         { return 22; }
fn OP_DIV() -> i32         { return 23; }
fn OP_NEG() -> i32         { return 24; }
fn OP_MOD() -> i32         { return 25; }

// Comparison
fn OP_EQ() -> i32          { return 30; }
fn OP_NEQ() -> i32         { return 31; }
fn OP_LT() -> i32          { return 32; }
fn OP_GT() -> i32          { return 33; }
fn OP_LTE() -> i32         { return 34; }
fn OP_GTE() -> i32         { return 35; }

// Logic
fn OP_AND() -> i32         { return 40; }
fn OP_OR() -> i32          { return 41; }
fn OP_NOT() -> i32         { return 42; }

// Control flow
fn OP_JUMP() -> i32        { return 50; }
fn OP_JUMP_IF_FALSE() -> i32 { return 51; }
fn OP_CALL() -> i32        { return 52; }
fn OP_RETURN() -> i32      { return 53; }

// Temporal
fn OP_HISTORY() -> i32     { return 60; }
fn OP_REFLECT() -> i32     { return 61; }
fn OP_DRIFT() -> i32       { return 62; }
fn OP_FORGET() -> i32      { return 63; }
fn OP_SNAPSHOT() -> i32    { return 64; }

// Persistence
fn OP_PERSIST() -> i32     { return 70; }
fn OP_RESTORE() -> i32     { return 71; }

// I/O
fn OP_PRINT() -> i32       { return 80; }
fn OP_PRINT_HIST() -> i32  { return 81; }

// ── Value type tags ──────────────────────────────────

fn VT_NIL() -> i32    { return 0; }
fn VT_I32() -> i32    { return 1; }
fn VT_BOOL() -> i32   { return 2; }
fn VT_STR() -> i32    { return 3; }

// ── Value store ──────────────────────────────────────
// Values are stored in parallel arrays, indexed by value ID.
// Each value has: type, integer data, string data, confidence.

var v_type: i32 = 0;       // VT_NIL / VT_I32 / VT_BOOL / VT_STR
var v_idata: i32 = 0;      // integer data (i32 value, or bool as 0/1)
var v_sdata: i32 = 0;      // string index in string pool
var v_conf: i32 = 0;       // confidence 0-100 (100 = certain)
var v_count: i32 = 0;

// String pool — strings stored as arrays of char codes
var sp_strings: i32 = 0;
var str_pool_count: i32 = 0;

fn sp_store(s: string) -> i32 {
    let idx: i32 = str_pool_count;
    let chars: i32 = array_new(0);
    var i: i32 = 0;
    while i < len(s) {
        array_push(chars, char_at(s, i));
        i = i + 1;
    }
    array_push(sp_strings, chars);
    str_pool_count = str_pool_count + 1;
    return idx;
}

fn sp_get(idx: i32) -> string {
    let chars: i32 = array_get(sp_strings, idx);
    var result: string = "";
    var i: i32 = 0;
    let n: i32 = array_len(chars);
    while i < n {
        result = str_concat(result, char_to_str(array_get(chars, i)));
        i = i + 1;
    }
    return result;
}

// Create a new value and return its ID
fn val_nil() -> i32 {
    let id: i32 = v_count;
    array_push(v_type, VT_NIL());
    array_push(v_idata, 0);
    array_push(v_sdata, 0);
    array_push(v_conf, 100);
    v_count = v_count + 1;
    return id;
}

fn val_i32(n: i32) -> i32 {
    let id: i32 = v_count;
    array_push(v_type, VT_I32());
    array_push(v_idata, n);
    array_push(v_sdata, 0);
    array_push(v_conf, 100);
    v_count = v_count + 1;
    return id;
}

fn val_bool(b: i32) -> i32 {
    let id: i32 = v_count;
    array_push(v_type, VT_BOOL());
    array_push(v_idata, b);
    array_push(v_sdata, 0);
    array_push(v_conf, 100);
    v_count = v_count + 1;
    return id;
}

fn val_str(s: string) -> i32 {
    let id: i32 = v_count;
    let si: i32 = sp_store(s);
    array_push(v_type, VT_STR());
    array_push(v_idata, 0);
    array_push(v_sdata, si);
    array_push(v_conf, 100);
    v_count = v_count + 1;
    return id;
}

fn val_approx(n: i32, conf: i32) -> i32 {
    let id: i32 = v_count;
    array_push(v_type, VT_I32());
    array_push(v_idata, n);
    array_push(v_sdata, 0);
    array_push(v_conf, conf);
    v_count = v_count + 1;
    return id;
}

fn val_get_type(id: i32) -> i32  { return array_get(v_type, id); }
fn val_get_int(id: i32) -> i32   { return array_get(v_idata, id); }
fn val_get_str(id: i32) -> string {
    return sp_get(array_get(v_sdata, id));
}
fn val_get_conf(id: i32) -> i32  { return array_get(v_conf, id); }

fn val_is_truthy(id: i32) -> bool {
    let conf: i32 = val_get_conf(id);
    if conf < 50 { return false; }
    let t: i32 = val_get_type(id);
    if t == VT_NIL() { return false; }
    if t == VT_BOOL() { return val_get_int(id) != 0; }
    if t == VT_I32() { return val_get_int(id) != 0; }
    if t == VT_STR() {
        let s: string = val_get_str(id);
        return len(s) > 0;
    }
    return false;
}

fn propagate_conf(a: i32, b: i32) -> i32 {
    if a < b { return a; }
    return b;
}

fn val_display(id: i32) -> string {
    let t: i32 = val_get_type(id);
    let conf: i32 = val_get_conf(id);
    var prefix: string = "";
    if conf < 100 {
        prefix = str_concat("~", str_concat(int_to_str(conf), "% "));
    }
    if t == VT_NIL() { return str_concat(prefix, "nil"); }
    if t == VT_I32() { return str_concat(prefix, int_to_str(val_get_int(id))); }
    if t == VT_BOOL() {
        if val_get_int(id) != 0 { return str_concat(prefix, "true"); }
        return str_concat(prefix, "false");
    }
    if t == VT_STR() {
        return str_concat(prefix, str_concat("\"", str_concat(val_get_str(id), "\"")));
    }
    return "?";
}

// ── Timeline store ───────────────────────────────────
// Each variable has a timeline: sequence of (value_id, tick, source_id)

var tl_vals: i32 = 0;      // array of arrays: value IDs per timeline
var tl_ticks: i32 = 0;     // array of arrays: tick numbers per timeline
var tl_sources: i32 = 0;   // array of arrays: source string indices per timeline
var tl_count: i32 = 0;

fn tl_new() -> i32 {
    let id: i32 = tl_count;
    let vals: i32 = array_new(0);
    let ticks: i32 = array_new(0);
    let sources: i32 = array_new(0);
    array_push(tl_vals, vals);
    array_push(tl_ticks, ticks);
    array_push(tl_sources, sources);
    tl_count = tl_count + 1;
    return id;
}

fn tl_append(tl_id: i32, val_id: i32, tick: i32, source: string) -> i32 {
    let vals: i32 = array_get(tl_vals, tl_id);
    let ticks: i32 = array_get(tl_ticks, tl_id);
    let sources: i32 = array_get(tl_sources, tl_id);
    let src_id: i32 = sp_store(source);
    array_push(vals, val_id);
    array_push(ticks, tick);
    array_push(sources, src_id);
    return 0;
}

fn tl_current(tl_id: i32) -> i32 {
    let vals: i32 = array_get(tl_vals, tl_id);
    let n: i32 = array_len(vals);
    if n == 0 { return val_nil(); }
    return array_get(vals, n - 1);
}

fn tl_length(tl_id: i32) -> i32 {
    let vals: i32 = array_get(tl_vals, tl_id);
    return array_len(vals);
}

fn tl_get_val(tl_id: i32, idx: i32) -> i32 {
    let vals: i32 = array_get(tl_vals, tl_id);
    return array_get(vals, idx);
}

fn tl_get_tick(tl_id: i32, idx: i32) -> i32 {
    let ticks: i32 = array_get(tl_ticks, tl_id);
    return array_get(ticks, idx);
}

fn tl_get_source(tl_id: i32, idx: i32) -> string {
    let sources: i32 = array_get(tl_sources, tl_id);
    return sp_get(array_get(sources, idx));
}

// ── Environment ──────────────────────────────────────
// Maps variable names to timeline IDs. Linear search.

var env_names: i32 = 0;    // string pool indices for variable names
var env_tl_ids: i32 = 0;   // timeline IDs
var env_forgotten: i32 = 0; // 0 or 1
var env_count: i32 = 0;

fn env_init() -> i32 {
    env_names = array_new(0);
    env_tl_ids = array_new(0);
    env_forgotten = array_new(0);
    env_count = 0;
    return 0;
}

fn env_find(name: string) -> i32 {
    var i: i32 = 0;
    while i < env_count {
        let stored: string = sp_get(array_get(env_names, i));
        if str_eq(stored, name) { return i; }
        i = i + 1;
    }
    return 0 - 1;
}

fn env_bind(name: string, val_id: i32, tick: i32, source: string) -> i32 {
    let idx: i32 = env_find(name);
    if idx >= 0 {
        // Existing binding — append to timeline (never overwrite)
        let tl_id: i32 = array_get(env_tl_ids, idx);
        tl_append(tl_id, val_id, tick, source);
        return 0;
    }
    // New binding — create timeline
    let name_si: i32 = sp_store(name);
    let tl_id: i32 = tl_new();
    tl_append(tl_id, val_id, tick, source);
    array_push(env_names, name_si);
    array_push(env_tl_ids, tl_id);
    array_push(env_forgotten, 0);
    env_count = env_count + 1;
    return 0;
}

fn env_load(name: string) -> i32 {
    let idx: i32 = env_find(name);
    if idx < 0 {
        println(str_concat("runtime error: undefined binding: ", name));
        return val_nil();
    }
    if array_get(env_forgotten, idx) != 0 {
        println(str_concat("runtime error: binding was forgotten: ", name));
        return val_nil();
    }
    let tl_id: i32 = array_get(env_tl_ids, idx);
    return tl_current(tl_id);
}

fn env_forget(name: string) -> i32 {
    let idx: i32 = env_find(name);
    if idx < 0 { return 0; }
    array_set(env_forgotten, idx, 1);
    let tl_id: i32 = array_get(env_tl_ids, idx);
    let nil_id: i32 = val_nil();
    tl_append(tl_id, nil_id, vm_tick, "forgotten");
    return 0;
}

// ── Bytecode program ─────────────────────────────────

var code: i32 = 0;
var code_len: i32 = 0;

var name_table: i32 = 0;   // string pool indices
var name_count: i32 = 0;

fn code_add(op: i32) -> i32 {
    array_push(code, op);
    code_len = code_len + 1;
    return code_len - 1;
}

fn name_add(s: string) -> i32 {
    var i: i32 = 0;
    while i < name_count {
        let stored: string = sp_get(array_get(name_table, i));
        if str_eq(stored, s) { return i; }
        i = i + 1;
    }
    let si: i32 = sp_store(s);
    array_push(name_table, si);
    name_count = name_count + 1;
    return name_count - 1;
}

fn name_get(idx: i32) -> string {
    return sp_get(array_get(name_table, idx));
}

// ── Stack ────────────────────────────────────────────

var stack: i32 = 0;
var stack_top: i32 = 0;

fn stack_push(val_id: i32) -> i32 {
    if stack_top < array_len(stack) {
        array_set(stack, stack_top, val_id);
    } else {
        array_push(stack, val_id);
    }
    stack_top = stack_top + 1;
    return 0;
}

fn stack_pop() -> i32 {
    if stack_top <= 0 {
        println("runtime error: stack underflow");
        return val_nil();
    }
    stack_top = stack_top - 1;
    return array_get(stack, stack_top);
}

fn stack_peek() -> i32 {
    if stack_top <= 0 {
        println("runtime error: stack underflow on peek");
        return val_nil();
    }
    return array_get(stack, stack_top - 1);
}

// ── VM state ─────────────────────────────────────────

var vm_tick: i32 = 0;
var vm_halted: bool = false;
var vm_error: bool = false;

// ── Execution engine ─────────────────────────────────

fn vm_init() -> i32 {
    v_type = array_new(0);
    v_idata = array_new(0);
    v_sdata = array_new(0);
    v_conf = array_new(0);
    v_count = 0;

    sp_strings = array_new(0);
    str_pool_count = 0;

    tl_vals = array_new(0);
    tl_ticks = array_new(0);
    tl_sources = array_new(0);
    tl_count = 0;

    env_init();

    code = array_new(0);
    code_len = 0;

    name_table = array_new(0);
    name_count = 0;

    stack = array_new(0);
    stack_top = 0;

    vm_tick = 0;
    vm_halted = false;
    vm_error = false;

    return 0;
}

fn vm_exec() -> i32 {
    var ip: i32 = 0;

    while ip < code_len && !vm_halted && !vm_error {
        let op: i32 = array_get(code, ip);
        ip = ip + 1;
        vm_tick = vm_tick + 1;

        if op == OP_NOP() {
            // nothing
        } else if op == OP_HALT() {
            vm_halted = true;
        }

        // ── Stack operations ──
        else if op == OP_PUSH_NIL() {
            stack_push(val_nil());
        }
        else if op == OP_PUSH_I32() {
            let n: i32 = array_get(code, ip);
            ip = ip + 1;
            stack_push(val_i32(n));
        }
        else if op == OP_PUSH_BOOL() {
            let b: i32 = array_get(code, ip);
            ip = ip + 1;
            stack_push(val_bool(b));
        }
        else if op == OP_PUSH_STR() {
            let name_idx: i32 = array_get(code, ip);
            ip = ip + 1;
            let s: string = name_get(name_idx);
            stack_push(val_str(s));
        }
        else if op == OP_PUSH_APPROX() {
            let n: i32 = array_get(code, ip);
            ip = ip + 1;
            let conf: i32 = array_get(code, ip);
            ip = ip + 1;
            stack_push(val_approx(n, conf));
        }
        else if op == OP_POP() {
            stack_pop();
        }
        else if op == OP_DUP() {
            let top: i32 = stack_peek();
            stack_push(top);
        }

        // ── Variable operations ──
        else if op == OP_BIND() {
            let name_idx: i32 = array_get(code, ip);
            ip = ip + 1;
            let val_id: i32 = stack_pop();
            let name: string = name_get(name_idx);
            env_bind(name, val_id, vm_tick, "bind");
        }
        else if op == OP_BIND_APPROX() {
            let name_idx: i32 = array_get(code, ip);
            ip = ip + 1;
            let conf_val: i32 = stack_pop();
            let data_val: i32 = stack_pop();
            let conf: i32 = val_get_int(conf_val);
            let name: string = name_get(name_idx);
            let new_val: i32 = val_approx(val_get_int(data_val), conf);
            env_bind(name, new_val, vm_tick, "bind_approx");
        }
        else if op == OP_LOAD() {
            let name_idx: i32 = array_get(code, ip);
            ip = ip + 1;
            let name: string = name_get(name_idx);
            let val_id: i32 = env_load(name);
            stack_push(val_id);
        }

        // ── Arithmetic ──
        else if op == OP_ADD() {
            let b: i32 = stack_pop();
            let a: i32 = stack_pop();
            let result: i32 = val_get_int(a) + val_get_int(b);
            let conf: i32 = propagate_conf(val_get_conf(a), val_get_conf(b));
            stack_push(val_approx(result, conf));
        }
        else if op == OP_SUB() {
            let b: i32 = stack_pop();
            let a: i32 = stack_pop();
            let result: i32 = val_get_int(a) - val_get_int(b);
            let conf: i32 = propagate_conf(val_get_conf(a), val_get_conf(b));
            stack_push(val_approx(result, conf));
        }
        else if op == OP_MUL() {
            let b: i32 = stack_pop();
            let a: i32 = stack_pop();
            let result: i32 = val_get_int(a) * val_get_int(b);
            let conf: i32 = propagate_conf(val_get_conf(a), val_get_conf(b));
            stack_push(val_approx(result, conf));
        }
        else if op == OP_DIV() {
            let b: i32 = stack_pop();
            let a: i32 = stack_pop();
            let bv: i32 = val_get_int(b);
            if bv == 0 {
                println("runtime error: division by zero");
                stack_push(val_nil());
                vm_error = true;
            } else {
                let result: i32 = val_get_int(a) / bv;
                let conf: i32 = propagate_conf(val_get_conf(a), val_get_conf(b));
                stack_push(val_approx(result, conf));
            }
        }
        else if op == OP_NEG() {
            let a: i32 = stack_pop();
            let result: i32 = 0 - val_get_int(a);
            stack_push(val_approx(result, val_get_conf(a)));
        }
        else if op == OP_MOD() {
            let b: i32 = stack_pop();
            let a: i32 = stack_pop();
            let bv: i32 = val_get_int(b);
            if bv == 0 {
                println("runtime error: modulo by zero");
                stack_push(val_nil());
                vm_error = true;
            } else {
                let result: i32 = val_get_int(a) % bv;
                let conf: i32 = propagate_conf(val_get_conf(a), val_get_conf(b));
                stack_push(val_approx(result, conf));
            }
        }

        // ── Comparison ──
        else if op == OP_EQ() {
            let b: i32 = stack_pop();
            let a: i32 = stack_pop();
            let r: i32 = 0;
            if val_get_int(a) == val_get_int(b) { r = 1; }
            let conf: i32 = propagate_conf(val_get_conf(a), val_get_conf(b));
            let rv: i32 = v_count;
            array_push(v_type, VT_BOOL());
            array_push(v_idata, r);
            array_push(v_sdata, 0);
            array_push(v_conf, conf);
            v_count = v_count + 1;
            stack_push(rv);
        }
        else if op == OP_NEQ() {
            let b: i32 = stack_pop();
            let a: i32 = stack_pop();
            let r: i32 = 0;
            if val_get_int(a) != val_get_int(b) { r = 1; }
            let conf: i32 = propagate_conf(val_get_conf(a), val_get_conf(b));
            let rv: i32 = v_count;
            array_push(v_type, VT_BOOL());
            array_push(v_idata, r);
            array_push(v_sdata, 0);
            array_push(v_conf, conf);
            v_count = v_count + 1;
            stack_push(rv);
        }
        else if op == OP_LT() {
            let b: i32 = stack_pop();
            let a: i32 = stack_pop();
            let r: i32 = 0;
            if val_get_int(a) < val_get_int(b) { r = 1; }
            let conf: i32 = propagate_conf(val_get_conf(a), val_get_conf(b));
            let rv: i32 = v_count;
            array_push(v_type, VT_BOOL());
            array_push(v_idata, r);
            array_push(v_sdata, 0);
            array_push(v_conf, conf);
            v_count = v_count + 1;
            stack_push(rv);
        }
        else if op == OP_GT() {
            let b: i32 = stack_pop();
            let a: i32 = stack_pop();
            let r: i32 = 0;
            if val_get_int(a) > val_get_int(b) { r = 1; }
            let conf: i32 = propagate_conf(val_get_conf(a), val_get_conf(b));
            let rv: i32 = v_count;
            array_push(v_type, VT_BOOL());
            array_push(v_idata, r);
            array_push(v_sdata, 0);
            array_push(v_conf, conf);
            v_count = v_count + 1;
            stack_push(rv);
        }
        else if op == OP_LTE() {
            let b: i32 = stack_pop();
            let a: i32 = stack_pop();
            let r: i32 = 0;
            if val_get_int(a) <= val_get_int(b) { r = 1; }
            let conf: i32 = propagate_conf(val_get_conf(a), val_get_conf(b));
            let rv: i32 = v_count;
            array_push(v_type, VT_BOOL());
            array_push(v_idata, r);
            array_push(v_sdata, 0);
            array_push(v_conf, conf);
            v_count = v_count + 1;
            stack_push(rv);
        }
        else if op == OP_GTE() {
            let b: i32 = stack_pop();
            let a: i32 = stack_pop();
            let r: i32 = 0;
            if val_get_int(a) >= val_get_int(b) { r = 1; }
            let conf: i32 = propagate_conf(val_get_conf(a), val_get_conf(b));
            let rv: i32 = v_count;
            array_push(v_type, VT_BOOL());
            array_push(v_idata, r);
            array_push(v_sdata, 0);
            array_push(v_conf, conf);
            v_count = v_count + 1;
            stack_push(rv);
        }

        // ── Logic ──
        else if op == OP_AND() {
            let b: i32 = stack_pop();
            let a: i32 = stack_pop();
            let r: i32 = 0;
            if val_is_truthy(a) && val_is_truthy(b) { r = 1; }
            let conf: i32 = propagate_conf(val_get_conf(a), val_get_conf(b));
            let rv: i32 = v_count;
            array_push(v_type, VT_BOOL());
            array_push(v_idata, r);
            array_push(v_sdata, 0);
            array_push(v_conf, conf);
            v_count = v_count + 1;
            stack_push(rv);
        }
        else if op == OP_OR() {
            let b: i32 = stack_pop();
            let a: i32 = stack_pop();
            let r: i32 = 0;
            if val_is_truthy(a) || val_is_truthy(b) { r = 1; }
            let conf: i32 = propagate_conf(val_get_conf(a), val_get_conf(b));
            let rv: i32 = v_count;
            array_push(v_type, VT_BOOL());
            array_push(v_idata, r);
            array_push(v_sdata, 0);
            array_push(v_conf, conf);
            v_count = v_count + 1;
            stack_push(rv);
        }
        else if op == OP_NOT() {
            let a: i32 = stack_pop();
            let r: i32 = 1;
            if val_is_truthy(a) { r = 0; }
            let rv: i32 = v_count;
            array_push(v_type, VT_BOOL());
            array_push(v_idata, r);
            array_push(v_sdata, 0);
            array_push(v_conf, val_get_conf(a));
            v_count = v_count + 1;
            stack_push(rv);
        }

        // ── Control flow ──
        else if op == OP_JUMP() {
            let offset: i32 = array_get(code, ip);
            ip = ip + 1;
            ip = ip + offset;
        }
        else if op == OP_JUMP_IF_FALSE() {
            let offset: i32 = array_get(code, ip);
            ip = ip + 1;
            let cond: i32 = stack_pop();
            if !val_is_truthy(cond) {
                ip = ip + offset;
            }
        }

        // ── Temporal ──
        else if op == OP_HISTORY() {
            let name_idx: i32 = array_get(code, ip);
            ip = ip + 1;
            let name: string = name_get(name_idx);
            let idx: i32 = env_find(name);
            if idx < 0 {
                println("  (undefined)");
            } else {
                let tl_id: i32 = array_get(env_tl_ids, idx);
                let n: i32 = tl_length(tl_id);
                var j: i32 = 0;
                while j < n {
                    let vid: i32 = tl_get_val(tl_id, j);
                    let tk: i32 = tl_get_tick(tl_id, j);
                    let src: string = tl_get_source(tl_id, j);
                    print(str_concat("  [", str_concat(int_to_str(j), "] tick ")));
                    print(str_concat(int_to_str(tk), str_concat(" = ", val_display(vid))));
                    println(str_concat(" (", str_concat(src, ")")));
                    j = j + 1;
                }
            }
        }
        else if op == OP_REFLECT() {
            var certain_n: i32 = 0;
            var approx_n: i32 = 0;
            var forgotten_n: i32 = 0;
            var most_changed: string = "";
            var max_hist: i32 = 0;
            var i: i32 = 0;
            while i < env_count {
                if array_get(env_forgotten, i) != 0 {
                    forgotten_n = forgotten_n + 1;
                } else {
                    let tl_id: i32 = array_get(env_tl_ids, i);
                    let cur: i32 = tl_current(tl_id);
                    if val_get_conf(cur) >= 100 {
                        certain_n = certain_n + 1;
                    } else {
                        approx_n = approx_n + 1;
                    }
                    let h: i32 = tl_length(tl_id);
                    if h > max_hist {
                        max_hist = h;
                        most_changed = sp_get(array_get(env_names, i));
                    }
                }
                i = i + 1;
            }
            println(str_concat("  bindings: ", int_to_str(env_count)));
            println(str_concat("  certain: ", int_to_str(certain_n)));
            println(str_concat("  approximate: ", int_to_str(approx_n)));
            if forgotten_n > 0 {
                println(str_concat("  forgotten: ", int_to_str(forgotten_n)));
            }
            if max_hist > 1 {
                println(str_concat("  most changed: ", str_concat(most_changed, str_concat(" (", str_concat(int_to_str(max_hist), " entries)")))));
            }
        }
        else if op == OP_DRIFT() {
            var changed_n: i32 = 0;
            var stable_n: i32 = 0;
            var i: i32 = 0;
            while i < env_count {
                let tl_id: i32 = array_get(env_tl_ids, i);
                let h: i32 = tl_length(tl_id);
                let name: string = sp_get(array_get(env_names, i));
                if h > 1 {
                    changed_n = changed_n + 1;
                    println(str_concat("  ~ ", str_concat(name, str_concat(" (changed ", str_concat(int_to_str(h - 1), " times)")))));
                } else {
                    stable_n = stable_n + 1;
                }
                i = i + 1;
            }
            println(str_concat("  stable: ", str_concat(int_to_str(stable_n), str_concat(", changed: ", int_to_str(changed_n)))));
        }
        else if op == OP_FORGET() {
            let name_idx: i32 = array_get(code, ip);
            ip = ip + 1;
            let name: string = name_get(name_idx);
            env_forget(name);
        }
        else if op == OP_SNAPSHOT() {
            vm_snapshot();
        }
        else if op == OP_PERSIST() {
            // File path from name table
            let name_idx: i32 = array_get(code, ip);
            ip = ip + 1;
            let path: string = name_get(name_idx);
            vm_persist(path);
        }
        else if op == OP_RESTORE() {
            let name_idx: i32 = array_get(code, ip);
            ip = ip + 1;
            let path: string = name_get(name_idx);
            vm_restore(path);
        }

        // ── I/O ──
        else if op == OP_PRINT() {
            let val_id: i32 = stack_pop();
            println(str_concat("  = ", val_display(val_id)));
        }
        else if op == OP_PRINT_HIST() {
            let name_idx: i32 = array_get(code, ip);
            ip = ip + 1;
            let name: string = name_get(name_idx);
            let idx: i32 = env_find(name);
            if idx < 0 {
                println("  (undefined)");
            } else {
                let tl_id: i32 = array_get(env_tl_ids, idx);
                println(str_concat("  history of ", str_concat(name, ":")));
                let n: i32 = tl_length(tl_id);
                var j: i32 = 0;
                while j < n {
                    let vid: i32 = tl_get_val(tl_id, j);
                    let tk: i32 = tl_get_tick(tl_id, j);
                    let src: string = tl_get_source(tl_id, j);
                    print(str_concat("    [", str_concat(int_to_str(j), "] tick ")));
                    print(str_concat(int_to_str(tk), str_concat(" = ", val_display(vid))));
                    println(str_concat(" (", str_concat(src, ")")));
                    j = j + 1;
                }
            }
        }

        else {
            println(str_concat("runtime error: unknown opcode ", int_to_str(op)));
            vm_error = true;
        }
    }

    return 0;
}

// ── Persistence ──────────────────────────────────────
// Serialize VM state to text format (M has write_file/read_file).
// Format: line-based, parseable with M string ops.
//
// MCHV1                        (magic + version)
// B <count>                    (binding count)
// N <name>                     (binding name)
// F <0|1>                      (forgotten flag)
// T <timeline_length>          (timeline entry count)
// V <type> <idata> <sdata_len> <sdata> <conf> <tick> <source>
// ...
// E                            (end of binding)

fn vm_serialize() -> string {
    var out: string = "MCHV1\n";
    out = str_concat(out, str_concat("B ", str_concat(int_to_str(env_count), "\n")));

    var i: i32 = 0;
    while i < env_count {
        let name: string = sp_get(array_get(env_names, i));
        out = str_concat(out, str_concat("N ", str_concat(name, "\n")));
        out = str_concat(out, str_concat("F ", str_concat(int_to_str(array_get(env_forgotten, i)), "\n")));

        let tl_id: i32 = array_get(env_tl_ids, i);
        let tl_len: i32 = tl_length(tl_id);
        out = str_concat(out, str_concat("T ", str_concat(int_to_str(tl_len), "\n")));

        var j: i32 = 0;
        while j < tl_len {
            let vid: i32 = tl_get_val(tl_id, j);
            let tk: i32 = tl_get_tick(tl_id, j);
            let src: string = tl_get_source(tl_id, j);
            let vtype: i32 = val_get_type(vid);
            let vidata: i32 = val_get_int(vid);
            let vconf: i32 = val_get_conf(vid);
            var vsdata: string = "";
            if vtype == VT_STR() {
                vsdata = val_get_str(vid);
            }
            // V type idata sdata_len sdata conf tick source
            out = str_concat(out, "V ");
            out = str_concat(out, str_concat(int_to_str(vtype), " "));
            out = str_concat(out, str_concat(int_to_str(vidata), " "));
            out = str_concat(out, str_concat(int_to_str(len(vsdata)), " "));
            out = str_concat(out, str_concat(vsdata, " "));
            out = str_concat(out, str_concat(int_to_str(vconf), " "));
            out = str_concat(out, str_concat(int_to_str(tk), " "));
            out = str_concat(out, str_concat(src, "\n"));
            j = j + 1;
        }
        out = str_concat(out, "E\n");
        i = i + 1;
    }
    return out;
}

fn vm_persist(path: string) -> i32 {
    let data: string = vm_serialize();
    write_file(path, data);
    return 0;
}

// Parse helpers for deserialize
fn parse_int_at(s: string, start: i32) -> i32 {
    // Parse integer starting at position, stop at space or newline
    var result: i32 = 0;
    var neg: bool = false;
    var i: i32 = start;
    if i < len(s) && char_at(s, i) == 45 {
        neg = true;
        i = i + 1;
    }
    while i < len(s) {
        let c: i32 = char_at(s, i);
        if c >= 48 && c <= 57 {
            result = result * 10 + (c - 48);
        } else {
            // stop at non-digit
            if neg { return 0 - result; }
            return result;
        }
        i = i + 1;
    }
    if neg { return 0 - result; }
    return result;
}

fn skip_to_newline(s: string, start: i32) -> i32 {
    var i: i32 = start;
    while i < len(s) && char_at(s, i) != 10 {
        i = i + 1;
    }
    return i + 1;
}

fn extract_after_space(line: string) -> string {
    // Return everything after first space in a line
    var i: i32 = 0;
    while i < len(line) && char_at(line, i) != 32 {
        i = i + 1;
    }
    if i + 1 >= len(line) { return ""; }
    return substr(line, i + 1, len(line) - i - 1);
}

fn read_line_at(s: string, start: i32) -> string {
    // Read from start until newline
    var i: i32 = start;
    while i < len(s) && char_at(s, i) != 10 {
        i = i + 1;
    }
    return substr(s, start, i - start);
}

fn vm_deserialize(data: string) -> i32 {
    // Reset VM state but keep code/name_table intact
    v_type = array_new(0);
    v_idata = array_new(0);
    v_sdata = array_new(0);
    v_conf = array_new(0);
    v_count = 0;
    sp_strings = array_new(0);
    str_pool_count = 0;
    tl_vals = array_new(0);
    tl_ticks = array_new(0);
    tl_sources = array_new(0);
    tl_count = 0;
    env_names = array_new(0);
    env_tl_ids = array_new(0);
    env_forgotten = array_new(0);
    env_count = 0;

    var pos: i32 = 0;

    // Check magic
    let magic: string = read_line_at(data, pos);
    if !str_eq(magic, "MCHV1") {
        println("restore error: invalid format");
        return 0 - 1;
    }
    pos = skip_to_newline(data, pos);

    // Read binding count
    let bline: string = read_line_at(data, pos);
    let bcount: i32 = parse_int_at(bline, 2);
    pos = skip_to_newline(data, pos);

    var bi: i32 = 0;
    while bi < bcount {
        // N name
        let nline: string = read_line_at(data, pos);
        let name: string = substr(nline, 2, len(nline) - 2);
        pos = skip_to_newline(data, pos);

        // F flag
        let fline: string = read_line_at(data, pos);
        let forgotten: i32 = parse_int_at(fline, 2);
        pos = skip_to_newline(data, pos);

        // T timeline_length
        let tline: string = read_line_at(data, pos);
        let tl_len: i32 = parse_int_at(tline, 2);
        pos = skip_to_newline(data, pos);

        // Create timeline and binding
        let name_si: i32 = sp_store(name);
        let tl_id: i32 = tl_new();

        var tj: i32 = 0;
        while tj < tl_len {
            // V type idata sdata_len sdata conf tick source
            let vline: string = read_line_at(data, pos);
            pos = skip_to_newline(data, pos);

            // Parse: skip "V "
            var vp: i32 = 2;
            let vtype: i32 = parse_int_at(vline, vp);
            // skip past type number and space
            while vp < len(vline) && char_at(vline, vp) != 32 { vp = vp + 1; }
            vp = vp + 1;

            let vidata: i32 = parse_int_at(vline, vp);
            while vp < len(vline) && char_at(vline, vp) != 32 { vp = vp + 1; }
            vp = vp + 1;

            let sdata_len: i32 = parse_int_at(vline, vp);
            while vp < len(vline) && char_at(vline, vp) != 32 { vp = vp + 1; }
            vp = vp + 1;

            var vsdata: string = "";
            if sdata_len > 0 {
                vsdata = substr(vline, vp, sdata_len);
                vp = vp + sdata_len;
            }
            // skip space after sdata
            if vp < len(vline) && char_at(vline, vp) == 32 { vp = vp + 1; }

            let vconf: i32 = parse_int_at(vline, vp);
            while vp < len(vline) && char_at(vline, vp) != 32 { vp = vp + 1; }
            vp = vp + 1;

            let vtick: i32 = parse_int_at(vline, vp);
            while vp < len(vline) && char_at(vline, vp) != 32 { vp = vp + 1; }
            vp = vp + 1;

            // Rest is source
            let vsource: string = substr(vline, vp, len(vline) - vp);

            // Create value
            var vid: i32 = 0;
            if vtype == VT_NIL() {
                vid = val_nil();
            } else if vtype == VT_I32() {
                vid = val_approx(vidata, vconf);
            } else if vtype == VT_BOOL() {
                let bv: i32 = v_count;
                array_push(v_type, VT_BOOL());
                array_push(v_idata, vidata);
                array_push(v_sdata, 0);
                array_push(v_conf, vconf);
                v_count = v_count + 1;
                vid = bv;
            } else if vtype == VT_STR() {
                vid = val_str(vsdata);
                // Override confidence
                array_set(v_conf, vid, vconf);
            }

            tl_append(tl_id, vid, vtick, vsource);
            tj = tj + 1;
        }

        // Skip E line
        pos = skip_to_newline(data, pos);

        // Add to environment
        array_push(env_names, name_si);
        array_push(env_tl_ids, tl_id);
        array_push(env_forgotten, forgotten);
        env_count = env_count + 1;

        bi = bi + 1;
    }

    return 0;
}

fn vm_restore(path: string) -> i32 {
    let data: string = read_file(path);
    if len(data) == 0 {
        println("restore error: empty or missing file");
        return 0 - 1;
    }
    return vm_deserialize(data);
}

// ── Snapshot (in-memory) ─────────────────────────────
// Snapshot stores serialized state for rollback without disk I/O.

var snapshot_data: string = "";
var snapshot_valid: bool = false;

fn vm_snapshot() -> i32 {
    snapshot_data = vm_serialize();
    snapshot_valid = true;
    return 0;
}

fn vm_rollback() -> i32 {
    if !snapshot_valid {
        println("runtime error: no snapshot to restore");
        return 0 - 1;
    }
    return vm_deserialize(snapshot_data);
}

// Library ends here. Tests are in machine_vm_test.m
