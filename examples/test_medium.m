// Medium complexity test for M VM validation
// Uses: functions, arrays, strings, globals, loops, conditionals

var counter: i32 = 0;

fn inc() -> i32 {
    counter = counter + 1;
    return counter;
}

fn make_range(n: i32) -> i32 {
    let arr: i32 = array_new(0);
    var i: i32 = 0;
    while i < n {
        array_push(arr, i);
        i = i + 1;
    }
    return arr;
}

fn sum(arr: i32) -> i32 {
    var s: i32 = 0;
    var i: i32 = 0;
    while i < array_len(arr) {
        s = s + array_get(arr, i);
        i = i + 1;
    }
    return s;
}

fn map_double(arr: i32) -> i32 {
    let result: i32 = array_new(0);
    var i: i32 = 0;
    while i < array_len(arr) {
        array_push(result, array_get(arr, i) * 2);
        i = i + 1;
    }
    return result;
}

fn join_ints(arr: i32, sep: string) -> string {
    var r: string = "";
    var i: i32 = 0;
    while i < array_len(arr) {
        if i > 0 { r = str_concat(r, sep); }
        r = str_concat(r, int_to_str(array_get(arr, i)));
        i = i + 1;
    }
    return r;
}

fn lookup(names: i32, vals: i32, key: string) -> i32 {
    var i: i32 = 0;
    while i < array_len(names) {
        if str_eq(array_get(names, i), key) {
            return array_get(vals, i);
        }
        i = i + 1;
    }
    return 0 - 1;
}

fn main() -> i32 {
    // Range + sum: 0+1+2+3+4 = 10
    let r: i32 = make_range(5);
    let s: i32 = sum(r);
    print(int_to_str(s));
    print("|");

    // Map + sum: 0+2+4+6+8 = 20
    let doubled: i32 = map_double(r);
    print(int_to_str(sum(doubled)));
    print("|");

    // Join: "0,1,2,3,4"
    print(join_ints(r, ","));
    print("|");

    // Global counter: 3
    inc();
    inc();
    inc();
    print(int_to_str(counter));
    print("|");

    // Symbol table lookup
    let names: i32 = array_new(0);
    let vals: i32 = array_new(0);
    array_push(names, "width");
    array_push(vals, 800);
    array_push(names, "height");
    array_push(vals, 600);
    let h: i32 = lookup(names, vals, "height");
    print(int_to_str(h));
    print("|");

    // String building
    let greeting: string = str_concat("hello", " ");
    let full: string = str_concat(greeting, "machine");
    print(full);

    println("");
    return s;
}
