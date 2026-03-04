// Machine REPL -Interactive Temporal Computing Shell
// A terminal where you experience Machine's temporal computation model.
//
// Usage:
//   mc.exe self_codegen.m machine_repl.m
//
// Commands:
//   bind <name> = <value>     -bind a name to a value (creates timeline)
//   bind <name> ~ <value>     -bind with uncertainty (approximate value)
//   load <name>               -load current value of a name
//   history <name>            -show full timeline of a name
//   forget <name>             -forget a binding (value persists in history)
//   snapshot                  -save current state
//   rollback                  -restore to last snapshot
//   drift                     -show which values have changed over time
//   env                       -show all current bindings
//   analyze <file.m>          -analyze M source file (Phase C)
//   funcs                     -list functions from analysis
//   calls <name>              -show what a function calls
//   callers <name>            -show who calls a function
//   search <pattern>          -search functions matching substring
//   deps                      -show dependency tree (use directives)
//   top [N]                   -show N largest functions (default 10)
//   diff                      -show changes between two analyses
//   compare <c_file> <m_file> -compare C and M implementations
//   unused                    -find functions with no callers
//   hotspots [N]              -show N most-called functions
//   health                    -code health report with score
//   stats                     -show code metrics
//   help                      -show command reference
//   quit / exit               -exit the shell

use "machine_vm.m"
use "machine_analyze.m"
use "machine_mind.m"

// ── String helpers ───────────────────────────────────

fn str_starts_with(s: string, prefix: string) -> bool {
    if len(prefix) > len(s) { return false; }
    return str_eq(substr(s, 0, len(prefix)), prefix);
}

fn is_ws(c: i32) -> bool { return c == 32 || c == 9 || c == 10 || c == 13; }

fn str_trim(s: string) -> string {
    var start: i32 = 0;
    while start < len(s) && is_ws(char_at(s, start)) {
        start = start + 1;
    }
    var end: i32 = len(s);
    while end > start && is_ws(char_at(s, end - 1)) {
        end = end - 1;
    }
    return substr(s, start, end - start);
}

fn is_digit_char(c: i32) -> bool { return c >= 48 && c <= 57; }

fn str_to_int(s: string) -> i32 {
    var result: i32 = 0;
    var i: i32 = 0;
    var neg: bool = false;
    if len(s) > 0 && char_at(s, 0) == 45 {
        neg = true;
        i = 1;
    }
    while i < len(s) {
        let c: i32 = char_at(s, i);
        if !is_digit_char(c) { break; }
        result = result * 10 + (c - 48);
        i = i + 1;
    }
    if neg { return 0 - result; }
    return result;
}

fn is_number(s: string) -> bool {
    if len(s) == 0 { return false; }
    var i: i32 = 0;
    if char_at(s, 0) == 45 { i = 1; }
    if i >= len(s) { return false; }
    while i < len(s) {
        let c: i32 = char_at(s, i);
        if !is_digit_char(c) { return false; }
        i = i + 1;
    }
    return true;
}

fn find_char(s: string, c: i32) -> i32 {
    var i: i32 = 0;
    while i < len(s) {
        if char_at(s, i) == c { return i; }
        i = i + 1;
    }
    return 0 - 1;
}

fn str_contains(haystack: string, needle: string) -> bool {
    if len(needle) > len(haystack) { return false; }
    var i: i32 = 0;
    while i <= len(haystack) - len(needle) {
        if str_eq(substr(haystack, i, len(needle)), needle) { return true; }
        i = i + 1;
    }
    return false;
}


// ── REPL display helpers ─────────────────────────────

fn print_val(vid: i32) {
    let t: i32 = val_get_type(vid);
    let conf: i32 = val_get_conf(vid);
    if t == VT_NIL() {
        print("nil");
    } else if t == VT_I32() {
        if conf < 100 {
            print("~");
            print(int_to_str(val_get_int(vid)));
            print(" (conf:");
            print(int_to_str(conf));
            print("%)");
        } else {
            print(int_to_str(val_get_int(vid)));
        }
    } else if t == VT_BOOL() {
        if val_get_int(vid) != 0 { print("true"); }
        else { print("false"); }
    } else if t == VT_STR() {
        print("\"");
        print(val_get_str(vid));
        print("\"");
    } else {
        print("?");
    }
}

fn show_help() {
    println("");
    println("  Machine REPL -Temporal Computing Shell");
    println("  ========================================");
    println("");
    println("  bind <name> = <value>   Bind a name to a value");
    println("  bind <name> ~ <value>   Bind with uncertainty (~approximate)");
    println("  load <name>             Show current value");
    println("  history <name>          Show full timeline");
    println("  forget <name>           Forget a binding");
    println("  snapshot                Save to memory (for rollback)");
    println("  rollback                Restore from memory snapshot");
    println("  save [path]             Save state to disk");
    println("  restore [path]          Restore state from disk");
    println("  drift                   Show value changes over time");
    println("  env                     Show all bindings");
    println("  help                    This message");
    println("  quit / exit             Exit (auto-saves)");
    println("");
    println("  Expressions are evaluated directly:");
    println("    2 + 3              -> 5");
    println("    x * 2 + 1          -> uses bound variables");
    println("    (10 + x) * 3       -> parentheses work");
    println("    x > 5 && x < 100   -> comparisons + logic");
    println("");
    println("  Code analysis:");
    println("    analyze <file.m>       Analyze M source file");
    println("    funcs                  List functions from analysis");
    println("    calls <name>           Show what a function calls");
    println("    callers <name>         Show who calls a function");
    println("    search <pattern>       Search functions by name substring");
    println("    deps                   Show dependency tree (use directives)");
    println("    top [N]                Show N largest functions (default 10)");
    println("    stats                  Show code metrics");
    println("    project <file.m>       Analyze file + all dependencies");
    println("    where <name>           Find which file defines a function");
    println("    complexity [N]         Show N most complex functions");
    println("    diff                   Show changes between analyses");
    println("    compare <c> <m>        Compare C and M implementations");
    println("    unused                 Find functions with no callers");
    println("    hotspots [N]           Show N most-called functions");
    println("    health                 Code health report with score");
    println("    audit                  Comprehensive code quality audit");
    println("    map                    Dependency map (architecture overview)");
    println("    explain <name>         Machine explains what a function does");
    println("    summary                Narrative summary of analyzed code");
    println("    focus <name>           Deep analysis of a single function");
    println("    suggest                Improvement suggestions");
    println("    coupling [N]           Show N most coupled function pairs");
    println("    self                   Machine analyzes itself");
    println("");
    println("  Mind (autonomous cognition):");
    println("    think [N]              Run N cycles of autonomous thinking");
    println("    mind                   Show mind status");
    println("    seed <file.m>          Add a file to the mind's exploration queue");
    println("");
    println("  Values: integers (42), strings (\"hello\"), booleans (true/false)");
    println("  Approximate: bind x ~ 100  (value with uncertainty)");
    println("");
}

fn show_banner() {
    println("");
    println("  Machine -Temporal Computing Shell");
    println("  Tohum v0.1 | Type 'help' for commands");
    println("");
}

// ── Command parsing ──────────────────────────────────

fn parse_value(s: string) -> i32 {
    let trimmed: string = str_trim(s);
    if len(trimmed) == 0 { return val_nil(); }
    if str_eq(trimmed, "true") { return val_bool(1); }
    if str_eq(trimmed, "false") { return val_bool(0); }
    if str_eq(trimmed, "nil") { return val_nil(); }

    // String literal: "..."
    if len(trimmed) >= 2 && char_at(trimmed, 0) == 34 && char_at(trimmed, len(trimmed) - 1) == 34 {
        return val_str(substr(trimmed, 1, len(trimmed) - 2));
    }

    // Number
    if is_number(trimmed) {
        return val_i32(str_to_int(trimmed));
    }

    // Try to load as name reference
    let ref_slot: i32 = env_find(trimmed);
    if ref_slot >= 0 {
        return env_load(trimmed);
    }

    // Unknown -treat as string
    return val_str(trimmed);
}

fn cmd_bind(args: string) {
    // Find = or ~ operator
    let eq_pos: i32 = find_char(args, 61);  // '='
    let tilde_pos: i32 = find_char(args, 126);  // '~'

    var name: string = "";
    var value_str: string = "";
    var approx: bool = false;

    if tilde_pos >= 0 && (eq_pos < 0 || tilde_pos < eq_pos) {
        name = str_trim(substr(args, 0, tilde_pos));
        value_str = str_trim(substr(args, tilde_pos + 1, len(args) - tilde_pos - 1));
        approx = true;
    } else if eq_pos >= 0 {
        name = str_trim(substr(args, 0, eq_pos));
        value_str = str_trim(substr(args, eq_pos + 1, len(args) - eq_pos - 1));
    } else {
        println("  Error: use 'bind <name> = <value>' or 'bind <name> ~ <value>'");
        return;
    }

    if len(name) == 0 {
        println("  Error: name cannot be empty");
        return;
    }

    var vid: i32 = 0;
    if approx {
        if is_number(value_str) {
            vid = val_approx(str_to_int(value_str), 70);
        } else {
            println("  Error: approximate values must be numeric");
            return;
        }
    } else {
        vid = parse_value(value_str);
    }

    // Check if this is a rebind (name already exists)
    let existing: i32 = env_find(name);
    let tick: i32 = vm_get_tick();
    env_bind(name, vid, tick, "repl");

    print("  ");
    print(name);
    if existing >= 0 {
        print(" -> ");
    } else {
        print(" = ");
    }
    print_val(vid);
    println("");
}

fn cmd_load(args: string) {
    let name: string = str_trim(args);
    if len(name) == 0 {
        println("  Error: use 'load <name>'");
        return;
    }
    let slot: i32 = env_find(name);
    if slot < 0 {
        print("  '");
        print(name);
        println("' not found");
        return;
    }
    if env_is_forgotten(name) {
        print("  '");
        print(name);
        println("' was forgotten");
        return;
    }
    let vid: i32 = env_load(name);
    print("  ");
    print(name);
    print(" = ");
    print_val(vid);
    println("");
}

fn cmd_history(args: string) {
    let name: string = str_trim(args);
    if len(name) == 0 {
        println("  Error: use 'history <name>'");
        return;
    }
    let slot: i32 = env_find(name);
    if slot < 0 {
        print("  '");
        print(name);
        println("' not found");
        return;
    }

    let tl: i32 = env_get_timeline(name);
    let tlen: i32 = tl_length(tl);

    print("  ");
    print(name);
    print(" timeline (");
    print(int_to_str(tlen));
    println(" entries):");

    var i: i32 = 0;
    while i < tlen {
        let vid: i32 = tl_get_val(tl, i);
        let src: string = tl_get_source(tl, i);
        print("    [");
        print(int_to_str(i));
        print("] ");
        print_val(vid);
        if len(src) > 0 {
            print("  (");
            print(src);
            print(")");
        }
        if i == tlen - 1 { print("  <- current"); }
        println("");
        i = i + 1;
    }
}

fn cmd_forget(args: string) {
    let name: string = str_trim(args);
    if len(name) == 0 {
        println("  Error: use 'forget <name>'");
        return;
    }
    let slot: i32 = env_find(name);
    if slot < 0 {
        print("  '");
        print(name);
        println("' not found");
        return;
    }
    env_forget(name);
    print("  forgot '");
    print(name);
    println("'");
}

fn cmd_env() {
    let count: i32 = env_get_count();
    if count == 0 {
        println("  (no bindings)");
        return;
    }
    println("  Current bindings:");
    var i: i32 = 0;
    while i < count {
        let name: string = env_get_name(i);
        if len(name) > 0 && !env_is_forgotten(name) {
            let vid: i32 = env_load(name);
            print("    ");
            print(name);
            print(" = ");
            print_val(vid);

            // Show timeline length if > 1
            let tl: i32 = env_get_timeline(name);
            let tlen: i32 = tl_length(tl);
            if tlen > 1 {
                print("  (");
                print(int_to_str(tlen));
                print(" versions)");
            }
            println("");
        }
        i = i + 1;
    }
}

fn cmd_drift() {
    let count: i32 = env_get_count();
    if count == 0 {
        println("  (no bindings to analyze)");
        return;
    }
    var stable: i32 = 0;
    var changed: i32 = 0;
    println("  Drift analysis:");
    var i: i32 = 0;
    while i < count {
        let name: string = env_get_name(i);
        if len(name) > 0 {
            let tl: i32 = env_get_timeline(name);
            let tlen: i32 = tl_length(tl);
            if tlen > 1 {
                print("    ");
                print(name);
                print(": ");
                print_val(tl_get_val(tl, 0));
                print(" -> ");
                print_val(tl_get_val(tl, tlen - 1));
                print("  (");
                print(int_to_str(tlen));
                println(" changes)");
                changed = changed + 1;
            } else {
                stable = stable + 1;
            }
        }
        i = i + 1;
    }
    print("  stable: ");
    print(int_to_str(stable));
    print(", changed: ");
    println(int_to_str(changed));
}

fn cmd_snapshot() {
    vm_snapshot();
    println("  State saved.");
}

fn cmd_rollback() {
    let ok: i32 = vm_rollback();
    if ok == 0 {
        println("  Rolled back to last snapshot.");
    } else {
        println("  No snapshot to restore.");
    }
}

// Default state file path
fn state_path() -> string { return ".machine_state"; }

fn cmd_save(args: string) {
    var path: string = str_trim(args);
    if len(path) == 0 { path = state_path(); }
    let ok: i32 = vm_persist(path);
    if ok == 0 {
        print("  State saved to ");
        println(path);
    } else {
        println("  Error: could not save state");
    }
}

fn cmd_restore(args: string) {
    var path: string = str_trim(args);
    if len(path) == 0 { path = state_path(); }
    let ok: i32 = vm_restore(path);
    if ok == 0 {
        print("  State restored from ");
        println(path);
    } else {
        print("  No saved state at ");
        println(path);
    }
}

fn try_auto_restore() {
    // Silently try to restore default state file
    let data: string = read_file(state_path());
    if len(data) > 0 {
        vm_deserialize(data);
        print("  (restored ");
        print(int_to_str(env_get_count()));
        println(" bindings from previous session)");
    }
}

// ── Code analysis commands ───────────────────────────

fn cmd_analyze(args: string) {
    let path: string = str_trim(args);
    if len(path) == 0 {
        println("  Error: use 'analyze <file.m>'");
        return;
    }

    let result: i32 = analyze_file(path);
    if result < 0 {
        print("  Error: could not read '");
        print(path);
        println("'");
        return;
    }

    // Populate VM with analysis bindings + complexity scores
    ana_populate_vm();
    ana_populate_complexity();

    // Show summary
    println("");
    print("  Analyzed: ");
    println(path);
    print("  Lines: ");
    println(int_to_str(ana_get_lines()));
    print("  Functions: ");
    println(int_to_str(ana_get_func_count()));
    print("  Globals: ");
    println(int_to_str(ana_get_global_count()));
    if ana_get_use_count() > 0 {
        print("  Dependencies: ");
        println(int_to_str(ana_get_use_count()));
    }
    print("  Avg function size: ");
    print(int_to_str(ana_avg_func_lines()));
    println(" lines");
    print("  Largest function: ");
    print(ana_max_func_name());
    print(" (");
    print(int_to_str(ana_max_func_lines()));
    println(" lines)");
    println("");
    println("  Use 'funcs' to list functions, 'calls <name>' for call graph.");
    println("  Analysis bound to VM -- use 'load _funcs' or 'load fn.<name>.lines'.");
}

fn cmd_funcs() {
    if ana_get_func_count() == 0 {
        println("  No analysis loaded. Use 'analyze <file.m>' first.");
        return;
    }

    print("  Functions in ");
    print(ana_get_file());
    print(" (");
    print(int_to_str(ana_get_func_count()));
    println("):");

    var i: i32 = 0;
    while i < ana_get_func_count() {
        print("    ");
        print(ana_func_name(i));
        print("(");
        let pc: i32 = ana_func_params(i);
        if pc > 0 {
            print(int_to_str(pc));
            print(" params");
        }
        print(")  ");
        print(int_to_str(ana_func_lines(i)));
        print("L  ");
        let cc: i32 = ana_func_call_count(i);
        if cc > 0 {
            print(int_to_str(cc));
            print(" calls");
        }
        println("");
        i = i + 1;
    }
}

fn cmd_calls(args: string) {
    let name: string = str_trim(args);
    if len(name) == 0 {
        println("  Error: use 'calls <function_name>'");
        return;
    }

    let idx: i32 = ana_find_func(name);
    if idx < 0 {
        print("  Function '");
        print(name);
        println("' not found in analysis.");
        return;
    }

    print("  ");
    print(name);
    print(" (lines ");
    print(int_to_str(ana_func_start(idx)));
    print("-");
    print(int_to_str(ana_func_end(idx)));
    print(", ");
    print(int_to_str(ana_func_params(idx)));
    println(" params)");

    let cc: i32 = ana_func_call_count(idx);
    if cc == 0 {
        println("    (no calls)");
        return;
    }

    print("    calls (");
    print(int_to_str(cc));
    println("):");
    var i: i32 = 0;
    while i < cc {
        let call_name: string = ana_func_call_name(idx, i);
        print("      -> ");
        print(call_name);
        // Check if target is in same file
        let target: i32 = ana_find_func(call_name);
        if target >= 0 {
            print("  (line ");
            print(int_to_str(ana_func_start(target)));
            print(")");
        } else {
            print("  (external)");
        }
        println("");
        i = i + 1;
    }
}

fn cmd_callers(args: string) {
    let name: string = str_trim(args);
    if len(name) == 0 {
        println("  Error: use 'callers <function_name>'");
        return;
    }

    if ana_get_func_count() == 0 {
        println("  No analysis loaded. Use 'analyze <file.m>' first.");
        return;
    }

    // Search all functions for calls to this name
    var found: i32 = 0;
    print("  Who calls ");
    print(name);
    println(":");

    var i: i32 = 0;
    while i < ana_get_func_count() {
        var j: i32 = 0;
        let cc: i32 = ana_func_call_count(i);
        while j < cc {
            if str_eq(ana_func_call_name(i, j), name) {
                print("    <- ");
                print(ana_func_name(i));
                print("  (line ");
                print(int_to_str(ana_func_start(i)));
                println(")");
                found = found + 1;
            }
            j = j + 1;
        }
        i = i + 1;
    }

    if found == 0 {
        println("    (no callers found in this file)");
    } else {
        print("  ");
        print(int_to_str(found));
        println(" callers");
    }
}

fn cmd_stats() {
    if ana_get_func_count() == 0 {
        println("  No analysis loaded. Use 'analyze <file.m>' first.");
        return;
    }

    println("  Code metrics:");
    print("    Total lines: ");
    println(int_to_str(ana_get_lines()));
    print("    Functions: ");
    println(int_to_str(ana_get_func_count()));
    print("    Globals: ");
    println(int_to_str(ana_get_global_count()));
    print("    Avg function size: ");
    print(int_to_str(ana_avg_func_lines()));
    println(" lines");
    print("    Largest: ");
    print(ana_max_func_name());
    print(" (");
    print(int_to_str(ana_max_func_lines()));
    println(" lines)");

    // Count functions by size category
    var small: i32 = 0;   // 1-5 lines
    var medium: i32 = 0;  // 6-20 lines
    var large: i32 = 0;   // 21-50 lines
    var huge: i32 = 0;    // 50+ lines
    var i: i32 = 0;
    while i < ana_get_func_count() {
        let l: i32 = ana_func_lines(i);
        if l <= 5 { small = small + 1; }
        else if l <= 20 { medium = medium + 1; }
        else if l <= 50 { large = large + 1; }
        else { huge = huge + 1; }
        i = i + 1;
    }
    println("    Size distribution:");
    print("      small (1-5):    ");
    println(int_to_str(small));
    print("      medium (6-20):  ");
    println(int_to_str(medium));
    print("      large (21-50):  ");
    println(int_to_str(large));
    print("      huge (50+):     ");
    println(int_to_str(huge));

    // Find most-called functions (callers count)
    // Build reverse call index
    println("    Most connected:");
    var max_calls: i32 = 0;
    var max_calls_name: string = "";
    i = 0;
    while i < ana_get_func_count() {
        let cc: i32 = ana_func_call_count(i);
        if cc > max_calls {
            max_calls = cc;
            max_calls_name = ana_func_name(i);
        }
        i = i + 1;
    }
    if max_calls > 0 {
        print("      ");
        print(max_calls_name);
        print(" calls ");
        print(int_to_str(max_calls));
        println(" other functions");
    }
}

fn cmd_project(args: string) {
    let path: string = str_trim(args);
    if len(path) == 0 {
        println("  Error: use 'project <file.m>'");
        return;
    }

    ana_multi_init();
    let n: i32 = ana_resolve_deps(path);
    if n < 0 {
        print("  Error: could not read '");
        print(path);
        println("'");
        return;
    }

    println("");
    print("  Project: ");
    println(path);
    print("  Files: ");
    println(int_to_str(ana_all_file_count));
    print("  Total functions: ");
    println(int_to_str(ana_all_func_total));
    println("");

    var i: i32 = 0;
    while i < ana_all_file_count {
        print("    ");
        print(ana_all_file_path(i));
        print("  (");
        print(int_to_str(ana_all_file_func_count(i)));
        println(" funcs)");
        i = i + 1;
    }

    // Populate VM with project-level bindings
    let tick: i32 = vm_get_tick();
    env_bind("_project", val_str(path), tick, "project");
    env_bind("_project_files", val_i32(ana_all_file_count), tick, "project");
    env_bind("_project_funcs", val_i32(ana_all_func_total), tick, "project");

    println("");
    println("  Use 'where <func>' to find which file defines a function.");
}

fn cmd_where(args: string) {
    let name: string = str_trim(args);
    if len(name) == 0 {
        println("  Error: use 'where <function_name>'");
        return;
    }

    if ana_all_file_count == 0 {
        println("  No project loaded. Use 'project <file.m>' first.");
        return;
    }

    let file: string = ana_who_defines(name);
    if len(file) == 0 {
        print("  '");
        print(name);
        println("' not found in any analyzed file.");
        return;
    }

    print("  ");
    print(name);
    print(" is defined in ");
    println(file);
}

fn cmd_self() {
    // Machine analyzes itself — the REPL and all its dependencies
    println("  Machine analyzing itself...");
    ana_multi_init();
    let n: i32 = ana_resolve_deps("examples/machine_repl.m");

    println("");
    println("  Self-analysis complete:");
    print("  Files: ");
    println(int_to_str(ana_all_file_count));
    print("  Total functions: ");
    println(int_to_str(ana_all_func_total));

    var i: i32 = 0;
    while i < ana_all_file_count {
        print("    ");
        print(ana_all_file_path(i));
        print("  (");
        print(int_to_str(ana_all_file_func_count(i)));
        println(" funcs)");
        i = i + 1;
    }

    // Now analyze the REPL itself for detailed metrics
    analyze_file("examples/machine_repl.m");
    ana_populate_vm();
    ana_populate_complexity();

    let tick: i32 = vm_get_tick();
    env_bind("_self", val_str("machine_repl.m"), tick, "self");
    env_bind("_self_funcs", val_i32(ana_all_func_total), tick, "self");
    env_bind("_self_files", val_i32(ana_all_file_count), tick, "self");

    println("");
    print("  REPL: ");
    print(int_to_str(ana_get_func_count()));
    print(" functions, ");
    print(int_to_str(ana_get_lines()));
    println(" lines");
    print("  Most complex: ");

    // Find most complex in REPL
    var max_c: i32 = 0;
    var max_name: string = "";
    i = 0;
    while i < ana_get_func_count() {
        let c: i32 = ana_func_complexity(i);
        if c > max_c {
            max_c = c;
            max_name = ana_func_name(i);
        }
        i = i + 1;
    }
    print(max_name);
    print(" (~");
    print(int_to_str(max_c));
    println(")");
    println("");
    println("  Machine knows itself.");
}

fn cmd_compare(args: string) {
    let arg: string = str_trim(args);
    if len(arg) == 0 {
        println("  Usage: compare <c_file> <m_file>");
        println("  Example: compare m/bootstrap/vm.c examples/machine_vm.m");
        return;
    }

    // Split args into two file paths
    var space_pos: i32 = 0;
    var found_space: bool = false;
    while space_pos < len(arg) {
        if char_at(arg, space_pos) == 32 {
            found_space = true;
            space_pos = space_pos + len(arg);  // exit
        } else {
            space_pos = space_pos + 1;
        }
    }
    if found_space { space_pos = space_pos - len(arg); }

    if !found_space {
        println("  Error: need two file paths. Example:");
        println("    compare m/bootstrap/vm.c examples/machine_vm.m");
        return;
    }

    let c_path: string = substr(arg, 0, space_pos);
    let m_path: string = str_trim(substr(arg, space_pos + 1, len(arg) - space_pos - 1));

    // Analyze C file first
    println("  Analyzing C file...");
    let r1: i32 = analyze_file(c_path);
    if r1 < 0 {
        print("  Error: could not read '");
        print(c_path);
        println("'");
        return;
    }
    let c_funcs: i32 = ana_get_func_count();
    let c_lines: i32 = ana_get_lines();
    let c_globals: i32 = ana_get_global_count();

    // Collect C function names + metrics for comparison
    var c_names: i32 = array_new(0);
    var c_fn_lines: i32 = array_new(0);
    var c_fn_calls: i32 = array_new(0);
    var ci: i32 = 0;
    while ci < c_funcs {
        array_push(c_names, sp_store(ana_func_name(ci)));
        array_push(c_fn_lines, ana_func_lines(ci));
        array_push(c_fn_calls, ana_func_call_count(ci));
        ci = ci + 1;
    }

    // Analyze M file (auto-saves C as previous)
    println("  Analyzing M file...");
    let r2: i32 = analyze_file(m_path);
    if r2 < 0 {
        print("  Error: could not read '");
        print(m_path);
        println("'");
        return;
    }
    let m_funcs: i32 = ana_get_func_count();
    let m_lines: i32 = ana_get_lines();
    let m_globals: i32 = ana_get_global_count();
    ana_populate_vm();

    // Header
    println("");
    println("  ╔══════════════════════════════════════════╗");
    println("  ║  C vs M — Structural Comparison          ║");
    println("  ╚══════════════════════════════════════════╝");
    println("");

    // File summaries
    print("  C: ");
    print(c_path);
    print("  (");
    print(int_to_str(c_lines));
    print(" lines, ");
    print(int_to_str(c_funcs));
    print(" funcs, ");
    print(int_to_str(c_globals));
    println(" globals)");

    print("  M: ");
    print(m_path);
    print("  (");
    print(int_to_str(m_lines));
    print(" lines, ");
    print(int_to_str(m_funcs));
    print(" funcs, ");
    print(int_to_str(m_globals));
    println(" globals)");
    println("");

    // Growth
    print("  Lines: ");
    if m_lines > c_lines {
        print("+");
        print(int_to_str(m_lines - c_lines));
        print(" (");
        print(int_to_str(m_lines * 100 / c_lines));
        println("% of C)");
    } else {
        print(int_to_str(m_lines - c_lines));
        print(" (");
        print(int_to_str(m_lines * 100 / c_lines));
        println("% of C)");
    }

    print("  Functions: ");
    print(int_to_str(c_funcs));
    print(" -> ");
    print(int_to_str(m_funcs));
    print(" (+");
    print(int_to_str(m_funcs - c_funcs));
    println(")");
    println("");

    // Shared function names (same name in both)
    var shared_count: i32 = 0;
    var ci2: i32 = 0;
    println("  Shared functions (same name in C and M):");
    while ci2 < c_funcs {
        let cname: string = sp_get(array_get(c_names, ci2));
        let m_idx: i32 = ana_find_func(cname);
        if m_idx >= 0 {
            shared_count = shared_count + 1;
            let c_l: i32 = array_get(c_fn_lines, ci2);
            let m_l: i32 = ana_func_lines(m_idx);
            let delta: i32 = m_l - c_l;
            print("    ");
            print(cname);
            print("  C:");
            print(int_to_str(c_l));
            print("L -> M:");
            print(int_to_str(m_l));
            print("L");
            if delta > 0 {
                print(" (+");
                print(int_to_str(delta));
                print(")");
            } else if delta < 0 {
                print(" (");
                print(int_to_str(delta));
                print(")");
            } else {
                print(" (same)");
            }
            println("");
        }
        ci2 = ci2 + 1;
    }

    if shared_count == 0 {
        println("    (no shared function names)");
    } else {
        print("    ");
        print(int_to_str(shared_count));
        println(" shared functions");
    }

    // C-only functions
    println("");
    println("  C-only functions (not in M):");
    var c_only: i32 = 0;
    ci2 = 0;
    while ci2 < c_funcs {
        let cname: string = sp_get(array_get(c_names, ci2));
        if ana_find_func(cname) < 0 {
            c_only = c_only + 1;
            print("    ");
            print(cname);
            print("  ");
            print(int_to_str(array_get(c_fn_lines, ci2)));
            println("L");
        }
        ci2 = ci2 + 1;
    }
    if c_only == 0 { println("    (none)"); }

    // M-only functions
    println("");
    print("  M-only functions (");
    print(int_to_str(m_funcs - shared_count));
    println(" new):");
    var m_only_count: i32 = 0;
    var mi: i32 = 0;
    while mi < m_funcs {
        let mname: string = ana_func_name(mi);
        // Check if in C
        var in_c: bool = false;
        var ck: i32 = 0;
        while ck < c_funcs {
            if str_eq(sp_get(array_get(c_names, ck)), mname) { in_c = true; }
            ck = ck + 1;
        }
        if !in_c {
            m_only_count = m_only_count + 1;
            if m_only_count <= 15 {
                print("    ");
                print(mname);
                print("  ");
                print(int_to_str(ana_func_lines(mi)));
                println("L");
            }
        }
        mi = mi + 1;
    }
    if m_only_count > 15 {
        print("    ... and ");
        print(int_to_str(m_only_count - 15));
        println(" more");
    }

    // Store comparison results
    let tick: i32 = vm_get_tick();
    env_bind("_compare_c", val_str(c_path), tick, "compare");
    env_bind("_compare_m", val_str(m_path), tick, "compare");
    env_bind("_compare_shared", val_i32(shared_count), tick, "compare");

    println("");
}

fn cmd_complexity(args: string) {
    if ana_get_func_count() == 0 {
        println("  No analysis loaded. Use 'analyze <file.m>' first.");
        return;
    }

    let trimmed: string = str_trim(args);
    var n: i32 = 10;
    if len(trimmed) > 0 && is_number(trimmed) {
        n = str_to_int(trimmed);
        if n <= 0 { n = 10; }
    }
    if n > ana_get_func_count() {
        n = ana_get_func_count();
    }

    print("  Top ");
    print(int_to_str(n));
    println(" most complex functions:");

    // Selection sort by complexity score
    var used: i32 = array_new(0);
    var ui: i32 = 0;
    while ui < ana_get_func_count() {
        array_push(used, 0);
        ui = ui + 1;
    }

    var rank: i32 = 0;
    while rank < n {
        var best_idx: i32 = 0 - 1;
        var best_score: i32 = 0 - 1;
        var i: i32 = 0;
        while i < ana_get_func_count() {
            if array_get(used, i) == 0 {
                let s: i32 = ana_func_complexity(i);
                if s > best_score {
                    best_score = s;
                    best_idx = i;
                }
            }
            i = i + 1;
        }
        if best_idx < 0 { rank = n; }
        else {
            array_set(used, best_idx, 1);
            let conf: i32 = ana_func_complexity_conf(best_idx);
            print("    ");
            print(int_to_str(rank + 1));
            print(". ");
            print(ana_func_name(best_idx));
            print("  ~");
            print(int_to_str(best_score));
            print(" (conf:");
            print(int_to_str(conf));
            print("%)  ");
            print(int_to_str(ana_func_lines(best_idx)));
            print("L ");
            print(int_to_str(ana_func_call_count(best_idx)));
            print("calls ");
            print(int_to_str(ana_func_params(best_idx)));
            println("params");
            rank = rank + 1;
        }
    }
}

fn cmd_diff() {
    if !ana_has_previous() {
        println("  No previous analysis to compare. Run 'analyze' twice.");
        return;
    }
    if ana_get_func_count() == 0 {
        println("  No current analysis. Use 'analyze <file.m>' first.");
        return;
    }

    // Header
    println("");
    print("  Diff: ");
    print(ana_prev_get_file());
    print(" -> ");
    println(ana_get_file());
    println("  ────────────────────────────────────");

    // Summary line changes
    let prev_lines: i32 = ana_prev_get_lines();
    let cur_lines: i32 = ana_get_lines();
    let line_delta: i32 = cur_lines - prev_lines;
    print("  Lines: ");
    print(int_to_str(prev_lines));
    print(" -> ");
    print(int_to_str(cur_lines));
    if line_delta > 0 {
        print(" (+");
        print(int_to_str(line_delta));
        println(")");
    } else if line_delta < 0 {
        print(" (");
        print(int_to_str(line_delta));
        println(")");
    } else {
        println(" (unchanged)");
    }

    // Summary function count changes
    let prev_fns: i32 = ana_prev_get_func_count();
    let cur_fns: i32 = ana_get_func_count();
    let fn_delta: i32 = cur_fns - prev_fns;
    print("  Functions: ");
    print(int_to_str(prev_fns));
    print(" -> ");
    print(int_to_str(cur_fns));
    if fn_delta > 0 {
        print(" (+");
        print(int_to_str(fn_delta));
        println(")");
    } else if fn_delta < 0 {
        print(" (");
        print(int_to_str(fn_delta));
        println(")");
    } else {
        println(" (unchanged)");
    }

    // New functions
    let new_fns: i32 = ana_diff_new();
    let new_count: i32 = array_len(new_fns);
    if new_count > 0 {
        println("");
        print("  + New (");
        print(int_to_str(new_count));
        println("):");
        var i: i32 = 0;
        while i < new_count {
            let name: string = sp_get(array_get(new_fns, i));
            let idx: i32 = ana_find_func(name);
            print("    + ");
            print(name);
            print("  ");
            print(int_to_str(ana_func_lines(idx)));
            print("L  ");
            print(int_to_str(ana_func_call_count(idx)));
            println(" calls");
            i = i + 1;
        }
    }

    // Removed functions
    let rem_fns: i32 = ana_diff_removed();
    let rem_count: i32 = array_len(rem_fns);
    if rem_count > 0 {
        println("");
        print("  - Removed (");
        print(int_to_str(rem_count));
        println("):");
        var i: i32 = 0;
        while i < rem_count {
            let name: string = sp_get(array_get(rem_fns, i));
            let prev_idx: i32 = ana_prev_find_func(name);
            print("    - ");
            print(name);
            print("  was ");
            print(int_to_str(ana_prev_func_lines(prev_idx)));
            print("L  ");
            print(int_to_str(ana_prev_func_calls(prev_idx)));
            println(" calls");
            i = i + 1;
        }
    }

    // Changed functions
    let chg_fns: i32 = ana_diff_changed();
    let chg_count: i32 = array_len(chg_fns);
    if chg_count > 0 {
        println("");
        print("  ~ Changed (");
        print(int_to_str(chg_count));
        println("):");
        var i: i32 = 0;
        while i < chg_count {
            let name: string = sp_get(array_get(chg_fns, i));
            let ld: i32 = ana_diff_line_delta(name);
            let cd: i32 = ana_diff_call_delta(name);
            print("    ~ ");
            print(name);
            if ld != 0 {
                print("  lines ");
                if ld > 0 { print("+"); }
                print(int_to_str(ld));
            }
            if cd != 0 {
                print("  calls ");
                if cd > 0 { print("+"); }
                print(int_to_str(cd));
            }
            println("");
            i = i + 1;
        }
    }

    // No changes
    if new_count == 0 && rem_count == 0 && chg_count == 0 && line_delta == 0 {
        println("");
        println("  No structural changes detected.");
    }

    println("");
}

fn cmd_unused() {
    if ana_get_func_count() == 0 {
        println("  No analysis loaded. Use 'analyze <file.m>' first.");
        return;
    }

    let dead: i32 = ana_dead_code();
    let count: i32 = array_len(dead);

    if count == 0 {
        println("  No unused functions detected.");
        println("  (main, test_, OP_, VT_, ANA_ prefixes are excluded)");
        return;
    }

    print("  Potentially unused functions (");
    print(int_to_str(count));
    println("):");
    println("  (No other function in this file calls these)");
    println("");

    var i: i32 = 0;
    while i < count {
        let idx: i32 = array_get(dead, i);
        print("    ");
        print(ana_func_name(idx));
        print("  ");
        print(int_to_str(ana_func_lines(idx)));
        print("L  ");
        let cc: i32 = ana_func_call_count(idx);
        if cc > 0 {
            print("calls ");
            print(int_to_str(cc));
            print(" others");
        } else {
            print("leaf function");
        }
        println("");
        i = i + 1;
    }

    println("");
    let ratio: i32 = count * 100 / ana_get_func_count();
    print("  ");
    print(int_to_str(ratio));
    println("% of functions have no internal callers.");
}

fn cmd_hotspots(args: string) {
    if ana_get_func_count() == 0 {
        println("  No analysis loaded. Use 'analyze <file.m>' first.");
        return;
    }

    let trimmed: string = str_trim(args);
    var n: i32 = 10;
    if len(trimmed) > 0 && is_number(trimmed) {
        n = str_to_int(trimmed);
        if n <= 0 { n = 10; }
    }
    if n > ana_get_func_count() { n = ana_get_func_count(); }

    println("  Hotspots (most-called functions):");
    println("  Functions that many others depend on.");
    println("");

    let spots: i32 = ana_hotspots(n);
    var i: i32 = 0;
    while i < array_len(spots) {
        let idx: i32 = array_get(spots, i);
        let name: string = ana_func_name(idx);
        let callers: i32 = ana_caller_count(name);

        if callers == 0 {
            i = array_len(spots);  // stop showing zero-caller functions
        } else {
            print("    ");
            print(int_to_str(i + 1));
            print(". ");
            print(name);
            print("  <- ");
            print(int_to_str(callers));
            print(" callers  ");
            print(int_to_str(ana_func_lines(idx)));
            println("L");
            i = i + 1;
        }
    }
    println("");
}

fn cmd_health() {
    if ana_get_func_count() == 0 {
        println("  No analysis loaded. Use 'analyze <file.m>' first.");
        return;
    }

    let score: i32 = ana_health_score();
    let conf: i32 = ana_health_conf();

    println("");
    println("  Code Health Report");
    println("  ══════════════════════════════════════");
    print("  File: ");
    println(ana_get_file());
    print("  Functions: ");
    print(int_to_str(ana_get_func_count()));
    print("  Lines: ");
    println(int_to_str(ana_get_lines()));
    println("");

    // Overall score
    print("  Health: ~");
    print(int_to_str(score));
    print("/100 (conf:");
    print(int_to_str(conf));
    println("%)");

    // Grade
    print("  Grade: ");
    if score >= 80 { println("A — well-structured"); }
    else if score >= 65 { println("B — good, minor issues"); }
    else if score >= 50 { println("C — acceptable, some concerns"); }
    else if score >= 35 { println("D — needs attention"); }
    else { println("F — significant restructuring needed"); }
    println("");

    // Size distribution summary
    var tiny: i32 = 0;
    var small: i32 = 0;
    var medium: i32 = 0;
    var large: i32 = 0;
    var huge: i32 = 0;
    var i: i32 = 0;
    while i < ana_get_func_count() {
        let l: i32 = ana_func_lines(i);
        if l <= 1 { tiny = tiny + 1; }
        else if l <= 5 { small = small + 1; }
        else if l <= 20 { medium = medium + 1; }
        else if l <= 50 { large = large + 1; }
        else { huge = huge + 1; }
        i = i + 1;
    }
    println("  Structure:");
    print("    tiny (1L):     ");
    print(int_to_str(tiny));
    print("  (");
    print(int_to_str(tiny * 100 / ana_get_func_count()));
    println("%)");
    print("    small (2-5L):  ");
    print(int_to_str(small));
    print("  (");
    print(int_to_str(small * 100 / ana_get_func_count()));
    println("%)");
    print("    medium (6-20): ");
    print(int_to_str(medium));
    print("  (");
    print(int_to_str(medium * 100 / ana_get_func_count()));
    println("%)");
    print("    large (21-50): ");
    print(int_to_str(large));
    print("  (");
    print(int_to_str(large * 100 / ana_get_func_count()));
    println("%)");
    print("    huge (50+):    ");
    print(int_to_str(huge));
    print("  (");
    print(int_to_str(huge * 100 / ana_get_func_count()));
    println("%)");

    // Warnings
    println("");
    println("  Findings:");
    var warnings: i32 = 0;

    // Large functions warning
    if huge > 0 {
        warnings = warnings + 1;
        print("    ! ");
        print(int_to_str(huge));
        print(" function");
        if huge > 1 { print("s"); }
        print(" over 50 lines: ");
        var shown: i32 = 0;
        i = 0;
        while i < ana_get_func_count() {
            if ana_func_lines(i) > 50 && shown < 3 {
                if shown > 0 { print(", "); }
                print(ana_func_name(i));
                print("(");
                print(int_to_str(ana_func_lines(i)));
                print("L)");
                shown = shown + 1;
            }
            i = i + 1;
        }
        if huge > 3 {
            print(" +");
            print(int_to_str(huge - 3));
            print(" more");
        }
        println("");
    }

    // Dead code warning
    let dead: i32 = ana_dead_code();
    let dead_count: i32 = array_len(dead);
    if dead_count > 0 {
        warnings = warnings + 1;
        print("    ! ");
        print(int_to_str(dead_count));
        print(" function");
        if dead_count > 1 { print("s"); }
        println(" with no callers (use 'unused' for details)");
    }

    // Hotspot warning (functions called by > 30% of all functions)
    var hot_count: i32 = 0;
    i = 0;
    while i < ana_get_func_count() {
        let cc: i32 = ana_caller_count(ana_func_name(i));
        if cc > ana_get_func_count() / 3 {
            hot_count = hot_count + 1;
        }
        i = i + 1;
    }
    if hot_count > 0 {
        warnings = warnings + 1;
        print("    ! ");
        print(int_to_str(hot_count));
        println(" critical hotspot(s) (called by >33% of functions)");
    }

    // All good
    if warnings == 0 {
        println("    No significant issues detected.");
    }

    // Populate VM
    ana_populate_intelligence();
    println("");
    println("  Results bound to VM: load _health, load _dead_code");
    println("");
}

fn cmd_summary() {
    if ana_get_func_count() == 0 {
        println("  No analysis loaded. Use 'analyze <file.m>' first.");
        return;
    }

    let nfuncs: i32 = ana_get_func_count();
    let nlines: i32 = ana_get_lines();
    let nglobals: i32 = ana_get_global_count();

    println("");
    println("  Summary");
    println("  ══════════════════════════════════════");
    print("  ");
    println(ana_get_file());
    println("");

    // Scale description
    print("  Scale: ");
    if nfuncs > 200 { print("large system"); }
    else if nfuncs > 50 { print("medium system"); }
    else if nfuncs > 20 { print("small system"); }
    else { print("module"); }
    print(" (");
    print(int_to_str(nfuncs));
    print(" functions, ");
    print(int_to_str(nlines));
    print(" lines, ");
    print(int_to_str(nglobals));
    println(" globals)");

    // Architecture: count roles
    var n_const: i32 = 0;
    var n_util: i32 = 0;
    var n_core: i32 = 0;
    var n_iface: i32 = 0;
    var n_test: i32 = 0;
    var i: i32 = 0;
    while i < nfuncs {
        let role: i32 = ana_func_role(i);
        if role == 1 { n_const = n_const + 1; }
        else if role == 2 { n_util = n_util + 1; }
        else if role == 3 { n_core = n_core + 1; }
        else if role == 4 { n_iface = n_iface + 1; }
        else if role == 5 { n_test = n_test + 1; }
        i = i + 1;
    }

    println("");
    println("  Architecture:");
    print("    ");
    print(int_to_str(n_const));
    print(" constants, ");
    print(int_to_str(n_util));
    print(" utilities, ");
    print(int_to_str(n_core));
    print(" core, ");
    print(int_to_str(n_iface));
    print(" interfaces, ");
    print(int_to_str(n_test));
    println(" tests");

    // Identify the "spine" — top 3 core functions by lines
    println("");
    println("  Spine (largest core functions):");
    var spine_shown: i32 = 0;
    // Simple selection: find top 3 core functions by lines
    var used: i32 = array_new(0);
    i = 0;
    while i < nfuncs {
        array_push(used, 0);
        i = i + 1;
    }

    while spine_shown < 3 {
        var best: i32 = 0 - 1;
        var best_lines: i32 = 0;
        i = 0;
        while i < nfuncs {
            if array_get(used, i) == 0 && ana_func_role(i) == 3 {
                if ana_func_lines(i) > best_lines {
                    best_lines = ana_func_lines(i);
                    best = i;
                }
            }
            i = i + 1;
        }
        if best < 0 { spine_shown = 3; }  // no more core funcs
        else {
            array_set(used, best, 1);
            print("    ");
            print(ana_func_name(best));
            print(" (");
            print(int_to_str(best_lines));
            print("L, ");
            print(int_to_str(ana_func_call_count(best)));
            print(" calls, risk:");
            print(int_to_str(ana_func_risk(best)));
            println(")");
            spine_shown = spine_shown + 1;
        }
    }

    // Health summary
    let score: i32 = ana_health_score();
    let conf: i32 = ana_health_conf();
    println("");
    print("  Health: ~");
    print(int_to_str(score));
    print("/100 (conf:");
    print(int_to_str(conf));
    print("%) — ");
    if score >= 80 { println("well-structured"); }
    else if score >= 65 { println("good with minor issues"); }
    else if score >= 50 { println("acceptable, some concerns"); }
    else { println("needs attention"); }

    // Key findings
    let dead: i32 = ana_dead_code();
    let ndead: i32 = array_len(dead);
    let nsug: i32 = ana_suggest();

    println("");
    println("  Key findings:");
    print("    ");
    print(int_to_str(ndead));
    println(" potentially unused functions");
    print("    ");
    print(int_to_str(nsug));
    println(" improvement suggestions (use 'suggest' for details)");

    // Dependencies
    let nuses: i32 = ana_get_use_count();
    if nuses > 0 {
        print("    ");
        print(int_to_str(nuses));
        println(" external dependencies (use 'deps' for details)");
    }

    println("");
}

fn cmd_audit() {
    if ana_get_func_count() == 0 {
        println("  No analysis loaded. Use 'analyze <file.m>' first.");
        return;
    }

    let nfuncs: i32 = ana_get_func_count();
    let nlines: i32 = ana_get_lines();

    println("");
    println("  ┌─────────────────────────────────────────────┐");
    println("  │              Code Audit Report               │");
    println("  └─────────────────────────────────────────────┘");
    print("  File: ");
    println(ana_get_file());
    print("  Functions: ");
    print(int_to_str(nfuncs));
    print("  Lines: ");
    print(int_to_str(nlines));
    print("  Globals: ");
    println(int_to_str(ana_get_global_count()));
    println("");

    // 1. Health Score
    let score: i32 = ana_health_score();
    let conf: i32 = ana_health_conf();
    print("  1. HEALTH: ~");
    print(int_to_str(score));
    print("/100 (conf:");
    print(int_to_str(conf));
    print("%) ");
    if score >= 80 { println("[PASS]"); }
    else if score >= 50 { println("[WARN]"); }
    else { println("[FAIL]"); }

    // 2. Size Balance
    var huge_count: i32 = 0;
    var huge_total_lines: i32 = 0;
    var i: i32 = 0;
    while i < nfuncs {
        if ana_func_lines(i) > 50 {
            huge_count = huge_count + 1;
            huge_total_lines = huge_total_lines + ana_func_lines(i);
        }
        i = i + 1;
    }
    print("  2. SIZE BALANCE: ");
    if huge_count == 0 { println("no large functions [PASS]"); }
    else {
        print(int_to_str(huge_count));
        print(" large functions (");
        print(int_to_str(huge_total_lines));
        print(" lines, ");
        print(int_to_str(huge_total_lines * 100 / nlines));
        println("% of code) [WARN]");
    }

    // 3. Dead Code
    let dead: i32 = ana_dead_code();
    let ndead: i32 = array_len(dead);
    print("  3. DEAD CODE: ");
    if ndead == 0 { println("none detected [PASS]"); }
    else {
        print(int_to_str(ndead));
        print(" functions (");
        print(int_to_str(ndead * 100 / nfuncs));
        println("%) [WARN]");
    }

    // 4. Coupling
    let pairs: i32 = ana_coupled_pairs(3);
    let npairs: i32 = array_len(pairs) / 3;
    var mutual_deps: i32 = 0;
    i = 0;
    while i < npairs {
        if array_get(pairs, i * 3 + 2) >= 2 {
            mutual_deps = mutual_deps + 1;
        }
        i = i + 1;
    }
    print("  4. COUPLING: ");
    if mutual_deps == 0 { println("no mutual dependencies [PASS]"); }
    else {
        print(int_to_str(mutual_deps));
        println(" mutual dependency pair(s) [WARN]");
    }

    // 5. Hotspots
    var critical_hotspots: i32 = 0;
    i = 0;
    while i < nfuncs {
        let cc: i32 = ana_caller_count(ana_func_name(i));
        if cc > nfuncs / 3 { critical_hotspots = critical_hotspots + 1; }
        i = i + 1;
    }
    print("  5. HOTSPOTS: ");
    if critical_hotspots == 0 { println("no critical hotspots [PASS]"); }
    else {
        print(int_to_str(critical_hotspots));
        println(" function(s) called by >33% of codebase [WARN]");
    }

    // 6. Architecture balance
    var n_const: i32 = 0;
    var n_util: i32 = 0;
    var n_core: i32 = 0;
    var n_iface: i32 = 0;
    i = 0;
    while i < nfuncs {
        let role: i32 = ana_func_role(i);
        if role == 1 { n_const = n_const + 1; }
        else if role == 2 { n_util = n_util + 1; }
        else if role == 3 { n_core = n_core + 1; }
        else if role == 4 { n_iface = n_iface + 1; }
        i = i + 1;
    }
    print("  6. ARCHITECTURE: ");
    // Good architecture: many utilities, few core, some interfaces
    if n_core <= nfuncs / 5 { println("well-layered [PASS]"); }
    else {
        print(int_to_str(n_core * 100 / nfuncs));
        println("% core — consider extracting utilities [WARN]");
    }

    // Overall verdict
    println("");
    var warnings: i32 = 0;
    if score < 80 { warnings = warnings + 1; }
    if huge_count > 0 { warnings = warnings + 1; }
    if ndead > nfuncs / 5 { warnings = warnings + 1; }
    if mutual_deps > 0 { warnings = warnings + 1; }
    if critical_hotspots > 0 { warnings = warnings + 1; }
    if n_core > nfuncs / 5 { warnings = warnings + 1; }

    print("  VERDICT: ");
    if warnings == 0 { println("CLEAN — no issues detected"); }
    else if warnings <= 2 { println("GOOD — minor issues, low risk"); }
    else if warnings <= 4 { println("FAIR — some concerns, review recommended"); }
    else { println("ATTENTION — multiple issues, refactoring recommended"); }

    // Suggestions count
    let nsug: i32 = ana_suggest();
    print("  ");
    print(int_to_str(nsug));
    println(" improvement suggestions available (use 'suggest' for details)");

    // Populate VM
    ana_populate_intelligence();
    ana_populate_suggestions();
    println("  Results bound to VM.");
    println("");
}

fn cmd_map() {
    if ana_get_func_count() == 0 {
        println("  No analysis loaded. Use 'analyze <file.m>' first.");
        return;
    }

    let nfuncs: i32 = ana_get_func_count();

    println("");
    println("  Dependency Map");
    println("  ══════════════════════════════════════");
    println("");

    // Group functions by role
    // Print entry points (interfaces) first — they're the "top" of the architecture
    var has_iface: bool = false;
    var i: i32 = 0;
    while i < nfuncs {
        if ana_func_role(i) == 4 {
            if !has_iface {
                println("  Entry Points:");
                has_iface = true;
            }
            print("    [");
            print(ana_func_name(i));
            print("]");
            let calls: i32 = ana_func_call_count(i);
            if calls > 0 {
                print(" -> ");
                var j: i32 = 0;
                var shown: i32 = 0;
                while j < calls && shown < 5 {
                    if shown > 0 { print(", "); }
                    print(ana_func_call_name(i, j));
                    shown = shown + 1;
                    j = j + 1;
                }
                if calls > 5 {
                    print(" +");
                    print(int_to_str(calls - 5));
                }
            }
            println("");
        }
        i = i + 1;
    }
    if has_iface { println(""); }

    // Core functions — the spine
    println("  Core Functions:");
    i = 0;
    while i < nfuncs {
        if ana_func_role(i) == 3 {
            let name: string = ana_func_name(i);
            let lines: i32 = ana_func_lines(i);
            let callers: i32 = ana_caller_count(name);
            let calls: i32 = ana_func_call_count(i);

            // Draw box proportional to size
            print("    ");
            if lines > 100 { print("████ "); }
            else if lines > 50 { print("███ "); }
            else if lines > 20 { print("██ "); }
            else { print("█ "); }
            print(name);
            print(" (");
            print(int_to_str(lines));
            print("L");
            if callers > 0 {
                print(", ");
                print(int_to_str(callers));
                print("<-");
            }
            if calls > 0 {
                print(", ");
                print(int_to_str(calls));
                print("->");
            }
            println(")");
        }
        i = i + 1;
    }
    println("");

    // Utilities — grouped by caller count
    var util_widely_used: i32 = 0;  // 5+ callers
    var util_normal: i32 = 0;        // 1-4 callers
    i = 0;
    while i < nfuncs {
        if ana_func_role(i) == 2 {
            let cc: i32 = ana_caller_count(ana_func_name(i));
            if cc >= 5 { util_widely_used = util_widely_used + 1; }
            else { util_normal = util_normal + 1; }
        }
        i = i + 1;
    }

    print("  Utilities: ");
    print(int_to_str(util_widely_used));
    print(" widely used, ");
    print(int_to_str(util_normal));
    println(" normal");

    // Show widely-used utilities
    if util_widely_used > 0 {
        i = 0;
        while i < nfuncs {
            if ana_func_role(i) == 2 {
                let name: string = ana_func_name(i);
                let cc: i32 = ana_caller_count(name);
                if cc >= 5 {
                    print("    * ");
                    print(name);
                    print(" (");
                    print(int_to_str(cc));
                    println(" callers)");
                }
            }
            i = i + 1;
        }
    }

    // Constants count
    var n_const: i32 = 0;
    i = 0;
    while i < nfuncs {
        if ana_func_role(i) == 1 { n_const = n_const + 1; }
        i = i + 1;
    }
    if n_const > 0 {
        print("  Constants: ");
        print(int_to_str(n_const));
        println(" value definitions");
    }

    // Tests count
    var n_test: i32 = 0;
    i = 0;
    while i < nfuncs {
        if ana_func_role(i) == 5 { n_test = n_test + 1; }
        i = i + 1;
    }
    if n_test > 0 {
        print("  Tests: ");
        print(int_to_str(n_test));
        println(" test functions");
    }

    println("");
}

fn cmd_explain(args: string) {
    let name: string = str_trim(args);
    if len(name) == 0 {
        println("  Error: use 'explain <function_name>'");
        return;
    }

    if ana_get_func_count() == 0 {
        println("  No analysis loaded. Use 'analyze <file.m>' first.");
        return;
    }

    let idx: i32 = ana_find_func(name);
    if idx < 0 {
        print("  Function not found: ");
        println(name);
        return;
    }

    let lines: i32 = ana_func_lines(idx);
    let params: i32 = ana_func_params(idx);
    let calls: i32 = ana_func_call_count(idx);
    let callers: i32 = ana_caller_count(name);
    let role: i32 = ana_func_role(idx);

    println("");
    print("  ");
    print(name);

    // Describe based on role
    if role == 1 {
        print(" is a constant — returns a fixed value");
    } else if role == 5 {
        print(" is a test function — verifies behavior");
    } else if role == 4 {
        print(" is an entry point — called from outside this file");
    } else if role == 2 {
        print(" is a utility — a helper used by other functions");
    } else {
        print(" is a core function — central to this file's purpose");
    }
    println(".");

    // Size description
    print("  It is ");
    if lines <= 5 { print("tiny"); }
    else if lines <= 20 { print("small"); }
    else if lines <= 50 { print("medium-sized"); }
    else if lines <= 100 { print("large"); }
    else if lines <= 200 { print("very large"); }
    else { print("massive"); }
    print(" (");
    print(int_to_str(lines));
    print(" lines)");
    if params > 0 {
        print(" and takes ");
        print(int_to_str(params));
        print(" parameter");
        if params > 1 { print("s"); }
    }
    println(".");

    // Dependency description
    if calls > 0 {
        print("  It depends on ");
        print(int_to_str(calls));
        print(" other function");
        if calls > 1 { print("s"); }

        // Name the most important callees (first 3)
        print(": ");
        var shown: i32 = 0;
        var i: i32 = 0;
        while i < calls && shown < 3 {
            if shown > 0 { print(", "); }
            print(ana_func_call_name(idx, i));
            shown = shown + 1;
            i = i + 1;
        }
        if calls > 3 {
            print(" and ");
            print(int_to_str(calls - 3));
            print(" more");
        }
        println(".");
    } else {
        println("  It has no dependencies on other functions.");
    }

    // Impact description
    if callers > 5 {
        print("  It is widely used (");
        print(int_to_str(callers));
        println(" callers) — changes here ripple through the codebase.");
    } else if callers > 0 {
        print("  It is used by ");
        print(int_to_str(callers));
        print(" function");
        if callers > 1 { print("s"); }
        println(".");
    } else if role != 4 && role != 5 && role != 1 {
        println("  It appears unused — no other function calls it.");
    }

    // Pattern detection
    if lines > 100 && calls > 20 {
        println("  Pattern: dispatcher — large function routing to many smaller ones.");
    } else if lines <= 5 && calls == 0 && callers > 3 {
        println("  Pattern: accessor — simple value provider used broadly.");
    } else if callers == 0 && calls > 5 {
        println("  Pattern: orchestrator — coordinates others but isn't called internally.");
    } else if lines <= 2 && callers > 0 {
        println("  Pattern: wrapper — thin delegation layer.");
    }

    println("");
}

fn cmd_focus(args: string) {
    let name: string = str_trim(args);
    if len(name) == 0 {
        println("  Error: use 'focus <function_name>'");
        return;
    }

    if ana_get_func_count() == 0 {
        println("  No analysis loaded. Use 'analyze <file.m>' first.");
        return;
    }

    let idx: i32 = ana_find_func(name);
    if idx < 0 {
        print("  Function not found: ");
        println(name);
        return;
    }

    let lines: i32 = ana_func_lines(idx);
    let params: i32 = ana_func_params(idx);
    let calls: i32 = ana_func_call_count(idx);
    let callers: i32 = ana_caller_count(name);
    let role: i32 = ana_func_role(idx);
    let risk: i32 = ana_func_risk(idx);

    println("");
    print("  Focus: ");
    println(name);
    println("  ══════════════════════════════════════");

    // Identity
    print("  Role: ");
    println(ana_role_name(role));
    print("  Lines: ");
    print(int_to_str(lines));
    print("  Params: ");
    print(int_to_str(params));
    print("  Calls: ");
    print(int_to_str(calls));
    print("  Callers: ");
    println(int_to_str(callers));
    println("");

    // Risk assessment
    print("  Risk: ~");
    print(int_to_str(risk));
    print("/100");
    if risk >= 70 { println("  !! HIGH — changes here affect many parts"); }
    else if risk >= 40 { println("  ! MEDIUM — test after changes"); }
    else { println("  LOW — safe to modify"); }
    println("");

    // Who calls this function
    let who: i32 = ana_who_calls(name);
    let nwho: i32 = array_len(who);
    if nwho > 0 {
        print("  Called by (");
        print(int_to_str(nwho));
        println("):");
        var i: i32 = 0;
        var shown: i32 = 0;
        while i < nwho && shown < 10 {
            print("    <- ");
            println(ana_func_name(array_get(who, i)));
            shown = shown + 1;
            i = i + 1;
        }
        if nwho > 10 {
            print("    ... +");
            print(int_to_str(nwho - 10));
            println(" more");
        }
    } else {
        println("  Called by: nobody (entry point or unused)");
    }

    // What this function calls
    if calls > 0 {
        print("  Calls (");
        print(int_to_str(calls));
        println("):");
        var j: i32 = 0;
        var shown2: i32 = 0;
        while j < calls && shown2 < 10 {
            print("    -> ");
            println(ana_func_call_name(idx, j));
            shown2 = shown2 + 1;
            j = j + 1;
        }
        if calls > 10 {
            print("    ... +");
            print(int_to_str(calls - 10));
            println(" more");
        }
    }
    println("");

    // Suggestions specific to this function
    var has_sug: bool = false;
    if lines > 100 {
        has_sug = true;
        print("  Suggestion: SPLIT — ");
        print(int_to_str(lines));
        println(" lines is too large for a single function");
    }
    if calls > 20 {
        has_sug = true;
        print("  Suggestion: EXTRACT — ");
        print(int_to_str(calls));
        println(" callees means high fan-out, extract helper functions");
    }
    if callers == 0 && role != 5 && role != 1 {
        has_sug = true;
        println("  Suggestion: REMOVE — no callers, possibly dead code");
    }
    if callers > 8 {
        has_sug = true;
        print("  Suggestion: PROTECT — ");
        print(int_to_str(callers));
        println(" callers, changes have wide impact");
    }
    if !has_sug {
        println("  No specific suggestions — function looks well-structured.");
    }

    // Bind to VM
    ana_populate_focus(idx);
    print("  Results bound to VM: load focus.");
    print(name);
    println(".role/risk/callers/lines/calls");
    println("");
}

fn cmd_suggest() {
    if ana_get_func_count() == 0 {
        println("  No analysis loaded. Use 'analyze <file.m>' first.");
        return;
    }

    let nsug: i32 = ana_suggest();
    if nsug == 0 {
        println("  No suggestions — code looks clean.");
        return;
    }

    println("");
    println("  Suggestions");
    println("  ══════════════════════════════════════");

    // Show high priority first, then medium, then low
    var priority: i32 = 3;
    while priority >= 1 {
        var shown_header: bool = false;
        var i: i32 = 0;
        while i < nsug {
            if ana_sug_priority(i) == priority {
                if !shown_header {
                    print("  ");
                    if priority == 3 { println("[HIGH]"); }
                    else if priority == 2 { println("[MEDIUM]"); }
                    else { println("[LOW]"); }
                    shown_header = true;
                }
                print("    ");
                let stype: string = ana_sug_type(i);
                if str_eq(stype, "split") { print("SPLIT"); }
                else if str_eq(stype, "remove") { print("REMOVE"); }
                else if str_eq(stype, "extract") { print("EXTRACT"); }
                else if str_eq(stype, "protect") { print("PROTECT"); }
                else { print(stype); }
                print(" ");
                print(ana_sug_target(i));
                print(" — ");
                println(ana_sug_reason(i));
            }
            i = i + 1;
        }
        priority = priority - 1;
    }

    println("");
    print("  Total: ");
    print(int_to_str(nsug));
    println(" suggestions");

    // Count by priority
    var high: i32 = 0;
    var med: i32 = 0;
    var low: i32 = 0;
    var j: i32 = 0;
    while j < nsug {
        let p: i32 = ana_sug_priority(j);
        if p == 3 { high = high + 1; }
        else if p == 2 { med = med + 1; }
        else { low = low + 1; }
        j = j + 1;
    }
    print("  ");
    print(int_to_str(high));
    print(" high, ");
    print(int_to_str(med));
    print(" medium, ");
    print(int_to_str(low));
    println(" low");

    // Populate VM
    ana_populate_suggestions();
    println("  Results bound to VM: load _suggestions, _sug_high, _sug_medium, _sug_low");
    println("");
}

fn cmd_coupling(args: string) {
    if ana_get_func_count() == 0 {
        println("  No analysis loaded. Use 'analyze <file.m>' first.");
        return;
    }

    var n: i32 = 5;
    let trimmed: string = str_trim(args);
    if len(trimmed) > 0 {
        n = str_to_int(trimmed);
        if n <= 0 { n = 5; }
    }

    let pairs: i32 = ana_coupled_pairs(n);
    let npairs: i32 = array_len(pairs) / 3;

    if npairs == 0 {
        println("  No coupled function pairs found.");
        return;
    }

    println("");
    println("  Coupling Analysis");
    println("  ══════════════════════════════════════");
    print("  Top ");
    print(int_to_str(npairs));
    println(" coupled pairs:");
    println("");

    var i: i32 = 0;
    while i < npairs {
        let a_idx: i32 = array_get(pairs, i * 3);
        let b_idx: i32 = array_get(pairs, i * 3 + 1);
        let score: i32 = array_get(pairs, i * 3 + 2);

        print("  ");
        print(int_to_str(i + 1));
        print(". ");
        print(ana_func_name(a_idx));
        print(" <-> ");
        print(ana_func_name(b_idx));
        print("  (score: ");
        print(int_to_str(score));
        print(")");

        // Annotate coupling type
        if score >= 2 {
            print("  !! mutual dependency");
        }
        println("");
        i = i + 1;
    }

    // Bind to VM
    let tick: i32 = vm_get_tick();
    env_bind("_coupled_pairs", val_i32(npairs), tick, "coupling");
    println("");
    println("  Results bound to VM: load _coupled_pairs");
    println("");
}

fn cmd_search(args: string) {
    let pattern: string = str_trim(args);
    if len(pattern) == 0 {
        println("  Error: use 'search <pattern>'");
        return;
    }

    if ana_get_func_count() == 0 {
        println("  No analysis loaded. Use 'analyze <file.m>' first.");
        return;
    }

    print("  Functions matching '");
    print(pattern);
    println("':");

    var found: i32 = 0;
    var i: i32 = 0;
    while i < ana_get_func_count() {
        let name: string = ana_func_name(i);
        if str_contains(name, pattern) {
            print("    ");
            print(name);
            print("  ");
            print(int_to_str(ana_func_lines(i)));
            print("L  ");
            let pc: i32 = ana_func_params(i);
            print(int_to_str(pc));
            print(" params");
            println("");
            found = found + 1;
        }
        i = i + 1;
    }

    if found == 0 {
        println("    (no matches)");
    } else {
        print("  ");
        print(int_to_str(found));
        print(" match");
        if found > 1 { print("es"); }
        println("");
    }
}

fn cmd_deps() {
    if ana_get_func_count() == 0 && ana_get_use_count() == 0 {
        println("  No analysis loaded. Use 'analyze <file.m>' first.");
        return;
    }

    print("  Dependencies of ");
    println(ana_get_file());

    if ana_get_use_count() == 0 {
        println("    (no dependencies)");
        return;
    }

    var i: i32 = 0;
    while i < ana_get_use_count() {
        print("    use \"");
        print(ana_use_path(i));
        println("\"");
        i = i + 1;
    }

    print("  ");
    print(int_to_str(ana_get_use_count()));
    println(" dependencies");
}

fn cmd_top(args: string) {
    if ana_get_func_count() == 0 {
        println("  No analysis loaded. Use 'analyze <file.m>' first.");
        return;
    }

    let trimmed: string = str_trim(args);
    var n: i32 = 10;
    if len(trimmed) > 0 && is_number(trimmed) {
        n = str_to_int(trimmed);
        if n <= 0 { n = 10; }
    }
    if n > ana_get_func_count() {
        n = ana_get_func_count();
    }

    print("  Top ");
    print(int_to_str(n));
    println(" largest functions:");

    // Selection sort approach: find max N times using a "used" marker array
    var used: i32 = array_new(0);
    var ui: i32 = 0;
    while ui < ana_get_func_count() {
        array_push(used, 0);
        ui = ui + 1;
    }

    var rank: i32 = 0;
    while rank < n {
        var best_idx: i32 = 0 - 1;
        var best_lines: i32 = 0 - 1;
        var i: i32 = 0;
        while i < ana_get_func_count() {
            if array_get(used, i) == 0 {
                let l: i32 = ana_func_lines(i);
                if l > best_lines {
                    best_lines = l;
                    best_idx = i;
                }
            }
            i = i + 1;
        }
        if best_idx < 0 { break; }
        array_set(used, best_idx, 1);

        print("    ");
        print(int_to_str(rank + 1));
        print(". ");
        print(ana_func_name(best_idx));
        print("  ");
        print(int_to_str(best_lines));
        print("L  ");
        print(int_to_str(ana_func_params(best_idx)));
        print(" params  ");
        print(int_to_str(ana_func_call_count(best_idx)));
        println(" calls");

        rank = rank + 1;
    }
}

// ── Expression evaluator ─────────────────────────────
// Tokenizes, parses, compiles to VM bytecode, runs.
// Supports: integers, variables, +, -, *, /, %, (, ), unary -
// Comparisons: ==, !=, <, >, <=, >=
// Booleans: true, false, &&, ||, !

// Token types for expression parser
fn ET_NUM() -> i32   { return 1; }
fn ET_IDENT() -> i32 { return 2; }
fn ET_PLUS() -> i32  { return 3; }
fn ET_MINUS() -> i32 { return 4; }
fn ET_STAR() -> i32  { return 5; }
fn ET_SLASH() -> i32 { return 6; }
fn ET_MOD() -> i32   { return 7; }
fn ET_LPAREN() -> i32 { return 8; }
fn ET_RPAREN() -> i32 { return 9; }
fn ET_EOF2() -> i32  { return 10; }
fn ET_STR() -> i32   { return 11; }
fn ET_EQ() -> i32    { return 12; }
fn ET_NEQ() -> i32   { return 13; }
fn ET_LT() -> i32    { return 14; }
fn ET_GT() -> i32    { return 15; }
fn ET_LTE() -> i32   { return 16; }
fn ET_GTE() -> i32   { return 17; }
fn ET_AND() -> i32   { return 18; }
fn ET_OR() -> i32    { return 19; }
fn ET_NOT() -> i32   { return 20; }

// Expression tokenizer state
var etk_src: string = "";
var etk_pos: i32 = 0;
var etk_types: i32 = 0;
var etk_ivals: i32 = 0;
var etk_svals: i32 = 0;
var etk_count: i32 = 0;
var etk_cur: i32 = 0;

fn etk_is_alpha(c: i32) -> bool {
    if c >= 65 && c <= 90 { return true; }
    if c >= 97 && c <= 122 { return true; }
    return c == 95;
}

fn etk_tokenize(src: string) -> i32 {
    etk_src = src;
    etk_pos = 0;
    etk_types = array_new(0);
    etk_ivals = array_new(0);
    etk_svals = array_new(0);
    etk_count = 0;
    etk_cur = 0;

    while etk_pos < len(src) {
        let c: i32 = char_at(src, etk_pos);

        if c == 32 || c == 9 {
            etk_pos = etk_pos + 1;
        }
        else if is_digit_char(c) {
            var n: i32 = 0;
            while etk_pos < len(src) && is_digit_char(char_at(src, etk_pos)) {
                n = n * 10 + (char_at(src, etk_pos) - 48);
                etk_pos = etk_pos + 1;
            }
            array_push(etk_types, ET_NUM());
            array_push(etk_ivals, n);
            array_push(etk_svals, 0);
            etk_count = etk_count + 1;
        }
        else if etk_is_alpha(c) {
            var start: i32 = etk_pos;
            while etk_pos < len(src) && (etk_is_alpha(char_at(src, etk_pos)) || is_digit_char(char_at(src, etk_pos))) {
                etk_pos = etk_pos + 1;
            }
            let word: string = substr(src, start, etk_pos - start);
            array_push(etk_types, ET_IDENT());
            array_push(etk_ivals, 0);
            array_push(etk_svals, sp_store(word));
            etk_count = etk_count + 1;
        }
        else if c == 34 {
            etk_pos = etk_pos + 1;
            var start: i32 = etk_pos;
            while etk_pos < len(src) && char_at(src, etk_pos) != 34 {
                etk_pos = etk_pos + 1;
            }
            let s: string = substr(src, start, etk_pos - start);
            if etk_pos < len(src) { etk_pos = etk_pos + 1; }
            array_push(etk_types, ET_STR());
            array_push(etk_ivals, 0);
            array_push(etk_svals, sp_store(s));
            etk_count = etk_count + 1;
        }
        else if c == 61 && etk_pos + 1 < len(src) && char_at(src, etk_pos + 1) == 61 {
            array_push(etk_types, ET_EQ()); array_push(etk_ivals, 0); array_push(etk_svals, 0);
            etk_count = etk_count + 1; etk_pos = etk_pos + 2;
        }
        else if c == 33 && etk_pos + 1 < len(src) && char_at(src, etk_pos + 1) == 61 {
            array_push(etk_types, ET_NEQ()); array_push(etk_ivals, 0); array_push(etk_svals, 0);
            etk_count = etk_count + 1; etk_pos = etk_pos + 2;
        }
        else if c == 60 && etk_pos + 1 < len(src) && char_at(src, etk_pos + 1) == 61 {
            array_push(etk_types, ET_LTE()); array_push(etk_ivals, 0); array_push(etk_svals, 0);
            etk_count = etk_count + 1; etk_pos = etk_pos + 2;
        }
        else if c == 62 && etk_pos + 1 < len(src) && char_at(src, etk_pos + 1) == 61 {
            array_push(etk_types, ET_GTE()); array_push(etk_ivals, 0); array_push(etk_svals, 0);
            etk_count = etk_count + 1; etk_pos = etk_pos + 2;
        }
        else if c == 38 && etk_pos + 1 < len(src) && char_at(src, etk_pos + 1) == 38 {
            array_push(etk_types, ET_AND()); array_push(etk_ivals, 0); array_push(etk_svals, 0);
            etk_count = etk_count + 1; etk_pos = etk_pos + 2;
        }
        else if c == 124 && etk_pos + 1 < len(src) && char_at(src, etk_pos + 1) == 124 {
            array_push(etk_types, ET_OR()); array_push(etk_ivals, 0); array_push(etk_svals, 0);
            etk_count = etk_count + 1; etk_pos = etk_pos + 2;
        }
        else if c == 43 { array_push(etk_types, ET_PLUS()); array_push(etk_ivals, 0); array_push(etk_svals, 0); etk_count = etk_count + 1; etk_pos = etk_pos + 1; }
        else if c == 45 { array_push(etk_types, ET_MINUS()); array_push(etk_ivals, 0); array_push(etk_svals, 0); etk_count = etk_count + 1; etk_pos = etk_pos + 1; }
        else if c == 42 { array_push(etk_types, ET_STAR()); array_push(etk_ivals, 0); array_push(etk_svals, 0); etk_count = etk_count + 1; etk_pos = etk_pos + 1; }
        else if c == 47 { array_push(etk_types, ET_SLASH()); array_push(etk_ivals, 0); array_push(etk_svals, 0); etk_count = etk_count + 1; etk_pos = etk_pos + 1; }
        else if c == 37 { array_push(etk_types, ET_MOD()); array_push(etk_ivals, 0); array_push(etk_svals, 0); etk_count = etk_count + 1; etk_pos = etk_pos + 1; }
        else if c == 40 { array_push(etk_types, ET_LPAREN()); array_push(etk_ivals, 0); array_push(etk_svals, 0); etk_count = etk_count + 1; etk_pos = etk_pos + 1; }
        else if c == 41 { array_push(etk_types, ET_RPAREN()); array_push(etk_ivals, 0); array_push(etk_svals, 0); etk_count = etk_count + 1; etk_pos = etk_pos + 1; }
        else if c == 60 { array_push(etk_types, ET_LT()); array_push(etk_ivals, 0); array_push(etk_svals, 0); etk_count = etk_count + 1; etk_pos = etk_pos + 1; }
        else if c == 62 { array_push(etk_types, ET_GT()); array_push(etk_ivals, 0); array_push(etk_svals, 0); etk_count = etk_count + 1; etk_pos = etk_pos + 1; }
        else if c == 33 { array_push(etk_types, ET_NOT()); array_push(etk_ivals, 0); array_push(etk_svals, 0); etk_count = etk_count + 1; etk_pos = etk_pos + 1; }
        else {
            etk_pos = etk_pos + 1;
        }
    }

    array_push(etk_types, ET_EOF2());
    array_push(etk_ivals, 0);
    array_push(etk_svals, 0);
    etk_count = etk_count + 1;
    return etk_count;
}

fn etk_type() -> i32 { return array_get(etk_types, etk_cur); }
fn etk_ival() -> i32 { return array_get(etk_ivals, etk_cur); }
fn etk_sval() -> string { return sp_get(array_get(etk_svals, etk_cur)); }
fn etk_advance() { etk_cur = etk_cur + 1; }

// ── Recursive descent parser -> VM bytecode ──────────
// Precedence (low to high):
//   ||  ->  &&  ->  ==,!=  ->  <,>,<=,>=  ->  +,-  ->  *,/,%  ->  unary -,!  ->  atom

var expr_error: bool = false;

fn parse_expr() {
    parse_or();
}

fn parse_or() {
    parse_and();
    while etk_type() == ET_OR() && !expr_error {
        etk_advance();
        parse_and();
        code_add(OP_OR());
    }
}

fn parse_and() {
    parse_equality();
    while etk_type() == ET_AND() && !expr_error {
        etk_advance();
        parse_equality();
        code_add(OP_AND());
    }
}

fn parse_equality() {
    parse_comparison();
    while (etk_type() == ET_EQ() || etk_type() == ET_NEQ()) && !expr_error {
        let op: i32 = etk_type();
        etk_advance();
        parse_comparison();
        if op == ET_EQ() { code_add(OP_EQ()); }
        else { code_add(OP_NEQ()); }
    }
}

fn parse_comparison() {
    parse_additive();
    while (etk_type() == ET_LT() || etk_type() == ET_GT() || etk_type() == ET_LTE() || etk_type() == ET_GTE()) && !expr_error {
        let op: i32 = etk_type();
        etk_advance();
        parse_additive();
        if op == ET_LT() { code_add(OP_LT()); }
        else if op == ET_GT() { code_add(OP_GT()); }
        else if op == ET_LTE() { code_add(OP_LTE()); }
        else { code_add(OP_GTE()); }
    }
}

fn parse_additive() {
    parse_multiplicative();
    while (etk_type() == ET_PLUS() || etk_type() == ET_MINUS()) && !expr_error {
        let op: i32 = etk_type();
        etk_advance();
        parse_multiplicative();
        if op == ET_PLUS() { code_add(OP_ADD()); }
        else { code_add(OP_SUB()); }
    }
}

fn parse_multiplicative() {
    parse_unary();
    while (etk_type() == ET_STAR() || etk_type() == ET_SLASH() || etk_type() == ET_MOD()) && !expr_error {
        let op: i32 = etk_type();
        etk_advance();
        parse_unary();
        if op == ET_STAR() { code_add(OP_MUL()); }
        else if op == ET_SLASH() { code_add(OP_DIV()); }
        else { code_add(OP_MOD()); }
    }
}

fn parse_unary() {
    if etk_type() == ET_MINUS() {
        etk_advance();
        parse_unary();
        code_add(OP_NEG());
    } else if etk_type() == ET_NOT() {
        etk_advance();
        parse_unary();
        code_add(OP_NOT());
    } else {
        parse_atom();
    }
}

fn parse_atom() {
    let t: i32 = etk_type();

    if t == ET_NUM() {
        code_add(OP_PUSH_I32());
        code_add(etk_ival());
        etk_advance();
    }
    else if t == ET_STR() {
        let ni: i32 = name_add(etk_sval());
        code_add(OP_PUSH_STR());
        code_add(ni);
        etk_advance();
    }
    else if t == ET_IDENT() {
        let word: string = etk_sval();
        if str_eq(word, "true") {
            code_add(OP_PUSH_BOOL());
            code_add(1);
        } else if str_eq(word, "false") {
            code_add(OP_PUSH_BOOL());
            code_add(0);
        } else if str_eq(word, "nil") {
            code_add(OP_PUSH_NIL());
        } else {
            let ni: i32 = name_add(word);
            code_add(OP_LOAD());
            code_add(ni);
        }
        etk_advance();
    }
    else if t == ET_LPAREN() {
        etk_advance();
        parse_expr();
        if etk_type() == ET_RPAREN() {
            etk_advance();
        } else {
            expr_error = true;
            println("  Error: expected ')'");
        }
    }
    else {
        expr_error = true;
    }
}

// ── Evaluate expression string ───────────────────────

fn eval_expression(src: string) {
    etk_tokenize(src);
    expr_error = false;

    vm_reset_code();
    parse_expr();

    if expr_error { return; }

    if etk_type() != ET_EOF2() {
        println("  Error: unexpected input after expression");
        return;
    }

    code_add(OP_HALT());
    vm_run();

    if stack_top > 0 {
        let result: i32 = stack_peek();
        print("  = ");
        print_val(result);
        println("");
    }
}

// ── Mind commands ────────────────────────────────────

fn cmd_think(args: string) {
    if !mind_initialized {
        mind_init();
    }

    var n: i32 = 5;
    let trimmed: string = str_trim(args);
    if len(trimmed) > 0 && is_number(trimmed) {
        n = str_to_int(trimmed);
        if n < 1 { n = 1; }
        if n > 100 { n = 100; }
    }

    // If no files seeded, use current analysis or ask for one
    if mind_get_file_count() == 0 {
        if len(ana_get_file()) > 0 {
            mind_seed(ana_get_file());
        } else {
            println("  No files to think about. Use 'analyze <file>' first, or 'seed <file>'.");
            return;
        }
    }

    println("");
    print("  Machine Mind — ");
    print(int_to_str(n));
    println(" cycles");
    println("  ─────────────────────");

    var i: i32 = 0;
    while i < n {
        let prev_cycle: i32 = mind_get_cycle();
        mind_one_cycle();

        let action: i32 = mind_get_last_action();
        let target: i32 = mind_get_last_target();

        print("  [");
        print(int_to_str(mind_get_cycle()));
        print("] ");
        print(act_name(action));

        if target >= 0 && target < mind_get_file_count() {
            print(" ");
            print(mind_file_path(target));
        }

        if action == ACT_EXPLORE() || action == ACT_REPREDICT() {
            if target >= 0 {
                print("  error:");
                print(int_to_str(mind_get_error(target)));
                print("%");
            }
        }

        println("");

        if mind_idle_streak >= 2 {
            println("  (idle — nothing more to explore)");
            break;
        }

        i = i + 1;
    }

    println("");
    print("  Competence: ~");
    print(int_to_str(mind_get_competence()));
    print("% | Files: ");
    print(int_to_str(mind_count_analyzed()));
    print("/");
    print(int_to_str(mind_get_file_count()));
    print(" | Predictions: ");
    println(int_to_str(mind_get_total_preds()));
}

fn cmd_mind() {
    if !mind_initialized {
        println("  Mind not active. Use 'think [N]' to start.");
        return;
    }

    println("");
    println("  Machine Mind — Status");
    println("  ─────────────────────");
    print("  Cycle: ");
    println(int_to_str(mind_get_cycle()));
    print("  Files known: ");
    println(int_to_str(mind_get_file_count()));
    print("  Files analyzed: ");
    println(int_to_str(mind_count_analyzed()));
    print("  Competence: ~");
    print(int_to_str(mind_get_competence()));
    println("%");
    print("  Avg error: ");
    print(int_to_str(mind_get_avg_error()));
    println("%");
    print("  Predictions: ");
    println(int_to_str(mind_get_total_preds()));

    // Show per-file status
    if mind_get_file_count() > 0 {
        println("");
        println("  Files:");
        var i: i32 = 0;
        while i < mind_get_file_count() {
            print("    ");
            if mind_is_analyzed(i) {
                print("[x] ");
            } else {
                print("[ ] ");
            }
            print(mind_file_path(i));
            if mind_is_analyzed(i) {
                let err: i32 = mind_get_error(i);
                if err > 0 {
                    print("  (error:");
                    print(int_to_str(err));
                    print("%)");
                }
            }
            println("");
            i = i + 1;
        }
    }
    println("");
}

fn cmd_seed(args: string) {
    let path: string = str_trim(args);
    if len(path) == 0 {
        println("  Error: use 'seed <file.m>'");
        return;
    }
    if !mind_initialized {
        mind_init();
    }
    if mind_seed(path) {
        print("  Seeded: ");
        println(path);
    } else {
        print("  Already known: ");
        println(path);
    }
}

// ── Main REPL loop ───────────────────────────────────

fn main() -> i32 {
    vm_init();

    show_banner();

    var running: bool = true;
    while running {
        print("machine> ");
        flush();
        let input: string = read_line();

        // EOF detection: read_line returns \x04 on EOF
        if len(input) == 1 && char_at(input, 0) == 4 {
            running = false;
            break;
        }

        let line: string = str_trim(input);

        if len(line) == 0 {
            // empty line, continue
        } else if str_eq(line, "quit") || str_eq(line, "exit") {
            running = false;
        } else if str_eq(line, "help") {
            show_help();
        } else if str_eq(line, "env") {
            cmd_env();
        } else if str_eq(line, "drift") {
            cmd_drift();
        } else if str_eq(line, "snapshot") {
            cmd_snapshot();
        } else if str_eq(line, "rollback") {
            cmd_rollback();
        } else if str_eq(line, "save") || str_starts_with(line, "save ") {
            if len(line) > 5 { cmd_save(substr(line, 5, len(line) - 5)); }
            else { cmd_save(""); }
        } else if str_eq(line, "restore") || str_starts_with(line, "restore ") {
            if len(line) > 8 { cmd_restore(substr(line, 8, len(line) - 8)); }
            else { cmd_restore(""); }
        } else if str_starts_with(line, "analyze ") {
            cmd_analyze(substr(line, 8, len(line) - 8));
        } else if str_eq(line, "funcs") {
            cmd_funcs();
        } else if str_starts_with(line, "calls ") {
            cmd_calls(substr(line, 6, len(line) - 6));
        } else if str_starts_with(line, "callers ") {
            cmd_callers(substr(line, 8, len(line) - 8));
        } else if str_eq(line, "stats") {
            cmd_stats();
        } else if str_starts_with(line, "search ") {
            cmd_search(substr(line, 7, len(line) - 7));
        } else if str_eq(line, "deps") {
            cmd_deps();
        } else if str_eq(line, "top") || str_starts_with(line, "top ") {
            if len(line) > 4 { cmd_top(substr(line, 4, len(line) - 4)); }
            else { cmd_top(""); }
        } else if str_starts_with(line, "project ") {
            cmd_project(substr(line, 8, len(line) - 8));
        } else if str_starts_with(line, "where ") {
            cmd_where(substr(line, 6, len(line) - 6));
        } else if str_eq(line, "complexity") || str_starts_with(line, "complexity ") {
            if len(line) > 11 { cmd_complexity(substr(line, 11, len(line) - 11)); }
            else { cmd_complexity(""); }
        } else if str_eq(line, "diff") {
            cmd_diff();
        } else if str_eq(line, "unused") {
            cmd_unused();
        } else if str_eq(line, "hotspots") || str_starts_with(line, "hotspots ") {
            if len(line) > 9 { cmd_hotspots(substr(line, 9, len(line) - 9)); }
            else { cmd_hotspots(""); }
        } else if str_eq(line, "health") {
            cmd_health();
        } else if str_eq(line, "audit") {
            cmd_audit();
        } else if str_eq(line, "map") {
            cmd_map();
        } else if str_starts_with(line, "explain ") {
            cmd_explain(substr(line, 8, len(line) - 8));
        } else if str_eq(line, "summary") {
            cmd_summary();
        } else if str_starts_with(line, "focus ") {
            cmd_focus(substr(line, 6, len(line) - 6));
        } else if str_eq(line, "suggest") {
            cmd_suggest();
        } else if str_eq(line, "coupling") || str_starts_with(line, "coupling ") {
            if len(line) > 9 { cmd_coupling(substr(line, 9, len(line) - 9)); }
            else { cmd_coupling(""); }
        } else if str_starts_with(line, "compare ") {
            cmd_compare(substr(line, 8, len(line) - 8));
        } else if str_eq(line, "self") {
            cmd_self();
        } else if str_eq(line, "think") || str_starts_with(line, "think ") {
            if len(line) > 6 { cmd_think(substr(line, 6, len(line) - 6)); }
            else { cmd_think(""); }
        } else if str_eq(line, "mind") {
            cmd_mind();
        } else if str_starts_with(line, "seed ") {
            cmd_seed(substr(line, 5, len(line) - 5));
        } else if str_starts_with(line, "bind ") {
            cmd_bind(substr(line, 5, len(line) - 5));
        } else if str_starts_with(line, "load ") {
            cmd_load(substr(line, 5, len(line) - 5));
        } else if str_starts_with(line, "history ") {
            cmd_history(substr(line, 8, len(line) - 8));
        } else if str_starts_with(line, "forget ") {
            cmd_forget(substr(line, 7, len(line) - 7));
        } else {
            // Try as expression
            eval_expression(line);
        }
    }

    // Auto-save on exit
    if env_get_count() > 0 {
        vm_persist(state_path());
    }

    println("");
    println("  Goodbye.");
    return 0;
}
