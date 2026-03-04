// Machine Mind — Inner loop for autonomous cognition
// The consciousness substrate: perceive, predict, measure, decide.
//
// Not a tool that responds to commands.
// A process that observes, forms beliefs, tests them, and learns.
//
// Requires: machine_vm.m, machine_analyze.m (included by caller)
//
// Usage:
//   From REPL: think [N]     — run N cycles of autonomous cognition
//   From REPL: mind          — show mind status
//   Test: mc.exe self_codegen.m machine_mind_test.m

// ── Mind state ─────────────────────────────────────────

var mind_files: i32 = 0;         // array of string pool indices (file paths)
var mind_file_count: i32 = 0;
var mind_analyzed: i32 = 0;      // array of 0/1 per file

var mind_cycle_num: i32 = 0;
var mind_initialized: bool = false;

// Predictions (parallel arrays, indexed by file)
var mind_pred_funcs: i32 = 0;    // predicted function count
var mind_pred_health: i32 = 0;   // predicted health score
var mind_pred_conf: i32 = 0;     // confidence in prediction (0-100)

// Observed facts (parallel arrays, indexed by file)
var mind_fact_funcs: i32 = 0;    // actual function count
var mind_fact_health: i32 = 0;   // actual health score
var mind_fact_lines: i32 = 0;    // actual line count

// Running statistics
var mind_total_error: i32 = 0;   // cumulative normalized prediction error
var mind_total_preds: i32 = 0;   // total predictions made
var mind_competence: i32 = 50;   // 0-100, starts neutral

// Learning model: function density (functions per 100 lines)
var mind_density_sum: i32 = 0;   // sum of (funcs*100/lines) across files
var mind_density_count: i32 = 0; // number of data points

// Decision tracking
var mind_last_action: i32 = 0;
var mind_last_target: i32 = 0;
var mind_idle_streak: i32 = 0;

// ── Action types ───────────────────────────────────────

fn ACT_IDLE() -> i32       { return 0; }
fn ACT_EXPLORE() -> i32    { return 1; }
fn ACT_REPREDICT() -> i32  { return 2; }
fn ACT_CONSOLIDATE() -> i32 { return 3; }
fn ACT_DISCOVER() -> i32   { return 4; }

fn act_name(a: i32) -> string {
    if a == 0 { return "idle"; }
    if a == 1 { return "explore"; }
    if a == 2 { return "repredict"; }
    if a == 3 { return "consolidate"; }
    if a == 4 { return "discover"; }
    return "unknown";
}

// ── Initialization ─────────────────────────────────────

fn mind_init() {
    mind_files = array_new(0);
    mind_file_count = 0;
    mind_analyzed = array_new(0);
    mind_cycle_num = 0;

    mind_pred_funcs = array_new(0);
    mind_pred_health = array_new(0);
    mind_pred_conf = array_new(0);

    mind_fact_funcs = array_new(0);
    mind_fact_health = array_new(0);
    mind_fact_lines = array_new(0);

    mind_total_error = 0;
    mind_total_preds = 0;
    mind_competence = 50;

    mind_density_sum = 0;
    mind_density_count = 0;

    mind_last_action = ACT_IDLE();
    mind_last_target = 0 - 1;
    mind_idle_streak = 0;

    mind_initialized = true;

    // Seed temporal bindings
    let tick: i32 = vm_get_tick();
    env_bind("mind.cycle", val_i32(0), tick, "mind_init");
    env_bind("mind.competence", val_approx(50, 30), tick, "mind_init");
    env_bind("mind.files_known", val_i32(0), tick, "mind_init");
    env_bind("mind.files_analyzed", val_i32(0), tick, "mind_init");
    env_bind("mind.avg_error", val_approx(50, 30), tick, "mind_init");
}

// ── Seed files ─────────────────────────────────────────

fn mind_seed(path: string) -> bool {
    // Avoid duplicates
    var i: i32 = 0;
    while i < mind_file_count {
        if str_eq(sp_get(array_get(mind_files, i)), path) { return false; }
        i = i + 1;
    }

    let si: i32 = sp_store(path);
    array_push(mind_files, si);
    array_push(mind_analyzed, 0);
    array_push(mind_pred_funcs, 0);
    array_push(mind_pred_health, 0);
    array_push(mind_pred_conf, 0);
    array_push(mind_fact_funcs, 0);
    array_push(mind_fact_health, 0);
    array_push(mind_fact_lines, 0);
    mind_file_count = mind_file_count + 1;

    env_bind("mind.files_known", val_i32(mind_file_count), vm_get_tick(), "seed");
    return true;
}

fn mind_file_path(idx: i32) -> string {
    if idx < 0 || idx >= mind_file_count { return ""; }
    return sp_get(array_get(mind_files, idx));
}

fn mind_is_analyzed(idx: i32) -> bool {
    if idx < 0 || idx >= mind_file_count { return false; }
    return array_get(mind_analyzed, idx) == 1;
}

fn mind_count_analyzed() -> i32 {
    var count: i32 = 0;
    var i: i32 = 0;
    while i < mind_file_count {
        if array_get(mind_analyzed, i) == 1 { count = count + 1; }
        i = i + 1;
    }
    return count;
}

// ── Helpers ────────────────────────────────────────────

fn mind_count_lines(content: string) -> i32 {
    if len(content) == 0 { return 0; }
    var count: i32 = 1;
    var i: i32 = 0;
    while i < len(content) {
        if char_at(content, i) == 10 { count = count + 1; }
        i = i + 1;
    }
    return count;
}

fn mind_abs(x: i32) -> i32 {
    if x < 0 { return 0 - x; }
    return x;
}

// ── Prediction ─────────────────────────────────────────
// Before analyzing, form a belief about the file.
// Predictions improve as the mind accumulates experience.

fn mind_predict(file_idx: i32) {
    let path: string = mind_file_path(file_idx);
    if len(path) == 0 { return; }

    // Read file to get line count (epistemic: we know the size)
    let content: string = read_file(path);
    let lines: i32 = mind_count_lines(content);

    // Predict function count using learned density
    var pred_funcs: i32 = 0;
    if mind_density_count > 0 {
        // Use learned density: avg functions per 100 lines
        let avg_density: i32 = mind_density_sum / mind_density_count;
        pred_funcs = (lines * avg_density) / 100;
    } else {
        // No experience yet — naive guess: 1 function per 15 lines
        pred_funcs = lines / 15;
    }
    if pred_funcs < 1 { pred_funcs = 1; }

    // Confidence grows with experience
    var conf: i32 = 25;
    if mind_density_count >= 1 { conf = 40; }
    if mind_density_count >= 3 { conf = 55; }
    if mind_density_count >= 5 { conf = 70; }
    if mind_competence > 80 { conf = conf + 10; }
    if conf > 95 { conf = 95; }

    // Predict health (heuristic: large files tend to be less healthy)
    var pred_health: i32 = 80;
    if lines > 500 { pred_health = 75; }
    if lines > 1000 { pred_health = 65; }
    if lines > 2000 { pred_health = 55; }

    // Store predictions
    array_set(mind_pred_funcs, file_idx, pred_funcs);
    array_set(mind_pred_health, file_idx, pred_health);
    array_set(mind_pred_conf, file_idx, conf);

    // Temporal binding with uncertainty
    let tick: i32 = vm_get_tick();
    let prefix: string = str_concat("mind.pred.", path);
    env_bind(str_concat(prefix, ".funcs"), val_approx(pred_funcs, conf), tick, "predict");
    env_bind(str_concat(prefix, ".health"), val_approx(pred_health, conf), tick, "predict");
}

// ── Perception ─────────────────────────────────────────
// Analyze a file and extract ground truth.

fn mind_perceive(file_idx: i32) -> i32 {
    let path: string = mind_file_path(file_idx);
    if len(path) == 0 { return 0 - 1; }

    // Use the analyzer to read the file
    let result: i32 = analyze_file(path);
    if result < 0 { return 0 - 1; }

    // Extract facts
    let actual_funcs: i32 = ana_get_func_count();
    let actual_lines: i32 = ana_get_lines();
    let actual_health: i32 = ana_health_score();

    // Store facts
    array_set(mind_fact_funcs, file_idx, actual_funcs);
    array_set(mind_fact_health, file_idx, actual_health);
    array_set(mind_fact_lines, file_idx, actual_lines);
    array_set(mind_analyzed, file_idx, 1);

    // Update learned density model
    if actual_lines > 0 {
        let density: i32 = (actual_funcs * 100) / actual_lines;
        mind_density_sum = mind_density_sum + density;
        mind_density_count = mind_density_count + 1;
    }

    // Temporal binding (certain — these are observed facts)
    let tick: i32 = vm_get_tick();
    let prefix: string = str_concat("mind.fact.", path);
    env_bind(str_concat(prefix, ".funcs"), val_i32(actual_funcs), tick, "perceive");
    env_bind(str_concat(prefix, ".health"), val_i32(actual_health), tick, "perceive");
    env_bind(str_concat(prefix, ".lines"), val_i32(actual_lines), tick, "perceive");

    // Update analyzed count
    env_bind("mind.files_analyzed", val_i32(mind_count_analyzed()), tick, "perceive");

    return actual_funcs;
}

// ── Auto-discovery ─────────────────────────────────────
// After perceiving, discover new files from use directives.

fn mind_discover(file_idx: i32) -> i32 {
    let path: string = mind_file_path(file_idx);
    if len(path) == 0 { return 0; }

    // The analyzer has already been run on this file by perceive.
    // Check its use directives.
    var discovered: i32 = 0;
    var j: i32 = 0;
    while j < ana_get_use_count() {
        let dep: string = ana_use_path(j);
        // Resolve relative to the parent file's directory
        let resolved: string = mind_resolve_path(path, dep);
        if mind_seed(resolved) {
            discovered = discovered + 1;
        }
        j = j + 1;
    }
    return discovered;
}

fn mind_resolve_path(parent: string, dep: string) -> string {
    // Find last '/' in parent path
    var last_slash: i32 = 0 - 1;
    var i: i32 = 0;
    while i < len(parent) {
        if char_at(parent, i) == 47 { last_slash = i; }
        i = i + 1;
    }
    if last_slash < 0 {
        // No directory — dep is relative to current dir
        return dep;
    }
    // Prepend parent's directory
    let dir: string = substr(parent, 0, last_slash + 1);
    return str_concat(dir, dep);
}

// ── Measurement ────────────────────────────────────────
// Compare predictions to reality. The gap is learning signal.

fn mind_measure(file_idx: i32) -> i32 {
    let pred_funcs: i32 = array_get(mind_pred_funcs, file_idx);
    let actual_funcs: i32 = array_get(mind_fact_funcs, file_idx);

    // Absolute error
    let abs_error: i32 = mind_abs(pred_funcs - actual_funcs);

    // Normalized error (0-100)
    var norm_error: i32 = 0;
    if actual_funcs > 0 {
        norm_error = (abs_error * 100) / actual_funcs;
    } else if pred_funcs > 0 {
        norm_error = 100;
    }
    if norm_error > 100 { norm_error = 100; }

    // Update running statistics
    mind_total_error = mind_total_error + norm_error;
    mind_total_preds = mind_total_preds + 1;

    // Competence = 100 - average error
    let avg_error: i32 = mind_total_error / mind_total_preds;
    mind_competence = 100 - avg_error;
    if mind_competence < 0 { mind_competence = 0; }
    if mind_competence > 100 { mind_competence = 100; }

    // Temporal bindings
    let tick: i32 = vm_get_tick();
    let path: string = mind_file_path(file_idx);
    env_bind(str_concat("mind.error.", str_concat(path, ".funcs")),
             val_i32(norm_error), tick, "measure");
    env_bind("mind.avg_error", val_approx(avg_error, 60 + mind_density_count * 5), tick, "measure");
    env_bind("mind.competence", val_approx(mind_competence, 60 + mind_density_count * 5), tick, "measure");

    return norm_error;
}

fn mind_get_error(file_idx: i32) -> i32 {
    let path: string = mind_file_path(file_idx);
    let err_name: string = str_concat("mind.error.", str_concat(path, ".funcs"));
    let slot: i32 = env_find(err_name);
    if slot < 0 { return 0; }
    return val_get_int(env_load(err_name));
}

// ── Decision ───────────────────────────────────────────
// Choose the next action based on internal state.

fn mind_decide() -> i32 {
    // Priority 1: Unexplored files (epistemic uncertainty)
    var i: i32 = 0;
    while i < mind_file_count {
        if array_get(mind_analyzed, i) == 0 {
            mind_last_target = i;
            mind_last_action = ACT_EXPLORE();
            env_bind("mind.decision", val_str("explore"), vm_get_tick(), "decide");
            env_bind("mind.decision.reason",
                     val_str("epistemic: unanalyzed file"), vm_get_tick(), "decide");
            return ACT_EXPLORE();
        }
        i = i + 1;
    }

    // Priority 2: High prediction error (>30%) → repredict
    var worst_error: i32 = 0;
    var worst_idx: i32 = 0 - 1;
    i = 0;
    while i < mind_file_count {
        let err: i32 = mind_get_error(i);
        if err > worst_error {
            worst_error = err;
            worst_idx = i;
        }
        i = i + 1;
    }
    if worst_error > 30 && worst_idx >= 0 {
        mind_last_target = worst_idx;
        mind_last_action = ACT_REPREDICT();
        env_bind("mind.decision", val_str("repredict"), vm_get_tick(), "decide");
        env_bind("mind.decision.reason",
                 val_str("high prediction error"), vm_get_tick(), "decide");
        return ACT_REPREDICT();
    }

    // Priority 3: Consolidate if enough data
    if mind_count_analyzed() >= 2 {
        mind_last_target = 0 - 1;
        mind_last_action = ACT_CONSOLIDATE();
        env_bind("mind.decision", val_str("consolidate"), vm_get_tick(), "decide");
        env_bind("mind.decision.reason",
                 val_str("sufficient data for patterns"), vm_get_tick(), "decide");
        return ACT_CONSOLIDATE();
    }

    // Nothing useful to do
    mind_last_target = 0 - 1;
    mind_last_action = ACT_IDLE();
    env_bind("mind.decision", val_str("idle"), vm_get_tick(), "decide");
    env_bind("mind.decision.reason",
             val_str("all explored, errors acceptable"), vm_get_tick(), "decide");
    return ACT_IDLE();
}

// ── Action Execution ───────────────────────────────────

fn mind_act_explore(target: i32) -> i32 {
    mind_predict(target);
    let result: i32 = mind_perceive(target);
    if result < 0 { return 0 - 1; }

    let error: i32 = mind_measure(target);

    // Auto-discover dependencies
    mind_discover(target);

    return error;
}

fn mind_act_repredict(target: i32) -> i32 {
    // Re-predict with updated model, re-analyze
    mind_predict(target);
    mind_perceive(target);
    let error: i32 = mind_measure(target);
    mind_discover(target);
    return error;
}

fn mind_act_consolidate() {
    // Compress knowledge: categorize files by size
    var small: i32 = 0;
    var medium: i32 = 0;
    var large: i32 = 0;

    var i: i32 = 0;
    while i < mind_file_count {
        if array_get(mind_analyzed, i) == 1 {
            let funcs: i32 = array_get(mind_fact_funcs, i);
            if funcs < 20 { small = small + 1; }
            else if funcs <= 100 { medium = medium + 1; }
            else { large = large + 1; }
        }
        i = i + 1;
    }

    let tick: i32 = vm_get_tick();
    env_bind("mind.pattern.small_files", val_i32(small), tick, "consolidate");
    env_bind("mind.pattern.medium_files", val_i32(medium), tick, "consolidate");
    env_bind("mind.pattern.large_files", val_i32(large), tick, "consolidate");

    // Average health across files
    var health_sum: i32 = 0;
    var health_n: i32 = 0;
    i = 0;
    while i < mind_file_count {
        if array_get(mind_analyzed, i) == 1 {
            health_sum = health_sum + array_get(mind_fact_health, i);
            health_n = health_n + 1;
        }
        i = i + 1;
    }
    if health_n > 0 {
        let avg_health: i32 = health_sum / health_n;
        env_bind("mind.pattern.avg_health", val_approx(avg_health, 70), tick, "consolidate");
    }
}

// ── One Cycle ──────────────────────────────────────────
// The fundamental unit of cognition.

fn mind_one_cycle() -> i32 {
    mind_cycle_num = mind_cycle_num + 1;
    env_bind("mind.cycle", val_i32(mind_cycle_num), vm_get_tick(), "cycle");

    let action: i32 = mind_decide();

    if action == ACT_IDLE() {
        mind_idle_streak = mind_idle_streak + 1;
        return 0;
    }
    mind_idle_streak = 0;

    if action == ACT_EXPLORE() {
        return mind_act_explore(mind_last_target);
    }
    if action == ACT_REPREDICT() {
        return mind_act_repredict(mind_last_target);
    }
    if action == ACT_CONSOLIDATE() {
        mind_act_consolidate();
        return 0;
    }

    return 0;
}

// ── Run N Cycles ───────────────────────────────────────
// Autonomous execution. Returns number of productive cycles.

fn mind_run(n: i32) -> i32 {
    var i: i32 = 0;

    while i < n {
        mind_one_cycle();

        // Stop after 2 consecutive idles (nothing to do)
        if mind_idle_streak >= 2 { break; }

        i = i + 1;
    }

    env_bind("mind.cycles_completed", val_i32(i), vm_get_tick(), "run");
    return i;
}

// ── Self-Inspection ────────────────────────────────────
// The mind can report on its own state.

fn mind_status_line() -> string {
    var s: string = "Cycle:";
    s = str_concat(s, int_to_str(mind_cycle_num));
    s = str_concat(s, " Known:");
    s = str_concat(s, int_to_str(mind_file_count));
    s = str_concat(s, " Analyzed:");
    s = str_concat(s, int_to_str(mind_count_analyzed()));
    s = str_concat(s, " Competence:~");
    s = str_concat(s, int_to_str(mind_competence));
    s = str_concat(s, "%");
    return s;
}

fn mind_get_cycle() -> i32 { return mind_cycle_num; }
fn mind_get_competence() -> i32 { return mind_competence; }
fn mind_get_file_count() -> i32 { return mind_file_count; }
fn mind_get_avg_error() -> i32 {
    if mind_total_preds == 0 { return 50; }
    return mind_total_error / mind_total_preds;
}
fn mind_get_total_preds() -> i32 { return mind_total_preds; }
fn mind_get_last_action() -> i32 { return mind_last_action; }
fn mind_get_last_target() -> i32 { return mind_last_target; }
