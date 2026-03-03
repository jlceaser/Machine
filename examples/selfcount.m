// Count tokens in a simple expression
// First step toward self-hosting: M understanding M

fn is_digit(c: i32) -> bool {
    return c >= 48 && c <= 57;
}

fn is_alpha(c: i32) -> bool {
    if c >= 65 && c <= 90  { return true; }
    if c >= 97 && c <= 122 { return true; }
    if c == 95 { return true; }
    return false;
}

fn is_space(c: i32) -> bool {
    if c == 32 { return true; }
    if c == 10 { return true; }
    if c == 13 { return true; }
    if c == 9  { return true; }
    return false;
}

fn count_tokens(len: i32) -> i32 {
    // simulate scanning: count how many tokens
    // in a hypothetical stream of len characters
    var tokens: i32 = 0;
    var i: i32 = 0;
    while i < len {
        // skip spaces
        if is_space(i % 4 + 9) {
            i = i + 1;
        } else if is_digit(i % 10 + 48) {
            tokens = tokens + 1;
            // consume all digits
            while i < len && is_digit(i % 10 + 48) {
                i = i + 1;
            }
        } else if is_alpha(i % 26 + 97) {
            tokens = tokens + 1;
            while i < len && is_alpha(i % 26 + 97) {
                i = i + 1;
            }
        } else {
            tokens = tokens + 1;
            i = i + 1;
        }
    }
    return tokens;
}

fn main() -> i32 {
    let result: i32 = count_tokens(100);
    print("tokens in 100 chars: ");
    println(result);
    return 0;
}
