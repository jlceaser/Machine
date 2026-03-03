// M reads and tokenizes its own source file
// The circle closes: M understands M

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
    return false;
}

fn lex_file(path: string) -> i32 {
    let src: string = read_file(path);
    print("File: ");
    println(path);
    print("Size: ");
    print(len(src));
    println(" bytes");
    println("");

    var pos: i32 = 0;
    var tokens: i32 = 0;
    var keywords: i32 = 0;
    var identifiers: i32 = 0;
    var numbers: i32 = 0;
    var operators: i32 = 0;
    var strings: i32 = 0;
    var lines: i32 = 1;

    while pos < len(src) {
        let c: i32 = char_at(src, pos);

        if is_space(c) {
            if c == 10 { lines = lines + 1; }
            pos = pos + 1;
        } else if c == 47 && pos + 1 < len(src) && char_at(src, pos + 1) == 47 {
            // Line comment
            while pos < len(src) && char_at(src, pos) != 10 {
                pos = pos + 1;
            }
        } else if c == 34 {
            // String literal
            pos = pos + 1;
            while pos < len(src) && char_at(src, pos) != 34 {
                if char_at(src, pos) == 92 { pos = pos + 1; }
                pos = pos + 1;
            }
            if pos < len(src) { pos = pos + 1; }
            strings = strings + 1;
            tokens = tokens + 1;
        } else if is_digit(c) {
            while pos < len(src) && is_digit(char_at(src, pos)) {
                pos = pos + 1;
            }
            numbers = numbers + 1;
            tokens = tokens + 1;
        } else if is_alpha(c) {
            var start: i32 = pos;
            while pos < len(src) && is_alnum(char_at(src, pos)) {
                pos = pos + 1;
            }
            let word: string = substr(src, start, pos - start);
            if is_keyword(word) {
                keywords = keywords + 1;
            } else {
                identifiers = identifiers + 1;
            }
            tokens = tokens + 1;
        } else {
            // Check two-char operators
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
            operators = operators + 1;
            tokens = tokens + 1;
            pos = pos + consumed;
        }
    }

    println("=== Token Summary ===");
    print("  Lines:       ");
    println(lines);
    print("  Tokens:      ");
    println(tokens);
    print("  Keywords:    ");
    println(keywords);
    print("  Identifiers: ");
    println(identifiers);
    print("  Numbers:     ");
    println(numbers);
    print("  Strings:     ");
    println(strings);
    print("  Operators:   ");
    println(operators);
    return tokens;
}

fn main() -> i32 {
    lex_file("examples/self_lex.m");
    return 0;
}
