// Machine Mind — Test Suite
// Tests the consciousness substrate: predict, perceive, measure, decide.
//
// Usage: mc.exe self_codegen.m machine_mind_test.m

use "machine_vm.m"
use "machine_analyze.m"
use "machine_mind.m"

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

fn assert_true(label: string, value: bool) {
    test_total = test_total + 1;
    if value {
        test_pass = test_pass + 1;
    } else {
        test_fail = test_fail + 1;
        print("FAIL: ");
        println(label);
    }
}

fn assert_gt(label: string, value: i32, threshold: i32) {
    test_total = test_total + 1;
    if value > threshold {
        test_pass = test_pass + 1;
    } else {
        test_fail = test_fail + 1;
        print("FAIL: ");
        print(label);
        print(" value ");
        print(int_to_str(value));
        print(" not > ");
        println(int_to_str(threshold));
    }
}

fn assert_gte(label: string, value: i32, threshold: i32) {
    test_total = test_total + 1;
    if value >= threshold {
        test_pass = test_pass + 1;
    } else {
        test_fail = test_fail + 1;
        print("FAIL: ");
        print(label);
        print(" value ");
        print(int_to_str(value));
        print(" not >= ");
        println(int_to_str(threshold));
    }
}

fn assert_lt(label: string, value: i32, threshold: i32) {
    test_total = test_total + 1;
    if value < threshold {
        test_pass = test_pass + 1;
    } else {
        test_fail = test_fail + 1;
        print("FAIL: ");
        print(label);
        print(" value ");
        print(int_to_str(value));
        print(" not < ");
        println(int_to_str(threshold));
    }
}

fn assert_range(label: string, value: i32, lo: i32, hi: i32) {
    test_total = test_total + 1;
    if value >= lo && value <= hi {
        test_pass = test_pass + 1;
    } else {
        test_fail = test_fail + 1;
        print("FAIL: ");
        print(label);
        print(" value ");
        print(int_to_str(value));
        print(" not in [");
        print(int_to_str(lo));
        print(",");
        print(int_to_str(hi));
        println("]");
    }
}

// ── Tests ──────────────────────────────────────────────

fn test_mind_init() {
    println("  test_mind_init");
    vm_init();
    mind_init();

    assert_eq_i("cycle starts at 0", 0, mind_get_cycle());
    assert_eq_i("competence starts at 50", 50, mind_get_competence());
    assert_eq_i("no files known", 0, mind_get_file_count());
    assert_eq_i("no predictions yet", 0, mind_get_total_preds());
    assert_true("initialized flag", mind_initialized);

    // Check temporal bindings exist
    let slot: i32 = env_find("mind.cycle");
    assert_true("mind.cycle bound", slot >= 0);
    let comp_slot: i32 = env_find("mind.competence");
    assert_true("mind.competence bound", comp_slot >= 0);
}

fn test_mind_seed() {
    println("  test_mind_seed");
    vm_init();
    mind_init();

    let added1: bool = mind_seed("examples/machine_vm.m");
    assert_true("first seed accepted", added1);
    assert_eq_i("file count 1", 1, mind_get_file_count());

    let added2: bool = mind_seed("examples/machine_asm.m");
    assert_true("second seed accepted", added2);
    assert_eq_i("file count 2", 2, mind_get_file_count());

    // Duplicate rejected
    let dup: bool = mind_seed("examples/machine_vm.m");
    assert_true("duplicate rejected", !dup);
    assert_eq_i("still 2 files", 2, mind_get_file_count());

    // Check path retrieval
    assert_true("path 0", str_eq(mind_file_path(0), "examples/machine_vm.m"));
    assert_true("path 1", str_eq(mind_file_path(1), "examples/machine_asm.m"));
}

fn test_mind_predict() {
    println("  test_mind_predict");
    vm_init();
    mind_init();
    mind_seed("examples/machine_vm.m");

    mind_predict(0);

    // Prediction should exist with uncertainty
    let pred_name: string = "mind.pred.examples/machine_vm.m.funcs";
    let slot: i32 = env_find(pred_name);
    assert_true("prediction bound", slot >= 0);

    if slot >= 0 {
        let vid: i32 = env_load(pred_name);
        let conf: i32 = val_get_conf(vid);
        assert_lt("low initial confidence", conf, 100);
        assert_gt("prediction > 0", val_get_int(vid), 0);
    }
}

fn test_mind_perceive() {
    println("  test_mind_perceive");
    vm_init();
    mind_init();
    mind_seed("examples/machine_vm.m");

    let funcs: i32 = mind_perceive(0);
    assert_gt("perceived functions > 0", funcs, 0);
    assert_true("file marked analyzed", mind_is_analyzed(0));

    // Facts should be certain (conf=100)
    let fact_name: string = "mind.fact.examples/machine_vm.m.funcs";
    let slot: i32 = env_find(fact_name);
    assert_true("fact bound", slot >= 0);
    if slot >= 0 {
        let vid: i32 = env_load(fact_name);
        assert_eq_i("fact is certain", 100, val_get_conf(vid));
    }
}

fn test_mind_measure() {
    println("  test_mind_measure");
    vm_init();
    mind_init();
    mind_seed("examples/machine_vm.m");

    mind_predict(0);
    mind_perceive(0);
    let error: i32 = mind_measure(0);

    // Error should be a percentage (0-100)
    assert_gte("error >= 0", error, 0);
    assert_lt("error <= 100", error, 101);

    // After measurement, competence should be set
    let comp: i32 = mind_get_competence();
    assert_gte("competence >= 0", comp, 0);
    assert_lt("competence <= 100", comp, 101);

    // Total predictions should be 1
    assert_eq_i("one prediction", 1, mind_get_total_preds());
}

fn test_mind_decide_explore() {
    println("  test_mind_decide_explore");
    vm_init();
    mind_init();
    mind_seed("examples/machine_vm.m");

    // Unexplored file → should decide to explore
    let action: i32 = mind_decide();
    assert_eq_i("decide explore", ACT_EXPLORE(), action);

    // Target should be file 0
    assert_eq_i("target is 0", 0, mind_get_last_target());
}

fn test_mind_decide_after_explore() {
    println("  test_mind_decide_after_explore");
    vm_init();
    mind_init();
    // Use hello.m — standalone file with no use directives (no auto-discovery)
    mind_seed("examples/hello.m");

    // Explore the only file
    mind_act_explore(0);

    // After exploring a file with no deps: should NOT explore
    // (no new files discovered, original file already analyzed)
    let action: i32 = mind_decide();
    assert_true("not explore after complete",
                action != ACT_EXPLORE());
    // Should be one of the valid post-exploration actions
    assert_true("valid action",
                action == ACT_IDLE() || action == ACT_REPREDICT() || action == ACT_CONSOLIDATE());
}

fn test_mind_one_cycle() {
    println("  test_mind_one_cycle");
    vm_init();
    mind_init();
    mind_seed("examples/machine_asm.m");

    let error: i32 = mind_one_cycle();

    // Cycle should have incremented
    assert_eq_i("cycle is 1", 1, mind_get_cycle());
    // File should be analyzed
    assert_true("file analyzed", mind_is_analyzed(0));
    // One prediction made
    assert_eq_i("one prediction", 1, mind_get_total_preds());
}

fn test_mind_run_multiple() {
    println("  test_mind_run_multiple");
    vm_init();
    mind_init();
    mind_seed("examples/machine_vm.m");
    mind_seed("examples/machine_asm.m");

    let cycles: i32 = mind_run(10);

    // Should have explored both files, then consolidated, then idled
    assert_gte("at least 2 cycles", cycles, 2);
    assert_true("vm analyzed", mind_is_analyzed(0));
    assert_true("asm analyzed", mind_is_analyzed(1));
    assert_eq_i("all files analyzed", 2, mind_count_analyzed());
}

fn test_mind_learning() {
    println("  test_mind_learning");
    vm_init();
    mind_init();

    // Seed multiple files
    mind_seed("examples/machine_vm.m");
    mind_seed("examples/machine_asm.m");

    // After first file: prediction is naive
    mind_predict(0);
    mind_perceive(0);
    let error1: i32 = mind_measure(0);

    // After second file: prediction should use learned density
    mind_predict(1);
    mind_perceive(1);
    let error2: i32 = mind_measure(1);

    // We expect the model to EXIST (density_count > 0 after first file)
    assert_gt("density learned", mind_density_count, 0);
    assert_gt("total preds is 2", mind_get_total_preds(), 1);
}

fn test_mind_temporal() {
    println("  test_mind_temporal");
    vm_init();
    mind_init();
    mind_seed("examples/machine_vm.m");
    mind_seed("examples/machine_asm.m");

    // Run cycles — this will update mind.competence multiple times
    mind_run(5);

    // Check that competence has a timeline (multiple entries)
    let tl_id: i32 = env_get_timeline("mind.competence");
    assert_true("competence has timeline", tl_id >= 0);
    if tl_id >= 0 {
        let n: i32 = tl_length(tl_id);
        assert_gt("timeline has entries", n, 1);
    }

    // Check cycle timeline
    let cycle_tl: i32 = env_get_timeline("mind.cycle");
    assert_true("cycle has timeline", cycle_tl >= 0);
    if cycle_tl >= 0 {
        let n: i32 = tl_length(cycle_tl);
        assert_gt("cycle timeline grew", n, 1);
    }
}

fn test_mind_autodiscover() {
    println("  test_mind_autodiscover");
    vm_init();
    mind_init();

    // Seed the REPL which uses machine_vm.m and machine_analyze.m
    mind_seed("examples/machine_repl.m");
    mind_act_explore(0);

    // After exploring, the mind should have discovered dependencies
    // machine_repl.m uses machine_vm.m and machine_analyze.m
    assert_gt("discovered files", mind_get_file_count(), 1);
}

fn test_mind_consolidation() {
    println("  test_mind_consolidation");
    vm_init();
    mind_init();
    mind_seed("examples/machine_vm.m");
    mind_seed("examples/machine_asm.m");

    // Analyze both
    mind_act_explore(0);
    mind_act_explore(1);

    // Consolidate
    mind_act_consolidate();

    // Pattern bindings should exist
    let slot: i32 = env_find("mind.pattern.small_files");
    assert_true("pattern.small bound", slot >= 0);
    let slot2: i32 = env_find("mind.pattern.medium_files");
    assert_true("pattern.medium bound", slot2 >= 0);
    let slot3: i32 = env_find("mind.pattern.avg_health");
    assert_true("pattern.avg_health bound", slot3 >= 0);
}

fn test_mind_status() {
    println("  test_mind_status");
    vm_init();
    mind_init();
    mind_seed("examples/machine_asm.m");
    mind_run(3);

    let status: string = mind_status_line();
    assert_gt("status not empty", len(status), 10);
}

fn test_mind_path_resolve() {
    println("  test_mind_path_resolve");
    vm_init();
    mind_init();

    let resolved: string = mind_resolve_path("examples/machine_repl.m", "machine_vm.m");
    assert_true("resolved path", str_eq(resolved, "examples/machine_vm.m"));

    let no_dir: string = mind_resolve_path("file.m", "other.m");
    assert_true("no dir path", str_eq(no_dir, "other.m"));
}

fn test_mind_vm_bindings() {
    println("  test_mind_vm_bindings");
    vm_init();
    mind_init();
    mind_seed("examples/machine_asm.m");
    mind_run(3);

    // All key bindings should exist
    assert_true("mind.cycle exists", env_find("mind.cycle") >= 0);
    assert_true("mind.competence exists", env_find("mind.competence") >= 0);
    assert_true("mind.files_known exists", env_find("mind.files_known") >= 0);
    assert_true("mind.files_analyzed exists", env_find("mind.files_analyzed") >= 0);
    assert_true("mind.decision exists", env_find("mind.decision") >= 0);

    // Verify values make sense
    let cycle_val: i32 = val_get_int(env_load("mind.cycle"));
    assert_gt("cycle > 0", cycle_val, 0);

    let known_val: i32 = val_get_int(env_load("mind.files_known"));
    assert_gt("files known > 0", known_val, 0);
}

fn test_mind_competence_after_run() {
    println("  test_mind_competence_after_run");
    vm_init();
    mind_init();
    mind_seed("examples/machine_vm.m");
    mind_seed("examples/machine_asm.m");
    mind_seed("examples/machine_analyze.m");

    mind_run(10);

    // After analyzing 3 diverse files, competence should be reasonable
    let comp: i32 = mind_get_competence();
    assert_gte("competence >= 0", comp, 0);
    assert_lt("competence <= 100", comp, 101);
    // With naive predictions, we expect some error, but not catastrophic
    let avg_err: i32 = mind_get_avg_error();
    assert_lt("avg error < 80", avg_err, 80);
}

// ── Main ───────────────────────────────────────────────

fn main() -> i32 {
    println("Machine Mind — Test Suite");
    println("=========================");

    test_mind_init();
    test_mind_seed();
    test_mind_predict();
    test_mind_perceive();
    test_mind_measure();
    test_mind_decide_explore();
    test_mind_decide_after_explore();
    test_mind_one_cycle();
    test_mind_run_multiple();
    test_mind_learning();
    test_mind_temporal();
    test_mind_autodiscover();
    test_mind_consolidation();
    test_mind_status();
    test_mind_path_resolve();
    test_mind_vm_bindings();
    test_mind_competence_after_run();

    println("");
    print("Results: ");
    print(int_to_str(test_pass));
    print("/");
    print(int_to_str(test_total));
    println(" passed");

    if test_fail > 0 {
        print("FAILURES: ");
        println(int_to_str(test_fail));
        return 1;
    }

    println("ALL TESTS PASSED");
    return 0;
}
