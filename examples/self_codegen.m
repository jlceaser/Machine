// M Bytecode Compiler: tokenize -> parse -> emit bytecode -> run
// M compiles M. The final step before removing the C bootstrap.
// Reuses self_interp.m's frontend, replaces interpreter with codegen+VM.

// ── Character classification ─────────────────────────

fn is_digit(c: i32) -> bool { return c >= 48 && c <= 57; }
fn is_alpha(c: i32) -> bool {
    if c >= 65 && c <= 90 { return true; }
    if c >= 97 && c <= 122 { return true; }
    return c == 95;
}
fn is_alnum(c: i32) -> bool { return is_alpha(c) || is_digit(c); }
fn is_space(c: i32) -> bool { return c == 32 || c == 10 || c == 13 || c == 9; }

// ── Token types ──────────────────────────────────────

fn TK_EOF() -> i32    { return 0; }
fn TK_IDENT() -> i32  { return 1; }
fn TK_NUM() -> i32    { return 2; }
fn TK_STR() -> i32    { return 3; }
fn TK_KW_FN() -> i32  { return 10; }
fn TK_KW_LET() -> i32 { return 11; }
fn TK_KW_VAR() -> i32 { return 12; }
fn TK_KW_IF() -> i32  { return 13; }
fn TK_KW_ELSE() -> i32 { return 14; }
fn TK_KW_WHILE() -> i32 { return 15; }
fn TK_KW_RETURN() -> i32 { return 16; }
fn TK_KW_TRUE() -> i32  { return 17; }
fn TK_KW_FALSE() -> i32 { return 18; }
fn TK_KW_STRUCT() -> i32 { return 19; }
fn TK_KW_I32() -> i32   { return 20; }
fn TK_KW_I64() -> i32   { return 21; }
fn TK_KW_F64() -> i32   { return 22; }
fn TK_KW_BOOL() -> i32  { return 23; }
fn TK_KW_STRING() -> i32 { return 24; }
fn TK_PLUS() -> i32   { return 30; }
fn TK_MINUS() -> i32  { return 31; }
fn TK_STAR() -> i32   { return 32; }
fn TK_SLASH() -> i32  { return 33; }
fn TK_EQ() -> i32     { return 34; }
fn TK_NEQ() -> i32    { return 35; }
fn TK_LT() -> i32     { return 36; }
fn TK_GT() -> i32     { return 37; }
fn TK_LTE() -> i32    { return 38; }
fn TK_GTE() -> i32    { return 39; }
fn TK_ASSIGN() -> i32 { return 40; }
fn TK_AND() -> i32    { return 41; }
fn TK_OR() -> i32     { return 42; }
fn TK_NOT() -> i32    { return 43; }
fn TK_ARROW() -> i32  { return 44; }
fn TK_LPAREN() -> i32  { return 50; }
fn TK_RPAREN() -> i32  { return 51; }
fn TK_LBRACE() -> i32  { return 52; }
fn TK_RBRACE() -> i32  { return 53; }
fn TK_COLON() -> i32   { return 54; }
fn TK_SEMI() -> i32    { return 55; }
fn TK_COMMA() -> i32   { return 56; }
fn TK_DOT() -> i32     { return 57; }
fn TK_MOD() -> i32     { return 58; }

// ── Lexer state ──────────────────────────────────────

var tok_types: i32 = 0;
var tok_vals: i32 = 0;
var tok_count: i32 = 0;
var tok_pos: i32 = 0;

fn classify_word(w: string) -> i32 {
    if str_eq(w, "fn")     { return TK_KW_FN(); }
    if str_eq(w, "let")    { return TK_KW_LET(); }
    if str_eq(w, "var")    { return TK_KW_VAR(); }
    if str_eq(w, "if")     { return TK_KW_IF(); }
    if str_eq(w, "else")   { return TK_KW_ELSE(); }
    if str_eq(w, "while")  { return TK_KW_WHILE(); }
    if str_eq(w, "return") { return TK_KW_RETURN(); }
    if str_eq(w, "true")   { return TK_KW_TRUE(); }
    if str_eq(w, "false")  { return TK_KW_FALSE(); }
    if str_eq(w, "struct") { return TK_KW_STRUCT(); }
    if str_eq(w, "i32")    { return TK_KW_I32(); }
    if str_eq(w, "i64")    { return TK_KW_I64(); }
    if str_eq(w, "f64")    { return TK_KW_F64(); }
    if str_eq(w, "bool")   { return TK_KW_BOOL(); }
    if str_eq(w, "string") { return TK_KW_STRING(); }
    return TK_IDENT();
}

fn tokenize(src: string) -> i32 {
    tok_types = array_new(0);
    tok_vals = array_new(0);
    var i: i32 = 0;

    while i < len(src) {
        let c: i32 = char_at(src, i);
        if is_space(c) {
            i = i + 1;
        } else if c == 47 && i + 1 < len(src) && char_at(src, i + 1) == 47 {
            while i < len(src) && char_at(src, i) != 10 { i = i + 1; }
        } else if c == 34 {
            var start: i32 = i + 1;
            i = i + 1;
            while i < len(src) && char_at(src, i) != 34 {
                if char_at(src, i) == 92 { i = i + 1; }
                i = i + 1;
            }
            array_push(tok_types, TK_STR());
            array_push(tok_vals, substr(src, start, i - start));
            if i < len(src) { i = i + 1; }
        } else if is_digit(c) {
            var start: i32 = i;
            while i < len(src) && is_digit(char_at(src, i)) { i = i + 1; }
            array_push(tok_types, TK_NUM());
            array_push(tok_vals, substr(src, start, i - start));
        } else if is_alpha(c) {
            var start: i32 = i;
            while i < len(src) && is_alnum(char_at(src, i)) { i = i + 1; }
            let word: string = substr(src, start, i - start);
            array_push(tok_types, classify_word(word));
            array_push(tok_vals, word);
        } else if c == 61 && i + 1 < len(src) && char_at(src, i + 1) == 61 {
            array_push(tok_types, TK_EQ()); array_push(tok_vals, "=="); i = i + 2;
        } else if c == 33 && i + 1 < len(src) && char_at(src, i + 1) == 61 {
            array_push(tok_types, TK_NEQ()); array_push(tok_vals, "!="); i = i + 2;
        } else if c == 60 && i + 1 < len(src) && char_at(src, i + 1) == 61 {
            array_push(tok_types, TK_LTE()); array_push(tok_vals, "<="); i = i + 2;
        } else if c == 62 && i + 1 < len(src) && char_at(src, i + 1) == 61 {
            array_push(tok_types, TK_GTE()); array_push(tok_vals, ">="); i = i + 2;
        } else if c == 45 && i + 1 < len(src) && char_at(src, i + 1) == 62 {
            array_push(tok_types, TK_ARROW()); array_push(tok_vals, "->"); i = i + 2;
        } else if c == 38 && i + 1 < len(src) && char_at(src, i + 1) == 38 {
            array_push(tok_types, TK_AND()); array_push(tok_vals, "&&"); i = i + 2;
        } else if c == 124 && i + 1 < len(src) && char_at(src, i + 1) == 124 {
            array_push(tok_types, TK_OR()); array_push(tok_vals, "||"); i = i + 2;
        } else if c == 43 { array_push(tok_types, TK_PLUS()); array_push(tok_vals, "+"); i = i + 1;
        } else if c == 45 { array_push(tok_types, TK_MINUS()); array_push(tok_vals, "-"); i = i + 1;
        } else if c == 42 { array_push(tok_types, TK_STAR()); array_push(tok_vals, "*"); i = i + 1;
        } else if c == 47 { array_push(tok_types, TK_SLASH()); array_push(tok_vals, "/"); i = i + 1;
        } else if c == 37 { array_push(tok_types, TK_MOD()); array_push(tok_vals, "%"); i = i + 1;
        } else if c == 33 { array_push(tok_types, TK_NOT()); array_push(tok_vals, "!"); i = i + 1;
        } else if c == 61 { array_push(tok_types, TK_ASSIGN()); array_push(tok_vals, "="); i = i + 1;
        } else if c == 60 { array_push(tok_types, TK_LT()); array_push(tok_vals, "<"); i = i + 1;
        } else if c == 62 { array_push(tok_types, TK_GT()); array_push(tok_vals, ">"); i = i + 1;
        } else if c == 40 { array_push(tok_types, TK_LPAREN()); array_push(tok_vals, "("); i = i + 1;
        } else if c == 41 { array_push(tok_types, TK_RPAREN()); array_push(tok_vals, ")"); i = i + 1;
        } else if c == 123 { array_push(tok_types, TK_LBRACE()); array_push(tok_vals, "{"); i = i + 1;
        } else if c == 125 { array_push(tok_types, TK_RBRACE()); array_push(tok_vals, "}"); i = i + 1;
        } else if c == 58 { array_push(tok_types, TK_COLON()); array_push(tok_vals, ":"); i = i + 1;
        } else if c == 59 { array_push(tok_types, TK_SEMI()); array_push(tok_vals, ";"); i = i + 1;
        } else if c == 44 { array_push(tok_types, TK_COMMA()); array_push(tok_vals, ","); i = i + 1;
        } else if c == 46 { array_push(tok_types, TK_DOT()); array_push(tok_vals, "."); i = i + 1;
        } else {
            i = i + 1;
        }
    }

    array_push(tok_types, TK_EOF());
    array_push(tok_vals, "");
    tok_count = array_len(tok_types);
    tok_pos = 0;
    return tok_count;
}

// ── Parser helpers ───────────────────────────────────

fn peek() -> i32 {
    if tok_pos < tok_count { return array_get(tok_types, tok_pos); }
    return TK_EOF();
}

fn peek_val() -> string {
    if tok_pos < tok_count { return array_get(tok_vals, tok_pos); }
    return "";
}

fn advance() -> i32 {
    let t: i32 = peek();
    tok_pos = tok_pos + 1;
    return t;
}

fn advance_val() -> string {
    let v: string = peek_val();
    tok_pos = tok_pos + 1;
    return v;
}

fn expect(t: i32, msg: string) -> i32 {
    if peek() == t { advance(); return 1; }
    print("PARSE ERROR: expected ");
    print(msg);
    print(" got '");
    print(peek_val());
    println("'");
    return 0;
}

fn match_tok(t: i32) -> bool {
    if peek() == t { advance(); return true; }
    return false;
}

// ── AST node types ───────────────────────────────────

fn NK_INT_LIT() -> i32   { return 1; }
fn NK_STR_LIT() -> i32   { return 2; }
fn NK_BOOL_LIT() -> i32  { return 3; }
fn NK_IDENT() -> i32     { return 4; }
fn NK_BINARY() -> i32    { return 5; }
fn NK_UNARY() -> i32     { return 6; }
fn NK_CALL() -> i32      { return 7; }
fn NK_LET() -> i32       { return 10; }
fn NK_ASSIGN() -> i32    { return 11; }
fn NK_RETURN() -> i32    { return 12; }
fn NK_IF() -> i32        { return 13; }
fn NK_WHILE() -> i32     { return 14; }
fn NK_BLOCK() -> i32     { return 15; }
fn NK_EXPR_STMT() -> i32 { return 16; }
fn NK_FN_DECL() -> i32   { return 20; }
fn NK_VAR_DECL() -> i32  { return 21; }
fn NK_PROGRAM() -> i32   { return 30; }

// ── AST storage (flat arrays) ────────────────────────

var node_kinds: i32 = 0;
var node_data: i32 = 0;
var node_extra: i32 = 0;
var node_extra2: i32 = 0;
var node_names: i32 = 0;
var node_count: i32 = 0;
var child_lists: i32 = 0;
var child_count: i32 = 0;

fn init_ast() -> i32 {
    node_kinds = array_new(0);
    node_data = array_new(0);
    node_extra = array_new(0);
    node_extra2 = array_new(0);
    node_names = array_new(0);
    child_lists = array_new(0);
    node_count = 0;
    child_count = 0;
    return 0;
}

fn new_node(kind: i32, data: i32, extra: i32, extra2: i32, name: string) -> i32 {
    let idx: i32 = node_count;
    array_push(node_kinds, kind);
    array_push(node_data, data);
    array_push(node_extra, extra);
    array_push(node_extra2, extra2);
    array_push(node_names, name);
    node_count = node_count + 1;
    return idx;
}

fn flush_children(temp: i32) -> i32 {
    let start: i32 = child_count;
    var i: i32 = 0;
    while i < array_len(temp) {
        array_push(child_lists, array_get(temp, i));
        child_count = child_count + 1;
        i = i + 1;
    }
    return start;
}

fn nk(idx: i32) -> i32  { return array_get(node_kinds, idx); }
fn nd(idx: i32) -> i32  { return array_get(node_data, idx); }
fn ne(idx: i32) -> i32  { return array_get(node_extra, idx); }
fn ne2(idx: i32) -> i32 { return array_get(node_extra2, idx); }
fn nn(idx: i32) -> string { return array_get(node_names, idx); }
fn child(start: i32, i: i32) -> i32 { return array_get(child_lists, start + i); }

// ── Expression parser ────────────────────────────────

fn parse_expr() -> i32;
fn parse_stmt() -> i32;

fn parse_primary() -> i32 {
    let t: i32 = peek();
    if t == TK_NUM()      { return new_node(NK_INT_LIT(), 0, 0, 0, advance_val()); }
    if t == TK_STR()      { return new_node(NK_STR_LIT(), 0, 0, 0, advance_val()); }
    if t == TK_KW_TRUE()  { advance(); return new_node(NK_BOOL_LIT(), 1, 0, 0, "true"); }
    if t == TK_KW_FALSE() { advance(); return new_node(NK_BOOL_LIT(), 0, 0, 0, "false"); }
    if t == TK_IDENT()    { return new_node(NK_IDENT(), 0, 0, 0, advance_val()); }
    if t == TK_LPAREN() {
        advance();
        let inner: i32 = parse_expr();
        expect(TK_RPAREN(), "')'");
        return inner;
    }
    advance();
    return new_node(NK_INT_LIT(), 0, 0, 0, "0");
}

fn parse_postfix() -> i32 {
    var node: i32 = parse_primary();
    while true {
        if peek() == TK_LPAREN() {
            advance();
            var args: i32 = array_new(0);
            while peek() != TK_RPAREN() && peek() != TK_EOF() {
                array_push(args, parse_expr());
                if peek() != TK_RPAREN() { expect(TK_COMMA(), "','"); }
            }
            expect(TK_RPAREN(), "')'");
            let start: i32 = flush_children(args);
            node = new_node(NK_CALL(), node, start, array_len(args), "");
        } else {
            return node;
        }
    }
    return node;
}

fn parse_unary() -> i32 {
    if peek() == TK_MINUS() { advance(); return new_node(NK_UNARY(), parse_postfix(), 31, 0, "-"); }
    if peek() == TK_NOT()   { advance(); return new_node(NK_UNARY(), parse_postfix(), 43, 0, "!"); }
    return parse_postfix();
}

fn parse_factor() -> i32 {
    var left: i32 = parse_unary();
    while peek() == TK_STAR() || peek() == TK_SLASH() || peek() == TK_MOD() {
        let op: i32 = advance();
        let right: i32 = parse_unary();
        let name: string = "*";
        if op == TK_SLASH() { name = "/"; }
        if op == TK_MOD() { name = "%"; }
        left = new_node(NK_BINARY(), left, right, op, name);
    }
    return left;
}

fn parse_term() -> i32 {
    var left: i32 = parse_factor();
    while peek() == TK_PLUS() || peek() == TK_MINUS() {
        let op: i32 = advance();
        let right: i32 = parse_factor();
        let name: string = "+";
        if op == TK_MINUS() { name = "-"; }
        left = new_node(NK_BINARY(), left, right, op, name);
    }
    return left;
}

fn parse_comparison() -> i32 {
    var left: i32 = parse_term();
    while peek() == TK_LT() || peek() == TK_GT() || peek() == TK_LTE() || peek() == TK_GTE() {
        let op: i32 = advance();
        let right: i32 = parse_term();
        let name: string = "<";
        if op == TK_GT() { name = ">"; }
        if op == TK_LTE() { name = "<="; }
        if op == TK_GTE() { name = ">="; }
        left = new_node(NK_BINARY(), left, right, op, name);
    }
    return left;
}

fn parse_equality() -> i32 {
    var left: i32 = parse_comparison();
    while peek() == TK_EQ() || peek() == TK_NEQ() {
        let op: i32 = advance();
        let right: i32 = parse_comparison();
        let name: string = "==";
        if op == TK_NEQ() { name = "!="; }
        left = new_node(NK_BINARY(), left, right, op, name);
    }
    return left;
}

fn parse_and() -> i32 {
    var left: i32 = parse_equality();
    while peek() == TK_AND() {
        advance();
        left = new_node(NK_BINARY(), left, parse_equality(), TK_AND(), "&&");
    }
    return left;
}

fn parse_expr() -> i32 {
    var left: i32 = parse_and();
    while peek() == TK_OR() {
        advance();
        left = new_node(NK_BINARY(), left, parse_and(), TK_OR(), "||");
    }
    return left;
}

// ── Statement parser ─────────────────────────────────

fn parse_block() -> i32 {
    expect(TK_LBRACE(), "'{'");
    var stmts: i32 = array_new(0);
    while peek() != TK_RBRACE() && peek() != TK_EOF() {
        array_push(stmts, parse_stmt());
    }
    expect(TK_RBRACE(), "'}'");
    let start: i32 = flush_children(stmts);
    return new_node(NK_BLOCK(), start, array_len(stmts), 0, "");
}

fn parse_type() -> string {
    let t: i32 = peek();
    if t == TK_KW_I32()    { advance(); return "i32"; }
    if t == TK_KW_I64()    { advance(); return "i64"; }
    if t == TK_KW_F64()    { advance(); return "f64"; }
    if t == TK_KW_BOOL()   { advance(); return "bool"; }
    if t == TK_KW_STRING() { advance(); return "string"; }
    if t == TK_IDENT()     { return advance_val(); }
    return "unknown";
}

fn parse_stmt() -> i32 {
    if peek() == TK_KW_LET() || peek() == TK_KW_VAR() {
        let is_var: i32 = 0;
        if peek() == TK_KW_VAR() { is_var = 1; }
        advance();
        let name: string = advance_val();
        if match_tok(TK_COLON()) { parse_type(); }
        var init: i32 = 0 - 1;
        if match_tok(TK_ASSIGN()) { init = parse_expr(); }
        expect(TK_SEMI(), "';'");
        return new_node(NK_LET(), init, is_var, 0, name);
    }
    if peek() == TK_KW_RETURN() {
        advance();
        var val: i32 = 0 - 1;
        if peek() != TK_SEMI() { val = parse_expr(); }
        expect(TK_SEMI(), "';'");
        return new_node(NK_RETURN(), val, 0, 0, "");
    }
    if peek() == TK_KW_IF() {
        advance();
        let cond: i32 = parse_expr();
        let then_b: i32 = parse_block();
        var else_b: i32 = 0 - 1;
        if match_tok(TK_KW_ELSE()) {
            if peek() == TK_KW_IF() {
                else_b = parse_stmt();
            } else {
                else_b = parse_block();
            }
        }
        return new_node(NK_IF(), cond, then_b, else_b, "");
    }
    if peek() == TK_KW_WHILE() {
        advance();
        let cond: i32 = parse_expr();
        let body: i32 = parse_block();
        return new_node(NK_WHILE(), cond, body, 0, "");
    }
    if peek() == TK_LBRACE() { return parse_block(); }

    let expr: i32 = parse_expr();
    if match_tok(TK_ASSIGN()) {
        let val: i32 = parse_expr();
        expect(TK_SEMI(), "';'");
        return new_node(NK_ASSIGN(), expr, val, 0, "");
    }
    expect(TK_SEMI(), "';'");
    return new_node(NK_EXPR_STMT(), expr, 0, 0, "");
}

// ── Declaration parser ───────────────────────────────

fn parse_fn_decl() -> i32 {
    let name: string = advance_val();
    expect(TK_LPAREN(), "'('");
    var params: i32 = array_new(0);
    while peek() != TK_RPAREN() && peek() != TK_EOF() {
        let pname: string = advance_val();
        expect(TK_COLON(), "':'");
        parse_type();
        array_push(params, new_node(NK_LET(), 0 - 1, 0, 0, pname));
        if peek() != TK_RPAREN() { expect(TK_COMMA(), "','"); }
    }
    expect(TK_RPAREN(), "')'");
    if match_tok(TK_ARROW()) { parse_type(); }
    var body: i32 = 0 - 1;
    if peek() == TK_SEMI() { advance(); } else { body = parse_block(); }
    let ps: i32 = flush_children(params);
    return new_node(NK_FN_DECL(), body, ps, array_len(params), name);
}

fn parse_global_var() -> i32 {
    let name: string = advance_val();
    if match_tok(TK_COLON()) { parse_type(); }
    var init: i32 = 0 - 1;
    if match_tok(TK_ASSIGN()) { init = parse_expr(); }
    expect(TK_SEMI(), "';'");
    return new_node(NK_VAR_DECL(), init, 0, 0, name);
}

fn parse_program() -> i32 {
    var decls: i32 = array_new(0);
    while peek() != TK_EOF() {
        if peek() == TK_KW_FN() { advance(); array_push(decls, parse_fn_decl()); }
        else if peek() == TK_KW_VAR() { advance(); array_push(decls, parse_global_var()); }
        else { advance(); }
    }
    let start: i32 = flush_children(decls);
    return new_node(NK_PROGRAM(), start, array_len(decls), 0, "");
}

// ══════════════════════════════════════════════════════
// ── BYTECODE COMPILER ─────────────────────────────────
// ══════════════════════════════════════════════════════

// Opcodes — matching bytecode.h exactly
fn OP_CONST_INT() -> i32  { return 0; }
fn OP_TRUE() -> i32       { return 4; }
fn OP_FALSE() -> i32      { return 5; }
fn OP_NIL() -> i32        { return 6; }
fn OP_POP() -> i32        { return 7; }
fn OP_LOCAL_GET() -> i32  { return 8; }
fn OP_LOCAL_SET() -> i32  { return 9; }
fn OP_GLOBAL_GET() -> i32 { return 10; }
fn OP_GLOBAL_SET() -> i32 { return 11; }
fn OP_ADD() -> i32        { return 12; }
fn OP_SUB() -> i32        { return 13; }
fn OP_MUL() -> i32        { return 14; }
fn OP_DIV() -> i32        { return 15; }
fn OP_MOD() -> i32        { return 16; }
fn OP_NEG() -> i32        { return 17; }
fn OP_EQ() -> i32         { return 18; }
fn OP_NEQ() -> i32        { return 19; }
fn OP_LT() -> i32         { return 20; }
fn OP_GT() -> i32         { return 21; }
fn OP_LTE() -> i32        { return 22; }
fn OP_GTE() -> i32        { return 23; }
fn OP_NOT() -> i32        { return 26; }
fn OP_JUMP() -> i32       { return 27; }
fn OP_JUMP_FALSE() -> i32 { return 28; }
fn OP_CALL() -> i32       { return 29; }
fn OP_RETURN() -> i32     { return 30; }
fn OP_PRINT() -> i32      { return 38; }
fn OP_CONST_STRING() -> i32 { return 2; }

// Built-in function opcodes
fn OP_BUILTIN_LEN() -> i32        { return 39; }
fn OP_BUILTIN_CHAR_AT() -> i32    { return 40; }
fn OP_BUILTIN_SUBSTR() -> i32     { return 41; }
fn OP_BUILTIN_STR_CONCAT() -> i32 { return 42; }
fn OP_BUILTIN_INT_TO_STR() -> i32 { return 43; }
fn OP_BUILTIN_STR_EQ() -> i32     { return 44; }
fn OP_BUILTIN_READ_FILE() -> i32  { return 45; }
fn OP_BUILTIN_CHAR_TO_STR() -> i32 { return 46; }

// Array opcodes
fn OP_ARRAY_NEW() -> i32  { return 47; }
fn OP_ARRAY_GET() -> i32  { return 48; }
fn OP_ARRAY_SET() -> i32  { return 49; }
fn OP_ARRAY_LEN() -> i32  { return 50; }
fn OP_ARRAY_PUSH() -> i32 { return 51; }

fn OP_HALT() -> i32       { return 52; }

// ── Per-function bytecode chunk ──────────────────────

// Bytecode: flat array of bytes per function
// Constants: parallel arrays for int and string pools
// Locals: compile-time name→slot mapping

var code: i32 = 0;         // current function's bytecode (array of ints, each = 1 byte)
var int_pool: i32 = 0;     // int constants for current function
var str_pool: i32 = 0;     // string constants for current function

// Module: multiple functions
var mod_names: i32 = 0;     // function names
var mod_codes: i32 = 0;     // array of code arrays (each is a bytecode array)
var mod_ints: i32 = 0;      // array of int pool arrays
var mod_strs: i32 = 0;      // array of string pool arrays
var mod_params: i32 = 0;    // param count per function
var mod_locals: i32 = 0;    // max local count per function
var mod_count: i32 = 0;

// Global variable name table
var gv_names: i32 = 0;
var gv_count: i32 = 0;

// Local variable tracking for codegen
var local_names: i32 = 0;
var local_slots: i32 = 0;
var local_depths: i32 = 0;
var local_count: i32 = 0;
var max_local_count: i32 = 0;
var cg_scope_depth: i32 = 0;
var cur_func_idx: i32 = 0;

fn init_codegen() -> i32 {
    mod_names = array_new(0);
    mod_codes = array_new(0);
    mod_ints = array_new(0);
    mod_strs = array_new(0);
    mod_params = array_new(0);
    mod_locals = array_new(0);
    mod_count = 0;
    gv_names = array_new(0);
    gv_count = 0;
    return 0;
}

fn init_func_codegen() -> i32 {
    code = array_new(0);
    int_pool = array_new(0);
    str_pool = array_new(0);
    local_names = array_new(0);
    local_slots = array_new(0);
    local_depths = array_new(0);
    local_count = 0;
    max_local_count = 0;
    cg_scope_depth = 0;
    return 0;
}

// ── Emit helpers ─────────────────────────────────────

fn emit_byte(b: i32) -> i32 {
    array_push(code, b);
    return array_len(code) - 1;
}

fn emit_u16(val: i32) -> i32 {
    let hi: i32 = (val / 256) % 256;
    let lo: i32 = val % 256;
    emit_byte(hi);
    emit_byte(lo);
    return array_len(code) - 2;
}

fn emit_op_u16(op: i32, val: i32) -> i32 {
    emit_byte(op);
    emit_u16(val);
    return 0;
}

fn patch_i16(offset: i32, val: i32) -> i32 {
    // Encode signed i16 as two bytes
    var v: i32 = val;
    if v < 0 { v = v + 65536; }
    array_set(code, offset, (v / 256) % 256);
    array_set(code, offset + 1, v % 256);
    return 0;
}

fn emit_jump(op: i32) -> i32 {
    emit_byte(op);
    let offset: i32 = array_len(code);
    emit_u16(0); // placeholder
    return offset;
}

fn patch_jump(offset: i32) -> i32 {
    let jump: i32 = array_len(code) - offset - 2;
    patch_i16(offset, jump);
    return 0;
}

fn add_int_const(val: i32) -> i32 {
    array_push(int_pool, val);
    return array_len(int_pool) - 1;
}

fn add_str_const(val: string) -> i32 {
    array_push(str_pool, val);
    return array_len(str_pool) - 1;
}

// ── Local variable resolution ────────────────────────

fn resolve_local(name: string) -> i32 {
    var i: i32 = local_count - 1;
    while i >= 0 {
        if str_eq(array_get(local_names, i), name) {
            return array_get(local_slots, i);
        }
        i = i - 1;
    }
    return 0 - 1;
}

fn add_local(name: string) -> i32 {
    let slot: i32 = local_count;
    if local_count < array_len(local_names) {
        array_set(local_names, local_count, name);
        array_set(local_slots, local_count, slot);
        array_set(local_depths, local_count, cg_scope_depth);
    } else {
        array_push(local_names, name);
        array_push(local_slots, slot);
        array_push(local_depths, cg_scope_depth);
    }
    local_count = local_count + 1;
    if local_count > max_local_count { max_local_count = local_count; }
    return slot;
}

fn cg_begin_scope() -> i32 {
    cg_scope_depth = cg_scope_depth + 1;
    return 0;
}

fn cg_end_scope() -> i32 {
    while local_count > 0 && array_get(local_depths, local_count - 1) == cg_scope_depth {
        local_count = local_count - 1;
    }
    cg_scope_depth = cg_scope_depth - 1;
    return 0;
}

// ── Find function index ──────────────────────────────

fn find_func(name: string) -> i32 {
    var i: i32 = 0;
    while i < mod_count {
        if str_eq(array_get(mod_names, i), name) { return i; }
        i = i + 1;
    }
    return 0 - 1;
}

// ── Find global variable index ───────────────────────

fn find_global(name: string) -> i32 {
    var i: i32 = 0;
    while i < gv_count {
        if str_eq(array_get(gv_names, i), name) { return i; }
        i = i + 1;
    }
    return 0 - 1;
}

fn add_global_name(name: string) -> i32 {
    let idx: i32 = find_global(name);
    if idx >= 0 { return idx; }
    array_push(gv_names, name);
    gv_count = gv_count + 1;
    return gv_count - 1;
}

// ── Expression codegen ───────────────────────────────

fn gen_expr(idx: i32) -> i32;
fn gen_stmt(idx: i32) -> i32;

fn parse_num_str(s: string) -> i32 {
    var val: i32 = 0;
    var j: i32 = 0;
    while j < len(s) {
        val = val * 10 + char_at(s, j) - 48;
        j = j + 1;
    }
    return val;
}

fn gen_expr(idx: i32) -> i32 {
    if idx < 0 { emit_byte(OP_NIL()); return 0; }
    let kind: i32 = nk(idx);

    if kind == NK_INT_LIT() {
        let val: i32 = parse_num_str(nn(idx));
        let ci: i32 = add_int_const(val);
        emit_op_u16(OP_CONST_INT(), ci);
        return 0;
    }

    if kind == NK_STR_LIT() {
        let ci: i32 = add_str_const(nn(idx));
        emit_op_u16(OP_CONST_STRING(), ci);
        return 0;
    }

    if kind == NK_BOOL_LIT() {
        if nd(idx) != 0 { emit_byte(OP_TRUE()); }
        else { emit_byte(OP_FALSE()); }
        return 0;
    }

    if kind == NK_IDENT() {
        let name: string = nn(idx);
        let slot: i32 = resolve_local(name);
        if slot >= 0 {
            emit_op_u16(OP_LOCAL_GET(), slot);
        } else {
            // Try as function name
            let fi: i32 = find_func(name);
            if fi >= 0 {
                let ci: i32 = add_int_const(fi);
                emit_op_u16(OP_CONST_INT(), ci);
            } else {
                // Global variable
                let gi: i32 = add_global_name(name);
                emit_op_u16(OP_GLOBAL_GET(), gi);
            }
        }
        return 0;
    }

    if kind == NK_UNARY() {
        gen_expr(nd(idx));
        let op: i32 = ne(idx);
        if op == 31 { emit_byte(OP_NEG()); }
        if op == 43 { emit_byte(OP_NOT()); }
        return 0;
    }

    if kind == NK_BINARY() {
        let op: i32 = ne2(idx);

        // Short-circuit &&
        if op == TK_AND() {
            gen_expr(nd(idx));
            let skip: i32 = emit_jump(OP_JUMP_FALSE());
            gen_expr(ne(idx));
            let end: i32 = emit_jump(OP_JUMP());
            patch_jump(skip);
            emit_byte(OP_FALSE());
            patch_jump(end);
            return 0;
        }
        // Short-circuit ||
        if op == TK_OR() {
            gen_expr(nd(idx));
            let try_right: i32 = emit_jump(OP_JUMP_FALSE());
            emit_byte(OP_TRUE());
            let end: i32 = emit_jump(OP_JUMP());
            patch_jump(try_right);
            gen_expr(ne(idx));
            patch_jump(end);
            return 0;
        }

        gen_expr(nd(idx));
        gen_expr(ne(idx));
        if op == TK_PLUS()  { emit_byte(OP_ADD()); }
        if op == TK_MINUS() { emit_byte(OP_SUB()); }
        if op == TK_STAR()  { emit_byte(OP_MUL()); }
        if op == TK_SLASH() { emit_byte(OP_DIV()); }
        if op == TK_MOD()   { emit_byte(OP_MOD()); }
        if op == TK_EQ()    { emit_byte(OP_EQ()); }
        if op == TK_NEQ()   { emit_byte(OP_NEQ()); }
        if op == TK_LT()    { emit_byte(OP_LT()); }
        if op == TK_GT()    { emit_byte(OP_GT()); }
        if op == TK_LTE()   { emit_byte(OP_LTE()); }
        if op == TK_GTE()   { emit_byte(OP_GTE()); }
        return 0;
    }

    if kind == NK_CALL() {
        let callee_idx: i32 = nd(idx);
        let arg_start: i32 = ne(idx);
        let argc: i32 = ne2(idx);
        let callee_name: string = nn(callee_idx);

        // Built-in: print(expr)
        if str_eq(callee_name, "print") {
            if argc >= 1 { gen_expr(child(arg_start, 0)); }
            emit_byte(OP_PRINT());
            emit_byte(OP_NIL());
            return 0;
        }

        // Built-in: println(expr)
        if str_eq(callee_name, "println") {
            if argc >= 1 {
                gen_expr(child(arg_start, 0));
                emit_byte(OP_PRINT());
            }
            let ci: i32 = add_str_const("\n");
            emit_op_u16(OP_CONST_STRING(), ci);
            emit_byte(OP_PRINT());
            emit_byte(OP_NIL());
            return 0;
        }

        // Built-in: len(str) -> int
        if str_eq(callee_name, "len") {
            if argc >= 1 { gen_expr(child(arg_start, 0)); }
            emit_byte(OP_BUILTIN_LEN());
            return 0;
        }

        // Built-in: char_at(str, idx) -> int
        if str_eq(callee_name, "char_at") {
            if argc >= 2 {
                gen_expr(child(arg_start, 0));
                gen_expr(child(arg_start, 1));
            }
            emit_byte(OP_BUILTIN_CHAR_AT());
            return 0;
        }

        // Built-in: substr(str, start, len) -> string
        if str_eq(callee_name, "substr") {
            if argc >= 3 {
                gen_expr(child(arg_start, 0));
                gen_expr(child(arg_start, 1));
                gen_expr(child(arg_start, 2));
            }
            emit_byte(OP_BUILTIN_SUBSTR());
            return 0;
        }

        // Built-in: str_concat(a, b) -> string
        if str_eq(callee_name, "str_concat") {
            if argc >= 2 {
                gen_expr(child(arg_start, 0));
                gen_expr(child(arg_start, 1));
            }
            emit_byte(OP_BUILTIN_STR_CONCAT());
            return 0;
        }

        // Built-in: int_to_str(n) -> string
        if str_eq(callee_name, "int_to_str") {
            if argc >= 1 { gen_expr(child(arg_start, 0)); }
            emit_byte(OP_BUILTIN_INT_TO_STR());
            return 0;
        }

        // Built-in: str_eq(a, b) -> bool
        if str_eq(callee_name, "str_eq") {
            if argc >= 2 {
                gen_expr(child(arg_start, 0));
                gen_expr(child(arg_start, 1));
            }
            emit_byte(OP_BUILTIN_STR_EQ());
            return 0;
        }

        // Built-in: read_file(path) -> string
        if str_eq(callee_name, "read_file") {
            if argc >= 1 { gen_expr(child(arg_start, 0)); }
            emit_byte(OP_BUILTIN_READ_FILE());
            return 0;
        }

        // Built-in: char_to_str(c) -> string
        if str_eq(callee_name, "char_to_str") {
            if argc >= 1 { gen_expr(child(arg_start, 0)); }
            emit_byte(OP_BUILTIN_CHAR_TO_STR());
            return 0;
        }

        // Built-in: array_new(cap) -> array
        if str_eq(callee_name, "array_new") {
            if argc >= 1 { gen_expr(child(arg_start, 0)); }
            emit_byte(OP_ARRAY_NEW());
            return 0;
        }

        // Built-in: array_get(arr, idx) -> val
        if str_eq(callee_name, "array_get") {
            if argc >= 2 {
                gen_expr(child(arg_start, 0));
                gen_expr(child(arg_start, 1));
            }
            emit_byte(OP_ARRAY_GET());
            return 0;
        }

        // Built-in: array_set(arr, idx, val) -> void
        if str_eq(callee_name, "array_set") {
            if argc >= 3 {
                gen_expr(child(arg_start, 0));
                gen_expr(child(arg_start, 1));
                gen_expr(child(arg_start, 2));
            }
            emit_byte(OP_ARRAY_SET());
            emit_byte(OP_NIL());
            return 0;
        }

        // Built-in: array_len(arr) -> int
        if str_eq(callee_name, "array_len") {
            if argc >= 1 { gen_expr(child(arg_start, 0)); }
            emit_byte(OP_ARRAY_LEN());
            return 0;
        }

        // Built-in: array_push(arr, val) -> void
        if str_eq(callee_name, "array_push") {
            if argc >= 2 {
                gen_expr(child(arg_start, 0));
                gen_expr(child(arg_start, 1));
            }
            emit_byte(OP_ARRAY_PUSH());
            emit_byte(OP_NIL());
            return 0;
        }

        // Regular function call: push callee, then args
        gen_expr(callee_idx);
        var i: i32 = 0;
        while i < argc {
            gen_expr(child(arg_start, i));
            i = i + 1;
        }
        emit_op_u16(OP_CALL(), argc);
        return 0;
    }

    emit_byte(OP_NIL());
    return 0;
}

// ── Statement codegen ────────────────────────────────

fn gen_stmt(idx: i32) -> i32 {
    if idx < 0 { return 0; }
    let kind: i32 = nk(idx);

    if kind == NK_LET() {
        let name: string = nn(idx);
        let init: i32 = nd(idx);
        if init >= 0 { gen_expr(init); }
        else { emit_byte(OP_NIL()); }
        let slot: i32 = add_local(name);
        emit_op_u16(OP_LOCAL_SET(), slot);
        emit_byte(OP_POP());
        return 0;
    }

    if kind == NK_ASSIGN() {
        let target: i32 = nd(idx);
        let val: i32 = ne(idx);
        gen_expr(val);
        let name: string = nn(target);
        let slot: i32 = resolve_local(name);
        if slot >= 0 {
            emit_op_u16(OP_LOCAL_SET(), slot);
        } else {
            let gi: i32 = add_global_name(name);
            emit_op_u16(OP_GLOBAL_SET(), gi);
        }
        emit_byte(OP_POP());
        return 0;
    }

    if kind == NK_RETURN() {
        let val: i32 = nd(idx);
        if val >= 0 { gen_expr(val); }
        else { emit_byte(OP_NIL()); }
        emit_byte(OP_RETURN());
        return 0;
    }

    if kind == NK_IF() {
        let cond: i32 = nd(idx);
        let then_b: i32 = ne(idx);
        let else_b: i32 = ne2(idx);
        gen_expr(cond);
        let else_jump: i32 = emit_jump(OP_JUMP_FALSE());
        gen_stmt(then_b);
        if else_b >= 0 {
            let end_jump: i32 = emit_jump(OP_JUMP());
            patch_jump(else_jump);
            gen_stmt(else_b);
            patch_jump(end_jump);
        } else {
            patch_jump(else_jump);
        }
        return 0;
    }

    if kind == NK_WHILE() {
        let cond: i32 = nd(idx);
        let body: i32 = ne(idx);
        let loop_start: i32 = array_len(code);
        gen_expr(cond);
        let exit_jump: i32 = emit_jump(OP_JUMP_FALSE());
        gen_stmt(body);
        // Jump back
        emit_byte(OP_JUMP());
        let back: i32 = array_len(code);
        emit_u16(0);
        let offset: i32 = loop_start - back - 2;
        patch_i16(back, offset);
        patch_jump(exit_jump);
        return 0;
    }

    if kind == NK_BLOCK() {
        let start: i32 = nd(idx);
        let count: i32 = ne(idx);
        cg_begin_scope();
        var i: i32 = 0;
        while i < count {
            gen_stmt(child(start, i));
            i = i + 1;
        }
        cg_end_scope();
        return 0;
    }

    if kind == NK_EXPR_STMT() {
        gen_expr(nd(idx));
        emit_byte(OP_POP());
        return 0;
    }

    return 0;
}

// ── Compile a function ───────────────────────────────

fn compile_function(decl_idx: i32) -> i32 {
    let name: string = nn(decl_idx);
    let body: i32 = nd(decl_idx);
    let param_start: i32 = ne(decl_idx);
    let param_count: i32 = ne2(decl_idx);

    init_func_codegen();

    // Parameters are the first locals
    var i: i32 = 0;
    while i < param_count {
        let pname: string = nn(child(param_start, i));
        add_local(pname);
        i = i + 1;
    }

    // Compile body
    if body >= 0 {
        if nk(body) == NK_BLOCK() {
            let start: i32 = nd(body);
            let count: i32 = ne(body);
            var j: i32 = 0;
            while j < count {
                gen_stmt(child(start, j));
                j = j + 1;
            }
        } else {
            gen_stmt(body);
        }
    }

    // Implicit return
    emit_byte(OP_NIL());
    emit_byte(OP_RETURN());

    // Find or add function slot
    let fi: i32 = find_func(name);
    if fi >= 0 {
        // Reuse pre-registered slot
        array_set(mod_codes, fi, code);
        array_set(mod_ints, fi, int_pool);
        array_set(mod_strs, fi, str_pool);
        array_set(mod_params, fi, param_count);
        array_set(mod_locals, fi, max_local_count);
    } else {
        array_push(mod_names, name);
        array_push(mod_codes, code);
        array_push(mod_ints, int_pool);
        array_push(mod_strs, str_pool);
        array_push(mod_params, param_count);
        array_push(mod_locals, max_local_count);
        mod_count = mod_count + 1;
    }

    return 0;
}

// ── Compile program ──────────────────────────────────

fn compile_program(root: i32) -> i32 {
    let start: i32 = nd(root);
    let count: i32 = ne(root);

    // First pass: pre-register all function names
    var i: i32 = 0;
    while i < count {
        let decl: i32 = child(start, i);
        if nk(decl) == NK_FN_DECL() {
            array_push(mod_names, nn(decl));
            array_push(mod_codes, array_new(0));
            array_push(mod_ints, array_new(0));
            array_push(mod_strs, array_new(0));
            array_push(mod_params, ne2(decl));
            array_push(mod_locals, 0);
            mod_count = mod_count + 1;
        }
        if nk(decl) == NK_VAR_DECL() {
            add_global_name(nn(decl));
        }
        i = i + 1;
    }

    // Second pass: compile each function
    i = 0;
    while i < count {
        let decl: i32 = child(start, i);
        if nk(decl) == NK_FN_DECL() {
            let body: i32 = nd(decl);
            if body >= 0 {
                compile_function(decl);
            }
        }
        i = i + 1;
    }

    // Generate __init for global variable initializers
    var has_globals: i32 = 0;
    i = 0;
    while i < count {
        if nk(child(start, i)) == NK_VAR_DECL() { has_globals = 1; }
        i = i + 1;
    }

    if has_globals != 0 {
        init_func_codegen();
        i = 0;
        while i < count {
            let decl: i32 = child(start, i);
            if nk(decl) == NK_VAR_DECL() {
                let init: i32 = nd(decl);
                if init >= 0 { gen_expr(init); }
                else { emit_byte(OP_NIL()); }
                let gi: i32 = find_global(nn(decl));
                emit_op_u16(OP_GLOBAL_SET(), gi);
                emit_byte(OP_POP());
            }
            i = i + 1;
        }
        emit_byte(OP_NIL());
        emit_byte(OP_RETURN());

        array_push(mod_names, "__init");
        array_push(mod_codes, code);
        array_push(mod_ints, int_pool);
        array_push(mod_strs, str_pool);
        array_push(mod_params, 0);
        array_push(mod_locals, max_local_count);
        mod_count = mod_count + 1;
    }

    return 0;
}

// ══════════════════════════════════════════════════════
// ── VIRTUAL MACHINE (typed, stack-based) ─────────────
// ══════════════════════════════════════════════════════

// Value types
fn VT_INT() -> i32  { return 0; }
fn VT_STR() -> i32  { return 1; }
fn VT_BOOL() -> i32 { return 2; }
fn VT_VOID() -> i32 { return 3; }
fn VT_ARR() -> i32  { return 4; }

// Typed stack: parallel arrays (type, int_val, str_val)
// Arrays stored as handles in int_val (index into arr_store)
var vm_types: i32 = 0;
var vm_ivals: i32 = 0;
var vm_svals: i32 = 0;
var vm_top: i32 = 0;

// Array store: typed triple (types, ivals, svals per array)
var arr_types_store: i32 = 0;
var arr_ivals_store: i32 = 0;
var arr_svals_store: i32 = 0;
var arr_count: i32 = 0;

// Call frame stack
var frame_func: i32 = 0;
var frame_ip: i32 = 0;
var frame_base: i32 = 0;
var frame_count: i32 = 0;

// Globals: typed parallel arrays
var gv_types: i32 = 0;
var gv_ivals: i32 = 0;
var gv_svals: i32 = 0;
var vm_global_count: i32 = 0;

var vm_output: string = "";

fn init_vm() -> i32 {
    vm_types = array_new(0);
    vm_ivals = array_new(0);
    vm_svals = array_new(0);
    vm_top = 0;
    arr_types_store = array_new(0);
    arr_ivals_store = array_new(0);
    arr_svals_store = array_new(0);
    arr_count = 0;
    frame_func = array_new(0);
    frame_ip = array_new(0);
    frame_base = array_new(0);
    frame_count = 0;
    gv_types = array_new(0);
    gv_ivals = array_new(0);
    gv_svals = array_new(0);
    vm_global_count = 0;
    vm_output = "";
    // Pre-allocate stack
    var i: i32 = 0;
    while i < 512 {
        array_push(vm_types, VT_VOID());
        array_push(vm_ivals, 0);
        array_push(vm_svals, "");
        i = i + 1;
    }
    return 0;
}

fn vm_push_int(v: i32) -> i32 {
    if vm_top < array_len(vm_types) {
        array_set(vm_types, vm_top, VT_INT());
        array_set(vm_ivals, vm_top, v);
        array_set(vm_svals, vm_top, "");
    } else {
        array_push(vm_types, VT_INT());
        array_push(vm_ivals, v);
        array_push(vm_svals, "");
    }
    vm_top = vm_top + 1;
    return 0;
}

fn vm_push_str(v: string) -> i32 {
    if vm_top < array_len(vm_types) {
        array_set(vm_types, vm_top, VT_STR());
        array_set(vm_ivals, vm_top, 0);
        array_set(vm_svals, vm_top, v);
    } else {
        array_push(vm_types, VT_STR());
        array_push(vm_ivals, 0);
        array_push(vm_svals, v);
    }
    vm_top = vm_top + 1;
    return 0;
}

fn vm_push_bool(v: i32) -> i32 {
    if vm_top < array_len(vm_types) {
        array_set(vm_types, vm_top, VT_BOOL());
        array_set(vm_ivals, vm_top, v);
        array_set(vm_svals, vm_top, "");
    } else {
        array_push(vm_types, VT_BOOL());
        array_push(vm_ivals, v);
        array_push(vm_svals, "");
    }
    vm_top = vm_top + 1;
    return 0;
}

fn vm_push_void() -> i32 {
    if vm_top < array_len(vm_types) {
        array_set(vm_types, vm_top, VT_VOID());
        array_set(vm_ivals, vm_top, 0);
        array_set(vm_svals, vm_top, "");
    } else {
        array_push(vm_types, VT_VOID());
        array_push(vm_ivals, 0);
        array_push(vm_svals, "");
    }
    vm_top = vm_top + 1;
    return 0;
}

fn vm_push_arr(handle: i32) -> i32 {
    if vm_top < array_len(vm_types) {
        array_set(vm_types, vm_top, VT_ARR());
        array_set(vm_ivals, vm_top, handle);
        array_set(vm_svals, vm_top, "");
    } else {
        array_push(vm_types, VT_ARR());
        array_push(vm_ivals, handle);
        array_push(vm_svals, "");
    }
    vm_top = vm_top + 1;
    return 0;
}

// Copy slot at index to top of stack
fn vm_push_slot(idx: i32) -> i32 {
    let t: i32 = array_get(vm_types, idx);
    let iv: i32 = array_get(vm_ivals, idx);
    let sv: string = array_get(vm_svals, idx);
    if vm_top < array_len(vm_types) {
        array_set(vm_types, vm_top, t);
        array_set(vm_ivals, vm_top, iv);
        array_set(vm_svals, vm_top, sv);
    } else {
        array_push(vm_types, t);
        array_push(vm_ivals, iv);
        array_push(vm_svals, sv);
    }
    vm_top = vm_top + 1;
    return 0;
}

fn vm_pop_type() -> i32 { vm_top = vm_top - 1; return array_get(vm_types, vm_top); }
fn vm_pop_ival() -> i32 { return array_get(vm_ivals, vm_top); }
fn vm_pop_sval() -> string { return array_get(vm_svals, vm_top); }

fn vm_peek_type(d: i32) -> i32 { return array_get(vm_types, vm_top - 1 - d); }
fn vm_peek_ival(d: i32) -> i32 { return array_get(vm_ivals, vm_top - 1 - d); }
fn vm_peek_sval(d: i32) -> string { return array_get(vm_svals, vm_top - 1 - d); }

// Set slot at absolute index
fn vm_set_slot(idx: i32, t: i32, iv: i32, sv: string) -> i32 {
    array_set(vm_types, idx, t);
    array_set(vm_ivals, idx, iv);
    array_set(vm_svals, idx, sv);
    return 0;
}

// Array store: create new array, return handle
fn arr_new() -> i32 {
    let handle: i32 = arr_count;
    array_push(arr_types_store, array_new(0));
    array_push(arr_ivals_store, array_new(0));
    array_push(arr_svals_store, array_new(0));
    arr_count = arr_count + 1;
    return handle;
}

// Bytecode reading
fn read_byte_vm() -> i32 {
    let fi: i32 = array_get(frame_func, frame_count - 1);
    let ip: i32 = array_get(frame_ip, frame_count - 1);
    let bytecode: i32 = array_get(mod_codes, fi);
    let b: i32 = array_get(bytecode, ip);
    array_set(frame_ip, frame_count - 1, ip + 1);
    return b;
}

fn read_u16_vm() -> i32 {
    let hi: i32 = read_byte_vm();
    let lo: i32 = read_byte_vm();
    return hi * 256 + lo;
}

fn read_i16_vm() -> i32 {
    let val: i32 = read_u16_vm();
    if val >= 32768 { return val - 65536; }
    return val;
}

// ── VM execution loop ────────────────────────────────

fn vm_run_func(fi: i32, argc: i32) -> i32 {
    // argc arguments are already on the stack at [vm_top - argc, vm_top)
    let base: i32 = vm_top - argc;
    if frame_count < array_len(frame_func) {
        array_set(frame_func, frame_count, fi);
        array_set(frame_ip, frame_count, 0);
        array_set(frame_base, frame_count, base);
    } else {
        array_push(frame_func, fi);
        array_push(frame_ip, 0);
        array_push(frame_base, base);
    }
    frame_count = frame_count + 1;

    // Reserve remaining locals beyond params
    let n_locals: i32 = array_get(mod_locals, fi);
    let extra: i32 = n_locals - argc;
    var j: i32 = 0;
    while j < extra { vm_push_void(); j = j + 1; }

    while true {
        let op: i32 = read_byte_vm();
        let cur_fi: i32 = array_get(frame_func, frame_count - 1);
        let base: i32 = array_get(frame_base, frame_count - 1);

        if op == OP_CONST_INT() {
            let ci: i32 = read_u16_vm();
            let pool: i32 = array_get(mod_ints, cur_fi);
            vm_push_int(array_get(pool, ci));
        } else if op == OP_CONST_STRING() {
            let ci: i32 = read_u16_vm();
            let pool: i32 = array_get(mod_strs, cur_fi);
            vm_push_str(array_get(pool, ci));
        } else if op == OP_TRUE() {
            vm_push_bool(1);
        } else if op == OP_FALSE() {
            vm_push_bool(0);
        } else if op == OP_NIL() {
            vm_push_void();
        } else if op == OP_POP() {
            vm_pop_type();
        } else if op == OP_LOCAL_GET() {
            let slot: i32 = read_u16_vm();
            vm_push_slot(base + slot);
        } else if op == OP_LOCAL_SET() {
            let slot: i32 = read_u16_vm();
            let t: i32 = vm_peek_type(0);
            let iv: i32 = vm_peek_ival(0);
            let sv: string = vm_peek_sval(0);
            vm_set_slot(base + slot, t, iv, sv);
        } else if op == OP_GLOBAL_GET() {
            let gi: i32 = read_u16_vm();
            if gi < vm_global_count {
                let t: i32 = array_get(gv_types, gi);
                let iv: i32 = array_get(gv_ivals, gi);
                let sv: string = array_get(gv_svals, gi);
                if t == VT_INT() { vm_push_int(iv); }
                else if t == VT_STR() { vm_push_str(sv); }
                else if t == VT_BOOL() { vm_push_bool(iv); }
                else if t == VT_ARR() { vm_push_arr(iv); }
                else { vm_push_void(); }
            } else {
                vm_push_void();
            }
        } else if op == OP_GLOBAL_SET() {
            let gi: i32 = read_u16_vm();
            while gi >= vm_global_count {
                if vm_global_count < array_len(gv_types) {
                    array_set(gv_types, vm_global_count, VT_VOID());
                    array_set(gv_ivals, vm_global_count, 0);
                    array_set(gv_svals, vm_global_count, "");
                } else {
                    array_push(gv_types, VT_VOID());
                    array_push(gv_ivals, 0);
                    array_push(gv_svals, "");
                }
                vm_global_count = vm_global_count + 1;
            }
            let t: i32 = vm_peek_type(0);
            let iv: i32 = vm_peek_ival(0);
            let sv: string = vm_peek_sval(0);
            array_set(gv_types, gi, t);
            array_set(gv_ivals, gi, iv);
            array_set(gv_svals, gi, sv);
        } else if op == OP_ADD() {
            vm_pop_type(); let bi: i32 = vm_pop_ival();
            vm_pop_type(); let ai: i32 = vm_pop_ival();
            vm_push_int(ai + bi);
        } else if op == OP_SUB() {
            vm_pop_type(); let bi: i32 = vm_pop_ival();
            vm_pop_type(); let ai: i32 = vm_pop_ival();
            vm_push_int(ai - bi);
        } else if op == OP_MUL() {
            vm_pop_type(); let bi: i32 = vm_pop_ival();
            vm_pop_type(); let ai: i32 = vm_pop_ival();
            vm_push_int(ai * bi);
        } else if op == OP_DIV() {
            vm_pop_type(); let bi: i32 = vm_pop_ival();
            vm_pop_type(); let ai: i32 = vm_pop_ival();
            if bi != 0 { vm_push_int(ai / bi); } else { vm_push_int(0); }
        } else if op == OP_MOD() {
            vm_pop_type(); let bi: i32 = vm_pop_ival();
            vm_pop_type(); let ai: i32 = vm_pop_ival();
            if bi != 0 { vm_push_int(ai - (ai / bi) * bi); } else { vm_push_int(0); }
        } else if op == OP_NEG() {
            vm_pop_type(); let ai: i32 = vm_pop_ival();
            vm_push_int(0 - ai);
        } else if op == OP_EQ() {
            vm_pop_type(); let bi: i32 = vm_pop_ival();
            vm_pop_type(); let ai: i32 = vm_pop_ival();
            if ai == bi { vm_push_bool(1); } else { vm_push_bool(0); }
        } else if op == OP_NEQ() {
            vm_pop_type(); let bi: i32 = vm_pop_ival();
            vm_pop_type(); let ai: i32 = vm_pop_ival();
            if ai != bi { vm_push_bool(1); } else { vm_push_bool(0); }
        } else if op == OP_LT() {
            vm_pop_type(); let bi: i32 = vm_pop_ival();
            vm_pop_type(); let ai: i32 = vm_pop_ival();
            if ai < bi { vm_push_bool(1); } else { vm_push_bool(0); }
        } else if op == OP_GT() {
            vm_pop_type(); let bi: i32 = vm_pop_ival();
            vm_pop_type(); let ai: i32 = vm_pop_ival();
            if ai > bi { vm_push_bool(1); } else { vm_push_bool(0); }
        } else if op == OP_LTE() {
            vm_pop_type(); let bi: i32 = vm_pop_ival();
            vm_pop_type(); let ai: i32 = vm_pop_ival();
            if ai <= bi { vm_push_bool(1); } else { vm_push_bool(0); }
        } else if op == OP_GTE() {
            vm_pop_type(); let bi: i32 = vm_pop_ival();
            vm_pop_type(); let ai: i32 = vm_pop_ival();
            if ai >= bi { vm_push_bool(1); } else { vm_push_bool(0); }
        } else if op == OP_NOT() {
            vm_pop_type(); let ai: i32 = vm_pop_ival();
            if ai == 0 { vm_push_bool(1); } else { vm_push_bool(0); }
        } else if op == OP_JUMP() {
            let offset: i32 = read_i16_vm();
            let cur_ip: i32 = array_get(frame_ip, frame_count - 1);
            array_set(frame_ip, frame_count - 1, cur_ip + offset);
        } else if op == OP_JUMP_FALSE() {
            let offset: i32 = read_i16_vm();
            vm_pop_type(); let cond: i32 = vm_pop_ival();
            if cond == 0 {
                let cur_ip: i32 = array_get(frame_ip, frame_count - 1);
                array_set(frame_ip, frame_count - 1, cur_ip + offset);
            }
        } else if op == OP_CALL() {
            let argc: i32 = read_u16_vm();
            let callee: i32 = array_get(vm_ivals, vm_top - 1 - argc);

            // Shift args down over callee
            var k: i32 = 0;
            while k < argc {
                let si: i32 = vm_top - argc + k;
                let di: i32 = vm_top - 1 - argc + k;
                vm_set_slot(di, array_get(vm_types, si), array_get(vm_ivals, si), array_get(vm_svals, si));
                k = k + 1;
            }
            vm_top = vm_top - 1;

            if frame_count < array_len(frame_func) {
                array_set(frame_func, frame_count, callee);
                array_set(frame_ip, frame_count, 0);
                array_set(frame_base, frame_count, vm_top - argc);
            } else {
                array_push(frame_func, callee);
                array_push(frame_ip, 0);
                array_push(frame_base, vm_top - argc);
            }
            frame_count = frame_count + 1;

            let target_locals: i32 = array_get(mod_locals, callee);
            let extra: i32 = target_locals - argc;
            var el: i32 = 0;
            while el < extra { vm_push_void(); el = el + 1; }
        } else if op == OP_RETURN() {
            let rt: i32 = vm_pop_type();
            let riv: i32 = vm_pop_ival();
            let rsv: string = vm_pop_sval();
            frame_count = frame_count - 1;
            if frame_count == 0 {
                if rt == VT_INT() || rt == VT_BOOL() { vm_push_int(riv); }
                else if rt == VT_STR() { vm_push_str(rsv); }
                else { vm_push_int(riv); }
                return riv;
            }
            let prev_base: i32 = array_get(frame_base, frame_count);
            vm_top = prev_base;
            if rt == VT_INT() { vm_push_int(riv); }
            else if rt == VT_STR() { vm_push_str(rsv); }
            else if rt == VT_BOOL() { vm_push_bool(riv); }
            else if rt == VT_ARR() { vm_push_arr(riv); }
            else { vm_push_void(); }
        } else if op == OP_PRINT() {
            let pt: i32 = vm_pop_type();
            let piv: i32 = vm_pop_ival();
            let psv: string = vm_pop_sval();
            if pt == VT_STR() {
                vm_output = str_concat(vm_output, psv);
            } else if pt == VT_INT() {
                vm_output = str_concat(vm_output, int_to_str(piv));
            } else if pt == VT_BOOL() {
                if piv != 0 { vm_output = str_concat(vm_output, "true"); }
                else { vm_output = str_concat(vm_output, "false"); }
            }

        // ── String built-ins ─────────────────────────
        } else if op == OP_BUILTIN_LEN() {
            vm_pop_type();
            let sv: string = vm_pop_sval();
            vm_push_int(len(sv));
        } else if op == OP_BUILTIN_CHAR_AT() {
            vm_pop_type(); let idx_v: i32 = vm_pop_ival();
            vm_pop_type(); let sv: string = vm_pop_sval();
            vm_push_int(char_at(sv, idx_v));
        } else if op == OP_BUILTIN_SUBSTR() {
            vm_pop_type(); let slen: i32 = vm_pop_ival();
            vm_pop_type(); let start: i32 = vm_pop_ival();
            vm_pop_type(); let sv: string = vm_pop_sval();
            vm_push_str(substr(sv, start, slen));
        } else if op == OP_BUILTIN_STR_CONCAT() {
            vm_pop_type(); let bsv: string = vm_pop_sval();
            vm_pop_type(); let asv: string = vm_pop_sval();
            vm_push_str(str_concat(asv, bsv));
        } else if op == OP_BUILTIN_INT_TO_STR() {
            vm_pop_type(); let iv: i32 = vm_pop_ival();
            vm_push_str(int_to_str(iv));
        } else if op == OP_BUILTIN_STR_EQ() {
            vm_pop_type(); let bsv: string = vm_pop_sval();
            vm_pop_type(); let asv: string = vm_pop_sval();
            if str_eq(asv, bsv) { vm_push_bool(1); }
            else { vm_push_bool(0); }
        } else if op == OP_BUILTIN_READ_FILE() {
            vm_pop_type(); let path: string = vm_pop_sval();
            vm_push_str(read_file(path));
        } else if op == OP_BUILTIN_CHAR_TO_STR() {
            vm_pop_type(); let cv: i32 = vm_pop_ival();
            vm_push_str(char_to_str(cv));

        // ── Array built-ins ──────────────────────────
        } else if op == OP_ARRAY_NEW() {
            vm_pop_type(); // pop capacity hint (not used)
            let handle: i32 = arr_new();
            vm_push_arr(handle);
        } else if op == OP_ARRAY_GET() {
            vm_pop_type(); let idx_v: i32 = vm_pop_ival();
            vm_pop_type(); let handle: i32 = vm_pop_ival();
            let et: i32 = array_get(array_get(arr_types_store, handle), idx_v);
            let eiv: i32 = array_get(array_get(arr_ivals_store, handle), idx_v);
            let esv: string = array_get(array_get(arr_svals_store, handle), idx_v);
            if et == VT_INT() { vm_push_int(eiv); }
            else if et == VT_STR() { vm_push_str(esv); }
            else if et == VT_BOOL() { vm_push_bool(eiv); }
            else if et == VT_ARR() { vm_push_arr(eiv); }
            else { vm_push_void(); }
        } else if op == OP_ARRAY_SET() {
            let vt: i32 = vm_pop_type();
            let viv: i32 = vm_pop_ival();
            let vsv: string = vm_pop_sval();
            vm_pop_type(); let idx_v: i32 = vm_pop_ival();
            vm_pop_type(); let handle: i32 = vm_pop_ival();
            array_set(array_get(arr_types_store, handle), idx_v, vt);
            array_set(array_get(arr_ivals_store, handle), idx_v, viv);
            array_set(array_get(arr_svals_store, handle), idx_v, vsv);
        } else if op == OP_ARRAY_LEN() {
            vm_pop_type(); let handle: i32 = vm_pop_ival();
            vm_push_int(array_len(array_get(arr_types_store, handle)));
        } else if op == OP_ARRAY_PUSH() {
            let vt: i32 = vm_pop_type();
            let viv: i32 = vm_pop_ival();
            let vsv: string = vm_pop_sval();
            vm_pop_type(); let handle: i32 = vm_pop_ival();
            array_push(array_get(arr_types_store, handle), vt);
            array_push(array_get(arr_ivals_store, handle), viv);
            array_push(array_get(arr_svals_store, handle), vsv);
        } else {
            return 0 - 1;
        }
    }
    return 0;
}

// ── Run program ──────────────────────────────────────

fn vm_run_program() -> i32 {
    let init_fi: i32 = find_func("__init");
    if init_fi >= 0 {
        vm_run_func(init_fi, 0);
        vm_top = 0;
        frame_count = 0;
    }
    let main_fi: i32 = find_func("main");
    if main_fi < 0 {
        vm_output = str_concat(vm_output, "ERROR: no main() found\n");
        return 0 - 1;
    }
    return vm_run_func(main_fi, 0);
}

// ══════════════════════════════════════════════════════
// ── TESTS ────────────────────────────────────────────
// ══════════════════════════════════════════════════════

var tests_passed: i32 = 0;
var tests_run: i32 = 0;

fn run_test(src: string, expected_ret: i32, expected_out: string, label: string) -> i32 {
    tests_run = tests_run + 1;

    // Reset everything
    init_ast();
    init_codegen();
    init_vm();

    // Frontend: tokenize + parse
    tokenize(src);
    let root: i32 = parse_program();

    // Backend: compile to bytecode
    compile_program(root);

    // Execute
    let ret: i32 = vm_run_program();

    var ok: i32 = 1;
    if ret != expected_ret { ok = 0; }
    if len(expected_out) > 0 && !str_eq(vm_output, expected_out) { ok = 0; }

    if ok == 1 {
        tests_passed = tests_passed + 1;
        print("  OK  ");
    } else {
        print("  FAIL ");
        print("ret=");
        print(ret);
        print(" expected=");
        print(expected_ret);
        if len(expected_out) > 0 {
            print(" out='");
            print(vm_output);
            print("' expected='");
            print(expected_out);
            print("'");
        }
        print("  ");
    }
    println(label);
    return ok;
}

fn run_file_test(path: string, expected_ret: i32, expected_out: string, label: string) -> i32 {
    tests_run = tests_run + 1;
    let src: string = read_file(path);

    init_ast();
    init_codegen();
    init_vm();

    tokenize(src);
    let root: i32 = parse_program();
    compile_program(root);
    let ret: i32 = vm_run_program();

    var ok: i32 = 1;
    if ret != expected_ret { ok = 0; }
    if len(expected_out) > 0 && !str_eq(vm_output, expected_out) { ok = 0; }

    if ok == 1 {
        tests_passed = tests_passed + 1;
        print("  OK  ");
    } else {
        print("  FAIL ");
        print("ret=");
        print(ret);
        print(" expected=");
        print(expected_ret);
        if len(expected_out) > 0 {
            print(" out='");
            print(vm_output);
            print("' expected='");
            print(expected_out);
            print("'");
        }
        print("  ");
    }
    println(label);
    return ok;
}

fn main() -> i32 {
    println("=== M Bytecode Compiler ===");
    println("tokenize -> parse -> compile -> run bytecode");
    println("");

    // Basic returns
    run_test("fn main() -> i32 { return 42; }", 42, "", "return 42");
    run_test("fn main() -> i32 { return 0; }", 0, "", "return 0");

    // Arithmetic
    run_test("fn main() -> i32 { return 2 + 3; }", 5, "", "2 + 3");
    run_test("fn main() -> i32 { return 10 - 4; }", 6, "", "10 - 4");
    run_test("fn main() -> i32 { return 3 * 7; }", 21, "", "3 * 7");
    run_test("fn main() -> i32 { return 20 / 4; }", 5, "", "20 / 4");
    run_test("fn main() -> i32 { return 2 + 3 * 4; }", 14, "", "precedence: 2+3*4");
    run_test("fn main() -> i32 { return (2 + 3) * 4; }", 20, "", "parens: (2+3)*4");

    // Variables
    run_test("fn main() -> i32 { let x: i32 = 10; return x; }", 10, "", "let x = 10");
    run_test("fn main() -> i32 { var x: i32 = 5; x = x + 1; return x; }", 6, "", "var mutation");

    // If/else
    run_test("fn main() -> i32 { if 1 == 1 { return 10; } return 20; }", 10, "", "if true");
    run_test("fn main() -> i32 { if 1 == 2 { return 10; } return 20; }", 20, "", "if false");
    run_test("fn main() -> i32 { if 1 > 2 { return 1; } else { return 2; } }", 2, "", "if/else");

    // While
    run_test("fn main() -> i32 { var i: i32 = 0; while i < 10 { i = i + 1; } return i; }", 10, "", "while loop");

    // Functions
    run_test("fn add(a: i32, b: i32) -> i32 { return a + b; } fn main() -> i32 { return add(3, 4); }", 7, "", "fn call");
    run_test("fn fib(n: i32) -> i32 { if n <= 1 { return n; } return fib(n - 1) + fib(n - 2); } fn main() -> i32 { return fib(10); }", 55, "", "fibonacci(10)");

    // Forward calls
    run_test("fn a() -> i32 { return b(); } fn b() -> i32 { return 99; } fn main() -> i32 { return a(); }", 99, "", "forward call");

    // Global variables
    run_test("var g: i32 = 0; fn inc() -> i32 { g = g + 1; return g; } fn main() -> i32 { inc(); inc(); inc(); return g; }", 3, "", "global var");

    // Boolean logic
    run_test("fn main() -> i32 { if true && true { return 1; } return 0; }", 1, "", "&& true");
    run_test("fn main() -> i32 { if true && false { return 1; } return 0; }", 0, "", "&& false");
    run_test("fn main() -> i32 { if false || true { return 1; } return 0; }", 1, "", "|| true");

    // Print output
    run_test("fn main() -> i32 { print(42); return 0; }", 0, "42", "print int");
    run_test("fn main() -> i32 { println(\"hello\"); return 0; }", 0, "hello\n", "println str");

    // Comparison
    run_test("fn main() -> i32 { if 5 >= 5 { return 1; } return 0; }", 1, "", ">=");
    run_test("fn main() -> i32 { if 3 != 4 { return 1; } return 0; }", 1, "", "!=");

    // Negation
    run_test("fn main() -> i32 { return 0 - 42; }", 0 - 42, "", "negation");

    // Nested function calls
    run_test("fn double(x: i32) -> i32 { return x * 2; } fn main() -> i32 { return double(double(5)); }", 20, "", "nested calls");

    // Modulo
    run_test("fn main() -> i32 { return 17 % 5; }", 2, "", "modulo");

    // ── String built-ins ─────────────────────────
    run_test("fn main() -> i32 { return len(\"hello\"); }", 5, "", "len str");
    run_test("fn main() -> i32 { return char_at(\"abc\", 1); }", 98, "", "char_at");
    run_test("fn main() -> i32 { print(substr(\"hello\", 1, 3)); return 0; }", 0, "ell", "substr");
    run_test("fn main() -> i32 { print(str_concat(\"ab\", \"cd\")); return 0; }", 0, "abcd", "str_concat");
    run_test("fn main() -> i32 { print(int_to_str(42)); return 0; }", 0, "42", "int_to_str");
    run_test("fn main() -> i32 { if str_eq(\"ab\", \"ab\") { return 1; } return 0; }", 1, "", "str_eq true");
    run_test("fn main() -> i32 { if str_eq(\"ab\", \"cd\") { return 1; } return 0; }", 0, "", "str_eq false");
    run_test("fn main() -> i32 { print(char_to_str(65)); return 0; }", 0, "A", "char_to_str");

    // ── Array built-ins ──────────────────────────
    run_test("fn main() -> i32 { let a: i32 = array_new(0); return array_len(a); }", 0, "", "array new+len");
    run_test("fn main() -> i32 { let a: i32 = array_new(0); array_push(a, 42); return array_get(a, 0); }", 42, "", "array push+get");
    run_test("fn main() -> i32 { let a: i32 = array_new(0); array_push(a, 10); array_push(a, 20); array_push(a, 30); return array_len(a); }", 3, "", "array multi push");
    run_test("fn main() -> i32 { let a: i32 = array_new(0); array_push(a, 1); array_set(a, 0, 99); return array_get(a, 0); }", 99, "", "array set");
    run_test("fn main() -> i32 { let a: i32 = array_new(0); array_push(a, 0); array_push(a, 0); var i: i32 = 0; while i < 2 { array_set(a, i, i * 10); i = i + 1; } return array_get(a, 0) + array_get(a, 1); }", 10, "", "array loop");

    // ── Mixed types in arrays ────────────────────
    run_test("fn main() -> i32 { let a: i32 = array_new(0); array_push(a, 42); array_push(a, 7); return array_get(a, 0) + array_get(a, 1); }", 49, "", "array sum");

    // ── String in array ──────────────────────────
    run_test("fn main() -> i32 { let a: i32 = array_new(0); array_push(a, \"hello\"); print(array_get(a, 0)); return 0; }", 0, "hello", "array str push+get");

    // ── Nested arrays ────────────────────────────
    run_test("fn main() -> i32 { let outer: i32 = array_new(0); let inner: i32 = array_new(0); array_push(inner, 77); array_push(outer, inner); let got: i32 = array_get(outer, 0); return array_get(got, 0); }", 77, "", "nested array");

    // ── Integration: symbol table ────────────────
    run_test("fn lookup(names: i32, vals: i32, key: string) -> i32 { var i: i32 = 0; while i < array_len(names) { if str_eq(array_get(names, i), key) { return array_get(vals, i); } i = i + 1; } return 0 - 1; } fn main() -> i32 { let n: i32 = array_new(0); let v: i32 = array_new(0); array_push(n, \"x\"); array_push(v, 10); array_push(n, \"y\"); array_push(v, 20); array_push(n, \"z\"); array_push(v, 30); return lookup(n, v, \"y\"); }", 20, "", "symbol table lookup");

    // ── Integration: string builder ──────────────
    run_test("fn main() -> i32 { var s: string = \"\"; var i: i32 = 0; while i < 5 { s = str_concat(s, int_to_str(i)); if i < 4 { s = str_concat(s, \",\"); } i = i + 1; } print(s); return 0; }", 0, "0,1,2,3,4", "string builder");

    // ── Integration: not + built-in ──────────────
    run_test("fn main() -> i32 { if !str_eq(\"a\", \"b\") { return 1; } return 0; }", 1, "", "not str_eq");

    // ── Integration: array compute ───────────────
    run_test("fn main() -> i32 { let a: i32 = array_new(0); var i: i32 = 0; while i < 5 { array_push(a, i * i); i = i + 1; } var sum: i32 = 0; i = 0; while i < array_len(a) { sum = sum + array_get(a, i); i = i + 1; } return sum; }", 30, "", "array compute sum");

    // ── Integration: string + array + function ───
    run_test("fn join(arr: i32, sep: string) -> string { var r: string = \"\"; var i: i32 = 0; while i < array_len(arr) { if i > 0 { r = str_concat(r, sep); } r = str_concat(r, array_get(arr, i)); i = i + 1; } return r; } fn main() -> i32 { let a: i32 = array_new(0); array_push(a, \"fn\"); array_push(a, \"main\"); array_push(a, \"()\"); print(join(a, \" \")); return 0; }", 0, "fn main ()", "join function");

    // ── Integration: mini tokenizer ──────────────
    run_test("fn main() -> i32 { let s: string = \"x = 42\"; let toks: i32 = array_new(0); var i: i32 = 0; while i < len(s) { let c: i32 = char_at(s, i); if c == 32 { i = i + 1; } else if c >= 48 && c <= 57 { var n: string = \"\"; while i < len(s) && char_at(s, i) >= 48 && char_at(s, i) <= 57 { n = str_concat(n, char_to_str(char_at(s, i))); i = i + 1; } array_push(toks, n); } else if c >= 97 && c <= 122 { var w: string = \"\"; while i < len(s) && char_at(s, i) >= 97 && char_at(s, i) <= 122 { w = str_concat(w, char_to_str(char_at(s, i))); i = i + 1; } array_push(toks, w); } else { array_push(toks, char_to_str(c)); i = i + 1; } } var out: string = \"\"; i = 0; while i < array_len(toks) { if i > 0 { out = str_concat(out, \"|\"); } out = str_concat(out, array_get(toks, i)); i = i + 1; } print(out); return array_len(toks); }", 3, "x|=|42", "mini tokenizer");

    // ── Integration: global string var ───────────
    run_test("var buf: string = \"\"; fn emit(s: string) -> i32 { buf = str_concat(buf, s); return 0; } fn main() -> i32 { emit(\"hello\"); emit(\" \"); emit(\"world\"); print(buf); return len(buf); }", 11, "hello world", "global string emit");

    // ── File compilation ─────────────────────────
    run_file_test("examples/test_medium.m", 10, "10|20|0,1,2,3,4|3|600|hello machine\n", "file: medium program");

    // ── Self-compilation: compile ───────────────
    tests_run = tests_run + 1;
    let self_src: string = read_file("examples/self_codegen.m");
    init_ast();
    init_codegen();
    tokenize(self_src);
    let self_toks: i32 = tok_count;
    let self_root: i32 = parse_program();
    let self_nodes: i32 = node_count;
    compile_program(self_root);
    let self_funcs: i32 = mod_count;

    // Verify compilation output
    var self_ok: i32 = 1;
    if self_funcs < 50 { self_ok = 0; }
    if self_toks < 5000 { self_ok = 0; }
    if self_nodes < 3000 { self_ok = 0; }
    if find_func("main") < 0 { self_ok = 0; }
    if find_func("tokenize") < 0 { self_ok = 0; }
    if find_func("compile_program") < 0 { self_ok = 0; }
    if find_func("vm_run_func") < 0 { self_ok = 0; }

    if self_ok == 1 {
        tests_passed = tests_passed + 1;
        print("  OK  ");
        print(int_to_str(self_funcs));
        print(" funcs, ");
        print(int_to_str(self_toks));
        print(" toks, ");
        print(int_to_str(self_nodes));
        print(" nodes  ");
    } else {
        print("  FAIL ");
        print(int_to_str(self_funcs));
        print(" funcs  ");
    }
    println("self-compile (M compiles M)");

    // ── Self-compilation: run compiled functions ─
    // Proves compiled-by-M bytecode executes correctly.
    // Cannot run main() (infinite recursion), but CAN run individual functions.
    tests_run = tests_run + 1;
    init_vm();
    var run_ok: i32 = 1;

    // Test 1: is_digit(48) == 1  (48 = '0')
    let is_digit_fi: i32 = find_func("is_digit");
    if is_digit_fi >= 0 {
        vm_push_int(48);
        let r1: i32 = vm_run_func(is_digit_fi, 1);
        if r1 != 1 { run_ok = 0; }
        // Reset for next call
        vm_top = 0;
        frame_count = 0;
    } else { run_ok = 0; }

    // Test 2: is_digit(65) == 0  (65 = 'A')
    if is_digit_fi >= 0 {
        vm_push_int(65);
        let r2: i32 = vm_run_func(is_digit_fi, 1);
        if r2 != 0 { run_ok = 0; }
        vm_top = 0;
        frame_count = 0;
    }

    // Test 3: is_alpha(65) == 1  (65 = 'A')
    let is_alpha_fi: i32 = find_func("is_alpha");
    if is_alpha_fi >= 0 {
        vm_push_int(65);
        let r3: i32 = vm_run_func(is_alpha_fi, 1);
        if r3 != 1 { run_ok = 0; }
        vm_top = 0;
        frame_count = 0;
    } else { run_ok = 0; }

    // Test 4: is_space(32) == 1  (32 = ' ')
    let is_space_fi: i32 = find_func("is_space");
    if is_space_fi >= 0 {
        vm_push_int(32);
        let r4: i32 = vm_run_func(is_space_fi, 1);
        if r4 != 1 { run_ok = 0; }
        vm_top = 0;
        frame_count = 0;
    } else { run_ok = 0; }

    // Test 5: parse_num_str("42") == 42
    let parse_num_fi: i32 = find_func("parse_num_str");
    if parse_num_fi >= 0 {
        vm_push_str("42");
        let r5: i32 = vm_run_func(parse_num_fi, 1);
        if r5 != 42 { run_ok = 0; }
        vm_top = 0;
        frame_count = 0;
    } else { run_ok = 0; }

    // Test 6: parse_num_str("100") == 100
    if parse_num_fi >= 0 {
        vm_push_str("100");
        let r6: i32 = vm_run_func(parse_num_fi, 1);
        if r6 != 100 { run_ok = 0; }
        vm_top = 0;
        frame_count = 0;
    }

    // Test 7: is_alnum(65) == 1  (calls is_alpha + is_digit — cross-function)
    let is_alnum_fi: i32 = find_func("is_alnum");
    if is_alnum_fi >= 0 {
        vm_push_int(65);
        let r7: i32 = vm_run_func(is_alnum_fi, 1);
        if r7 != 1 { run_ok = 0; }
        vm_top = 0;
        frame_count = 0;
    } else { run_ok = 0; }

    // Test 8: is_alnum(32) == 0  (space is not alnum)
    if is_alnum_fi >= 0 {
        vm_push_int(32);
        let r8: i32 = vm_run_func(is_alnum_fi, 1);
        if r8 != 0 { run_ok = 0; }
        vm_top = 0;
        frame_count = 0;
    }

    // Test 9: Run __init (global variable initializers)
    let init_fi2: i32 = find_func("__init");
    if init_fi2 >= 0 {
        vm_run_func(init_fi2, 0);
        vm_top = 0;
        frame_count = 0;
    }

    // Test 10: After __init, call tokenize on a small program
    let tokenize_fi: i32 = find_func("tokenize");
    if tokenize_fi >= 0 {
        vm_push_str("fn main() -> i32 { return 42; }");
        let r10: i32 = vm_run_func(tokenize_fi, 1);
        // tokenize returns token count — should be > 8
        if r10 < 8 { run_ok = 0; }
        vm_top = 0;
        frame_count = 0;
    } else { run_ok = 0; }

    if run_ok == 1 {
        tests_passed = tests_passed + 1;
        println("  OK  self-run (10 funcs from compiled bytecode)");
    } else {
        println("  FAIL self-run");
    }

    // ── Self-compilation: full pipeline test ─────
    // M-compiled tokenizer + parser + compiler processing a small program.
    // This proves the ENTIRE pipeline works when compiled by M.
    tests_run = tests_run + 1;
    var pipe_ok: i32 = 1;

    // Reset compiler state via compiled __init + init functions
    init_vm();
    let init_fi3: i32 = find_func("__init");
    if init_fi3 >= 0 {
        vm_run_func(init_fi3, 0);
        vm_top = 0;
        frame_count = 0;
    }

    // Step 1: Run compiled init_ast()
    let init_ast_fi: i32 = find_func("init_ast");
    if init_ast_fi >= 0 {
        vm_run_func(init_ast_fi, 0);
        vm_top = 0;
        frame_count = 0;
    } else { pipe_ok = 0; }

    // Step 2: Run compiled init_codegen()
    let init_cg_fi: i32 = find_func("init_codegen");
    if init_cg_fi >= 0 {
        vm_run_func(init_cg_fi, 0);
        vm_top = 0;
        frame_count = 0;
    } else { pipe_ok = 0; }

    // Step 3: Run compiled tokenize("fn main() -> i32 { return 7 * 6; }")
    let tok_fi2: i32 = find_func("tokenize");
    if tok_fi2 >= 0 {
        vm_push_str("fn main() -> i32 { return 7 * 6; }");
        let ntoks: i32 = vm_run_func(tok_fi2, 1);
        if ntoks < 10 { pipe_ok = 0; }
        vm_top = 0;
        frame_count = 0;
    } else { pipe_ok = 0; }

    // Step 4: Run compiled parse_program()
    let parse_fi: i32 = find_func("parse_program");
    if parse_fi >= 0 {
        let root2: i32 = vm_run_func(parse_fi, 0);
        if root2 < 0 { pipe_ok = 0; }
        vm_top = 0;
        frame_count = 0;

        // Step 5: Run compiled compile_program(root)
        let comp_fi: i32 = find_func("compile_program");
        if comp_fi >= 0 {
            vm_push_int(root2);
            vm_run_func(comp_fi, 1);
            vm_top = 0;
            frame_count = 0;

            // Step 6: Run compiled init_vm()
            let init_vm_fi: i32 = find_func("init_vm");
            if init_vm_fi >= 0 {
                vm_run_func(init_vm_fi, 0);
                vm_top = 0;
                frame_count = 0;
            }

            // Step 7: Run compiled vm_run_program()
            let run_prog_fi: i32 = find_func("vm_run_program");
            if run_prog_fi >= 0 {
                let pipe_ret: i32 = vm_run_func(run_prog_fi, 0);
                if pipe_ret != 42 { pipe_ok = 0; }
                vm_top = 0;
                frame_count = 0;
            } else { pipe_ok = 0; }
        } else { pipe_ok = 0; }
    } else { pipe_ok = 0; }

    if pipe_ok == 1 {
        tests_passed = tests_passed + 1;
        println("  OK  self-pipeline (M-compiled compiler processes 7*6=42)");
    } else {
        println("  FAIL self-pipeline");
    }

    println("");
    print(tests_passed);
    print("/");
    print(tests_run);
    println(" tests passed");

    if tests_passed == tests_run {
        println("");
        println("M compiles M. The circle closes.");
    }

    return 0;
}
