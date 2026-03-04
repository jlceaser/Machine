// Machine Assembler — text format to bytecode
// Reads .masm files, assembles to VM bytecode, runs on Machine VM.
//
// Syntax:
//   push_i32 42       — push integer
//   push_bool 1       — push boolean (0/1)
//   push_nil          — push nil
//   push_str hello    — push string (rest of line)
//   push_approx 42 75 — push approximate value (value, confidence)
//   pop / dup         — stack ops
//   bind x            — bind top of stack to variable x
//   bind_approx x 60  — bind with explicit confidence
//   load x            — load variable x onto stack
//   add / sub / mul / div / neg / mod — arithmetic
//   eq / neq / lt / gt / lte / gte    — comparison
//   and / or / not                    — logic
//   jump LABEL        — unconditional jump
//   jump_if_false LABEL — conditional jump
//   halt              — stop execution
//   print             — print top of stack
//   print_hist x      — print history of variable x
//   history x         — push history length of x
//   reflect           — push binding count
//   drift             — push drift count (changes since last drift)
//   forget x          — forget variable x
//   snapshot          — save VM state
//   restore           — restore last snapshot
//   persist PATH      — persist state to file
//   restore_file PATH — restore state from file
//   nop               — no operation
//   LABEL:            — define a label (line ends with colon)
//   ; comment         — lines starting with ; are ignored
//   // comment        — lines starting with // are ignored

use "machine_vm.m"

// ── String helpers ───────────────────────────────────

fn asm_trim(s: string) -> string {
    var start: i32 = 0;
    while start < len(s) {
        let c: i32 = char_at(s, start);
        if c != 32 && c != 9 && c != 13 {
            start = start + 1;
        } else {
            start = start + 1;
        }
        start = start - 1;
        // re-check: only skip spaces/tabs/CR
        let ch: i32 = char_at(s, start);
        if ch == 32 || ch == 9 || ch == 13 {
            start = start + 1;
        } else {
            // found non-whitespace, break
            // M has no break — use a flag
            let end: i32 = len(s);
            // trim trailing
            while end > start {
                let ce: i32 = char_at(s, end - 1);
                if ce == 32 || ce == 9 || ce == 13 || ce == 10 {
                    end = end - 1;
                } else {
                    return substr(s, start, end - start);
                }
            }
            return "";
        }
    }
    return "";
}

// simpler trim — just strip leading/trailing whitespace
fn str_trim(s: string) -> string {
    var a: i32 = 0;
    while a < len(s) {
        let c: i32 = char_at(s, a);
        if c == 32 || c == 9 || c == 13 {
            a = a + 1;
        } else {
            a = a + len(s);  // break
        }
    }
    a = a - len(s);
    if a < 0 { a = 0; }

    var b: i32 = len(s);
    while b > a {
        let c: i32 = char_at(s, b - 1);
        if c == 32 || c == 9 || c == 13 || c == 10 {
            b = b - 1;
        } else {
            b = b - len(s);  // break
        }
    }
    b = b + len(s);
    if b > len(s) { b = len(s); }

    if b <= a { return ""; }
    return substr(s, a, b - a);
}

// Split a string into lines (by newline character 10)
fn split_lines(s: string) -> i32 {
    let lines: i32 = array_new(0);
    var start: i32 = 0;
    var i: i32 = 0;
    while i < len(s) {
        if char_at(s, i) == 10 {
            let line: string = substr(s, start, i - start);
            array_push(lines, sp_store(line));
            start = i + 1;
        }
        i = i + 1;
    }
    if start < len(s) {
        let line: string = substr(s, start, len(s) - start);
        array_push(lines, sp_store(line));
    }
    return lines;
}

// Get first word from a string (space-delimited)
fn first_word(s: string) -> string {
    var i: i32 = 0;
    while i < len(s) {
        let c: i32 = char_at(s, i);
        if c == 32 || c == 9 {
            return substr(s, 0, i);
        }
        i = i + 1;
    }
    return s;
}

// Get everything after the first word
fn rest_after_word(s: string) -> string {
    var i: i32 = 0;
    // skip first word
    while i < len(s) {
        let c: i32 = char_at(s, i);
        if c == 32 || c == 9 {
            i = i + len(s);  // break
        } else {
            i = i + 1;
        }
    }
    i = i - len(s);
    if i < 0 { i = 0; }
    // skip spaces
    while i < len(s) {
        let c: i32 = char_at(s, i);
        if c == 32 || c == 9 {
            i = i + 1;
        } else {
            return substr(s, i, len(s) - i);
        }
    }
    return "";
}

// Get second word from a string
fn second_word(s: string) -> string {
    let rest: string = rest_after_word(s);
    return first_word(rest);
}

// Get third word from a string
fn third_word(s: string) -> string {
    let rest: string = rest_after_word(s);
    let rest2: string = rest_after_word(rest);
    return first_word(rest2);
}

// Parse integer from string (handles negative)
fn parse_int(s: string) -> i32 {
    var result: i32 = 0;
    var i: i32 = 0;
    var negative: bool = false;
    if len(s) > 0 && char_at(s, 0) == 45 {
        negative = true;
        i = 1;
    }
    while i < len(s) {
        let c: i32 = char_at(s, i);
        if c >= 48 && c <= 57 {
            result = result * 10 + (c - 48);
        }
        i = i + 1;
    }
    if negative { return 0 - result; }
    return result;
}

// Check if string ends with a colon (label definition)
fn ends_with_colon(s: string) -> bool {
    if len(s) == 0 { return false; }
    return char_at(s, len(s) - 1) == 58;  // ':'
}

// ── Label table ──────────────────────────────────────

var label_names: i32 = 0;
var label_addrs: i32 = 0;
var label_count: i32 = 0;

// Patch table — unresolved forward references
var patch_addrs: i32 = 0;    // code offset to patch
var patch_labels: i32 = 0;   // label name (sp index)
var patch_count: i32 = 0;

fn label_init() -> i32 {
    label_names = array_new(0);
    label_addrs = array_new(0);
    label_count = 0;
    patch_addrs = array_new(0);
    patch_labels = array_new(0);
    patch_count = 0;
    return 0;
}

fn label_define(name: string, addr: i32) -> i32 {
    array_push(label_names, sp_store(name));
    array_push(label_addrs, addr);
    label_count = label_count + 1;
    return 0;
}

fn label_find(name: string) -> i32 {
    var i: i32 = 0;
    while i < label_count {
        if str_eq(sp_get(array_get(label_names, i)), name) {
            return array_get(label_addrs, i);
        }
        i = i + 1;
    }
    return 0 - 1;
}

fn patch_add(code_offset: i32, label_name: string) -> i32 {
    array_push(patch_addrs, code_offset);
    array_push(patch_labels, sp_store(label_name));
    patch_count = patch_count + 1;
    return 0;
}

fn patch_resolve() -> i32 {
    var i: i32 = 0;
    var errors: i32 = 0;
    while i < patch_count {
        let lbl: string = sp_get(array_get(patch_labels, i));
        let addr: i32 = label_find(lbl);
        if addr < 0 {
            print("asm error: undefined label: ");
            println(lbl);
            errors = errors + 1;
        } else {
            let slot: i32 = array_get(patch_addrs, i);
            // VM does: ip = (slot+1) + offset, so offset = target - slot - 1
            array_set(code, slot, addr - slot - 1);
        }
        i = i + 1;
    }
    return errors;
}

// ── Assembler ────────────────────────────────────────

fn asm_line(line: string) -> i32 {
    let trimmed: string = str_trim(line);
    if len(trimmed) == 0 { return 0; }

    // Comments
    if char_at(trimmed, 0) == 59 { return 0; }  // ;
    if len(trimmed) >= 2 {
        if char_at(trimmed, 0) == 47 && char_at(trimmed, 1) == 47 {
            return 0;  // //
        }
    }

    // Label definition
    if ends_with_colon(trimmed) {
        let name: string = substr(trimmed, 0, len(trimmed) - 1);
        label_define(name, code_len);
        return 0;
    }

    let cmd: string = first_word(trimmed);

    // Stack operations
    if str_eq(cmd, "push_nil") {
        code_add(OP_PUSH_NIL());
        return 0;
    }
    if str_eq(cmd, "push_i32") {
        let arg: string = second_word(trimmed);
        let n: i32 = parse_int(arg);
        code_add(OP_PUSH_I32());
        code_add(n);
        return 0;
    }
    if str_eq(cmd, "push_bool") {
        let arg: string = second_word(trimmed);
        let v: i32 = parse_int(arg);
        code_add(OP_PUSH_BOOL());
        code_add(v);
        return 0;
    }
    if str_eq(cmd, "push_str") {
        let arg: string = rest_after_word(trimmed);
        let ni: i32 = name_add(arg);
        code_add(OP_PUSH_STR());
        code_add(ni);
        return 0;
    }
    if str_eq(cmd, "push_approx") {
        let val_s: string = second_word(trimmed);
        let conf_s: string = third_word(trimmed);
        code_add(OP_PUSH_APPROX());
        code_add(parse_int(val_s));
        code_add(parse_int(conf_s));
        return 0;
    }
    if str_eq(cmd, "pop") { code_add(OP_POP()); return 0; }
    if str_eq(cmd, "dup") { code_add(OP_DUP()); return 0; }

    // Variables
    if str_eq(cmd, "bind") {
        let arg: string = second_word(trimmed);
        let ni: i32 = name_add(arg);
        code_add(OP_BIND());
        code_add(ni);
        return 0;
    }
    if str_eq(cmd, "bind_approx") {
        let arg: string = second_word(trimmed);
        let conf_s: string = third_word(trimmed);
        let ni: i32 = name_add(arg);
        code_add(OP_BIND_APPROX());
        code_add(ni);
        code_add(parse_int(conf_s));
        return 0;
    }
    if str_eq(cmd, "load") {
        let arg: string = second_word(trimmed);
        let ni: i32 = name_add(arg);
        code_add(OP_LOAD());
        code_add(ni);
        return 0;
    }

    // Arithmetic
    if str_eq(cmd, "add") { code_add(OP_ADD()); return 0; }
    if str_eq(cmd, "sub") { code_add(OP_SUB()); return 0; }
    if str_eq(cmd, "mul") { code_add(OP_MUL()); return 0; }
    if str_eq(cmd, "div") { code_add(OP_DIV()); return 0; }
    if str_eq(cmd, "neg") { code_add(OP_NEG()); return 0; }
    if str_eq(cmd, "mod") { code_add(OP_MOD()); return 0; }

    // Comparison
    if str_eq(cmd, "eq")  { code_add(OP_EQ()); return 0; }
    if str_eq(cmd, "neq") { code_add(OP_NEQ()); return 0; }
    if str_eq(cmd, "lt")  { code_add(OP_LT()); return 0; }
    if str_eq(cmd, "gt")  { code_add(OP_GT()); return 0; }
    if str_eq(cmd, "lte") { code_add(OP_LTE()); return 0; }
    if str_eq(cmd, "gte") { code_add(OP_GTE()); return 0; }

    // Logic
    if str_eq(cmd, "and") { code_add(OP_AND()); return 0; }
    if str_eq(cmd, "or")  { code_add(OP_OR()); return 0; }
    if str_eq(cmd, "not") { code_add(OP_NOT()); return 0; }

    // Control flow
    if str_eq(cmd, "jump") {
        let lbl: string = second_word(trimmed);
        code_add(OP_JUMP());
        let slot: i32 = code_add(0);  // placeholder
        let addr: i32 = label_find(lbl);
        if addr >= 0 {
            // VM does: ip = (slot+1) + offset
            array_set(code, slot, addr - slot - 1);
        } else {
            patch_add(slot, lbl);
        }
        return 0;
    }
    if str_eq(cmd, "jump_if_false") {
        let lbl: string = second_word(trimmed);
        code_add(OP_JUMP_IF_FALSE());
        let slot: i32 = code_add(0);
        let addr: i32 = label_find(lbl);
        if addr >= 0 {
            array_set(code, slot, addr - slot - 1);
        } else {
            patch_add(slot, lbl);
        }
        return 0;
    }
    if str_eq(cmd, "call") {
        let lbl: string = second_word(trimmed);
        code_add(OP_CALL());
        let slot: i32 = code_add(0);
        let addr: i32 = label_find(lbl);
        if addr >= 0 {
            array_set(code, slot, addr - slot - 1);
        } else {
            patch_add(slot, lbl);
        }
        return 0;
    }
    if str_eq(cmd, "return") { code_add(OP_RETURN()); return 0; }
    if str_eq(cmd, "halt") { code_add(OP_HALT()); return 0; }
    if str_eq(cmd, "nop") { code_add(OP_NOP()); return 0; }

    // Temporal
    if str_eq(cmd, "history") {
        let arg: string = second_word(trimmed);
        let ni: i32 = name_add(arg);
        code_add(OP_HISTORY());
        code_add(ni);
        return 0;
    }
    if str_eq(cmd, "reflect") { code_add(OP_REFLECT()); return 0; }
    if str_eq(cmd, "drift")   { code_add(OP_DRIFT()); return 0; }
    if str_eq(cmd, "forget") {
        let arg: string = second_word(trimmed);
        let ni: i32 = name_add(arg);
        code_add(OP_FORGET());
        code_add(ni);
        return 0;
    }
    if str_eq(cmd, "snapshot") { code_add(OP_SNAPSHOT()); return 0; }

    // Persistence
    if str_eq(cmd, "persist") {
        let arg: string = rest_after_word(trimmed);
        let ni: i32 = name_add(arg);
        code_add(OP_PERSIST());
        code_add(ni);
        return 0;
    }
    if str_eq(cmd, "restore_file") {
        let arg: string = rest_after_word(trimmed);
        let ni: i32 = name_add(arg);
        code_add(OP_RESTORE());
        code_add(ni);
        return 0;
    }
    if str_eq(cmd, "restore") { code_add(OP_RESTORE()); code_add(0); return 0; }

    // I/O
    if str_eq(cmd, "print") { code_add(OP_PRINT()); return 0; }
    if str_eq(cmd, "print_hist") {
        let arg: string = second_word(trimmed);
        let ni: i32 = name_add(arg);
        code_add(OP_PRINT_HIST());
        code_add(ni);
        return 0;
    }

    // Unknown instruction
    print("asm error: unknown instruction: ");
    println(cmd);
    return 1;
}

// Assemble full program text into bytecode
fn asm_program(source: string) -> i32 {
    label_init();
    let lines: i32 = split_lines(source);
    var i: i32 = 0;
    var errors: i32 = 0;
    while i < array_len(lines) {
        let line: string = sp_get(array_get(lines, i));
        let err: i32 = asm_line(line);
        if err != 0 {
            print("  at line ");
            println(int_to_str(i + 1));
            errors = errors + 1;
        }
        i = i + 1;
    }
    // Resolve forward references
    let patch_err: i32 = patch_resolve();
    errors = errors + patch_err;
    return errors;
}

// Assemble and run a program from text
fn asm_run(source: string) -> i32 {
    vm_init();
    let errors: i32 = asm_program(source);
    if errors > 0 {
        print("Assembly failed with ");
        print(int_to_str(errors));
        println(" errors");
        return 0 - 1;
    }
    return vm_exec();
}

// ── Tests ────────────────────────────────────────────

var asm_pass: i32 = 0;
var asm_fail: i32 = 0;

fn asm_assert(cond: bool, msg: string) -> i32 {
    if cond {
        asm_pass = asm_pass + 1;
    } else {
        print("FAIL: ");
        println(msg);
        asm_fail = asm_fail + 1;
    }
    return 0;
}

fn test_asm_basic() -> i32 {
    // Simple arithmetic: push 3, push 4, add, print, halt
    let src: string = "push_i32 3\npush_i32 4\nadd\nhalt";
    vm_init();
    let errors: i32 = asm_program(src);
    asm_assert(errors == 0, "basic: no assembly errors");
    vm_exec();
    let result: i32 = stack_pop();
    asm_assert(val_get_int(result) == 7, "basic: 3+4=7");
    return 0;
}

fn test_asm_bind_load() -> i32 {
    let src: string = "push_i32 42\nbind x\nload x\nhalt";
    vm_init();
    asm_program(src);
    vm_exec();
    let result: i32 = stack_pop();
    asm_assert(val_get_int(result) == 42, "bind_load: x=42");
    return 0;
}

fn test_asm_approx() -> i32 {
    let src: string = "push_approx 100 70\nhalt";
    vm_init();
    asm_program(src);
    vm_exec();
    let result: i32 = stack_pop();
    asm_assert(val_get_int(result) == 100, "approx: value=100");
    asm_assert(val_get_conf(result) == 70, "approx: confidence=70");
    return 0;
}

fn test_asm_string() -> i32 {
    let src: string = "push_str hello world\nhalt";
    vm_init();
    asm_program(src);
    vm_exec();
    let result: i32 = stack_pop();
    asm_assert(str_eq(val_get_str(result), "hello world"), "string: push_str");
    return 0;
}

fn test_asm_compare() -> i32 {
    let src: string = "push_i32 5\npush_i32 3\ngt\nhalt";
    vm_init();
    asm_program(src);
    vm_exec();
    let result: i32 = stack_pop();
    asm_assert(val_get_int(result) == 1, "compare: 5>3 is true");
    return 0;
}

fn test_asm_logic() -> i32 {
    let src: string = "push_bool 1\npush_bool 0\nor\nhalt";
    vm_init();
    asm_program(src);
    vm_exec();
    let result: i32 = stack_pop();
    asm_assert(val_get_int(result) == 1, "logic: true OR false = true");
    return 0;
}

fn test_asm_labels() -> i32 {
    // jump over a push, verify only the second push is on stack
    let src: string = "jump skip\npush_i32 99\nskip:\npush_i32 42\nhalt";
    vm_init();
    asm_program(src);
    vm_exec();
    let result: i32 = stack_pop();
    asm_assert(val_get_int(result) == 42, "labels: jumped to 42");
    asm_assert(stack_top == 0, "labels: 99 was skipped");
    return 0;
}

fn test_asm_loop() -> i32 {
    // count from 0 to 5 using a loop
    // x = 0; while x < 5: x = x + 1; result: x = 5
    let src: string = str_concat("push_i32 0\nbind x\n", str_concat(
        "loop:\nload x\npush_i32 5\nlt\njump_if_false done\n",
        "load x\npush_i32 1\nadd\nbind x\njump loop\ndone:\nhalt"));
    vm_init();
    asm_program(src);
    vm_exec();
    let xval: i32 = env_load("x");
    asm_assert(val_get_int(xval) == 5, "loop: x counted to 5");
    return 0;
}

fn test_asm_timeline() -> i32 {
    // bind x multiple times, verify timeline via env
    let src: string = "push_i32 10\nbind x\npush_i32 20\nbind x\npush_i32 30\nbind x\nhistory x\nhalt";
    vm_init();
    asm_program(src);
    vm_exec();
    // HISTORY prints timeline, doesn't push. Check env directly.
    let xval: i32 = env_load("x");
    asm_assert(val_get_int(xval) == 30, "timeline: x latest = 30");
    return 0;
}

fn test_asm_forget() -> i32 {
    // REFLECT prints stats, doesn't push. Just verify forget doesn't crash.
    let src: string = "push_i32 42\nbind y\nforget y\nreflect\nhalt";
    vm_init();
    asm_program(src);
    vm_exec();
    asm_assert(!vm_error, "forget: no runtime error");
    return 0;
}

fn test_asm_comments() -> i32 {
    let src: string = "; this is a comment\n// another comment\npush_i32 7\n; skip\nhalt";
    vm_init();
    let errors: i32 = asm_program(src);
    asm_assert(errors == 0, "comments: no errors");
    vm_exec();
    let result: i32 = stack_pop();
    asm_assert(val_get_int(result) == 7, "comments: got 7");
    return 0;
}

fn test_asm_sub_mul() -> i32 {
    let src: string = "push_i32 10\npush_i32 3\nsub\npush_i32 4\nmul\nhalt";
    vm_init();
    asm_program(src);
    vm_exec();
    let result: i32 = stack_pop();
    asm_assert(val_get_int(result) == 28, "sub_mul: (10-3)*4=28");
    return 0;
}

fn test_asm_cond_jump() -> i32 {
    // if false, jump to else
    let src: string = str_concat("push_bool 0\njump_if_false else_branch\n",
        str_concat("push_i32 1\njump end\nelse_branch:\npush_i32 2\n", "end:\nhalt"));
    vm_init();
    asm_program(src);
    vm_exec();
    let result: i32 = stack_pop();
    asm_assert(val_get_int(result) == 2, "cond_jump: took else branch");
    return 0;
}

fn test_asm_multi_bind() -> i32 {
    // Multiple variables
    let src: string = "push_i32 10\nbind a\npush_i32 20\nbind b\nload a\nload b\nadd\nhalt";
    vm_init();
    asm_program(src);
    vm_exec();
    let result: i32 = stack_pop();
    asm_assert(val_get_int(result) == 30, "multi_bind: a+b=30");
    return 0;
}

fn test_asm_approx_prop() -> i32 {
    // Confidence propagation: approx 80% + approx 60% => min(80,60) = 60%
    let src: string = "push_approx 10 80\npush_approx 20 60\nadd\nhalt";
    vm_init();
    asm_program(src);
    vm_exec();
    let result: i32 = stack_pop();
    asm_assert(val_get_int(result) == 30, "approx_prop: 10+20=30");
    asm_assert(val_get_conf(result) == 60, "approx_prop: min(80,60)=60");
    return 0;
}

fn test_asm_file() -> i32 {
    // Write a .masm file, read it, assemble and run
    let src: string = "; test program\npush_i32 6\npush_i32 7\nmul\nhalt\n";
    write_file("_test_prog.masm", src);
    let content: string = read_file("_test_prog.masm");
    vm_init();
    let errors: i32 = asm_program(content);
    asm_assert(errors == 0, "file: no assembly errors");
    vm_exec();
    let result: i32 = stack_pop();
    asm_assert(val_get_int(result) == 42, "file: 6*7=42");
    return 0;
}

fn test_asm_snapshot() -> i32 {
    let src: string = "push_i32 10\nbind x\nsnapshot\npush_i32 20\nbind x\nhalt";
    vm_init();
    asm_program(src);
    vm_exec();
    let before_rollback: i32 = env_load("x");
    asm_assert(val_get_int(before_rollback) == 20, "snapshot: x=20 before rollback");
    vm_rollback();
    let after_rollback: i32 = env_load("x");
    asm_assert(val_get_int(after_rollback) == 10, "snapshot: x=10 after rollback");
    return 0;
}

fn test_asm_neg_mod() -> i32 {
    let src: string = "push_i32 7\nneg\nhalt";
    vm_init();
    asm_program(src);
    vm_exec();
    let result: i32 = stack_pop();
    asm_assert(val_get_int(result) == 0 - 7, "neg: -7");

    let src2: string = "push_i32 17\npush_i32 5\nmod\nhalt";
    vm_init();
    asm_program(src2);
    vm_exec();
    let r2: i32 = stack_pop();
    asm_assert(val_get_int(r2) == 2, "mod: 17%5=2");
    return 0;
}

fn test_asm_drift() -> i32 {
    // DRIFT prints stats, doesn't push. Verify no crash.
    let src: string = "push_i32 1\nbind a\npush_i32 2\nbind b\ndrift\nhalt";
    vm_init();
    asm_program(src);
    vm_exec();
    asm_assert(!vm_error, "drift: no runtime error");
    return 0;
}

// ── Main ─────────────────────────────────────────────

fn main() -> i32 {
    // File mode: assemble and run a .masm file
    if argc() >= 2 {
        let path: string = argv(1);
        let source: string = read_file(path);
        if len(source) == 0 {
            print("error: cannot read file: ");
            println(path);
            return 1;
        }
        let result: i32 = asm_run(source);
        return result;
    }

    // Test mode
    println("Machine Assembler — test suite");
    println("==============================");

    test_asm_basic();
    println(str_concat("  basic: ", int_to_str(asm_pass)));

    test_asm_bind_load();
    println(str_concat("  bind_load: ", int_to_str(asm_pass)));

    test_asm_approx();
    println(str_concat("  approx: ", int_to_str(asm_pass)));

    test_asm_string();
    println(str_concat("  string: ", int_to_str(asm_pass)));

    test_asm_compare();
    println(str_concat("  compare: ", int_to_str(asm_pass)));

    test_asm_logic();
    println(str_concat("  logic: ", int_to_str(asm_pass)));

    test_asm_labels();
    println(str_concat("  labels: ", int_to_str(asm_pass)));

    test_asm_loop();
    println(str_concat("  loop: ", int_to_str(asm_pass)));

    test_asm_timeline();
    println(str_concat("  timeline: ", int_to_str(asm_pass)));

    test_asm_forget();
    println(str_concat("  forget: ", int_to_str(asm_pass)));

    test_asm_comments();
    println(str_concat("  comments: ", int_to_str(asm_pass)));

    test_asm_sub_mul();
    println(str_concat("  sub_mul: ", int_to_str(asm_pass)));

    test_asm_cond_jump();
    println(str_concat("  cond_jump: ", int_to_str(asm_pass)));

    test_asm_multi_bind();
    println(str_concat("  multi_bind: ", int_to_str(asm_pass)));

    test_asm_approx_prop();
    println(str_concat("  approx_prop: ", int_to_str(asm_pass)));

    test_asm_file();
    println(str_concat("  file: ", int_to_str(asm_pass)));

    test_asm_snapshot();
    println(str_concat("  snapshot: ", int_to_str(asm_pass)));

    test_asm_neg_mod();
    println(str_concat("  neg_mod: ", int_to_str(asm_pass)));

    test_asm_drift();
    println(str_concat("  drift: ", int_to_str(asm_pass)));

    println("==============================");
    print(int_to_str(asm_pass));
    print("/");
    print(int_to_str(asm_pass + asm_fail));
    println(" tests passed");

    if asm_fail > 0 {
        println("SOME TESTS FAILED");
        return 1;
    }

    println("ALL TESTS PASSED");
    return 0;
}
