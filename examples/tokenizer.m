// M tokenizer written in M
// First real step toward self-hosting

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

fn scan_token(src: string, pos: i32) -> i32 {
    // Returns number of characters consumed
    let c: i32 = char_at(src, pos);

    // Whitespace
    if is_space(c) {
        var n: i32 = 1;
        while pos + n < len(src) && is_space(char_at(src, pos + n)) {
            n = n + 1;
        }
        return n;
    }

    // Number
    if is_digit(c) {
        var n: i32 = 1;
        while pos + n < len(src) && is_digit(char_at(src, pos + n)) {
            n = n + 1;
        }
        return n;
    }

    // Identifier or keyword
    if is_alpha(c) {
        var n: i32 = 1;
        while pos + n < len(src) && is_alnum(char_at(src, pos + n)) {
            n = n + 1;
        }
        return n;
    }

    // Two-character operators: == != <= >= -> &&  ||
    if pos + 1 < len(src) {
        let c2: i32 = char_at(src, pos + 1);
        if c == 61 && c2 == 61 { return 2; }
        if c == 33 && c2 == 61 { return 2; }
        if c == 60 && c2 == 61 { return 2; }
        if c == 62 && c2 == 61 { return 2; }
        if c == 45 && c2 == 62 { return 2; }
        if c == 38 && c2 == 38 { return 2; }
        if c == 124 && c2 == 124 { return 2; }
    }

    // Single character
    return 1;
}

fn is_whitespace_token(src: string, pos: i32) -> bool {
    return is_space(char_at(src, pos));
}

fn tokenize(src: string) -> i32 {
    var pos: i32 = 0;
    var tokens: i32 = 0;

    while pos < len(src) {
        let consumed: i32 = scan_token(src, pos);

        if !is_whitespace_token(src, pos) {
            tokens = tokens + 1;
            // Print token
            let tok: string = substr(src, pos, consumed);
            print("[");
            print(tok);
            print("] ");
        }

        pos = pos + consumed;
    }

    println("");
    return tokens;
}

fn main() -> i32 {
    let code: string = "fn fib(n: i32) -> i32 { return n + 1; }";
    print("source: ");
    println(code);
    print("tokens: ");
    let count: i32 = tokenize(code);
    print("total: ");
    println(count);
    return 0;
}
