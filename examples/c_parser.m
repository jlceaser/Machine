// c_parser.m — C structural parser written in M
// Phase 2: M reads C code structure
//
// Parses C token streams into structural representation:
// - Function definitions/declarations with signatures
// - Struct definitions with fields
// - Enum definitions with constants
// - Typedefs
// - Global variables
// - Preprocessor directives
//
// Usage:
//   mc.exe self_codegen.m c_parser.m              -- run tests
//   mc.exe self_codegen.m c_parser.m <file.c>     -- analyze file

use "c_lexer.m";

// ── String helpers (not VM built-ins) ───────────────

// String helpers not available as VM built-ins

fn str_starts_with(s: string, prefix: string) -> bool {
    if len(prefix) > len(s) { return false; }
    return str_eq(substr(s, 0, len(prefix)), prefix);
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

// ── C AST Node Kinds ────────────────────────────────

fn CNK_PROGRAM() -> i32      { return 100; }
fn CNK_PREPROC() -> i32      { return 101; }
fn CNK_FUNC_DEF() -> i32     { return 102; }
fn CNK_FUNC_DECL() -> i32    { return 103; }
fn CNK_STRUCT_DEF() -> i32   { return 104; }
fn CNK_ENUM_DEF() -> i32     { return 105; }
fn CNK_TYPEDEF() -> i32      { return 106; }
fn CNK_GLOBAL_VAR() -> i32   { return 107; }
fn CNK_FIELD() -> i32        { return 108; }
fn CNK_ENUM_CONST() -> i32   { return 109; }
fn CNK_PARAM() -> i32        { return 110; }
fn CNK_FORWARD_DECL() -> i32 { return 111; }

// Expression node kinds
fn CNK_EXPR_INT() -> i32     { return 120; }  // integer literal, d1=value
fn CNK_EXPR_STR() -> i32     { return 121; }  // string literal, name=value
fn CNK_EXPR_IDENT() -> i32   { return 122; }  // identifier, name=ident
fn CNK_EXPR_CALL() -> i32    { return 123; }  // call, name=func, d1=args_start, d2=arg_count
fn CNK_EXPR_BINARY() -> i32  { return 124; }  // binary op, name=op, d1=left, d2=right
fn CNK_EXPR_UNARY() -> i32   { return 125; }  // unary op, name=op, d1=operand
fn CNK_EXPR_MEMBER() -> i32  { return 126; }  // member access, name=field, d1=object, d2=0(.) or 1(->)
fn CNK_EXPR_INDEX() -> i32   { return 127; }  // array index, d1=array, d2=index
fn CNK_EXPR_CAST() -> i32    { return 128; }  // cast, type=target type, d1=operand
fn CNK_EXPR_SIZEOF() -> i32  { return 129; }  // sizeof, name=type_or_expr
fn CNK_EXPR_TERNARY() -> i32 { return 130; }  // ternary, d1=cond, d2=then, d3=else
fn CNK_EXPR_ASSIGN() -> i32  { return 131; }  // assignment, name=op(=,+=,-=), d1=lhs, d2=rhs
fn CNK_EXPR_POSTFIX() -> i32 { return 132; }  // postfix ++/--, name=op, d1=operand
fn CNK_EXPR_ADDR() -> i32    { return 133; }  // &operand, d1=operand
fn CNK_EXPR_DEREF() -> i32   { return 134; }  // *operand, d1=operand
fn CNK_EXPR_CHAR() -> i32    { return 135; }  // char literal, name=value
fn CNK_EXPR_NULL() -> i32    { return 136; }  // NULL literal

// Statement node kinds
fn CNK_STMT_RETURN() -> i32  { return 150; }  // return, d1=expr (-1 if void)
fn CNK_STMT_IF() -> i32      { return 151; }  // if, d1=cond, d2=then_body, d3=else_body(-1)
fn CNK_STMT_WHILE() -> i32   { return 152; }  // while, d1=cond, d2=body
fn CNK_STMT_FOR() -> i32     { return 153; }  // for, d1=init, d2=cond, d3=body (step in name)
fn CNK_STMT_BLOCK() -> i32   { return 154; }  // block {}, d1=stmts_start, d2=stmt_count
fn CNK_STMT_EXPR() -> i32    { return 155; }  // expression statement, d1=expr
fn CNK_STMT_VAR() -> i32     { return 156; }  // var decl, name=var_name, type=type, d1=init(-1)
fn CNK_STMT_SWITCH() -> i32  { return 157; }  // switch, d1=expr, d2=cases_start, d3=case_count
fn CNK_STMT_CASE() -> i32    { return 158; }  // case, d1=expr(-1 for default), d2=body_start, d3=body_count
fn CNK_STMT_BREAK() -> i32   { return 159; }
fn CNK_STMT_CONTINUE() -> i32 { return 160; }
fn CNK_FUNC_BODY() -> i32    { return 161; }  // function with body, extends FUNC_DEF

// ── C AST Storage (flat arrays) ─────────────────────

var cn_kinds: i32 = 0;
var cn_d1: i32 = 0;       // primary data (child index, count, etc.)
var cn_d2: i32 = 0;       // secondary data
var cn_d3: i32 = 0;       // tertiary data
var cn_names: i32 = 0;    // identifier/name
var cn_types: i32 = 0;    // type string
var cn_count: i32 = 0;
var cn_children: i32 = 0;
var cn_child_count: i32 = 0;

fn cp_init_ast() -> i32 {
    cn_kinds = array_new(0);
    cn_d1 = array_new(0);
    cn_d2 = array_new(0);
    cn_d3 = array_new(0);
    cn_names = array_new(0);
    cn_types = array_new(0);
    cn_children = array_new(0);
    cn_count = 0;
    cn_child_count = 0;
    return 0;
}

fn cn_new(kind: i32, name: string, type_s: string, d1: i32, d2: i32, d3: i32) -> i32 {
    let idx: i32 = cn_count;
    array_push(cn_kinds, kind);
    array_push(cn_names, name);
    array_push(cn_types, type_s);
    array_push(cn_d1, d1);
    array_push(cn_d2, d2);
    array_push(cn_d3, d3);
    cn_count = cn_count + 1;
    return idx;
}

fn cnk(i: i32) -> i32     { return array_get(cn_kinds, i); }
fn cnn(i: i32) -> string   { return array_get(cn_names, i); }
fn cnt(i: i32) -> string   { return array_get(cn_types, i); }
fn cnd1(i: i32) -> i32    { return array_get(cn_d1, i); }
fn cnd2(i: i32) -> i32    { return array_get(cn_d2, i); }
fn cnd3(i: i32) -> i32    { return array_get(cn_d3, i); }

fn cn_flush(temp: i32) -> i32 {
    let start: i32 = cn_child_count;
    var i: i32 = 0;
    while i < array_len(temp) {
        array_push(cn_children, array_get(temp, i));
        cn_child_count = cn_child_count + 1;
        i = i + 1;
    }
    return start;
}

fn cn_child(start: i32, i: i32) -> i32 {
    return array_get(cn_children, start + i);
}

// ── Parser State ────────────────────────────────────

var cp_pos: i32 = 0;
var cp_type_names: i32 = 0;

fn cp_init() -> i32 {
    cp_pos = 0;
    cp_type_names = array_new(0);
    // Register built-in C type names
    array_push(cp_type_names, "void");
    array_push(cp_type_names, "char");
    array_push(cp_type_names, "short");
    array_push(cp_type_names, "int");
    array_push(cp_type_names, "long");
    array_push(cp_type_names, "float");
    array_push(cp_type_names, "double");
    array_push(cp_type_names, "signed");
    array_push(cp_type_names, "unsigned");
    array_push(cp_type_names, "size_t");
    array_push(cp_type_names, "ssize_t");
    array_push(cp_type_names, "ptrdiff_t");
    array_push(cp_type_names, "intptr_t");
    array_push(cp_type_names, "uintptr_t");
    array_push(cp_type_names, "int8_t");
    array_push(cp_type_names, "int16_t");
    array_push(cp_type_names, "int32_t");
    array_push(cp_type_names, "int64_t");
    array_push(cp_type_names, "uint8_t");
    array_push(cp_type_names, "uint16_t");
    array_push(cp_type_names, "uint32_t");
    array_push(cp_type_names, "uint64_t");
    array_push(cp_type_names, "bool");
    array_push(cp_type_names, "FILE");
    array_push(cp_type_names, "NULL");
    return 0;
}

fn cp_add_type_name(name: string) -> i32 {
    // Check if already registered
    var i: i32 = 0;
    while i < array_len(cp_type_names) {
        if str_eq(array_get(cp_type_names, i), name) { return 0; }
        i = i + 1;
    }
    array_push(cp_type_names, name);
    return 0;
}

fn cp_is_type_name(name: string) -> bool {
    var i: i32 = 0;
    while i < array_len(cp_type_names) {
        if str_eq(array_get(cp_type_names, i), name) { return true; }
        i = i + 1;
    }
    return false;
}

// ── Token Navigation ────────────────────────────────

fn cp_at_end() -> bool {
    return cp_pos >= c_tok_count;
}

fn cp_peek() -> i32 {
    if cp_pos >= c_tok_count { return CTK_EOF(); }
    return array_get(c_tok_types, cp_pos);
}

fn cp_peek_val() -> string {
    if cp_pos >= c_tok_count { return ""; }
    return array_get(c_tok_vals, cp_pos);
}

fn cp_peek_at(offset: i32) -> i32 {
    let p: i32 = cp_pos + offset;
    if p >= c_tok_count { return CTK_EOF(); }
    return array_get(c_tok_types, p);
}

fn cp_peek_val_at(offset: i32) -> string {
    let p: i32 = cp_pos + offset;
    if p >= c_tok_count { return ""; }
    return array_get(c_tok_vals, p);
}

fn cp_advance() -> string {
    let val: string = cp_peek_val();
    if cp_pos < c_tok_count { cp_pos = cp_pos + 1; }
    return val;
}

fn cp_match_type(t: i32) -> bool {
    if cp_peek() == t { cp_advance(); return true; }
    return false;
}

fn cp_match_val(v: string) -> bool {
    if str_eq(cp_peek_val(), v) { cp_advance(); return true; }
    return false;
}

fn cp_expect_val(v: string) -> i32 {
    if str_eq(cp_peek_val(), v) { cp_advance(); return 1; }
    return 0;
}

// ── Skip Helpers ────────────────────────────────────

// Skip balanced braces { ... }, assumes current token is {
fn cp_skip_braces() -> i32 {
    var depth: i32 = 0;
    if str_eq(cp_peek_val(), "{") { depth = 1; cp_advance(); }
    while !cp_at_end() && depth > 0 {
        let v: string = cp_advance();
        if str_eq(v, "{") { depth = depth + 1; }
        if str_eq(v, "}") { depth = depth - 1; }
    }
    return 0;
}

// Skip balanced parentheses ( ... ), assumes current token is (
fn cp_skip_parens() -> i32 {
    var depth: i32 = 0;
    if str_eq(cp_peek_val(), "(") { depth = 1; cp_advance(); }
    while !cp_at_end() && depth > 0 {
        let v: string = cp_advance();
        if str_eq(v, "(") { depth = depth + 1; }
        if str_eq(v, ")") { depth = depth - 1; }
    }
    return 0;
}

// Skip to next semicolon at depth 0
fn cp_skip_to_semi() -> i32 {
    var depth: i32 = 0;
    while !cp_at_end() {
        let v: string = cp_peek_val();
        if str_eq(v, "{") || str_eq(v, "(") || str_eq(v, "[") { depth = depth + 1; }
        if str_eq(v, "}") || str_eq(v, ")") || str_eq(v, "]") { depth = depth - 1; }
        if str_eq(v, ";") && depth == 0 { cp_advance(); return 0; }
        cp_advance();
    }
    return 0;
}

// ── Type Parsing ────────────────────────────────────
// Collects type specifiers into a string: "static const unsigned long long *"

fn cp_is_storage_class(v: string) -> bool {
    return str_eq(v, "static") || str_eq(v, "extern") || str_eq(v, "inline") ||
           str_eq(v, "register") || str_eq(v, "auto") || str_eq(v, "_Thread_local");
}

fn cp_is_type_qualifier(v: string) -> bool {
    return str_eq(v, "const") || str_eq(v, "volatile") || str_eq(v, "restrict") ||
           str_eq(v, "_Atomic");
}

fn cp_is_type_specifier(v: string) -> bool {
    return str_eq(v, "void") || str_eq(v, "char") || str_eq(v, "short") ||
           str_eq(v, "int") || str_eq(v, "long") || str_eq(v, "float") ||
           str_eq(v, "double") || str_eq(v, "signed") || str_eq(v, "unsigned") ||
           str_eq(v, "bool") || str_eq(v, "_Bool") ||
           str_eq(v, "struct") || str_eq(v, "union") || str_eq(v, "enum");
}

fn cp_is_type_start() -> bool {
    let v: string = cp_peek_val();
    if cp_is_storage_class(v) { return true; }
    if cp_is_type_qualifier(v) { return true; }
    if cp_is_type_specifier(v) { return true; }
    if cp_peek() == CTK_IDENT() && cp_is_type_name(v) { return true; }
    return false;
}

// Parse type specifiers, return as string. Stops before declarator.
// Examples: "int", "const char", "unsigned long long", "struct foo", "static int"
fn cp_parse_base_type() -> string {
    var result: string = "";
    var storage: string = "";

    // Collect storage class
    while cp_is_storage_class(cp_peek_val()) {
        if len(storage) > 0 { storage = str_concat(storage, " "); }
        storage = str_concat(storage, cp_advance());
    }

    // Collect qualifiers and type specifiers
    var got_type: bool = false;
    while !cp_at_end() {
        let v: string = cp_peek_val();

        if cp_is_type_qualifier(v) {
            if len(result) > 0 { result = str_concat(result, " "); }
            result = str_concat(result, cp_advance());
        } else if cp_is_type_specifier(v) {
            if len(result) > 0 { result = str_concat(result, " "); }
            // Handle struct/union/enum + name
            if str_eq(v, "struct") || str_eq(v, "union") || str_eq(v, "enum") {
                result = str_concat(result, cp_advance());
                if cp_peek() == CTK_IDENT() {
                    result = str_concat(result, str_concat(" ", cp_advance()));
                }
            } else {
                result = str_concat(result, cp_advance());
            }
            got_type = true;
        } else if cp_peek() == CTK_IDENT() && cp_is_type_name(v) && !got_type {
            if len(result) > 0 { result = str_concat(result, " "); }
            result = str_concat(result, cp_advance());
            got_type = true;
        } else {
            // Not a type token, stop
            if !got_type && cp_peek() == CTK_IDENT() {
                // Unknown identifier might be a typedef'd type
                // Heuristic: if followed by * or identifier, treat as type
                let next: i32 = cp_peek_at(1);
                let next_v: string = cp_peek_val_at(1);
                if str_eq(next_v, "*") || next == CTK_IDENT() {
                    if len(result) > 0 { result = str_concat(result, " "); }
                    let tn: string = cp_advance();
                    cp_add_type_name(tn);
                    result = str_concat(result, tn);
                    got_type = true;
                } else {
                    // Give up
                    if len(result) == 0 { result = "int"; }
                    if len(storage) > 0 { return str_concat(storage, str_concat(" ", result)); }
                    return result;
                }
            } else {
                if len(result) == 0 { result = "int"; }
                if len(storage) > 0 { return str_concat(storage, str_concat(" ", result)); }
                return result;
            }
        }
    }

    if len(result) == 0 { result = "int"; }
    if len(storage) > 0 { return str_concat(storage, str_concat(" ", result)); }
    return result;
}

// Collect pointer stars after base type
fn cp_parse_pointers() -> string {
    var ptrs: string = "";
    while str_eq(cp_peek_val(), "*") {
        ptrs = str_concat(ptrs, "*");
        cp_advance();
        // Collect const/volatile after *
        while cp_is_type_qualifier(cp_peek_val()) {
            ptrs = str_concat(ptrs, str_concat(" ", cp_advance()));
        }
    }
    return ptrs;
}

// ── Parameter Parsing ───────────────────────────────

// Parse a single function parameter, return node index
fn cp_parse_param() -> i32 {
    // Handle ... (variadic)
    if str_eq(cp_peek_val(), ".") {
        cp_advance();
        if str_eq(cp_peek_val(), ".") { cp_advance(); }
        if str_eq(cp_peek_val(), ".") { cp_advance(); }
        return cn_new(CNK_PARAM(), "...", "...", 0, 0, 0);
    }

    // Handle void parameter (just "void" with no name)
    if str_eq(cp_peek_val(), "void") {
        let save: i32 = cp_pos;
        cp_advance();
        if str_eq(cp_peek_val(), ")") || str_eq(cp_peek_val(), ",") {
            return cn_new(CNK_PARAM(), "", "void", 0, 0, 0);
        }
        cp_pos = save;
    }

    let base: string = cp_parse_base_type();
    let ptrs: string = cp_parse_pointers();
    var full_type: string = base;
    if len(ptrs) > 0 { full_type = str_concat(base, str_concat(" ", ptrs)); }

    // Parse declarator name (might be absent in declarations)
    var name: string = "";
    if cp_peek() == CTK_IDENT() {
        name = cp_advance();
    }

    // Handle array declarator: name[size]
    if str_eq(cp_peek_val(), "[") {
        cp_advance();
        while !cp_at_end() && !str_eq(cp_peek_val(), "]") { cp_advance(); }
        cp_match_val("]");
        full_type = str_concat(full_type, "[]");
    }

    // Handle function pointer: (*name)(params)
    // Already partially consumed, just skip
    if str_eq(cp_peek_val(), "(") {
        cp_skip_parens();
        full_type = str_concat(full_type, "(*)()");
    }

    return cn_new(CNK_PARAM(), name, full_type, 0, 0, 0);
}

// Parse parameter list (assumes '(' already consumed)
// Returns: temp array of param node indices
fn cp_parse_params() -> i32 {
    let params: i32 = array_new(0);

    if str_eq(cp_peek_val(), ")") { cp_advance(); return params; }

    array_push(params, cp_parse_param());
    while str_eq(cp_peek_val(), ",") {
        cp_advance();
        array_push(params, cp_parse_param());
    }

    cp_expect_val(")");
    return params;
}

// ── Struct Field Parsing ────────────────────────────

fn cp_parse_struct_fields() -> i32 {
    let fields: i32 = array_new(0);

    while !cp_at_end() && !str_eq(cp_peek_val(), "}") {
        // Skip preprocessor inside struct
        if cp_peek() == CTK_PREPROC() {
            cp_advance();
        }
        // Nested struct/union/enum with body
        else if str_eq(cp_peek_val(), "struct") || str_eq(cp_peek_val(), "union") || str_eq(cp_peek_val(), "enum") {
            let nested_kw: string = cp_advance();
            var nested_name: string = "";
            if cp_peek() == CTK_IDENT() { nested_name = cp_advance(); }
            if str_eq(cp_peek_val(), "{") {
                cp_skip_braces();
                // Optional field name after closing brace
                var fname: string = "";
                if cp_peek() == CTK_IDENT() { fname = cp_advance(); }
                var ntype: string = nested_kw;
                if len(nested_name) > 0 {
                    ntype = str_concat(nested_kw, str_concat(" ", nested_name));
                }
                array_push(fields, cn_new(CNK_FIELD(), fname, ntype, 0, 0, 0));
            }
            cp_match_val(";");
        }
        else if str_eq(cp_peek_val(), "}") {
            // end of struct
        }
        else {
            let save_pos: i32 = cp_pos;
            let base: string = cp_parse_base_type();
            // Parse one or more declarators
            var first: bool = true;
            while !cp_at_end() && !str_eq(cp_peek_val(), ";") && !str_eq(cp_peek_val(), "}") {
                if !first { cp_expect_val(","); }
                first = false;

                let ptrs: string = cp_parse_pointers();
                var full_type: string = base;
                if len(ptrs) > 0 { full_type = str_concat(base, str_concat(" ", ptrs)); }

                var name: string = "";
                if cp_peek() == CTK_IDENT() { name = cp_advance(); }

                // Function pointer field: (*name)(params)
                if str_eq(cp_peek_val(), "(") && len(name) == 0 {
                    cp_skip_parens();
                    name = "(*)";
                    if str_eq(cp_peek_val(), "(") { cp_skip_parens(); }
                }

                // Array field: name[size]
                if str_eq(cp_peek_val(), "[") {
                    cp_advance();
                    var arr_size: string = "";
                    while !cp_at_end() && !str_eq(cp_peek_val(), "]") {
                        arr_size = str_concat(arr_size, cp_advance());
                    }
                    cp_expect_val("]");
                    full_type = str_concat(full_type, str_concat("[", str_concat(arr_size, "]")));
                }

                // Bitfield: name : width
                if str_eq(cp_peek_val(), ":") {
                    cp_advance();
                    if cp_peek() == CTK_INT_LIT() {
                        full_type = str_concat(full_type, str_concat(":", cp_advance()));
                    }
                }

                array_push(fields, cn_new(CNK_FIELD(), name, full_type, 0, 0, 0));

                // Safety: if we didn't advance, force advance to prevent infinite loop
                if cp_pos == save_pos {
                    cp_advance();
                    save_pos = cp_pos;
                }
            }
            cp_match_val(";");
        }
    }

    return fields;
}

// ── Enum Constant Parsing ───────────────────────────

fn cp_parse_enum_consts() -> i32 {
    let consts: i32 = array_new(0);

    while !cp_at_end() && !str_eq(cp_peek_val(), "}") {
        if cp_peek() == CTK_IDENT() {
            let name: string = cp_advance();
            var val: string = "";
            if str_eq(cp_peek_val(), "=") {
                cp_advance();
                // Collect value expression until , or } at depth 0
                var depth: i32 = 0;
                var done: bool = false;
                while !cp_at_end() && !done {
                    let v: string = cp_peek_val();
                    if (str_eq(v, ",") || str_eq(v, "}")) && depth == 0 {
                        done = true;
                    }
                    if !done {
                        if str_eq(v, "(") { depth = depth + 1; }
                        if str_eq(v, ")") { depth = depth - 1; }
                        if len(val) > 0 { val = str_concat(val, " "); }
                        val = str_concat(val, cp_advance());
                    }
                }
            }
            array_push(consts, cn_new(CNK_ENUM_CONST(), name, val, 0, 0, 0));
            cp_match_val(",");
        } else {
            cp_advance(); // skip unexpected token
        }
    }

    return consts;
}

// ── Top-Level Parsing ───────────────────────────────

fn cp_parse_struct_or_union() -> i32 {
    let keyword: string = cp_advance(); // "struct" or "union"
    var name: string = "";
    if cp_peek() == CTK_IDENT() { name = cp_advance(); }

    if str_eq(cp_peek_val(), "{") {
        cp_advance(); // consume {
        let fields: i32 = cp_parse_struct_fields();
        cp_expect_val("}");

        let fstart: i32 = cn_flush(fields);
        let fcount: i32 = array_len(fields);

        // Register struct name as type
        if len(name) > 0 { cp_add_type_name(name); }

        // Check for variable declarations after struct def
        // struct foo { ... } var1, var2;
        if str_eq(cp_peek_val(), ";") {
            cp_advance();
            return cn_new(CNK_STRUCT_DEF(), name, keyword, fstart, fcount, 0);
        }

        // Variable declared with struct type
        let struct_node: i32 = cn_new(CNK_STRUCT_DEF(), name, keyword, fstart, fcount, 0);
        cp_skip_to_semi();
        return struct_node;
    }

    // Forward declaration: struct foo;
    // Or used as type: struct foo *ptr;
    return 0 - 1; // signal: this is a type, not a complete declaration
}

fn cp_parse_enum() -> i32 {
    cp_advance(); // consume "enum"
    var name: string = "";
    if cp_peek() == CTK_IDENT() { name = cp_advance(); }

    if str_eq(cp_peek_val(), "{") {
        cp_advance();
        let consts: i32 = cp_parse_enum_consts();
        cp_expect_val("}");

        let cstart: i32 = cn_flush(consts);
        let ccount: i32 = array_len(consts);

        if len(name) > 0 { cp_add_type_name(name); }

        cp_match_val(";");
        return cn_new(CNK_ENUM_DEF(), name, "enum", cstart, ccount, 0);
    }

    return 0 - 1;
}

fn cp_parse_typedef() -> i32 {
    cp_advance(); // consume "typedef"

    // typedef struct { ... } Name;
    // typedef enum { ... } Name;
    // typedef int (*FuncPtr)(int, int);
    // typedef unsigned long size_t;

    if str_eq(cp_peek_val(), "struct") || str_eq(cp_peek_val(), "union") {
        let keyword: string = cp_advance();
        var tag: string = "";
        if cp_peek() == CTK_IDENT() && str_eq(cp_peek_val_at(1), "{") {
            tag = cp_advance();
        } else if cp_peek() == CTK_IDENT() && !str_eq(cp_peek_val_at(1), "{") {
            // typedef struct Foo Foo;
            tag = cp_advance();
            var alias: string = "";
            if cp_peek() == CTK_IDENT() { alias = cp_advance(); }
            cp_match_val(";");
            if len(alias) > 0 { cp_add_type_name(alias); }
            return cn_new(CNK_TYPEDEF(), alias, str_concat(keyword, str_concat(" ", tag)), 0, 0, 0);
        }

        if str_eq(cp_peek_val(), "{") {
            cp_advance();
            let fields: i32 = cp_parse_struct_fields();
            cp_expect_val("}");
            let fstart: i32 = cn_flush(fields);
            let fcount: i32 = array_len(fields);

            // The name after } is the typedef name
            var alias2: string = "";
            let ptrs: string = cp_parse_pointers();
            if cp_peek() == CTK_IDENT() { alias2 = cp_advance(); }
            cp_match_val(";");

            if len(alias2) > 0 { cp_add_type_name(alias2); }
            if len(tag) > 0 { cp_add_type_name(tag); }

            // Create struct definition node
            let snode: i32 = cn_new(CNK_STRUCT_DEF(), tag, keyword, fstart, fcount, 0);
            return cn_new(CNK_TYPEDEF(), alias2, str_concat(keyword, str_concat(" ", tag)), snode, 0, 0);
        }
        cp_skip_to_semi();
        return cn_new(CNK_TYPEDEF(), "", keyword, 0, 0, 0);
    }

    if str_eq(cp_peek_val(), "enum") {
        cp_advance();
        var etag: string = "";
        if cp_peek() == CTK_IDENT() && str_eq(cp_peek_val_at(1), "{") {
            etag = cp_advance();
        }
        if str_eq(cp_peek_val(), "{") {
            cp_advance();
            let consts: i32 = cp_parse_enum_consts();
            cp_expect_val("}");
            let cstart: i32 = cn_flush(consts);
            let ccount: i32 = array_len(consts);

            var ealias: string = "";
            if cp_peek() == CTK_IDENT() { ealias = cp_advance(); }
            cp_match_val(";");

            if len(ealias) > 0 { cp_add_type_name(ealias); }
            let enode: i32 = cn_new(CNK_ENUM_DEF(), etag, "enum", cstart, ccount, 0);
            return cn_new(CNK_TYPEDEF(), ealias, "enum", enode, 0, 0);
        }
        cp_skip_to_semi();
        return cn_new(CNK_TYPEDEF(), "", "enum", 0, 0, 0);
    }

    // Simple typedef: typedef <type> <name>;
    // Or function pointer: typedef <ret> (*<name>)(<params>);
    let base: string = cp_parse_base_type();
    let ptrs2: string = cp_parse_pointers();
    var orig_type: string = base;
    if len(ptrs2) > 0 { orig_type = str_concat(base, str_concat(" ", ptrs2)); }

    // Function pointer typedef: typedef int (*name)(int, int);
    if str_eq(cp_peek_val(), "(") && str_eq(cp_peek_val_at(1), "*") {
        cp_advance(); // (
        cp_advance(); // *
        var fp_name: string = "";
        if cp_peek() == CTK_IDENT() { fp_name = cp_advance(); }
        cp_expect_val(")");
        // Skip parameter list
        if str_eq(cp_peek_val(), "(") { cp_skip_parens(); }
        cp_match_val(";");
        if len(fp_name) > 0 { cp_add_type_name(fp_name); }
        return cn_new(CNK_TYPEDEF(), fp_name, str_concat(orig_type, " (*)()"), 0, 0, 0);
    }

    var alias3: string = "";
    if cp_peek() == CTK_IDENT() { alias3 = cp_advance(); }

    // Array typedef: typedef int Arr[10];
    if str_eq(cp_peek_val(), "[") {
        cp_advance();
        var arr_sz: string = "";
        while !cp_at_end() && !str_eq(cp_peek_val(), "]") {
            arr_sz = str_concat(arr_sz, cp_advance());
        }
        cp_expect_val("]");
        orig_type = str_concat(orig_type, str_concat("[", str_concat(arr_sz, "]")));
    }

    cp_match_val(";");
    if len(alias3) > 0 { cp_add_type_name(alias3); }
    return cn_new(CNK_TYPEDEF(), alias3, orig_type, 0, 0, 0);
}

// ── Expression Parser (recursive descent with precedence) ─────

// Forward declarations for recursive calls
fn cp_parse_expr() -> i32;
fn cp_parse_assign_expr() -> i32;
fn cp_parse_stmt() -> i32;

// Primary: literals, identifiers, parenthesized expressions, sizeof
fn cp_parse_primary() -> i32 {
    let tv: string = cp_peek_val();
    let tt: i32 = cp_peek();

    // Integer literal
    if tt == CTK_INT_LIT() {
        let val: string = cp_advance();
        return cn_new(CNK_EXPR_INT(), val, "", 0, 0, 0);
    }

    // String literal
    if tt == CTK_STR_LIT() {
        let val: string = cp_advance();
        return cn_new(CNK_EXPR_STR(), val, "", 0, 0, 0);
    }

    // Char literal
    if tt == CTK_CHAR_LIT() {
        let val: string = cp_advance();
        return cn_new(CNK_EXPR_CHAR(), val, "", 0, 0, 0);
    }

    // NULL
    if str_eq(tv, "NULL") {
        cp_advance();
        return cn_new(CNK_EXPR_NULL(), "NULL", "", 0, 0, 0);
    }

    // sizeof(type_or_expr)
    if str_eq(tv, "sizeof") {
        cp_advance();
        cp_match_val("(");
        // Collect everything until matching )
        var content: string = "";
        var depth: i32 = 1;
        while !cp_at_end() && depth > 0 {
            let sv: string = cp_peek_val();
            if str_eq(sv, "(") { depth = depth + 1; }
            if str_eq(sv, ")") { depth = depth - 1; }
            if depth > 0 {
                if len(content) > 0 { content = str_concat(content, " "); }
                content = str_concat(content, cp_advance());
            }
        }
        cp_match_val(")");
        return cn_new(CNK_EXPR_SIZEOF(), content, "", 0, 0, 0);
    }

    // Identifier
    if tt == CTK_IDENT() {
        let name: string = cp_advance();
        return cn_new(CNK_EXPR_IDENT(), name, "", 0, 0, 0);
    }

    // Parenthesized expression or cast
    if str_eq(tv, "(") {
        cp_advance();

        // Check if this is a cast: (type)expr
        // Heuristic: if next token is a type keyword or known type name
        let peek_v: string = cp_peek_val();
        var is_cast: bool = false;
        if cp_is_type_keyword(peek_v) || cp_is_type_name(peek_v) {
            is_cast = true;
        }
        if str_eq(peek_v, "const") || str_eq(peek_v, "unsigned") || str_eq(peek_v, "signed") {
            is_cast = true;
        }
        if str_eq(peek_v, "struct") || str_eq(peek_v, "union") || str_eq(peek_v, "enum") {
            is_cast = true;
        }

        if is_cast {
            // Collect type until )
            var cast_type: string = "";
            while !cp_at_end() && !str_eq(cp_peek_val(), ")") {
                if len(cast_type) > 0 { cast_type = str_concat(cast_type, " "); }
                cast_type = str_concat(cast_type, cp_advance());
            }
            cp_match_val(")");
            let operand: i32 = cp_parse_unary();
            return cn_new(CNK_EXPR_CAST(), "", cast_type, operand, 0, 0);
        }

        // Regular parenthesized expression
        let inner: i32 = cp_parse_expr();
        cp_match_val(")");
        return inner;
    }

    // Unknown — create a placeholder
    let unk: string = cp_advance();
    return cn_new(CNK_EXPR_IDENT(), unk, "", 0, 0, 0);
}

// Unary: prefix !, -, ~, *, &, ++, --
fn cp_parse_unary() -> i32 {
    let tv: string = cp_peek_val();

    if str_eq(tv, "!") {
        cp_advance();
        let operand: i32 = cp_parse_unary();
        return cn_new(CNK_EXPR_UNARY(), "!", "", operand, 0, 0);
    }
    if str_eq(tv, "-") {
        cp_advance();
        let operand: i32 = cp_parse_unary();
        return cn_new(CNK_EXPR_UNARY(), "-", "", operand, 0, 0);
    }
    if str_eq(tv, "~") {
        cp_advance();
        let operand: i32 = cp_parse_unary();
        return cn_new(CNK_EXPR_UNARY(), "~", "", operand, 0, 0);
    }
    if str_eq(tv, "*") {
        cp_advance();
        let operand: i32 = cp_parse_unary();
        return cn_new(CNK_EXPR_DEREF(), "*", "", operand, 0, 0);
    }
    if str_eq(tv, "&") {
        cp_advance();
        let operand: i32 = cp_parse_unary();
        return cn_new(CNK_EXPR_ADDR(), "&", "", operand, 0, 0);
    }
    if str_eq(tv, "++") {
        cp_advance();
        let operand: i32 = cp_parse_unary();
        return cn_new(CNK_EXPR_UNARY(), "++pre", "", operand, 0, 0);
    }
    if str_eq(tv, "--") {
        cp_advance();
        let operand: i32 = cp_parse_unary();
        return cn_new(CNK_EXPR_UNARY(), "--pre", "", operand, 0, 0);
    }

    return cp_parse_postfix();
}

// Postfix: function call, array index, member access, ++, --
fn cp_parse_postfix() -> i32 {
    var node: i32 = cp_parse_primary();

    var cont: bool = true;
    while cont {
        let pv: string = cp_peek_val();

        // Function call: f(args...)
        if str_eq(pv, "(") {
            cp_advance();
            let args: i32 = array_new(0);
            if !str_eq(cp_peek_val(), ")") {
                array_push(args, cp_parse_assign_expr());
                while str_eq(cp_peek_val(), ",") {
                    cp_advance();
                    array_push(args, cp_parse_assign_expr());
                }
            }
            cp_match_val(")");
            let astart: i32 = cn_flush(args);
            node = cn_new(CNK_EXPR_CALL(), cnn(node), "", astart, array_len(args), 0);
        } else if str_eq(pv, "[") {
            // Array index: a[i]
            cp_advance();
            let idx_expr: i32 = cp_parse_expr();
            cp_match_val("]");
            node = cn_new(CNK_EXPR_INDEX(), "", "", node, idx_expr, 0);
        } else if str_eq(pv, ".") {
            // Member access: a.b
            cp_advance();
            let field: string = cp_advance();
            node = cn_new(CNK_EXPR_MEMBER(), field, "", node, 0, 0);
        } else if str_eq(pv, "->") {
            // Arrow member: a->b
            cp_advance();
            let field: string = cp_advance();
            node = cn_new(CNK_EXPR_MEMBER(), field, "", node, 1, 0);
        } else if str_eq(pv, "++") {
            cp_advance();
            node = cn_new(CNK_EXPR_POSTFIX(), "++", "", node, 0, 0);
        } else if str_eq(pv, "--") {
            cp_advance();
            node = cn_new(CNK_EXPR_POSTFIX(), "--", "", node, 0, 0);
        } else {
            cont = false;
        }
    }

    return node;
}

// Multiplicative: *, /, %
fn cp_parse_mul() -> i32 {
    var left: i32 = cp_parse_unary();
    while str_eq(cp_peek_val(), "*") || str_eq(cp_peek_val(), "/") || str_eq(cp_peek_val(), "%") {
        let op: string = cp_advance();
        let right: i32 = cp_parse_unary();
        left = cn_new(CNK_EXPR_BINARY(), op, "", left, right, 0);
    }
    return left;
}

// Additive: +, -
fn cp_parse_add() -> i32 {
    var left: i32 = cp_parse_mul();
    while str_eq(cp_peek_val(), "+") || str_eq(cp_peek_val(), "-") {
        let op: string = cp_advance();
        let right: i32 = cp_parse_mul();
        left = cn_new(CNK_EXPR_BINARY(), op, "", left, right, 0);
    }
    return left;
}

// Shift: <<, >>
fn cp_parse_shift() -> i32 {
    var left: i32 = cp_parse_add();
    while str_eq(cp_peek_val(), "<<") || str_eq(cp_peek_val(), ">>") {
        let op: string = cp_advance();
        let right: i32 = cp_parse_add();
        left = cn_new(CNK_EXPR_BINARY(), op, "", left, right, 0);
    }
    return left;
}

// Relational: <, >, <=, >=
fn cp_parse_rel() -> i32 {
    var left: i32 = cp_parse_shift();
    while str_eq(cp_peek_val(), "<") || str_eq(cp_peek_val(), ">") ||
          str_eq(cp_peek_val(), "<=") || str_eq(cp_peek_val(), ">=") {
        let op: string = cp_advance();
        let right: i32 = cp_parse_shift();
        left = cn_new(CNK_EXPR_BINARY(), op, "", left, right, 0);
    }
    return left;
}

// Equality: ==, !=
fn cp_parse_eq() -> i32 {
    var left: i32 = cp_parse_rel();
    while str_eq(cp_peek_val(), "==") || str_eq(cp_peek_val(), "!=") {
        let op: string = cp_advance();
        let right: i32 = cp_parse_rel();
        left = cn_new(CNK_EXPR_BINARY(), op, "", left, right, 0);
    }
    return left;
}

// Bitwise AND: &
fn cp_parse_bit_and() -> i32 {
    var left: i32 = cp_parse_eq();
    while str_eq(cp_peek_val(), "&") && !str_eq(cp_peek_val_at(1), "&") {
        cp_advance();
        let right: i32 = cp_parse_eq();
        left = cn_new(CNK_EXPR_BINARY(), "&", "", left, right, 0);
    }
    return left;
}

// Bitwise XOR: ^
fn cp_parse_bit_xor() -> i32 {
    var left: i32 = cp_parse_bit_and();
    while str_eq(cp_peek_val(), "^") {
        cp_advance();
        let right: i32 = cp_parse_bit_and();
        left = cn_new(CNK_EXPR_BINARY(), "^", "", left, right, 0);
    }
    return left;
}

// Bitwise OR: |
fn cp_parse_bit_or() -> i32 {
    var left: i32 = cp_parse_bit_xor();
    while str_eq(cp_peek_val(), "|") && !str_eq(cp_peek_val_at(1), "|") {
        cp_advance();
        let right: i32 = cp_parse_bit_xor();
        left = cn_new(CNK_EXPR_BINARY(), "|", "", left, right, 0);
    }
    return left;
}

// Logical AND: &&
fn cp_parse_log_and() -> i32 {
    var left: i32 = cp_parse_bit_or();
    while str_eq(cp_peek_val(), "&&") {
        cp_advance();
        let right: i32 = cp_parse_bit_or();
        left = cn_new(CNK_EXPR_BINARY(), "&&", "", left, right, 0);
    }
    return left;
}

// Logical OR: ||
fn cp_parse_log_or() -> i32 {
    var left: i32 = cp_parse_log_and();
    while str_eq(cp_peek_val(), "||") {
        cp_advance();
        let right: i32 = cp_parse_log_and();
        left = cn_new(CNK_EXPR_BINARY(), "||", "", left, right, 0);
    }
    return left;
}

// Ternary: cond ? then : else
fn cp_parse_ternary() -> i32 {
    var cond: i32 = cp_parse_log_or();
    if str_eq(cp_peek_val(), "?") {
        cp_advance();
        let then_e: i32 = cp_parse_expr();
        cp_match_val(":");
        let else_e: i32 = cp_parse_ternary();
        cond = cn_new(CNK_EXPR_TERNARY(), "", "", cond, then_e, else_e);
    }
    return cond;
}

// Assignment: lhs = rhs, lhs += rhs, etc.
fn cp_parse_assign_expr() -> i32 {
    let left: i32 = cp_parse_ternary();
    let av: string = cp_peek_val();
    if str_eq(av, "=") || str_eq(av, "+=") || str_eq(av, "-=") ||
       str_eq(av, "*=") || str_eq(av, "/=") || str_eq(av, "%=") ||
       str_eq(av, "&=") || str_eq(av, "|=") || str_eq(av, "^=") ||
       str_eq(av, "<<=") || str_eq(av, ">>=") {
        let op: string = cp_advance();
        let right: i32 = cp_parse_assign_expr();
        return cn_new(CNK_EXPR_ASSIGN(), op, "", left, right, 0);
    }
    return left;
}

// Comma expression (top-level)
fn cp_parse_expr() -> i32 {
    return cp_parse_assign_expr();
}

// ── Statement Parser ──────────────────────────────────

fn cp_parse_block() -> i32;

fn cp_parse_stmt() -> i32 {
    let sv: string = cp_peek_val();

    // Empty statement
    if str_eq(sv, ";") {
        cp_advance();
        return cn_new(CNK_STMT_EXPR(), "", "", -1, 0, 0);
    }

    // Block statement
    if str_eq(sv, "{") {
        return cp_parse_block();
    }

    // Return statement
    if str_eq(sv, "return") {
        cp_advance();
        var ret_expr: i32 = -1;
        if !str_eq(cp_peek_val(), ";") {
            ret_expr = cp_parse_expr();
        }
        cp_match_val(";");
        return cn_new(CNK_STMT_RETURN(), "", "", ret_expr, 0, 0);
    }

    // If statement
    if str_eq(sv, "if") {
        cp_advance();
        cp_match_val("(");
        let cond: i32 = cp_parse_expr();
        cp_match_val(")");
        let then_body: i32 = cp_parse_stmt();
        var else_body: i32 = -1;
        if str_eq(cp_peek_val(), "else") {
            cp_advance();
            else_body = cp_parse_stmt();
        }
        return cn_new(CNK_STMT_IF(), "", "", cond, then_body, else_body);
    }

    // While statement
    if str_eq(sv, "while") {
        cp_advance();
        cp_match_val("(");
        let cond: i32 = cp_parse_expr();
        cp_match_val(")");
        let body: i32 = cp_parse_stmt();
        return cn_new(CNK_STMT_WHILE(), "", "", cond, body, 0);
    }

    // For statement
    if str_eq(sv, "for") {
        cp_advance();
        cp_match_val("(");

        // Init: could be declaration or expression or empty
        var init_stmt: i32 = -1;
        if str_eq(cp_peek_val(), ";") {
            cp_advance();
        } else if cp_is_type_keyword(cp_peek_val()) || cp_is_type_name(cp_peek_val()) ||
                  str_eq(cp_peek_val(), "const") || str_eq(cp_peek_val(), "static") {
            // Variable declaration as init
            init_stmt = cp_parse_var_decl_stmt();
        } else {
            init_stmt = cp_parse_expr();
            cp_match_val(";");
        }

        // Condition
        var for_cond: i32 = -1;
        if !str_eq(cp_peek_val(), ";") {
            for_cond = cp_parse_expr();
        }
        cp_match_val(";");

        // Step
        var step_expr: i32 = -1;
        if !str_eq(cp_peek_val(), ")") {
            step_expr = cp_parse_expr();
        }
        cp_match_val(")");

        let for_body: i32 = cp_parse_stmt();

        // Pack: init in d1, cond in d2, body wraps step
        // Store step as a separate node referenced by d3
        let for_node: i32 = cn_new(CNK_STMT_FOR(), "", "", init_stmt, for_cond, step_expr);
        // Store body reference in type field as string hack (ugly but works)
        // Actually, let's use the children array
        let body_arr: i32 = array_new(0);
        array_push(body_arr, for_body);
        let body_start: i32 = cn_flush(body_arr);
        // Update d3 to hold both step and body_start encoded
        // Simpler: use cn_new for the for node differently
        // Let's just store body in name field as index string
        // Actually, simplest: d1=block wrapping init+cond+step+body
        // Let me just use a flat approach: for has 4 children
        let for_children: i32 = array_new(0);
        array_push(for_children, init_stmt);
        array_push(for_children, for_cond);
        array_push(for_children, step_expr);
        array_push(for_children, for_body);
        let fc_start: i32 = cn_flush(for_children);
        return cn_new(CNK_STMT_FOR(), "", "", fc_start, 4, 0);
    }

    // Switch statement
    if str_eq(sv, "switch") {
        cp_advance();
        cp_match_val("(");
        let sw_expr: i32 = cp_parse_expr();
        cp_match_val(")");
        cp_match_val("{");

        let cases: i32 = array_new(0);
        while !cp_at_end() && !str_eq(cp_peek_val(), "}") {
            if str_eq(cp_peek_val(), "case") {
                cp_advance();
                // Collect case value expression
                let case_expr: i32 = cp_parse_expr();
                cp_match_val(":");
                // Collect statements until next case/default/}
                let case_stmts: i32 = array_new(0);
                while !cp_at_end() && !str_eq(cp_peek_val(), "case") &&
                      !str_eq(cp_peek_val(), "default") && !str_eq(cp_peek_val(), "}") {
                    array_push(case_stmts, cp_parse_stmt());
                }
                let cs_start: i32 = cn_flush(case_stmts);
                array_push(cases, cn_new(CNK_STMT_CASE(), "", "", case_expr, cs_start, array_len(case_stmts)));
            } else if str_eq(cp_peek_val(), "default") {
                cp_advance();
                cp_match_val(":");
                let def_stmts: i32 = array_new(0);
                while !cp_at_end() && !str_eq(cp_peek_val(), "case") &&
                      !str_eq(cp_peek_val(), "default") && !str_eq(cp_peek_val(), "}") {
                    array_push(def_stmts, cp_parse_stmt());
                }
                let ds_start: i32 = cn_flush(def_stmts);
                array_push(cases, cn_new(CNK_STMT_CASE(), "default", "", -1, ds_start, array_len(def_stmts)));
            } else {
                cp_advance();
            }
        }
        cp_match_val("}");
        let case_start: i32 = cn_flush(cases);
        return cn_new(CNK_STMT_SWITCH(), "", "", sw_expr, case_start, array_len(cases));
    }

    // Break
    if str_eq(sv, "break") {
        cp_advance();
        cp_match_val(";");
        return cn_new(CNK_STMT_BREAK(), "", "", 0, 0, 0);
    }

    // Continue
    if str_eq(sv, "continue") {
        cp_advance();
        cp_match_val(";");
        return cn_new(CNK_STMT_CONTINUE(), "", "", 0, 0, 0);
    }

    // Variable declaration: starts with type keyword/name
    if cp_is_type_keyword(cp_peek_val()) || cp_is_type_name(cp_peek_val()) ||
       str_eq(cp_peek_val(), "const") || str_eq(cp_peek_val(), "static") ||
       str_eq(cp_peek_val(), "unsigned") || str_eq(cp_peek_val(), "signed") {
        // Check if this is really a declaration (type followed by ident)
        // vs an expression statement (could be a typedef'd type used as function call)
        return cp_parse_var_decl_stmt();
    }

    // Expression statement
    let expr: i32 = cp_parse_expr();
    cp_match_val(";");
    return cn_new(CNK_STMT_EXPR(), "", "", expr, 0, 0);
}

// Parse variable declaration statement: type name [= init] [, name2 [= init2]] ;
fn cp_parse_var_decl_stmt() -> i32 {
    let base: string = cp_parse_base_type();
    let ptrs: string = cp_parse_pointers();
    var full_type: string = base;
    if len(ptrs) > 0 { full_type = str_concat(base, str_concat(" ", ptrs)); }

    let var_name: string = cp_advance();

    // Handle array declarator
    if str_eq(cp_peek_val(), "[") {
        cp_advance();
        while !cp_at_end() && !str_eq(cp_peek_val(), "]") { cp_advance(); }
        cp_match_val("]");
        full_type = str_concat(full_type, "[]");
    }

    // Initializer
    var init_expr: i32 = -1;
    if str_eq(cp_peek_val(), "=") {
        cp_advance();
        // Handle {0} and similar struct initializers
        if str_eq(cp_peek_val(), "{") {
            // Skip initializer list
            cp_skip_braces();
            init_expr = cn_new(CNK_EXPR_INT(), "0", "", 0, 0, 0);
        } else {
            init_expr = cp_parse_assign_expr();
        }
    }

    // Handle additional declarators: int a = 1, b = 2;
    // For now, skip them
    while str_eq(cp_peek_val(), ",") {
        cp_advance();
        // Skip pointer stars
        while str_eq(cp_peek_val(), "*") { cp_advance(); }
        if cp_peek() == CTK_IDENT() { cp_advance(); }
        if str_eq(cp_peek_val(), "=") {
            cp_advance();
            if str_eq(cp_peek_val(), "{") { cp_skip_braces(); }
            else { cp_parse_assign_expr(); }
        }
    }

    cp_match_val(";");
    return cn_new(CNK_STMT_VAR(), var_name, full_type, init_expr, 0, 0);
}

// Parse block: { stmt* }
fn cp_parse_block() -> i32 {
    cp_match_val("{");
    let stmts: i32 = array_new(0);
    while !cp_at_end() && !str_eq(cp_peek_val(), "}") {
        let save: i32 = cp_pos;
        array_push(stmts, cp_parse_stmt());
        if cp_pos == save { cp_advance(); }  // safety
    }
    cp_match_val("}");
    let s_start: i32 = cn_flush(stmts);
    return cn_new(CNK_STMT_BLOCK(), "", "", s_start, array_len(stmts), 0);
}

// Parse function body: wraps cp_parse_block for a function definition
fn cp_parse_func_body() -> i32 {
    return cp_parse_block();
}

// ── Top-Level Declarations ──────────────────────────

// Parse a top-level declaration (function or global variable)
// Assumes type specifiers haven't been consumed yet
fn cp_parse_declaration() -> i32 {
    let base: string = cp_parse_base_type();
    let ptrs: string = cp_parse_pointers();
    var full_type: string = base;
    if len(ptrs) > 0 { full_type = str_concat(base, str_concat(" ", ptrs)); }

    // Function pointer declaration: type (*name)(params) = ...;
    if str_eq(cp_peek_val(), "(") && str_eq(cp_peek_val_at(1), "*") {
        cp_skip_to_semi();
        return cn_new(CNK_GLOBAL_VAR(), "", full_type, 0, 0, 0);
    }

    // Get declarator name
    var name: string = "";
    if cp_peek() == CTK_IDENT() { name = cp_advance(); }

    if len(name) == 0 {
        // No name found, skip to semicolon
        cp_skip_to_semi();
        return cn_new(CNK_GLOBAL_VAR(), "", full_type, 0, 0, 0);
    }

    // Function definition or declaration
    if str_eq(cp_peek_val(), "(") {
        cp_advance(); // consume (
        let params: i32 = cp_parse_params();
        let pstart: i32 = cn_flush(params);
        let pcount: i32 = array_len(params);

        // Possible attributes after params: __attribute__((...))
        while str_eq(cp_peek_val(), "__attribute__") {
            cp_advance();
            if str_eq(cp_peek_val(), "(") { cp_skip_parens(); }
        }

        if str_eq(cp_peek_val(), "{") {
            // Function definition — parse body
            let body: i32 = cp_parse_func_body();
            return cn_new(CNK_FUNC_DEF(), name, full_type, pstart, pcount, body);
        }

        // Function declaration
        cp_match_val(";");
        return cn_new(CNK_FUNC_DECL(), name, full_type, pstart, pcount, 0);
    }

    // Array variable: type name[size] = ...;
    if str_eq(cp_peek_val(), "[") {
        cp_advance();
        var arr_sz2: string = "";
        while !cp_at_end() && !str_eq(cp_peek_val(), "]") {
            arr_sz2 = str_concat(arr_sz2, cp_advance());
        }
        cp_expect_val("]");
        full_type = str_concat(full_type, str_concat("[", str_concat(arr_sz2, "]")));
    }

    // Variable with initializer
    if str_eq(cp_peek_val(), "=") {
        cp_advance();
        // Skip initializer (might contain braces for struct/array init)
        if str_eq(cp_peek_val(), "{") {
            cp_skip_braces();
        } else {
            // Skip expression until ;
            var depth: i32 = 0;
            while !cp_at_end() {
                let v: string = cp_peek_val();
                if str_eq(v, "(") || str_eq(v, "[") { depth = depth + 1; }
                if str_eq(v, ")") || str_eq(v, "]") { depth = depth - 1; }
                if str_eq(v, ";") && depth <= 0 { cp_advance(); return cn_new(CNK_GLOBAL_VAR(), name, full_type, 0, 0, 0); }
                cp_advance();
            }
        }
    }

    // Multiple declarators: int a, b, *c;
    while str_eq(cp_peek_val(), ",") {
        cp_advance();
        // Skip additional declarators
        while !cp_at_end() && !str_eq(cp_peek_val(), ",") && !str_eq(cp_peek_val(), ";") {
            if str_eq(cp_peek_val(), "=") {
                cp_advance();
                if str_eq(cp_peek_val(), "{") { cp_skip_braces(); }
            } else {
                cp_advance();
            }
        }
    }

    cp_match_val(";");
    return cn_new(CNK_GLOBAL_VAR(), name, full_type, 0, 0, 0);
}

// ── Main Program Parser ─────────────────────────────

fn cp_parse_program() -> i32 {
    let decls: i32 = array_new(0);

    while !cp_at_end() && cp_peek() != CTK_EOF() {
        let loop_save: i32 = cp_pos;

        // Preprocessor directive
        if cp_peek() == CTK_PREPROC() {
            let pval: string = cp_peek_val();
            cp_advance();
            array_push(decls, cn_new(CNK_PREPROC(), pval, "", 0, 0, 0));
        }
        // typedef
        else if str_eq(cp_peek_val(), "typedef") {
            let td: i32 = cp_parse_typedef();
            if td >= 0 { array_push(decls, td); }
        }
        // struct/union at top level
        else if str_eq(cp_peek_val(), "struct") || str_eq(cp_peek_val(), "union") {
            // Could be: struct definition, or type used in declaration
            // Peek ahead to decide
            let save: i32 = cp_pos;
            let kw: string = cp_peek_val();
            cp_advance(); // skip struct/union

            var tag_name: string = "";
            if cp_peek() == CTK_IDENT() { tag_name = cp_peek_val(); }

            // struct name { ... }
            if cp_peek() == CTK_IDENT() && str_eq(cp_peek_val_at(1), "{") {
                cp_pos = save;
                let sn: i32 = cp_parse_struct_or_union();
                if sn >= 0 { array_push(decls, sn); }
            }
            // struct { ... } (anonymous)
            else if str_eq(cp_peek_val(), "{") {
                cp_pos = save;
                let sn2: i32 = cp_parse_struct_or_union();
                if sn2 >= 0 { array_push(decls, sn2); }
            }
            // struct name *func(...) or struct name var;
            else {
                cp_pos = save;
                let decl: i32 = cp_parse_declaration();
                if decl >= 0 { array_push(decls, decl); }
            }
        }
        // enum at top level
        else if str_eq(cp_peek_val(), "enum") {
            let save2: i32 = cp_pos;
            cp_advance();
            // enum name { ... } or enum { ... }
            if str_eq(cp_peek_val(), "{") || (cp_peek() == CTK_IDENT() && str_eq(cp_peek_val_at(1), "{")) {
                cp_pos = save2;
                let en: i32 = cp_parse_enum();
                if en >= 0 { array_push(decls, en); }
            } else {
                // enum used as type in declaration
                cp_pos = save2;
                let decl2: i32 = cp_parse_declaration();
                if decl2 >= 0 { array_push(decls, decl2); }
            }
        }
        // Semicolons (empty statements)
        else if str_eq(cp_peek_val(), ";") {
            cp_advance();
        }
        // Regular declaration (function or variable)
        else if cp_is_type_start() {
            let decl3: i32 = cp_parse_declaration();
            if decl3 >= 0 { array_push(decls, decl3); }
        }
        // Unknown token — skip
        else {
            cp_advance();
        }

        // Safety: if no progress was made, force advance to prevent infinite loop
        if cp_pos == loop_save { cp_advance(); }
    }

    let dstart: i32 = cn_flush(decls);
    let dcount: i32 = array_len(decls);
    return cn_new(CNK_PROGRAM(), "", "", dstart, dcount, 0);
}

// ── Analysis Functions ──────────────────────────────

fn cp_count_by_kind(kind: i32, prog: i32) -> i32 {
    var count: i32 = 0;
    let start: i32 = cnd1(prog);
    let total: i32 = cnd2(prog);
    var i: i32 = 0;
    while i < total {
        if cnk(cn_child(start, i)) == kind { count = count + 1; }
        i = i + 1;
    }
    return count;
}

fn cp_count_functions(prog: i32) -> i32 {
    return cp_count_by_kind(CNK_FUNC_DEF(), prog);
}

fn cp_count_func_decls(prog: i32) -> i32 {
    return cp_count_by_kind(CNK_FUNC_DECL(), prog);
}

fn cp_count_structs(prog: i32) -> i32 {
    return cp_count_by_kind(CNK_STRUCT_DEF(), prog);
}

fn cp_count_enums(prog: i32) -> i32 {
    return cp_count_by_kind(CNK_ENUM_DEF(), prog);
}

fn cp_count_typedefs(prog: i32) -> i32 {
    return cp_count_by_kind(CNK_TYPEDEF(), prog);
}

fn cp_count_globals(prog: i32) -> i32 {
    return cp_count_by_kind(CNK_GLOBAL_VAR(), prog);
}

fn cp_count_preprocs(prog: i32) -> i32 {
    return cp_count_by_kind(CNK_PREPROC(), prog);
}

// Print function signature
fn cp_print_func(node: i32) -> i32 {
    let ret: string = cnt(node);
    let name: string = cnn(node);
    let pstart: i32 = cnd1(node);
    let pcount: i32 = cnd2(node);

    print(ret);
    print(" ");
    print(name);
    print("(");
    var i: i32 = 0;
    while i < pcount {
        if i > 0 { print(", "); }
        let p: i32 = cn_child(pstart, i);
        print(cnt(p));
        if len(cnn(p)) > 0 {
            print(" ");
            print(cnn(p));
        }
        i = i + 1;
    }
    println(")");
    return 0;
}

// Print struct definition
fn cp_print_struct(node: i32) -> i32 {
    let name: string = cnn(node);
    let kw: string = cnt(node);
    let fstart: i32 = cnd1(node);
    let fcount: i32 = cnd2(node);

    print(kw);
    print(" ");
    print(name);
    println(" {");
    var i: i32 = 0;
    while i < fcount {
        let f: i32 = cn_child(fstart, i);
        print("    ");
        print(cnt(f));
        if len(cnn(f)) > 0 {
            print(" ");
            print(cnn(f));
        }
        println(";");
        i = i + 1;
    }
    println("}");
    return 0;
}

// Full analysis report
fn cp_report(prog: i32) -> i32 {
    let total: i32 = cnd2(prog);
    println("=== C Parser Analysis ===");
    print("  Total declarations: ");
    println(int_to_str(total));
    print("  Functions: ");
    println(int_to_str(cp_count_functions(prog)));
    print("  Function declarations: ");
    println(int_to_str(cp_count_func_decls(prog)));
    print("  Structs: ");
    println(int_to_str(cp_count_structs(prog)));
    print("  Enums: ");
    println(int_to_str(cp_count_enums(prog)));
    print("  Typedefs: ");
    println(int_to_str(cp_count_typedefs(prog)));
    print("  Global variables: ");
    println(int_to_str(cp_count_globals(prog)));
    print("  Preprocessor: ");
    println(int_to_str(cp_count_preprocs(prog)));

    // List functions
    let nfuncs: i32 = cp_count_functions(prog);
    if nfuncs > 0 {
        println("");
        println("--- Functions ---");
        let start: i32 = cnd1(prog);
        var i: i32 = 0;
        while i < total {
            let node: i32 = cn_child(start, i);
            if cnk(node) == CNK_FUNC_DEF() {
                print("  ");
                cp_print_func(node);
            }
            i = i + 1;
        }
    }

    // List structs
    let nstructs: i32 = cp_count_structs(prog);
    if nstructs > 0 {
        println("");
        println("--- Structs ---");
        let start2: i32 = cnd1(prog);
        var i2: i32 = 0;
        while i2 < total {
            let node2: i32 = cn_child(start2, i2);
            if cnk(node2) == CNK_STRUCT_DEF() {
                cp_print_struct(node2);
            }
            i2 = i2 + 1;
        }
    }

    return 0;
}

// ── Parse helper: tokenize + parse ──────────────────

fn cp_parse(src: string) -> i32 {
    c_tokenize(src);
    cp_init();
    cp_init_ast();
    return cp_parse_program();
}

fn cp_parse_file(path: string) -> i32 {
    let src: string = read_file(path);
    if len(src) == 0 {
        println("Error: cannot read file");
        return 0 - 1;
    }
    return cp_parse(src);
}

// ── C → M Translation ───────────────────────────────

// Map C type to M type
fn cp_c_type_to_m(ct: string) -> string {
    // Remove storage class prefixes
    var t: string = ct;
    if str_starts_with(t, "static ") { t = substr(t, 7, len(t) - 7); }
    if str_starts_with(t, "extern ") { t = substr(t, 7, len(t) - 7); }
    if str_starts_with(t, "inline ") { t = substr(t, 7, len(t) - 7); }

    // Pointer types → string in M (simplified mapping)
    if str_contains(t, "*") { return "string"; }

    // Remove const/volatile
    if str_starts_with(t, "const ") { t = substr(t, 6, len(t) - 6); }
    if str_starts_with(t, "volatile ") { t = substr(t, 9, len(t) - 9); }

    // Basic type mapping
    if str_eq(t, "void") { return "i32"; }
    if str_eq(t, "int") { return "i32"; }
    if str_eq(t, "char") { return "i32"; }
    if str_eq(t, "short") { return "i32"; }
    if str_eq(t, "long") { return "i32"; }
    if str_eq(t, "long long") { return "i32"; }
    if str_eq(t, "unsigned") { return "i32"; }
    if str_eq(t, "unsigned int") { return "i32"; }
    if str_eq(t, "unsigned char") { return "i32"; }
    if str_eq(t, "unsigned long") { return "i32"; }
    if str_eq(t, "signed") { return "i32"; }
    if str_eq(t, "float") { return "i32"; }
    if str_eq(t, "double") { return "i32"; }
    if str_eq(t, "size_t") { return "i32"; }
    if str_eq(t, "bool") { return "bool"; }
    if str_eq(t, "_Bool") { return "bool"; }

    // Default: treat as i32
    return "i32";
}

// Generate M function signature from C function node
fn cp_gen_m_func_sig(node: i32) -> string {
    let c_ret: string = cnt(node);
    let name: string = cnn(node);
    let pstart: i32 = cnd1(node);
    let pcount: i32 = cnd2(node);
    let m_ret: string = cp_c_type_to_m(c_ret);

    var result: string = str_concat("fn ", name);
    result = str_concat(result, "(");

    var i: i32 = 0;
    while i < pcount {
        if i > 0 { result = str_concat(result, ", "); }
        let p: i32 = cn_child(pstart, i);
        let pname: string = cnn(p);
        let ptype: string = cnt(p);

        // Skip void params and variadic
        if str_eq(ptype, "void") || str_eq(ptype, "...") {
            i = i + 1;
        }
        if !str_eq(ptype, "void") && !str_eq(ptype, "...") {
            let m_ptype: string = cp_c_type_to_m(ptype);
            var param_name: string = pname;
            if len(param_name) == 0 {
                param_name = str_concat("arg", int_to_str(i));
            }
            result = str_concat(result, str_concat(param_name, str_concat(": ", m_ptype)));
            i = i + 1;
        }
    }

    result = str_concat(result, str_concat(") -> ", m_ret));
    return result;
}

// ── Expression/Statement → M Translation ──────────

fn cp_gen_m_expr(node: i32) -> string;
fn cp_gen_m_stmts(block: i32, indent: string) -> string;

fn cp_gen_m_expr(node: i32) -> string {
    if node < 0 { return "0"; }
    let k: i32 = cnk(node);

    if k == CNK_EXPR_INT() { return cnn(node); }
    if k == CNK_EXPR_CHAR() {
        // char literal: 'x' → char_at("x", 0) or just the int value
        let cv: string = cnn(node);
        if len(cv) == 1 {
            return str_concat(int_to_str(char_at(cv, 0)), str_concat(" /* '", str_concat(cv, "' */")));
        }
        return str_concat("0 /* '", str_concat(cv, "' */"));
    }
    if k == CNK_EXPR_STR() {
        return str_concat("\"", str_concat(cnn(node), "\""));
    }
    if k == CNK_EXPR_NULL() { return "0 /* NULL */"; }
    if k == CNK_EXPR_IDENT() { return cnn(node); }

    if k == CNK_EXPR_CALL() {
        var result: string = str_concat(cnn(node), "(");
        var i: i32 = 0;
        while i < cnd2(node) {
            if i > 0 { result = str_concat(result, ", "); }
            let arg: i32 = cn_child(cnd1(node), i);
            result = str_concat(result, cp_gen_m_expr(arg));
            i = i + 1;
        }
        return str_concat(result, ")");
    }

    if k == CNK_EXPR_BINARY() {
        let left: string = cp_gen_m_expr(cnd1(node));
        let right: string = cp_gen_m_expr(cnd2(node));
        return str_concat("(", str_concat(left, str_concat(str_concat(" ", str_concat(cnn(node), " ")), str_concat(right, ")"))));
    }

    if k == CNK_EXPR_UNARY() {
        let op: string = cnn(node);
        let operand: string = cp_gen_m_expr(cnd1(node));
        if str_eq(op, "!") { return str_concat("!", operand); }
        if str_eq(op, "-") { return str_concat("(0 - ", str_concat(operand, ")")); }
        return str_concat("/* ", str_concat(op, str_concat(" */ ", operand)));
    }

    if k == CNK_EXPR_DEREF() {
        return str_concat("/* *", str_concat(cp_gen_m_expr(cnd1(node)), " */"));
    }
    if k == CNK_EXPR_ADDR() {
        return str_concat("/* &", str_concat(cp_gen_m_expr(cnd1(node)), " */"));
    }

    if k == CNK_EXPR_MEMBER() {
        let obj: string = cp_gen_m_expr(cnd1(node));
        let field: string = cnn(node);
        // In M, we don't have struct access — generate commented notation
        if cnd2(node) == 1 {
            return str_concat(obj, str_concat("_", field));  // ptr->field → ptr_field
        }
        return str_concat(obj, str_concat("_", field));  // obj.field → obj_field
    }

    if k == CNK_EXPR_INDEX() {
        let arr: string = cp_gen_m_expr(cnd1(node));
        let idx: string = cp_gen_m_expr(cnd2(node));
        return str_concat("array_get(", str_concat(arr, str_concat(", ", str_concat(idx, ")"))));
    }

    if k == CNK_EXPR_CAST() {
        // Skip cast, just translate the operand
        return cp_gen_m_expr(cnd1(node));
    }

    if k == CNK_EXPR_SIZEOF() {
        return str_concat("0 /* sizeof(", str_concat(cnn(node), ") */"));
    }

    if k == CNK_EXPR_TERNARY() {
        // cond ? then : else → M doesn't have ternary, use comment
        let cond: string = cp_gen_m_expr(cnd1(node));
        let then_e: string = cp_gen_m_expr(cnd2(node));
        let else_e: string = cp_gen_m_expr(cnd3(node));
        return str_concat("/* ", str_concat(cond, str_concat(" ? ", str_concat(then_e, str_concat(" : ", str_concat(else_e, " */"))))));
    }

    if k == CNK_EXPR_ASSIGN() {
        let lhs: string = cp_gen_m_expr(cnd1(node));
        let rhs: string = cp_gen_m_expr(cnd2(node));
        let op: string = cnn(node);
        if str_eq(op, "=") {
            return str_concat(lhs, str_concat(" = ", rhs));
        }
        // Compound assignment: a += b → a = a + b
        // Extract the operator from +=, -=, etc.
        let base_op: string = substr(op, 0, len(op) - 1);
        return str_concat(lhs, str_concat(" = ", str_concat(lhs, str_concat(str_concat(" ", str_concat(base_op, " ")), rhs))));
    }

    if k == CNK_EXPR_POSTFIX() {
        let operand: string = cp_gen_m_expr(cnd1(node));
        let op: string = cnn(node);
        if str_eq(op, "++") {
            return str_concat(operand, str_concat(" = ", str_concat(operand, " + 1")));
        }
        if str_eq(op, "--") {
            return str_concat(operand, str_concat(" = ", str_concat(operand, " - 1")));
        }
        return operand;
    }

    return str_concat("/* unknown expr kind ", str_concat(int_to_str(k), " */"));
}

fn cp_gen_m_stmt(node: i32, indent: string) -> string {
    if node < 0 { return ""; }
    let k: i32 = cnk(node);
    let nl: string = "\n";
    let indent2: string = str_concat(indent, "    ");

    if k == CNK_STMT_RETURN() {
        if cnd1(node) >= 0 {
            return str_concat(indent, str_concat("return ", str_concat(cp_gen_m_expr(cnd1(node)), str_concat(";", nl))));
        }
        return str_concat(indent, str_concat("return 0;", nl));
    }

    if k == CNK_STMT_EXPR() {
        if cnd1(node) < 0 { return ""; }
        let expr_k: i32 = cnk(cnd1(node));
        if expr_k == CNK_EXPR_ASSIGN() {
            return str_concat(indent, str_concat(cp_gen_m_expr(cnd1(node)), str_concat(";", nl)));
        }
        // Function call as statement
        return str_concat(indent, str_concat(cp_gen_m_expr(cnd1(node)), str_concat(";", nl)));
    }

    if k == CNK_STMT_VAR() {
        let vname: string = cnn(node);
        let vtype: string = cp_c_type_to_m(cnt(node));
        if cnd1(node) >= 0 {
            return str_concat(indent, str_concat("var ", str_concat(vname, str_concat(": ", str_concat(vtype, str_concat(" = ", str_concat(cp_gen_m_expr(cnd1(node)), str_concat(";", nl))))))));
        }
        // Default initialization
        if str_eq(vtype, "string") {
            return str_concat(indent, str_concat("var ", str_concat(vname, str_concat(": string = \"\";", nl))));
        }
        if str_eq(vtype, "bool") {
            return str_concat(indent, str_concat("var ", str_concat(vname, str_concat(": bool = false;", nl))));
        }
        return str_concat(indent, str_concat("var ", str_concat(vname, str_concat(": i32 = 0;", nl))));
    }

    if k == CNK_STMT_IF() {
        var result: string = str_concat(indent, str_concat("if ", str_concat(cp_gen_m_expr(cnd1(node)), str_concat(" {", nl))));
        // then body
        if cnk(cnd2(node)) == CNK_STMT_BLOCK() {
            result = str_concat(result, cp_gen_m_stmts(cnd2(node), indent2));
        } else {
            result = str_concat(result, cp_gen_m_stmt(cnd2(node), indent2));
        }
        // else
        if cnd3(node) >= 0 {
            if cnk(cnd3(node)) == CNK_STMT_IF() {
                // else if → chain
                result = str_concat(result, str_concat(indent, str_concat("} else ", substr(cp_gen_m_stmt(cnd3(node), indent), len(indent), len(cp_gen_m_stmt(cnd3(node), indent)) - len(indent)))));
                return result;
            }
            result = str_concat(result, str_concat(indent, str_concat("} else {", nl)));
            if cnk(cnd3(node)) == CNK_STMT_BLOCK() {
                result = str_concat(result, cp_gen_m_stmts(cnd3(node), indent2));
            } else {
                result = str_concat(result, cp_gen_m_stmt(cnd3(node), indent2));
            }
        }
        result = str_concat(result, str_concat(indent, str_concat("}", nl)));
        return result;
    }

    if k == CNK_STMT_WHILE() {
        var result: string = str_concat(indent, str_concat("while ", str_concat(cp_gen_m_expr(cnd1(node)), str_concat(" {", nl))));
        if cnk(cnd2(node)) == CNK_STMT_BLOCK() {
            result = str_concat(result, cp_gen_m_stmts(cnd2(node), indent2));
        } else {
            result = str_concat(result, cp_gen_m_stmt(cnd2(node), indent2));
        }
        result = str_concat(result, str_concat(indent, str_concat("}", nl)));
        return result;
    }

    if k == CNK_STMT_FOR() {
        // for has 4 children: init, cond, step, body
        var init_s: string = "";
        var cond_s: string = "true";
        var step_s: string = "";
        let fc_start: i32 = cnd1(node);

        if fc_start >= 0 {
            let init_n: i32 = cn_child(fc_start, 0);
            let cond_n: i32 = cn_child(fc_start, 1);
            let step_n: i32 = cn_child(fc_start, 2);
            let body_n: i32 = cn_child(fc_start, 3);

            // Init as separate statement before while
            if init_n >= 0 {
                if cnk(init_n) == CNK_STMT_VAR() {
                    init_s = cp_gen_m_stmt(init_n, indent);
                } else {
                    init_s = str_concat(indent, str_concat(cp_gen_m_expr(init_n), str_concat(";", nl)));
                }
            }

            if cond_n >= 0 { cond_s = cp_gen_m_expr(cond_n); }
            if step_n >= 0 { step_s = cp_gen_m_expr(step_n); }

            // for → init; while (cond) { body; step; }
            var result: string = init_s;
            result = str_concat(result, str_concat(indent, str_concat("while ", str_concat(cond_s, str_concat(" {", nl)))));
            if cnk(body_n) == CNK_STMT_BLOCK() {
                result = str_concat(result, cp_gen_m_stmts(body_n, indent2));
            } else {
                result = str_concat(result, cp_gen_m_stmt(body_n, indent2));
            }
            if len(step_s) > 0 {
                result = str_concat(result, str_concat(indent2, str_concat(step_s, str_concat(";", nl))));
            }
            result = str_concat(result, str_concat(indent, str_concat("}", nl)));
            return result;
        }
        return str_concat(indent, str_concat("// for loop (unparsed)", nl));
    }

    if k == CNK_STMT_BREAK() {
        return str_concat(indent, str_concat("// break;", nl));
    }
    if k == CNK_STMT_CONTINUE() {
        return str_concat(indent, str_concat("// continue;", nl));
    }

    if k == CNK_STMT_SWITCH() {
        var result: string = str_concat(indent, str_concat("// switch (", str_concat(cp_gen_m_expr(cnd1(node)), str_concat(") {", nl))));
        var ci: i32 = 0;
        while ci < cnd3(node) {
            let case_n: i32 = cn_child(cnd2(node), ci);
            if cnd1(case_n) >= 0 {
                result = str_concat(result, str_concat(indent, str_concat("// case ", str_concat(cp_gen_m_expr(cnd1(case_n)), str_concat(":", nl)))));
            } else {
                result = str_concat(result, str_concat(indent, str_concat("// default:", nl)));
            }
            // Case body
            var si: i32 = 0;
            while si < cnd3(case_n) {
                let s: i32 = cn_child(cnd2(case_n), si);
                result = str_concat(result, cp_gen_m_stmt(s, indent2));
                si = si + 1;
            }
            ci = ci + 1;
        }
        result = str_concat(result, str_concat(indent, str_concat("// }", nl)));
        return result;
    }

    if k == CNK_STMT_BLOCK() {
        return cp_gen_m_stmts(node, indent);
    }

    return str_concat(indent, str_concat("// unknown stmt kind ", str_concat(int_to_str(k), nl)));
}

// Generate M statements from a block node
fn cp_gen_m_stmts(block: i32, indent: string) -> string {
    var result: string = "";
    let count: i32 = cnd2(block);
    let start: i32 = cnd1(block);
    var i: i32 = 0;
    while i < count {
        let stmt: i32 = cn_child(start, i);
        result = str_concat(result, cp_gen_m_stmt(stmt, indent));
        i = i + 1;
    }
    return result;
}

// Generate M function with translated body
fn cp_gen_m_func(node: i32) -> string {
    let sig: string = cp_gen_m_func_sig(node);
    let nl: string = "\n";
    let body_node: i32 = cnd3(node);

    var body: string = "";
    if body_node > 0 && cnk(body_node) == CNK_STMT_BLOCK() {
        body = cp_gen_m_stmts(body_node, "    ");
    } else {
        // Fallback: stub
        let m_ret: string = cp_c_type_to_m(cnt(node));
        if str_eq(m_ret, "string") {
            body = str_concat("    return \"\";", nl);
        } else if str_eq(m_ret, "bool") {
            body = str_concat("    return false;", nl);
        } else {
            body = str_concat("    return 0;", nl);
        }
    }

    return str_concat(sig, str_concat(str_concat(" {", nl), str_concat(body, str_concat("}", nl))));
}

// Generate M translation of entire C program
fn cp_gen_m_translation(prog: i32) -> string {
    let total: i32 = cnd2(prog);
    let start: i32 = cnd1(prog);
    let nl: string = "\n";
    var result: string = str_concat("// Auto-translated from C by Machine", nl);
    result = str_concat(result, str_concat("// Phase 2: M reads C, writes M", str_concat(nl, nl)));

    // First pass: struct comments
    var i: i32 = 0;
    while i < total {
        let node: i32 = cn_child(start, i);
        if cnk(node) == CNK_STRUCT_DEF() {
            let sname: string = cnn(node);
            let fstart: i32 = cnd1(node);
            let fcount: i32 = cnd2(node);
            result = str_concat(result, str_concat("// struct ", str_concat(sname, str_concat(" {", nl))));
            var j: i32 = 0;
            while j < fcount {
                let f: i32 = cn_child(fstart, j);
                result = str_concat(result, str_concat("//     ", str_concat(cnt(f), str_concat(" ", str_concat(cnn(f), str_concat(";", nl))))));
                j = j + 1;
            }
            result = str_concat(result, str_concat("// }", str_concat(nl, nl)));
        }
        i = i + 1;
    }

    // Second pass: function declarations
    i = 0;
    while i < total {
        let node2: i32 = cn_child(start, i);
        if cnk(node2) == CNK_FUNC_DECL() {
            let sig: string = cp_gen_m_func_sig(node2);
            result = str_concat(result, str_concat(sig, str_concat(";", nl)));
        }
        i = i + 1;
    }
    if cp_count_func_decls(prog) > 0 {
        result = str_concat(result, nl);
    }

    // Third pass: function definitions
    i = 0;
    while i < total {
        let node3: i32 = cn_child(start, i);
        if cnk(node3) == CNK_FUNC_DEF() {
            result = str_concat(result, str_concat(cp_gen_m_func(node3), nl));
        }
        i = i + 1;
    }

    return result;
}

// ── Print-based translation (streaming, no memory accumulation) ──

fn cp_print_m_stmt(node: i32, indent: string) -> i32;
fn cp_print_m_stmts(block: i32, indent: string) -> i32;

fn cp_print_m_stmt(node: i32, indent: string) -> i32 {
    if node < 0 { return 0; }
    let k: i32 = cnk(node);
    let indent2: string = str_concat(indent, "    ");

    if k == CNK_STMT_RETURN() {
        if cnd1(node) >= 0 {
            println(str_concat(indent, str_concat("return ", str_concat(cp_gen_m_expr(cnd1(node)), ";"))));
        } else {
            println(str_concat(indent, "return 0;"));
        }
        return 0;
    }

    if k == CNK_STMT_EXPR() {
        if cnd1(node) < 0 { return 0; }
        println(str_concat(indent, str_concat(cp_gen_m_expr(cnd1(node)), ";")));
        return 0;
    }

    if k == CNK_STMT_VAR() {
        let vname: string = cnn(node);
        let vtype: string = cp_c_type_to_m(cnt(node));
        if cnd1(node) >= 0 {
            println(str_concat(indent, str_concat("var ", str_concat(vname, str_concat(": ", str_concat(vtype, str_concat(" = ", str_concat(cp_gen_m_expr(cnd1(node)), ";"))))))));
        } else if str_eq(vtype, "string") {
            println(str_concat(indent, str_concat("var ", str_concat(vname, ": string = \"\";"))));
        } else if str_eq(vtype, "bool") {
            println(str_concat(indent, str_concat("var ", str_concat(vname, ": bool = false;"))));
        } else {
            println(str_concat(indent, str_concat("var ", str_concat(vname, ": i32 = 0;"))));
        }
        return 0;
    }

    if k == CNK_STMT_IF() {
        println(str_concat(indent, str_concat("if ", str_concat(cp_gen_m_expr(cnd1(node)), " {"))));
        if cnk(cnd2(node)) == CNK_STMT_BLOCK() {
            cp_print_m_stmts(cnd2(node), indent2);
        } else {
            cp_print_m_stmt(cnd2(node), indent2);
        }
        if cnd3(node) >= 0 {
            if cnk(cnd3(node)) == CNK_STMT_IF() {
                print(str_concat(indent, "} else "));
                cp_print_m_stmt(cnd3(node), indent);
                return 0;
            }
            println(str_concat(indent, "} else {"));
            if cnk(cnd3(node)) == CNK_STMT_BLOCK() {
                cp_print_m_stmts(cnd3(node), indent2);
            } else {
                cp_print_m_stmt(cnd3(node), indent2);
            }
        }
        println(str_concat(indent, "}"));
        return 0;
    }

    if k == CNK_STMT_WHILE() {
        println(str_concat(indent, str_concat("while ", str_concat(cp_gen_m_expr(cnd1(node)), " {"))));
        if cnk(cnd2(node)) == CNK_STMT_BLOCK() {
            cp_print_m_stmts(cnd2(node), indent2);
        } else {
            cp_print_m_stmt(cnd2(node), indent2);
        }
        println(str_concat(indent, "}"));
        return 0;
    }

    if k == CNK_STMT_FOR() {
        let fc_start: i32 = cnd1(node);
        if fc_start >= 0 {
            let init_n: i32 = cn_child(fc_start, 0);
            let cond_n: i32 = cn_child(fc_start, 1);
            let step_n: i32 = cn_child(fc_start, 2);
            let body_n: i32 = cn_child(fc_start, 3);
            if init_n >= 0 {
                if cnk(init_n) == CNK_STMT_VAR() {
                    cp_print_m_stmt(init_n, indent);
                } else {
                    println(str_concat(indent, str_concat(cp_gen_m_expr(init_n), ";")));
                }
            }
            var cond_s: string = "true";
            if cond_n >= 0 { cond_s = cp_gen_m_expr(cond_n); }
            println(str_concat(indent, str_concat("while ", str_concat(cond_s, " {"))));
            if cnk(body_n) == CNK_STMT_BLOCK() {
                cp_print_m_stmts(body_n, indent2);
            } else {
                cp_print_m_stmt(body_n, indent2);
            }
            if step_n >= 0 {
                println(str_concat(indent2, str_concat(cp_gen_m_expr(step_n), ";")));
            }
            println(str_concat(indent, "}"));
            return 0;
        }
        println(str_concat(indent, "// for loop (unparsed)"));
        return 0;
    }

    if k == CNK_STMT_BREAK() {
        println(str_concat(indent, "// break;"));
        return 0;
    }
    if k == CNK_STMT_CONTINUE() {
        println(str_concat(indent, "// continue;"));
        return 0;
    }

    if k == CNK_STMT_SWITCH() {
        println(str_concat(indent, str_concat("// switch (", str_concat(cp_gen_m_expr(cnd1(node)), ") {"))));
        var ci: i32 = 0;
        while ci < cnd3(node) {
            let case_n: i32 = cn_child(cnd2(node), ci);
            if cnd1(case_n) >= 0 {
                println(str_concat(indent, str_concat("// case ", str_concat(cp_gen_m_expr(cnd1(case_n)), ":"))));
            } else {
                println(str_concat(indent, "// default:"));
            }
            var si: i32 = 0;
            while si < cnd3(case_n) {
                let s: i32 = cn_child(cnd2(case_n), si);
                cp_print_m_stmt(s, indent2);
                si = si + 1;
            }
            ci = ci + 1;
        }
        println(str_concat(indent, "// }"));
        return 0;
    }

    if k == CNK_STMT_BLOCK() {
        cp_print_m_stmts(node, indent);
        return 0;
    }

    println(str_concat(indent, str_concat("// unknown stmt kind ", int_to_str(k))));
    return 0;
}

fn cp_print_m_stmts(block: i32, indent: string) -> i32 {
    let count: i32 = cnd2(block);
    let start: i32 = cnd1(block);
    var i: i32 = 0;
    while i < count {
        cp_print_m_stmt(cn_child(start, i), indent);
        i = i + 1;
    }
    return 0;
}

fn cp_print_m_func(node: i32) -> i32 {
    let sig: string = cp_gen_m_func_sig(node);
    let body_node: i32 = cnd3(node);
    println(str_concat(sig, " {"));
    if body_node > 0 && cnk(body_node) == CNK_STMT_BLOCK() {
        cp_print_m_stmts(body_node, "    ");
    } else {
        let m_ret: string = cp_c_type_to_m(cnt(node));
        if str_eq(m_ret, "string") {
            println("    return \"\";");
        } else if str_eq(m_ret, "bool") {
            println("    return false;");
        } else {
            println("    return 0;");
        }
    }
    println("}");
    return 0;
}

// Streaming translation — prints directly, no huge string accumulation
fn cp_print_m_translation(prog: i32) -> i32 {
    let total: i32 = cnd2(prog);
    let start: i32 = cnd1(prog);
    println("// Auto-translated from C by Machine");
    println("// Phase 2: M reads C, writes M");
    println("");

    // First pass: struct comments
    var i: i32 = 0;
    while i < total {
        let node: i32 = cn_child(start, i);
        if cnk(node) == CNK_STRUCT_DEF() {
            let sname: string = cnn(node);
            let fstart: i32 = cnd1(node);
            let fcount: i32 = cnd2(node);
            println(str_concat("// struct ", str_concat(sname, " {")));
            var j: i32 = 0;
            while j < fcount {
                let f: i32 = cn_child(fstart, j);
                println(str_concat("//     ", str_concat(cnt(f), str_concat(" ", str_concat(cnn(f), ";")))));
                j = j + 1;
            }
            println("// }");
            println("");
        }
        i = i + 1;
    }

    // Second pass: function declarations
    i = 0;
    while i < total {
        let node2: i32 = cn_child(start, i);
        if cnk(node2) == CNK_FUNC_DECL() {
            println(str_concat(cp_gen_m_func_sig(node2), ";"));
        }
        i = i + 1;
    }
    if cp_count_func_decls(prog) > 0 {
        println("");
    }

    // Third pass: function definitions (fully streaming)
    i = 0;
    while i < total {
        let node3: i32 = cn_child(start, i);
        if cnk(node3) == CNK_FUNC_DEF() {
            cp_print_m_func(node3);
            println("");
        }
        i = i + 1;
    }

    return 0;
}

// ── Tests ───────────────────────────────────────────

fn test_c_parser() -> i32 {
    var tests_run: i32 = 0;
    var tests_passed: i32 = 0;
    println("=== C Parser Tests ===");

    // Test 1: empty input
    tests_run = tests_run + 1;
    let t1: i32 = cp_parse("");
    if cnd2(t1) == 0 {
        tests_passed = tests_passed + 1;
        println("  OK  empty input");
    } else { println("  FAIL empty input"); }

    // Test 2: simple function
    tests_run = tests_run + 1;
    let t2: i32 = cp_parse("int main() { return 0; }");
    if cp_count_functions(t2) == 1 && str_eq(cnn(cn_child(cnd1(t2), 0)), "main") {
        tests_passed = tests_passed + 1;
        println("  OK  simple function");
    } else {
        print("  FAIL simple function (funcs=");
        print(int_to_str(cp_count_functions(t2)));
        println(")");
    }

    // Test 3: function with params
    tests_run = tests_run + 1;
    let t3: i32 = cp_parse("static char *read_file(const char *path) { return 0; }");
    if cp_count_functions(t3) == 1 {
        let f3: i32 = cn_child(cnd1(t3), 0);
        if str_eq(cnn(f3), "read_file") && cnd2(f3) == 1 {
            tests_passed = tests_passed + 1;
            println("  OK  function with params");
        } else {
            print("  FAIL function with params (name=");
            print(cnn(f3));
            print(", params=");
            print(int_to_str(cnd2(f3)));
            println(")");
        }
    } else {
        print("  FAIL function with params (funcs=");
        print(int_to_str(cp_count_functions(t3)));
        println(")");
    }

    // Test 4: struct definition
    tests_run = tests_run + 1;
    let t4: i32 = cp_parse("struct Point { int x; int y; };");
    if cp_count_structs(t4) == 1 {
        let s4: i32 = cn_child(cnd1(t4), 0);
        if str_eq(cnn(s4), "Point") && cnd2(s4) == 2 {
            tests_passed = tests_passed + 1;
            println("  OK  struct definition");
        } else {
            print("  FAIL struct definition (name=");
            print(cnn(s4));
            print(", fields=");
            print(int_to_str(cnd2(s4)));
            println(")");
        }
    } else {
        print("  FAIL struct definition (structs=");
        print(int_to_str(cp_count_structs(t4)));
        println(")");
    }

    // Test 5: typedef struct
    tests_run = tests_run + 1;
    let t5: i32 = cp_parse("typedef struct { int kind; const char *name; } TypeNode;");
    if cp_count_typedefs(t5) == 1 {
        let td5: i32 = cn_child(cnd1(t5), 0);
        if str_eq(cnn(td5), "TypeNode") {
            tests_passed = tests_passed + 1;
            println("  OK  typedef struct");
        } else {
            print("  FAIL typedef struct (name=");
            print(cnn(td5));
            println(")");
        }
    } else {
        print("  FAIL typedef struct (typedefs=");
        print(int_to_str(cp_count_typedefs(t5)));
        println(")");
    }

    // Test 6: typedef enum
    tests_run = tests_run + 1;
    let t6: i32 = cp_parse("typedef enum { TYPE_INT, TYPE_FLOAT, TYPE_VOID } TypeKind;");
    if cp_count_typedefs(t6) == 1 {
        let td6: i32 = cn_child(cnd1(t6), 0);
        if str_eq(cnn(td6), "TypeKind") {
            tests_passed = tests_passed + 1;
            println("  OK  typedef enum");
        } else {
            print("  FAIL typedef enum (name=");
            print(cnn(td6));
            println(")");
        }
    } else {
        print("  FAIL typedef enum (typedefs=");
        print(int_to_str(cp_count_typedefs(t6)));
        println(")");
    }

    // Test 7: global variable
    tests_run = tests_run + 1;
    let t7: i32 = cp_parse("static int count = 0;");
    if cp_count_globals(t7) == 1 {
        let g7: i32 = cn_child(cnd1(t7), 0);
        if str_eq(cnn(g7), "count") {
            tests_passed = tests_passed + 1;
            println("  OK  global variable");
        } else {
            print("  FAIL global variable (name=");
            print(cnn(g7));
            println(")");
        }
    } else {
        print("  FAIL global variable (globals=");
        print(int_to_str(cp_count_globals(t7)));
        println(")");
    }

    // Test 8: multiple functions
    tests_run = tests_run + 1;
    let t8: i32 = cp_parse("int add(int a, int b) { return a + b; } int sub(int a, int b) { return a - b; } int main() { return 0; }");
    if cp_count_functions(t8) == 3 {
        tests_passed = tests_passed + 1;
        println("  OK  multiple functions");
    } else {
        print("  FAIL multiple functions (funcs=");
        print(int_to_str(cp_count_functions(t8)));
        println(")");
    }

    // Test 9: function declaration (no body)
    tests_run = tests_run + 1;
    let t9: i32 = cp_parse("int printf(const char *fmt, ...);");
    if cp_count_func_decls(t9) == 1 {
        let fd9: i32 = cn_child(cnd1(t9), 0);
        if str_eq(cnn(fd9), "printf") && cnd2(fd9) == 2 {
            tests_passed = tests_passed + 1;
            println("  OK  function declaration");
        } else {
            print("  FAIL function declaration (name=");
            print(cnn(fd9));
            print(", params=");
            print(int_to_str(cnd2(fd9)));
            println(")");
        }
    } else {
        print("  FAIL function declaration (decls=");
        print(int_to_str(cp_count_func_decls(t9)));
        println(")");
    }

    // Test 10: preprocessor directives
    tests_run = tests_run + 1;
    let pp_src: string = "#include <stdio.h>";
    let t10: i32 = cp_parse(pp_src);
    if cp_count_preprocs(t10) == 1 {
        tests_passed = tests_passed + 1;
        println("  OK  preprocessor");
    } else {
        print("  FAIL preprocessor (preprocs=");
        print(int_to_str(cp_count_preprocs(t10)));
        println(")");
    }

    // Test 11: parse mc.c (real file)
    tests_run = tests_run + 1;
    let t11: i32 = cp_parse_file("m/bootstrap/mc.c");
    if t11 >= 0 {
        let mc_funcs: i32 = cp_count_functions(t11);
        if mc_funcs >= 3 {
            tests_passed = tests_passed + 1;
            print("  OK  mc.c (");
            print(int_to_str(mc_funcs));
            println(" functions)");
        } else {
            print("  FAIL mc.c (funcs=");
            print(int_to_str(mc_funcs));
            println(")");
        }
    } else { println("  FAIL mc.c (cannot read)"); }

    // Test 12: parse lexer.c
    tests_run = tests_run + 1;
    let t12: i32 = cp_parse_file("m/bootstrap/lexer.c");
    if t12 >= 0 {
        let lex_funcs: i32 = cp_count_functions(t12);
        if lex_funcs >= 5 {
            tests_passed = tests_passed + 1;
            print("  OK  lexer.c (");
            print(int_to_str(lex_funcs));
            println(" functions)");
        } else {
            print("  FAIL lexer.c (funcs=");
            print(int_to_str(lex_funcs));
            println(")");
        }
    } else { println("  FAIL lexer.c (cannot read)"); }

    // Test 13: parse parser.c
    tests_run = tests_run + 1;
    let t13: i32 = cp_parse_file("m/bootstrap/parser.c");
    if t13 >= 0 {
        let par_funcs: i32 = cp_count_functions(t13);
        let par_structs: i32 = cp_count_structs(t13);
        if par_funcs >= 10 {
            tests_passed = tests_passed + 1;
            print("  OK  parser.c (");
            print(int_to_str(par_funcs));
            print(" functions, ");
            print(int_to_str(par_structs));
            println(" structs)");
        } else {
            print("  FAIL parser.c (funcs=");
            print(int_to_str(par_funcs));
            println(")");
        }
    } else { println("  FAIL parser.c (cannot read)"); }

    // Test 14: parse ast.h (typedefs, enums, structs)
    tests_run = tests_run + 1;
    let t14: i32 = cp_parse_file("m/bootstrap/ast.h");
    if t14 >= 0 {
        let ast_typedefs: i32 = cp_count_typedefs(t14);
        let ast_structs: i32 = cp_count_structs(t14);
        if ast_typedefs >= 3 {
            tests_passed = tests_passed + 1;
            print("  OK  ast.h (");
            print(int_to_str(ast_typedefs));
            print(" typedefs, ");
            print(int_to_str(ast_structs));
            println(" structs)");
        } else {
            print("  FAIL ast.h (typedefs=");
            print(int_to_str(ast_typedefs));
            println(")");
        }
    } else { println("  FAIL ast.h (cannot read)"); }

    // Test 15: parse codegen.c (largest bootstrap file)
    tests_run = tests_run + 1;
    let t15: i32 = cp_parse_file("m/bootstrap/codegen.c");
    if t15 >= 0 {
        let cg_funcs: i32 = cp_count_functions(t15);
        let cg_globals: i32 = cp_count_globals(t15);
        if cg_funcs >= 10 {
            tests_passed = tests_passed + 1;
            print("  OK  codegen.c (");
            print(int_to_str(cg_funcs));
            print(" functions, ");
            print(int_to_str(cg_globals));
            println(" globals)");
        } else {
            print("  FAIL codegen.c (funcs=");
            print(int_to_str(cg_funcs));
            println(")");
        }
    } else { println("  FAIL codegen.c (cannot read)"); }

    // Test 16: parse vm.c
    tests_run = tests_run + 1;
    let t16: i32 = cp_parse_file("m/bootstrap/vm.c");
    if t16 >= 0 {
        let vm_funcs: i32 = cp_count_functions(t16);
        if vm_funcs >= 3 {
            tests_passed = tests_passed + 1;
            print("  OK  vm.c (");
            print(int_to_str(vm_funcs));
            println(" functions)");
        } else {
            print("  FAIL vm.c (funcs=");
            print(int_to_str(vm_funcs));
            println(")");
        }
    } else { println("  FAIL vm.c (cannot read)"); }

    println("");
    print(int_to_str(tests_passed));
    print("/");
    print(int_to_str(tests_run));
    println(" tests passed");

    // Test 17: C type to M type mapping
    tests_run = tests_run + 1;
    if str_eq(cp_c_type_to_m("int"), "i32") &&
       str_eq(cp_c_type_to_m("const char *"), "string") &&
       str_eq(cp_c_type_to_m("void"), "i32") &&
       str_eq(cp_c_type_to_m("static int"), "i32") &&
       str_eq(cp_c_type_to_m("char **"), "string") {
        tests_passed = tests_passed + 1;
        println("  OK  type mapping");
    } else { println("  FAIL type mapping"); }

    // Test 18: function signature translation
    tests_run = tests_run + 1;
    let t18: i32 = cp_parse("int add(int a, int b) { return a + b; }");
    let f18: i32 = cn_child(cnd1(t18), 0);
    let sig18: string = cp_gen_m_func_sig(f18);
    if str_eq(sig18, "fn add(a: i32, b: i32) -> i32") {
        tests_passed = tests_passed + 1;
        println("  OK  function signature translation");
    } else {
        print("  FAIL function signature translation: ");
        println(sig18);
    }

    // Test 19: full program translation
    tests_run = tests_run + 1;
    let t19: i32 = cp_parse("int main() { return 0; }");
    let m19: string = cp_gen_m_translation(t19);
    if str_contains(m19, "fn main() -> i32") && str_contains(m19, "return 0;") {
        tests_passed = tests_passed + 1;
        println("  OK  program translation");
    } else {
        println("  FAIL program translation");
    }

    // Test 20: real file translation (mc.c)
    tests_run = tests_run + 1;
    let t20: i32 = cp_parse_file("m/bootstrap/mc.c");
    if t20 >= 0 {
        let m20: string = cp_gen_m_translation(t20);
        if str_contains(m20, "fn read_file(") && str_contains(m20, "fn main(") {
            tests_passed = tests_passed + 1;
            println("  OK  mc.c translation");
        } else {
            println("  FAIL mc.c translation (missing functions)");
        }
    } else { println("  FAIL mc.c translation (cannot read)"); }

    // Test 21: function body parsing — return statement
    tests_run = tests_run + 1;
    let t21: i32 = cp_parse("int foo() { return 42; }");
    let f21: i32 = cn_child(cnd1(t21), 0);
    let body21: i32 = cnd3(f21);  // body is in d3 now
    if cnk(body21) == CNK_STMT_BLOCK() && cnd2(body21) >= 1 {
        let stmt21: i32 = cn_child(cnd1(body21), 0);  // first statement
        if cnk(stmt21) == CNK_STMT_RETURN() && cnd1(stmt21) >= 0 {
            let ret_expr: i32 = cnd1(stmt21);
            if cnk(ret_expr) == CNK_EXPR_INT() && str_eq(cnn(ret_expr), "42") {
                tests_passed = tests_passed + 1;
                println("  OK  body: return literal");
            } else {
                print("  FAIL body: return literal (expr kind=");
                print(int_to_str(cnk(ret_expr)));
                println(")");
            }
        } else {
            print("  FAIL body: return (stmt kind=");
            print(int_to_str(cnk(stmt21)));
            println(")");
        }
    } else {
        print("  FAIL body: return (body kind=");
        print(int_to_str(cnk(body21)));
        print(", stmts=");
        print(int_to_str(cnd2(body21)));
        println(")");
    }

    // Test 22: function body — variable declaration + assignment
    tests_run = tests_run + 1;
    let t22: i32 = cp_parse("int bar() { int x = 5; return x; }");
    let f22: i32 = cn_child(cnd1(t22), 0);
    let body22: i32 = cnd3(f22);
    if cnk(body22) == CNK_STMT_BLOCK() && cnd2(body22) >= 2 {
        let decl22: i32 = cn_child(cnd1(body22), 0);
        let ret22: i32 = cn_child(cnd1(body22), 1);
        if cnk(decl22) == CNK_STMT_VAR() && str_eq(cnn(decl22), "x") &&
           cnk(ret22) == CNK_STMT_RETURN() {
            tests_passed = tests_passed + 1;
            println("  OK  body: var decl + return");
        } else {
            print("  FAIL body: var decl + return (decl=");
            print(int_to_str(cnk(decl22)));
            print(", ret=");
            print(int_to_str(cnk(ret22)));
            println(")");
        }
    } else {
        print("  FAIL body: var decl (stmts=");
        print(int_to_str(cnd2(body22)));
        println(")");
    }

    // Test 23: function body — if/else
    tests_run = tests_run + 1;
    let t23: i32 = cp_parse("int abs(int n) { if (n < 0) { return -n; } else { return n; } }");
    let f23: i32 = cn_child(cnd1(t23), 0);
    let body23: i32 = cnd3(f23);
    if cnk(body23) == CNK_STMT_BLOCK() && cnd2(body23) >= 1 {
        let if23: i32 = cn_child(cnd1(body23), 0);
        if cnk(if23) == CNK_STMT_IF() && cnd3(if23) >= 0 {
            tests_passed = tests_passed + 1;
            println("  OK  body: if/else");
        } else {
            print("  FAIL body: if/else (kind=");
            print(int_to_str(cnk(if23)));
            print(", else=");
            print(int_to_str(cnd3(if23)));
            println(")");
        }
    } else {
        println("  FAIL body: if/else (no body)");
    }

    // Test 24: function body — while loop
    tests_run = tests_run + 1;
    let t24: i32 = cp_parse("void loop() { while (x > 0) { x = x - 1; } }");
    let f24: i32 = cn_child(cnd1(t24), 0);
    let body24: i32 = cnd3(f24);
    if cnk(body24) == CNK_STMT_BLOCK() && cnd2(body24) >= 1 {
        let wh24: i32 = cn_child(cnd1(body24), 0);
        if cnk(wh24) == CNK_STMT_WHILE() {
            tests_passed = tests_passed + 1;
            println("  OK  body: while loop");
        } else {
            print("  FAIL body: while loop (kind=");
            print(int_to_str(cnk(wh24)));
            println(")");
        }
    } else {
        println("  FAIL body: while loop (no body)");
    }

    // Test 25: function body — for loop
    tests_run = tests_run + 1;
    let t25: i32 = cp_parse("int sum(int n) { int s = 0; for (int i = 0; i < n; i++) { s = s + i; } return s; }");
    let f25: i32 = cn_child(cnd1(t25), 0);
    let body25: i32 = cnd3(f25);
    if cnk(body25) == CNK_STMT_BLOCK() && cnd2(body25) >= 3 {
        let for25: i32 = cn_child(cnd1(body25), 1);  // second statement is the for
        if cnk(for25) == CNK_STMT_FOR() {
            tests_passed = tests_passed + 1;
            println("  OK  body: for loop");
        } else {
            print("  FAIL body: for loop (kind=");
            print(int_to_str(cnk(for25)));
            println(")");
        }
    } else {
        print("  FAIL body: for loop (stmts=");
        print(int_to_str(cnd2(body25)));
        println(")");
    }

    // Test 26: function body — function call expression
    tests_run = tests_run + 1;
    let t26: i32 = cp_parse("void test() { printf(\"hello\"); }");
    let f26: i32 = cn_child(cnd1(t26), 0);
    let body26: i32 = cnd3(f26);
    if cnk(body26) == CNK_STMT_BLOCK() && cnd2(body26) >= 1 {
        let expr26: i32 = cn_child(cnd1(body26), 0);
        if cnk(expr26) == CNK_STMT_EXPR() {
            let call26: i32 = cnd1(expr26);
            if cnk(call26) == CNK_EXPR_CALL() && str_eq(cnn(call26), "printf") {
                tests_passed = tests_passed + 1;
                println("  OK  body: function call");
            } else {
                print("  FAIL body: function call (");
                print(int_to_str(cnk(call26)));
                println(")");
            }
        } else {
            print("  FAIL body: function call (stmt=");
            print(int_to_str(cnk(expr26)));
            println(")");
        }
    } else {
        println("  FAIL body: function call (no body)");
    }

    // Test 27: expression parsing — binary + member access
    tests_run = tests_run + 1;
    let t27: i32 = cp_parse("int f() { return a->x + b.y; }");
    let f27: i32 = cn_child(cnd1(t27), 0);
    let body27: i32 = cnd3(f27);
    if cnk(body27) == CNK_STMT_BLOCK() && cnd2(body27) >= 1 {
        let ret27: i32 = cn_child(cnd1(body27), 0);
        let rexpr27: i32 = cnd1(ret27);
        if cnk(rexpr27) == CNK_EXPR_BINARY() && str_eq(cnn(rexpr27), "+") {
            tests_passed = tests_passed + 1;
            println("  OK  body: binary + member access");
        } else {
            print("  FAIL body: binary (kind=");
            print(int_to_str(cnk(rexpr27)));
            println(")");
        }
    } else {
        println("  FAIL body: binary (no body)");
    }

    // Test 28: real file body parsing — mc.c functions have bodies
    tests_run = tests_run + 1;
    let t28: i32 = cp_parse_file("m/bootstrap/mc.c");
    if t28 >= 0 {
        let mc_f: i32 = cn_child(cnd1(t28), 0);
        // Find first FUNC_DEF
        var found_body: bool = false;
        var bi: i32 = 0;
        while bi < cnd2(t28) && !found_body {
            let nd: i32 = cn_child(cnd1(t28), bi);
            if cnk(nd) == CNK_FUNC_DEF() {
                let bd: i32 = cnd3(nd);
                if cnk(bd) == CNK_STMT_BLOCK() && cnd2(bd) > 0 {
                    found_body = true;
                }
            }
            bi = bi + 1;
        }
        if found_body {
            tests_passed = tests_passed + 1;
            println("  OK  body: mc.c functions parsed");
        } else {
            println("  FAIL body: mc.c no function bodies found");
        }
    } else {
        println("  FAIL body: mc.c cannot read");
    }

    println("");
    print(int_to_str(tests_passed));
    print("/");
    print(int_to_str(tests_run));
    println(" tests passed");

    if tests_passed == tests_run {
        println("");
        println("M reads C, writes M. Cross-language translation works.");
    }

    return tests_passed == tests_run;
}

// ── Driver ──────────────────────────────────────────

fn main() -> i32 {
    if argc() >= 2 && str_eq(argv(0), "--translate") {
        // Translation mode: --translate <file.c>
        let path: string = argv(1);
        let prog: i32 = cp_parse_file(path);
        if prog >= 0 {
            cp_print_m_translation(prog);
        }
        return 0;
    }

    if argc() >= 1 {
        // File analysis mode
        let path: string = argv(0);
        let prog: i32 = cp_parse_file(path);
        if prog >= 0 {
            cp_report(prog);
        }
        return 0;
    }

    // Test mode
    test_c_parser();
    return 0;
}
