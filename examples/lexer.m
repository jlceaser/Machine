// M lexer written in M — keyword recognition + token classification
// Self-hosting step: M can now understand M syntax

fn is_digit(c: i32) -> bool {
    return c >= 48 && c <= 57;
}

fn is_alpha(c: i32) -> bool {
    if c >= 65 && c <= 90 { return true; }
    if c >= 97 && c <= 122 { return true; }
    return c == 95;
}

fn is_alnum(c: i32) -> bool {
    return is_alpha(c) || is_digit(c);
}

fn is_space(c: i32) -> bool {
    return c == 32 || c == 10 || c == 13 || c == 9;
}

fn is_keyword(word: string) -> bool {
    if str_eq(word, "fn") { return true; }
    if str_eq(word, "let") { return true; }
    if str_eq(word, "var") { return true; }
    if str_eq(word, "if") { return true; }
    if str_eq(word, "else") { return true; }
    if str_eq(word, "while") { return true; }
    if str_eq(word, "return") { return true; }
    if str_eq(word, "true") { return true; }
    if str_eq(word, "false") { return true; }
    if str_eq(word, "struct") { return true; }
    if str_eq(word, "i32") { return true; }
    if str_eq(word, "i64") { return true; }
    if str_eq(word, "f64") { return true; }
    if str_eq(word, "bool") { return true; }
    if str_eq(word, "string") { return true; }
    if str_eq(word, "ptr") { return true; }
    if str_eq(word, "free") { return true; }
    return false;
}

fn lex(src: string) -> i32 {
    var pos: i32 = 0;
    var tokens: i32 = 0;

    while pos < len(src) {
        let c: i32 = char_at(src, pos);

        // Skip whitespace
        if is_space(c) {
            pos = pos + 1;
        } else if is_digit(c) {
            // Number literal
            var end: i32 = pos + 1;
            while end < len(src) && is_digit(char_at(src, end)) {
                end = end + 1;
            }
            let tok: string = substr(src, pos, end - pos);
            print("  NUM    ");
            println(tok);
            tokens = tokens + 1;
            pos = end;
        } else if is_alpha(c) {
            // Identifier or keyword
            var end: i32 = pos + 1;
            while end < len(src) && is_alnum(char_at(src, end)) {
                end = end + 1;
            }
            let tok: string = substr(src, pos, end - pos);
            if is_keyword(tok) {
                print("  KW     ");
            } else {
                print("  IDENT  ");
            }
            println(tok);
            tokens = tokens + 1;
            pos = end;
        } else {
            // Operator or punctuation
            var consumed: i32 = 1;
            if pos + 1 < len(src) {
                let c2: i32 = char_at(src, pos + 1);
                if c == 61 && c2 == 61 { consumed = 2; }
                if c == 33 && c2 == 61 { consumed = 2; }
                if c == 60 && c2 == 61 { consumed = 2; }
                if c == 62 && c2 == 61 { consumed = 2; }
                if c == 45 && c2 == 62 { consumed = 2; }
                if c == 38 && c2 == 38 { consumed = 2; }
                if c == 124 && c2 == 124 { consumed = 2; }
            }
            let tok: string = substr(src, pos, consumed);
            print("  OP     ");
            println(tok);
            tokens = tokens + 1;
            pos = pos + consumed;
        }
    }

    return tokens;
}

fn main() -> i32 {
    println("=== M Lexer (written in M) ===");
    println("");
    let code: string = "fn fib(n: i32) -> i32 { if n <= 1 { return n; } return fib(n - 1) + fib(n - 2); }";
    print("source: ");
    println(code);
    println("");
    let count: i32 = lex(code);
    println("");
    print("Total tokens: ");
    println(count);
    return 0;
}
