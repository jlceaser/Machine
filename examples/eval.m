// Expression evaluator written in M
// Parses and evaluates arithmetic: "2 + 3 * 4" -> 14
// Recursive descent with operator precedence

fn is_digit(c: i32) -> bool { return c >= 48 && c <= 57; }
fn is_space(c: i32) -> bool { return c == 32 || c == 9; }

// Token types
fn T_NUM() -> i32 { return 1; }
fn T_PLUS() -> i32 { return 2; }
fn T_MINUS() -> i32 { return 3; }
fn T_STAR() -> i32 { return 4; }
fn T_SLASH() -> i32 { return 5; }
fn T_LPAREN() -> i32 { return 6; }
fn T_RPAREN() -> i32 { return 7; }
fn T_EOF() -> i32 { return 0; }

// Globals via arrays: tok_types[], tok_vals[], tok_count, pos
var g_types: i32 = 0;
var g_vals: i32 = 0;
var g_count: i32 = 0;
var g_pos: i32 = 0;

fn tokenize(src: string) -> i32 {
    g_types = array_new(0);
    g_vals = array_new(0);
    var i: i32 = 0;
    while i < len(src) {
        let c: i32 = char_at(src, i);
        if is_space(c) {
            i = i + 1;
        } else if is_digit(c) {
            var n: i32 = 0;
            while i < len(src) && is_digit(char_at(src, i)) {
                n = n * 10 + char_at(src, i) - 48;
                i = i + 1;
            }
            array_push(g_types, T_NUM());
            array_push(g_vals, n);
        } else if c == 43 {
            array_push(g_types, T_PLUS());
            array_push(g_vals, 0);
            i = i + 1;
        } else if c == 45 {
            array_push(g_types, T_MINUS());
            array_push(g_vals, 0);
            i = i + 1;
        } else if c == 42 {
            array_push(g_types, T_STAR());
            array_push(g_vals, 0);
            i = i + 1;
        } else if c == 47 {
            array_push(g_types, T_SLASH());
            array_push(g_vals, 0);
            i = i + 1;
        } else if c == 40 {
            array_push(g_types, T_LPAREN());
            array_push(g_vals, 0);
            i = i + 1;
        } else if c == 41 {
            array_push(g_types, T_RPAREN());
            array_push(g_vals, 0);
            i = i + 1;
        } else {
            i = i + 1;
        }
    }
    array_push(g_types, T_EOF());
    array_push(g_vals, 0);
    g_count = array_len(g_types);
    g_pos = 0;
    return g_count;
}

fn peek() -> i32 {
    if g_pos < g_count {
        return array_get(g_types, g_pos);
    }
    return T_EOF();
}

fn advance() -> i32 {
    let t: i32 = peek();
    g_pos = g_pos + 1;
    return t;
}

fn cur_val() -> i32 {
    if g_pos > 0 {
        return array_get(g_vals, g_pos - 1);
    }
    return 0;
}

// Recursive descent parser with precedence
fn parse_primary() -> i32 {
    let t: i32 = advance();
    if t == T_NUM() {
        return cur_val();
    }
    if t == T_LPAREN() {
        let v: i32 = parse_expr();
        advance(); // consume )
        return v;
    }
    if t == T_MINUS() {
        return 0 - parse_primary();
    }
    return 0;
}

fn parse_factor() -> i32 {
    var left: i32 = parse_primary();
    while peek() == T_STAR() || peek() == T_SLASH() {
        let op: i32 = advance();
        let right: i32 = parse_primary();
        if op == T_STAR() {
            left = left * right;
        } else {
            left = left / right;
        }
    }
    return left;
}

fn parse_expr() -> i32 {
    var left: i32 = parse_factor();
    while peek() == T_PLUS() || peek() == T_MINUS() {
        let op: i32 = advance();
        let right: i32 = parse_factor();
        if op == T_PLUS() {
            left = left + right;
        } else {
            left = left - right;
        }
    }
    return left;
}

fn evaluate(expr: string) -> i32 {
    tokenize(expr);
    g_pos = 0;
    return parse_expr();
}

fn test(expr: string, expected: i32) -> i32 {
    let result: i32 = evaluate(expr);
    print(expr);
    print(" = ");
    print(result);
    if result == expected {
        println("  OK");
        return 1;
    } else {
        print("  FAIL (expected ");
        print(expected);
        println(")");
        return 0;
    }
}

fn main() -> i32 {
    println("=== M Expression Evaluator ===");
    println("");
    var passed: i32 = 0;
    passed = passed + test("42", 42);
    passed = passed + test("2 + 3", 5);
    passed = passed + test("10 - 4", 6);
    passed = passed + test("2 + 3 * 4", 14);
    passed = passed + test("(2 + 3) * 4", 20);
    passed = passed + test("100 / 5 / 4", 5);
    passed = passed + test("1 + 2 + 3 + 4 + 5", 15);
    passed = passed + test("2 * 3 + 4 * 5", 26);
    passed = passed + test("(1 + 2) * (3 + 4)", 21);
    passed = passed + test("10 - 3 - 2", 5);
    println("");
    print(passed);
    println("/10 tests passed");
    return 0;
}
