// Machine Analyze — Test Suite
// Tests the M source code analyzer.
//
// Usage: mc.exe self_codegen.m machine_analyze_test.m

use "machine_vm.m"
use "machine_analyze.m"

var test_pass: i32 = 0;
var test_fail: i32 = 0;
var test_total: i32 = 0;

fn assert_eq_i(label: string, expected: i32, actual: i32) {
    test_total = test_total + 1;
    if expected == actual {
        test_pass = test_pass + 1;
    } else {
        test_fail = test_fail + 1;
        print("FAIL: ");
        print(label);
        print(" expected ");
        print(int_to_str(expected));
        print(" got ");
        println(int_to_str(actual));
    }
}

fn assert_eq_s(label: string, expected: string, actual: string) {
    test_total = test_total + 1;
    if str_eq(expected, actual) {
        test_pass = test_pass + 1;
    } else {
        test_fail = test_fail + 1;
        print("FAIL: ");
        print(label);
        print(" expected '");
        print(expected);
        print("' got '");
        print(actual);
        println("'");
    }
}

fn assert_true(label: string, val: bool) {
    test_total = test_total + 1;
    if val {
        test_pass = test_pass + 1;
    } else {
        test_fail = test_fail + 1;
        print("FAIL: ");
        println(label);
    }
}

// ── Test: Analyze machine_vm.m ───────────────────────

fn test_analyze_vm() {
    println("-- test_analyze_vm --");
    vm_init();
    let r: i32 = analyze_file("examples/machine_vm.m");
    assert_eq_i("analyze_file returns 0", 0, r);
    assert_eq_s("file name", "examples/machine_vm.m", ana_get_file());
    assert_true("lines > 1000", ana_get_lines() > 1000);
    assert_true("funcs >= 90", ana_get_func_count() >= 90);
    assert_true("globals > 20", ana_get_global_count() > 20);
}

fn test_func_lookup() {
    println("-- test_func_lookup --");
    let idx: i32 = ana_find_func("vm_exec");
    assert_true("vm_exec found", idx >= 0);
    assert_true("vm_exec lines > 300", ana_func_lines(idx) > 300);
    assert_eq_i("vm_exec params", 0, ana_func_params(idx));
    assert_true("vm_exec calls > 50", ana_func_call_count(idx) > 50);
}

fn test_func_not_found() {
    println("-- test_func_not_found --");
    let idx: i32 = ana_find_func("nonexistent_xyz_123");
    assert_eq_i("nonexistent returns -1", 0 - 1, idx);
}

fn test_small_funcs() {
    println("-- test_small_funcs --");
    // OP_NOP should be 1-line function
    let idx: i32 = ana_find_func("OP_NOP");
    assert_true("OP_NOP found", idx >= 0);
    assert_eq_i("OP_NOP lines", 1, ana_func_lines(idx));
    assert_eq_i("OP_NOP params", 0, ana_func_params(idx));
}

fn test_params() {
    println("-- test_params --");
    let idx: i32 = ana_find_func("env_bind");
    assert_true("env_bind found", idx >= 0);
    assert_eq_i("env_bind params", 4, ana_func_params(idx));

    let idx2: i32 = ana_find_func("val_i32");
    assert_true("val_i32 found", idx2 >= 0);
    assert_eq_i("val_i32 params", 1, ana_func_params(idx2));
}

fn test_call_graph() {
    println("-- test_call_graph --");
    let idx: i32 = ana_find_func("env_bind");
    assert_true("env_bind has calls", ana_func_call_count(idx) > 0);

    // Check that env_bind calls env_find
    var found_env_find: bool = false;
    var i: i32 = 0;
    while i < ana_func_call_count(idx) {
        if str_eq(ana_func_call_name(idx, i), "env_find") {
            found_env_find = true;
        }
        i = i + 1;
    }
    assert_true("env_bind calls env_find", found_env_find);
}

fn test_vm_population() {
    println("-- test_vm_population --");
    vm_init();
    analyze_file("examples/machine_vm.m");
    ana_populate_vm();

    // Check bindings exist
    let slot: i32 = env_find("_funcs");
    assert_true("_funcs binding exists", slot >= 0);

    let vid: i32 = env_load("_funcs");
    assert_true("_funcs value >= 90", val_get_int(vid) >= 90);

    // Check function-level binding
    let vm_slot: i32 = env_find("fn.vm_exec.lines");
    assert_true("fn.vm_exec.lines exists", vm_slot >= 0);
    let vm_vid: i32 = env_load("fn.vm_exec.lines");
    assert_true("vm_exec lines > 300", val_get_int(vm_vid) > 300);
}

fn test_temporal_reanalyze() {
    println("-- test_temporal_reanalyze --");
    vm_init();

    // First analysis
    analyze_file("examples/machine_vm.m");
    ana_populate_vm();
    let v1: i32 = val_get_int(env_load("_funcs"));

    // Second analysis (different file)
    analyze_file("examples/machine_asm.m");
    ana_populate_vm();
    let v2: i32 = val_get_int(env_load("_funcs"));

    // Values should differ
    assert_true("different func counts", v1 != v2);

    // Timeline should have 2 entries
    let tl: i32 = env_get_timeline("_funcs");
    assert_eq_i("_funcs timeline length", 2, tl_length(tl));

    // First entry should be machine_vm.m count
    let first_vid: i32 = tl_get_val(tl, 0);
    assert_eq_i("first analysis func count", v1, val_get_int(first_vid));
}

fn test_analyze_self() {
    println("-- test_analyze_self --");
    vm_init();
    let r: i32 = analyze_file("examples/machine_analyze.m");
    assert_eq_i("analyze self returns 0", 0, r);
    assert_true("self has funcs", ana_get_func_count() > 20);
    assert_true("self has globals", ana_get_global_count() > 5);

    // Check that ana_populate_vm is found
    let idx: i32 = ana_find_func("ana_populate_vm");
    assert_true("ana_populate_vm found", idx >= 0);
}

fn test_metrics() {
    println("-- test_metrics --");
    analyze_file("examples/machine_vm.m");
    assert_true("avg lines > 0", ana_avg_func_lines() > 0);
    assert_true("max lines > 100", ana_max_func_lines() > 100);
    assert_eq_s("max func is vm_exec", "vm_exec", ana_max_func_name());
}

// NOTE: test_missing_file skipped — read_file is a fatal VM error for nonexistent files

fn test_analyze_asm() {
    println("-- test_analyze_asm --");
    vm_init();
    let r: i32 = analyze_file("examples/machine_asm.m");
    assert_eq_i("analyze asm returns 0", 0, r);
    assert_true("asm has funcs", ana_get_func_count() > 10);

    // Check use directive detected
    assert_true("asm uses machine_vm.m", ana_get_use_count() > 0);
    assert_eq_s("first use path", "machine_vm.m", ana_use_path(0));
}

// ── Tests: Cross-file dependency analysis ───────────

fn test_get_dir() {
    println("-- test_get_dir --");
    assert_eq_s("dir of path with /", "examples/", ana_get_dir("examples/foo.m"));
    assert_eq_s("dir of bare file", "", ana_get_dir("foo.m"));
    assert_eq_s("dir of nested", "a/b/c/", ana_get_dir("a/b/c/d.m"));
}

fn test_resolve_deps_single() {
    println("-- test_resolve_deps_single --");
    vm_init();
    ana_multi_init();
    // machine_vm.m has no use directives -> only 1 file
    let n: i32 = ana_resolve_deps("examples/machine_vm.m");
    assert_eq_i("resolve_deps returns 1", 1, n);
    assert_eq_i("all_file_count", 1, ana_all_file_count);
    assert_eq_s("first file", "examples/machine_vm.m", ana_all_file_path(0));
    assert_true("func total > 90", ana_all_func_total >= 90);
}

fn test_resolve_deps_asm() {
    println("-- test_resolve_deps_asm --");
    vm_init();
    ana_multi_init();
    // machine_asm.m uses machine_vm.m -> 2 files
    let n: i32 = ana_resolve_deps("examples/machine_asm.m");
    assert_eq_i("resolve_deps returns 2", 2, n);
    assert_eq_i("all_file_count", 2, ana_all_file_count);

    // First file analyzed is machine_asm.m (entry point)
    assert_eq_s("file 0 is asm", "examples/machine_asm.m", ana_all_file_path(0));
    // Second is machine_vm.m (its dependency)
    assert_eq_s("file 1 is vm", "examples/machine_vm.m", ana_all_file_path(1));

    // Total functions should be sum of both
    let asm_fns: i32 = ana_all_file_func_count(0);
    let vm_fns: i32 = ana_all_file_func_count(1);
    assert_true("asm has funcs", asm_fns > 10);
    assert_true("vm has funcs", vm_fns >= 90);
    assert_eq_i("total = sum", asm_fns + vm_fns, ana_all_func_total);
}

fn test_resolve_deps_repl() {
    println("-- test_resolve_deps_repl --");
    vm_init();
    ana_multi_init();
    // machine_repl.m uses machine_vm.m + machine_analyze.m -> 3 files
    let n: i32 = ana_resolve_deps("examples/machine_repl.m");
    assert_eq_i("resolve_deps returns 3", 3, n);
    assert_eq_i("all_file_count", 3, ana_all_file_count);
    assert_true("total funcs across 3 files", ana_all_func_total > 100);
}

fn test_resolve_deps_no_dup() {
    println("-- test_resolve_deps_no_dup --");
    vm_init();
    ana_multi_init();
    // Resolve asm first (pulls in vm), then resolve repl (uses vm + analyze).
    // vm should not be duplicated.
    ana_resolve_deps("examples/machine_asm.m");
    let before: i32 = ana_all_file_count;
    ana_resolve_deps("examples/machine_repl.m");
    // repl adds itself + analyze (vm already present)
    assert_eq_i("no dup: added 2 more", before + 2, ana_all_file_count);
}

fn test_who_defines() {
    println("-- test_who_defines --");
    vm_init();
    ana_multi_init();
    ana_resolve_deps("examples/machine_asm.m");
    // vm_exec is defined in machine_vm.m
    assert_eq_s("vm_exec in vm", "examples/machine_vm.m", ana_who_defines("vm_exec"));
    // asm_line is defined in machine_asm.m
    assert_eq_s("asm_line in asm", "examples/machine_asm.m", ana_who_defines("asm_line"));
    // nonexistent
    assert_eq_s("unknown returns empty", "", ana_who_defines("no_such_fn_xyz"));
}

fn test_external_calls() {
    println("-- test_external_calls --");
    vm_init();
    ana_multi_init();
    ana_resolve_deps("examples/machine_asm.m");
    // Re-analyze asm to get single-file call data loaded
    analyze_file("examples/machine_asm.m");

    // asm_run calls vm_init() and vm_exec() from machine_vm.m
    let idx: i32 = ana_find_func("asm_run");
    assert_true("asm_run found", idx >= 0);
    let ext: i32 = ana_external_calls(idx);
    assert_true("asm_run has external calls", array_len(ext) > 0);

    // Verify that at least one external call points to machine_vm.m
    var found_vm_call: bool = false;
    var i: i32 = 0;
    while i < array_len(ext) {
        let cname: string = sp_get(array_get(ext, i));
        let definer: string = ana_who_defines(cname);
        if str_eq(definer, "examples/machine_vm.m") {
            found_vm_call = true;
        }
        i = i + 1;
    }
    assert_true("ext call to vm file", found_vm_call);
}

fn test_file_func_names() {
    println("-- test_file_func_names --");
    vm_init();
    ana_multi_init();
    ana_resolve_deps("examples/machine_asm.m");
    // Check that we can read function names from the vm file (index 1)
    let vm_fi: i32 = ana_file_index("examples/machine_vm.m");
    assert_true("vm file found in multi", vm_fi >= 0);
    let fc: i32 = ana_all_file_func_count(vm_fi);
    assert_true("vm file has funcs", fc >= 90);
    // First function in machine_vm.m should be OP_NOP
    assert_eq_s("first vm func", "OP_NOP", ana_all_file_func_name(vm_fi, 0));
}

// ── Tests: Complexity scoring ────────────────────────

fn test_complexity_scores() {
    println("-- test_complexity_scores --");
    vm_init();
    analyze_file("examples/machine_vm.m");

    // OP_NOP: 1-line, no calls, no params -> low complexity
    let nop_idx: i32 = ana_find_func("OP_NOP");
    assert_true("OP_NOP complexity < 20", ana_func_complexity(nop_idx) < 20);

    // vm_exec: 411 lines, 72 calls -> high complexity
    let exec_idx: i32 = ana_find_func("vm_exec");
    assert_true("vm_exec complexity > 80", ana_func_complexity(exec_idx) > 80);

    // Confidence: small func = lower confidence, medium = higher
    let nop_conf: i32 = ana_func_complexity_conf(nop_idx);
    let bind_idx: i32 = ana_find_func("env_bind");
    let bind_conf: i32 = ana_func_complexity_conf(bind_idx);
    assert_true("OP_NOP conf <= 60", nop_conf <= 60);
    assert_true("env_bind conf >= 80", bind_conf >= 80);

    // vm_exec: huge -> reduced confidence
    let exec_conf: i32 = ana_func_complexity_conf(exec_idx);
    assert_true("vm_exec conf < 80", exec_conf < 80);
}

fn test_complexity_vm_binding() {
    println("-- test_complexity_vm_binding --");
    vm_init();
    analyze_file("examples/machine_vm.m");
    ana_populate_complexity();

    // Check that complexity bindings exist as approximate values
    let slot: i32 = env_find("fn.vm_exec.complexity");
    assert_true("complexity binding exists", slot >= 0);

    let vid: i32 = env_load("fn.vm_exec.complexity");
    let conf: i32 = val_get_conf(vid);
    assert_true("complexity is approximate", conf < 100);
    assert_true("complexity value > 80", val_get_int(vid) > 80);
}

// ── Run all tests ────────────────────────────────────

fn main() -> i32 {
    test_analyze_vm();
    test_func_lookup();
    test_func_not_found();
    test_small_funcs();
    test_params();
    test_call_graph();
    test_vm_population();
    test_temporal_reanalyze();
    test_analyze_self();
    test_metrics();
    test_analyze_asm();

    // Cross-file dependency tests
    test_get_dir();
    test_resolve_deps_single();
    test_resolve_deps_asm();
    test_resolve_deps_repl();
    test_resolve_deps_no_dup();
    test_who_defines();
    test_external_calls();
    test_file_func_names();

    // Complexity tests
    test_complexity_scores();
    test_complexity_vm_binding();

    println("==============================");
    print(int_to_str(test_pass));
    print("/");
    print(int_to_str(test_total));
    println(" tests passed");
    if test_fail > 0 {
        print("FAILED: ");
        println(int_to_str(test_fail));
    } else {
        println("ALL TESTS PASSED");
    }

    return test_fail;
}
