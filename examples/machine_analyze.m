// Machine Analyze — M source code analyzer for temporal VM
// Phase C: Machine reads and understands code.
//
// Reads M source files, extracts structure (functions, calls),
// and populates the temporal VM with program knowledge.
//
// Usage (from REPL):
//   analyze examples/self_codegen.m
//   funcs
//   calls vm_exec

// ── Analysis storage ─────────────────────────────────
// Functions found in analyzed file

var ana_file: string = "";        // current file path
var ana_source: string = "";      // raw source text
var ana_src_lines: i32 = 0;       // total source lines

// Function table (parallel arrays)
var ana_fn_names: i32 = 0;        // string pool indices
var ana_fn_params: i32 = 0;       // param count per function
var ana_fn_start: i32 = 0;        // start line number
var ana_fn_end: i32 = 0;          // end line number
var ana_fn_body_calls: i32 = 0;   // array of arrays: call target names (sp indices)
var ana_fn_count: i32 = 0;

// Global variable table
var ana_gv_names: i32 = 0;        // string pool indices
var ana_gv_types: i32 = 0;        // string pool indices (type name)
var ana_gv_count: i32 = 0;

// Use directive table
var ana_use_paths: i32 = 0;       // string pool indices
var ana_use_count: i32 = 0;

fn ana_init() {
    ana_fn_names = array_new(0);
    ana_fn_params = array_new(0);
    ana_fn_start = array_new(0);
    ana_fn_end = array_new(0);
    ana_fn_body_calls = array_new(0);
    ana_fn_count = 0;

    ana_gv_names = array_new(0);
    ana_gv_types = array_new(0);
    ana_gv_count = 0;

    ana_use_paths = array_new(0);
    ana_use_count = 0;

    ana_file = "";
    ana_source = "";
    ana_src_lines = 0;
}

// ── Tokenizer (minimal, for structure extraction) ────
// We only need to identify: fn, var, use, identifiers, braces, parens, strings, comments

fn ANA_TK_FN() -> i32     { return 1; }
fn ANA_TK_VAR() -> i32    { return 2; }
fn ANA_TK_USE() -> i32    { return 3; }
fn ANA_TK_IDENT() -> i32  { return 4; }
fn ANA_TK_LBRACE() -> i32 { return 5; }
fn ANA_TK_RBRACE() -> i32 { return 6; }
fn ANA_TK_LPAREN() -> i32 { return 7; }
fn ANA_TK_RPAREN() -> i32 { return 8; }
fn ANA_TK_COMMA() -> i32  { return 9; }
fn ANA_TK_COLON() -> i32  { return 10; }
fn ANA_TK_ARROW() -> i32  { return 11; }  // ->
fn ANA_TK_STR() -> i32    { return 12; }
fn ANA_TK_OTHER() -> i32  { return 13; }
fn ANA_TK_EOF() -> i32    { return 14; }

var tk_types: i32 = 0;
var tk_svals: i32 = 0;     // string pool indices for identifiers/strings
var tk_lines: i32 = 0;     // line number of each token
var tk_count: i32 = 0;

fn ana_is_alpha(c: i32) -> bool {
    if c >= 65 && c <= 90 { return true; }
    if c >= 97 && c <= 122 { return true; }
    return c == 95;
}

fn ana_is_digit(c: i32) -> bool { return c >= 48 && c <= 57; }

fn ana_tokenize(src: string) -> i32 {
    tk_types = array_new(0);
    tk_svals = array_new(0);
    tk_lines = array_new(0);
    tk_count = 0;

    var pos: i32 = 0;
    var line: i32 = 1;
    let slen: i32 = len(src);

    while pos < slen {
        let c: i32 = char_at(src, pos);

        // Newline
        if c == 10 {
            line = line + 1;
            pos = pos + 1;
        }
        // Whitespace
        else if c == 32 || c == 9 || c == 13 {
            pos = pos + 1;
        }
        // Line comment: //
        else if c == 47 && pos + 1 < slen && char_at(src, pos + 1) == 47 {
            while pos < slen && char_at(src, pos) != 10 {
                pos = pos + 1;
            }
        }
        // String literal
        else if c == 34 {
            pos = pos + 1;
            var start: i32 = pos;
            while pos < slen && char_at(src, pos) != 34 {
                if char_at(src, pos) == 92 { pos = pos + 1; }  // skip escape
                pos = pos + 1;
            }
            let s: string = substr(src, start, pos - start);
            if pos < slen { pos = pos + 1; }
            array_push(tk_types, ANA_TK_STR());
            array_push(tk_svals, sp_store(s));
            array_push(tk_lines, line);
            tk_count = tk_count + 1;
        }
        // Identifier or keyword
        else if ana_is_alpha(c) {
            var start: i32 = pos;
            while pos < slen && (ana_is_alpha(char_at(src, pos)) || ana_is_digit(char_at(src, pos))) {
                pos = pos + 1;
            }
            let word: string = substr(src, start, pos - start);
            var ttype: i32 = ANA_TK_IDENT();
            if str_eq(word, "fn") { ttype = ANA_TK_FN(); }
            else if str_eq(word, "var") { ttype = ANA_TK_VAR(); }
            else if str_eq(word, "use") { ttype = ANA_TK_USE(); }
            array_push(tk_types, ttype);
            array_push(tk_svals, sp_store(word));
            array_push(tk_lines, line);
            tk_count = tk_count + 1;
        }
        // Arrow: ->
        else if c == 45 && pos + 1 < slen && char_at(src, pos + 1) == 62 {
            array_push(tk_types, ANA_TK_ARROW());
            array_push(tk_svals, 0);
            array_push(tk_lines, line);
            tk_count = tk_count + 1;
            pos = pos + 2;
        }
        // Single-char tokens
        else if c == 123 {
            array_push(tk_types, ANA_TK_LBRACE());
            array_push(tk_svals, 0);
            array_push(tk_lines, line);
            tk_count = tk_count + 1;
            pos = pos + 1;
        }
        else if c == 125 {
            array_push(tk_types, ANA_TK_RBRACE());
            array_push(tk_svals, 0);
            array_push(tk_lines, line);
            tk_count = tk_count + 1;
            pos = pos + 1;
        }
        else if c == 40 {
            array_push(tk_types, ANA_TK_LPAREN());
            array_push(tk_svals, 0);
            array_push(tk_lines, line);
            tk_count = tk_count + 1;
            pos = pos + 1;
        }
        else if c == 41 {
            array_push(tk_types, ANA_TK_RPAREN());
            array_push(tk_svals, 0);
            array_push(tk_lines, line);
            tk_count = tk_count + 1;
            pos = pos + 1;
        }
        else if c == 44 {
            array_push(tk_types, ANA_TK_COMMA());
            array_push(tk_svals, 0);
            array_push(tk_lines, line);
            tk_count = tk_count + 1;
            pos = pos + 1;
        }
        else if c == 58 {
            array_push(tk_types, ANA_TK_COLON());
            array_push(tk_svals, 0);
            array_push(tk_lines, line);
            tk_count = tk_count + 1;
            pos = pos + 1;
        }
        else {
            // Skip anything else (numbers, operators, etc.)
            pos = pos + 1;
        }
    }

    // EOF token
    array_push(tk_types, ANA_TK_EOF());
    array_push(tk_svals, 0);
    array_push(tk_lines, line);
    tk_count = tk_count + 1;

    ana_src_lines = line;
    return tk_count;
}

// ── Structure extraction ─────────────────────────────

fn ana_tk_type(i: i32) -> i32 { return array_get(tk_types, i); }
fn ana_tk_sval(i: i32) -> string { return sp_get(array_get(tk_svals, i)); }
fn ana_tk_line(i: i32) -> i32 { return array_get(tk_lines, i); }

fn ana_extract_structure() {
    var i: i32 = 0;

    while i < tk_count {
        let tt: i32 = ana_tk_type(i);

        // use "path"
        if tt == ANA_TK_USE() && i + 1 < tk_count && ana_tk_type(i + 1) == ANA_TK_STR() {
            let path: string = ana_tk_sval(i + 1);
            array_push(ana_use_paths, sp_store(path));
            ana_use_count = ana_use_count + 1;
            i = i + 2;
        }

        // var name: type
        else if tt == ANA_TK_VAR() && i + 1 < tk_count && ana_tk_type(i + 1) == ANA_TK_IDENT() {
            let name: string = ana_tk_sval(i + 1);
            var typename: string = "unknown";
            // Look for : type pattern
            if i + 2 < tk_count && ana_tk_type(i + 2) == ANA_TK_COLON() {
                if i + 3 < tk_count && ana_tk_type(i + 3) == ANA_TK_IDENT() {
                    typename = ana_tk_sval(i + 3);
                }
            }
            array_push(ana_gv_names, sp_store(name));
            array_push(ana_gv_types, sp_store(typename));
            ana_gv_count = ana_gv_count + 1;
            i = i + 2;
        }

        // fn name(params) -> type { body }
        else if tt == ANA_TK_FN() && i + 1 < tk_count && ana_tk_type(i + 1) == ANA_TK_IDENT() {
            let fname: string = ana_tk_sval(i + 1);
            let start_line: i32 = ana_tk_line(i);

            // Count parameters
            var param_count: i32 = 0;
            var j: i32 = i + 2;

            // Skip to (
            while j < tk_count && ana_tk_type(j) != ANA_TK_LPAREN() && ana_tk_type(j) != ANA_TK_LBRACE() {
                j = j + 1;
            }

            if j < tk_count && ana_tk_type(j) == ANA_TK_LPAREN() {
                j = j + 1;
                // Count params by looking for identifiers before colons
                var in_params: bool = true;
                while j < tk_count && in_params {
                    if ana_tk_type(j) == ANA_TK_RPAREN() {
                        in_params = false;
                    } else if ana_tk_type(j) == ANA_TK_IDENT() && j + 1 < tk_count && ana_tk_type(j + 1) == ANA_TK_COLON() {
                        param_count = param_count + 1;
                        j = j + 1;
                    } else {
                        j = j + 1;
                    }
                }
            }

            // Find opening brace
            while j < tk_count && ana_tk_type(j) != ANA_TK_LBRACE() {
                j = j + 1;
            }

            // Match braces to find function end, collect calls
            var calls: i32 = array_new(0);
            var call_set: i32 = array_new(0);  // dedup: sp indices of already-added calls
            var call_set_n: i32 = 0;
            var depth: i32 = 0;
            if j < tk_count && ana_tk_type(j) == ANA_TK_LBRACE() {
                depth = 1;
                j = j + 1;
                while j < tk_count && depth > 0 {
                    let bt: i32 = ana_tk_type(j);
                    if bt == ANA_TK_LBRACE() {
                        depth = depth + 1;
                    } else if bt == ANA_TK_RBRACE() {
                        depth = depth - 1;
                    }
                    // Detect function calls: IDENT followed by LPAREN
                    else if bt == ANA_TK_IDENT() && j + 1 < tk_count && ana_tk_type(j + 1) == ANA_TK_LPAREN() {
                        let call_name: string = ana_tk_sval(j);
                        let call_si: i32 = sp_store(call_name);
                        // Dedup check
                        var found: bool = false;
                        var k: i32 = 0;
                        while k < call_set_n {
                            if str_eq(sp_get(array_get(call_set, k)), call_name) {
                                found = true;
                            }
                            k = k + 1;
                        }
                        if !found {
                            array_push(calls, call_si);
                            array_push(call_set, call_si);
                            call_set_n = call_set_n + 1;
                        }
                    }
                    j = j + 1;
                }
            }

            let end_line: i32 = ana_tk_line(j - 1);

            // Store function
            array_push(ana_fn_names, sp_store(fname));
            array_push(ana_fn_params, param_count);
            array_push(ana_fn_start, start_line);
            array_push(ana_fn_end, end_line);
            array_push(ana_fn_body_calls, calls);
            ana_fn_count = ana_fn_count + 1;

            i = j;
        }

        else {
            i = i + 1;
        }
    }
}

// ── Public API ───────────────────────────────────────

fn analyze_file(path: string) -> i32 {
    ana_init();
    ana_file = path;
    ana_source = read_file(path);
    if len(ana_source) == 0 {
        return 0 - 1;
    }
    ana_tokenize(ana_source);
    ana_extract_structure();
    return 0;
}

fn ana_get_file() -> string { return ana_file; }
fn ana_get_lines() -> i32 { return ana_src_lines; }
fn ana_get_func_count() -> i32 { return ana_fn_count; }
fn ana_get_global_count() -> i32 { return ana_gv_count; }
fn ana_get_use_count() -> i32 { return ana_use_count; }

fn ana_func_name(idx: i32) -> string {
    if idx < 0 || idx >= ana_fn_count { return ""; }
    return sp_get(array_get(ana_fn_names, idx));
}

fn ana_func_params(idx: i32) -> i32 {
    if idx < 0 || idx >= ana_fn_count { return 0; }
    return array_get(ana_fn_params, idx);
}

fn ana_func_start(idx: i32) -> i32 {
    if idx < 0 || idx >= ana_fn_count { return 0; }
    return array_get(ana_fn_start, idx);
}

fn ana_func_end(idx: i32) -> i32 {
    if idx < 0 || idx >= ana_fn_count { return 0; }
    return array_get(ana_fn_end, idx);
}

fn ana_func_lines(idx: i32) -> i32 {
    return ana_func_end(idx) - ana_func_start(idx) + 1;
}

fn ana_func_call_count(idx: i32) -> i32 {
    if idx < 0 || idx >= ana_fn_count { return 0; }
    return array_len(array_get(ana_fn_body_calls, idx));
}

fn ana_func_call_name(func_idx: i32, call_idx: i32) -> string {
    if func_idx < 0 || func_idx >= ana_fn_count { return ""; }
    let calls: i32 = array_get(ana_fn_body_calls, func_idx);
    if call_idx < 0 || call_idx >= array_len(calls) { return ""; }
    return sp_get(array_get(calls, call_idx));
}

fn ana_find_func(name: string) -> i32 {
    var i: i32 = 0;
    while i < ana_fn_count {
        if str_eq(ana_func_name(i), name) { return i; }
        i = i + 1;
    }
    return 0 - 1;
}

fn ana_global_name(idx: i32) -> string {
    if idx < 0 || idx >= ana_gv_count { return ""; }
    return sp_get(array_get(ana_gv_names, idx));
}

fn ana_global_type(idx: i32) -> string {
    if idx < 0 || idx >= ana_gv_count { return ""; }
    return sp_get(array_get(ana_gv_types, idx));
}

fn ana_use_path(idx: i32) -> string {
    if idx < 0 || idx >= ana_use_count { return ""; }
    return sp_get(array_get(ana_use_paths, idx));
}

// ── VM population ────────────────────────────────────
// Creates temporal VM bindings from analysis results.
// Each analysis is a "tick" — re-analyzing shows drift.

fn ana_populate_vm() {
    let tick: i32 = vm_get_tick();

    // File-level bindings
    env_bind("_file", val_str(ana_file), tick, "analyze");
    env_bind("_lines", val_i32(ana_src_lines), tick, "analyze");
    env_bind("_funcs", val_i32(ana_fn_count), tick, "analyze");
    env_bind("_globals", val_i32(ana_gv_count), tick, "analyze");
    env_bind("_uses", val_i32(ana_use_count), tick, "analyze");

    // Per-function bindings: fn.<name>.lines, fn.<name>.params, fn.<name>.calls
    var i: i32 = 0;
    while i < ana_fn_count {
        let name: string = ana_func_name(i);
        let key_lines: string = str_concat("fn.", str_concat(name, ".lines"));
        let key_params: string = str_concat("fn.", str_concat(name, ".params"));
        let key_calls: string = str_concat("fn.", str_concat(name, ".calls"));

        env_bind(key_lines, val_i32(ana_func_lines(i)), tick, "analyze");
        env_bind(key_params, val_i32(ana_func_params(i)), tick, "analyze");
        env_bind(key_calls, val_i32(ana_func_call_count(i)), tick, "analyze");
        i = i + 1;
    }
}

// ── Complexity metrics ───────────────────────────────

fn ana_avg_func_lines() -> i32 {
    if ana_fn_count == 0 { return 0; }
    var total: i32 = 0;
    var i: i32 = 0;
    while i < ana_fn_count {
        total = total + ana_func_lines(i);
        i = i + 1;
    }
    return total / ana_fn_count;
}

fn ana_max_func_lines() -> i32 {
    var max_l: i32 = 0;
    var i: i32 = 0;
    while i < ana_fn_count {
        let l: i32 = ana_func_lines(i);
        if l > max_l { max_l = l; }
        i = i + 1;
    }
    return max_l;
}

fn ana_max_func_name() -> string {
    var max_l: i32 = 0;
    var max_name: string = "";
    var i: i32 = 0;
    while i < ana_fn_count {
        let l: i32 = ana_func_lines(i);
        if l > max_l {
            max_l = l;
            max_name = ana_func_name(i);
        }
        i = i + 1;
    }
    return max_name;
}

// ── Complexity scoring ───────────────────────────────
// Each function gets a complexity score (0-100) based on:
//   - Line count (more lines = more complex)
//   - Call count (more calls = more connected)
//   - Parameter count (more params = wider interface)
//
// The score is intentionally APPROXIMATE — stored with confidence
// that reflects how reliable the metric is. This is Machine's
// nature: even analysis results carry uncertainty.

fn ana_func_complexity(idx: i32) -> i32 {
    if idx < 0 || idx >= ana_fn_count { return 0; }

    let lines: i32 = ana_func_lines(idx);
    let calls: i32 = ana_func_call_count(idx);
    let params: i32 = ana_func_params(idx);

    // Line score: 1-line = 5, 10 lines = 20, 50 = 50, 100+ = 70
    var line_score: i32 = lines * 7 / 10;
    if line_score > 70 { line_score = 70; }
    if line_score < 5 { line_score = 5; }

    // Call score: 0 calls = 0, 5 = 10, 20+ = 20
    var call_score: i32 = calls;
    if call_score > 20 { call_score = 20; }

    // Param score: 0 = 0, 2 = 5, 4+ = 10
    var param_score: i32 = params * 5 / 2;
    if param_score > 10 { param_score = 10; }

    var total: i32 = line_score + call_score + param_score;
    if total > 100 { total = 100; }
    return total;
}

// Confidence of complexity score decreases for very small or very large functions
// (hard to judge 1-liners as "simple" or 500-line monsters)
fn ana_func_complexity_conf(idx: i32) -> i32 {
    if idx < 0 || idx >= ana_fn_count { return 0; }
    let lines: i32 = ana_func_lines(idx);
    // 1-line: 60% confident (could be wrapper or constant)
    // 5-50 lines: 90% confident (clear picture)
    // 100+: 75% confident (hard to assess without deeper analysis)
    if lines <= 1 { return 60; }
    if lines <= 5 { return 80; }
    if lines <= 50 { return 90; }
    if lines <= 100 { return 80; }
    return 75;
}

// Populate VM with complexity as approximate values
fn ana_populate_complexity() {
    let tick: i32 = vm_get_tick();
    var i: i32 = 0;
    while i < ana_fn_count {
        let name: string = ana_func_name(i);
        let key: string = str_concat("fn.", str_concat(name, ".complexity"));
        let score: i32 = ana_func_complexity(i);
        let conf: i32 = ana_func_complexity_conf(i);
        env_bind(key, val_approx(score, conf), tick, "analyze");
        i = i + 1;
    }
}

// ── Cross-file dependency analysis ──────────────────
// Recursively follows `use` directives and builds a project-wide view.
//
// Per-file records (parallel arrays, indexed by file index):
//   ana_all_files        — file paths
//   ana_all_fn_names     — array of arrays: function name sp-indices per file
//   ana_all_fn_counts    — function count per file
//   ana_all_use_paths    — array of arrays: use path sp-indices per file
//   ana_all_use_counts   — use count per file

var ana_all_files: i32 = 0;
var ana_all_fn_names: i32 = 0;
var ana_all_fn_counts: i32 = 0;
var ana_all_use_paths_arr: i32 = 0;
var ana_all_use_counts: i32 = 0;
var ana_all_file_count: i32 = 0;
var ana_all_func_total: i32 = 0;

fn ana_multi_init() {
    ana_all_files = array_new(0);
    ana_all_fn_names = array_new(0);
    ana_all_fn_counts = array_new(0);
    ana_all_use_paths_arr = array_new(0);
    ana_all_use_counts = array_new(0);
    ana_all_file_count = 0;
    ana_all_func_total = 0;
}

// Extract directory prefix from a path.
// "examples/foo.m" -> "examples/"
// "foo.m" -> ""
fn ana_get_dir(path: string) -> string {
    let slen: i32 = len(path);
    // Scan backwards for '/' (47) or '\' (92)
    var last_sep: i32 = 0 - 1;
    var i: i32 = slen - 1;
    while i >= 0 {
        let c: i32 = char_at(path, i);
        if c == 47 || c == 92 {
            last_sep = i;
            i = 0 - 1;  // exit loop (no break in M)
        } else {
            i = i - 1;
        }
    }
    if last_sep < 0 { return ""; }
    return substr(path, 0, last_sep + 1);
}

// Check if a file path is already in the multi-file list.
fn ana_already_analyzed(path: string) -> bool {
    var i: i32 = 0;
    while i < ana_all_file_count {
        if str_eq(sp_get(array_get(ana_all_files, i)), path) { return true; }
        i = i + 1;
    }
    return false;
}

// Resolve a use path relative to the parent file's directory.
// parent="examples/machine_analyze.m", use_path="machine_vm.m"
// -> "examples/machine_vm.m"
fn ana_resolve_use_path(parent_path: string, use_path: string) -> string {
    let dir: string = ana_get_dir(parent_path);
    if len(dir) == 0 { return use_path; }
    return str_concat(dir, use_path);
}

// Record current single-file analysis results into multi-file storage.
fn ana_record_current() {
    let file_idx: i32 = ana_all_file_count;
    array_push(ana_all_files, sp_store(ana_file));
    array_push(ana_all_fn_counts, ana_fn_count);
    array_push(ana_all_use_counts, ana_use_count);

    // Copy function names for this file
    var fnames: i32 = array_new(0);
    var i: i32 = 0;
    while i < ana_fn_count {
        array_push(fnames, array_get(ana_fn_names, i));
        i = i + 1;
    }
    array_push(ana_all_fn_names, fnames);

    // Copy use paths for this file
    var upaths: i32 = array_new(0);
    i = 0;
    while i < ana_use_count {
        array_push(upaths, array_get(ana_use_paths, i));
        i = i + 1;
    }
    array_push(ana_all_use_paths_arr, upaths);

    ana_all_file_count = ana_all_file_count + 1;
    ana_all_func_total = ana_all_func_total + ana_fn_count;
}

// Recursively analyze a file and all its `use` dependencies.
// Returns the number of files analyzed (including this one), or -1 on error.
fn ana_resolve_deps(path: string) -> i32 {
    if ana_already_analyzed(path) { return 0; }

    // Analyze the file
    let r: i32 = analyze_file(path);
    if r < 0 { return 0 - 1; }

    // Snapshot single-file results before recursing (analyze_file resets state)
    let this_fn_count: i32 = ana_fn_count;
    let this_use_count: i32 = ana_use_count;

    // Collect use paths before they get overwritten
    var dep_paths: i32 = array_new(0);
    var i: i32 = 0;
    while i < this_use_count {
        let resolved: string = ana_resolve_use_path(path, ana_use_path(i));
        array_push(dep_paths, sp_store(resolved));
        i = i + 1;
    }

    // Record this file into multi-file storage
    ana_record_current();
    var files_added: i32 = 1;

    // Recurse into dependencies
    i = 0;
    while i < array_len(dep_paths) {
        let dep: string = sp_get(array_get(dep_paths, i));
        if !ana_already_analyzed(dep) {
            let sub: i32 = ana_resolve_deps(dep);
            if sub > 0 {
                files_added = files_added + sub;
            }
            // sub < 0 means file unreadable — skip silently (no try/catch in M)
        }
        i = i + 1;
    }

    return files_added;
}

// Search all analyzed files to find which file defines a function.
// Returns the file path, or "" if not found.
fn ana_who_defines(func_name: string) -> string {
    var fi: i32 = 0;
    while fi < ana_all_file_count {
        let fnames: i32 = array_get(ana_all_fn_names, fi);
        let fcount: i32 = array_get(ana_all_fn_counts, fi);
        var j: i32 = 0;
        while j < fcount {
            if str_eq(sp_get(array_get(fnames, j)), func_name) {
                return sp_get(array_get(ana_all_files, fi));
            }
            j = j + 1;
        }
        fi = fi + 1;
    }
    return "";
}

// Check if a function name is defined in a specific file (by file index).
fn ana_defined_in_file(func_name: string, file_idx: i32) -> bool {
    if file_idx < 0 || file_idx >= ana_all_file_count { return false; }
    let fnames: i32 = array_get(ana_all_fn_names, file_idx);
    let fcount: i32 = array_get(ana_all_fn_counts, file_idx);
    var j: i32 = 0;
    while j < fcount {
        if str_eq(sp_get(array_get(fnames, j)), func_name) { return true; }
        j = j + 1;
    }
    return false;
}

// Find the file index for a given path. Returns -1 if not found.
fn ana_file_index(path: string) -> i32 {
    var i: i32 = 0;
    while i < ana_all_file_count {
        if str_eq(sp_get(array_get(ana_all_files, i)), path) { return i; }
        i = i + 1;
    }
    return 0 - 1;
}

// Get external calls for a function (calls to functions in OTHER files).
// Must be called after ana_resolve_deps so multi-file data is populated,
// AND after analyze_file on the file containing func_idx so single-file
// call graph data is current.
//
// Returns an array of sp-indices (call target names defined elsewhere).
fn ana_external_calls(func_idx: i32) -> i32 {
    var result: i32 = array_new(0);
    if func_idx < 0 || func_idx >= ana_fn_count { return result; }

    // Find current file's index in multi-file storage
    let cur_fi: i32 = ana_file_index(ana_file);

    let calls: i32 = array_get(ana_fn_body_calls, func_idx);
    let ncalls: i32 = array_len(calls);
    var i: i32 = 0;
    while i < ncalls {
        let call_name: string = sp_get(array_get(calls, i));
        // Check if this call is NOT defined in the current file
        if !ana_defined_in_file(call_name, cur_fi) {
            // Check if it IS defined in any other file
            let definer: string = ana_who_defines(call_name);
            if len(definer) > 0 {
                array_push(result, array_get(calls, i));
            }
        }
        i = i + 1;
    }
    return result;
}

// Get the file path for a given multi-file index.
fn ana_all_file_path(idx: i32) -> string {
    if idx < 0 || idx >= ana_all_file_count { return ""; }
    return sp_get(array_get(ana_all_files, idx));
}

// Get the function count for a given multi-file index.
fn ana_all_file_func_count(idx: i32) -> i32 {
    if idx < 0 || idx >= ana_all_file_count { return 0; }
    return array_get(ana_all_fn_counts, idx);
}

// Get a function name from a specific file by file index and function index.
fn ana_all_file_func_name(file_idx: i32, fn_idx: i32) -> string {
    if file_idx < 0 || file_idx >= ana_all_file_count { return ""; }
    let fnames: i32 = array_get(ana_all_fn_names, file_idx);
    let fcount: i32 = array_get(ana_all_fn_counts, file_idx);
    if fn_idx < 0 || fn_idx >= fcount { return ""; }
    return sp_get(array_get(fnames, fn_idx));
}
