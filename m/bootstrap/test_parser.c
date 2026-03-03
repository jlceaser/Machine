/*
 * test_parser.c — Verify the M parser builds correct ASTs.
 * Bootstrap test: will be replaced by M-language tests.
 */

#include "parser.h"
#include <stdio.h>
#include <string.h>

static int tests_run = 0;
static int tests_passed = 0;

static void check(int condition, const char *name) {
    tests_run++;
    if (condition) {
        tests_passed++;
    } else {
        printf("  FAIL: %s\n", name);
    }
}

/* ── Expression tests ──────────────────────────────── */

static void test_int_literal(void) {
    Parser p;
    parser_init(&p, "42");
    Expr *e = parser_parse_expr(&p);
    check(!parser_had_error(&p), "int lit: no error");
    check(e != NULL, "int lit: not null");
    check(e->kind == EXPR_INT_LIT, "int lit: kind");
    check(e->int_val == 42, "int lit: value 42");
}

static void test_float_literal(void) {
    Parser p;
    parser_init(&p, "3.14");
    Expr *e = parser_parse_expr(&p);
    check(!parser_had_error(&p), "float lit: no error");
    check(e != NULL, "float lit: not null");
    check(e->kind == EXPR_FLOAT_LIT, "float lit: kind");
    check(e->float_val > 3.13 && e->float_val < 3.15, "float lit: value ~3.14");
}

static void test_string_literal(void) {
    Parser p;
    parser_init(&p, "\"hello\"");
    Expr *e = parser_parse_expr(&p);
    check(!parser_had_error(&p), "string lit: no error");
    check(e != NULL, "string lit: not null");
    check(e->kind == EXPR_STRING_LIT, "string lit: kind");
    check(e->str_len == 5, "string lit: length");
    check(memcmp(e->str, "hello", 5) == 0, "string lit: value");
}

static void test_bool_literal(void) {
    Parser p;
    parser_init(&p, "true");
    Expr *e = parser_parse_expr(&p);
    check(!parser_had_error(&p), "bool true: no error");
    check(e->kind == EXPR_BOOL_LIT, "bool true: kind");
    check(e->bool_val == 1, "bool true: value");

    parser_init(&p, "false");
    e = parser_parse_expr(&p);
    check(!parser_had_error(&p), "bool false: no error");
    check(e->kind == EXPR_BOOL_LIT, "bool false: kind");
    check(e->bool_val == 0, "bool false: value");
}

static void test_identifier(void) {
    Parser p;
    parser_init(&p, "foo");
    Expr *e = parser_parse_expr(&p);
    check(!parser_had_error(&p), "ident: no error");
    check(e->kind == EXPR_IDENT, "ident: kind");
    check(e->ident_len == 3 && memcmp(e->ident, "foo", 3) == 0, "ident: value");
}

static void test_binary_add(void) {
    Parser p;
    parser_init(&p, "1 + 2");
    Expr *e = parser_parse_expr(&p);
    check(!parser_had_error(&p), "add: no error");
    check(e->kind == EXPR_BINARY, "add: kind");
    check(e->bin_op == BIN_ADD, "add: op");
    check(e->lhs->kind == EXPR_INT_LIT && e->lhs->int_val == 1, "add: lhs");
    check(e->rhs->kind == EXPR_INT_LIT && e->rhs->int_val == 2, "add: rhs");
}

static void test_binary_precedence(void) {
    /* 1 + 2 * 3  should parse as 1 + (2 * 3) */
    Parser p;
    parser_init(&p, "1 + 2 * 3");
    Expr *e = parser_parse_expr(&p);
    check(!parser_had_error(&p), "prec: no error");
    check(e->kind == EXPR_BINARY, "prec: top is binary");
    check(e->bin_op == BIN_ADD, "prec: top is +");
    check(e->lhs->int_val == 1, "prec: lhs is 1");
    check(e->rhs->kind == EXPR_BINARY, "prec: rhs is binary");
    check(e->rhs->bin_op == BIN_MUL, "prec: rhs is *");
    check(e->rhs->lhs->int_val == 2, "prec: 2");
    check(e->rhs->rhs->int_val == 3, "prec: 3");
}

static void test_comparison(void) {
    Parser p;
    parser_init(&p, "a < b");
    Expr *e = parser_parse_expr(&p);
    check(!parser_had_error(&p), "cmp: no error");
    check(e->kind == EXPR_BINARY, "cmp: binary");
    check(e->bin_op == BIN_LT, "cmp: LT");
}

static void test_logical(void) {
    Parser p;
    parser_init(&p, "x && y || z");
    Expr *e = parser_parse_expr(&p);
    check(!parser_had_error(&p), "logic: no error");
    check(e->kind == EXPR_BINARY, "logic: binary");
    check(e->bin_op == BIN_OR, "logic: top is OR");
    check(e->lhs->kind == EXPR_BINARY, "logic: lhs is binary");
    check(e->lhs->bin_op == BIN_AND, "logic: lhs is AND");
}

static void test_unary_neg(void) {
    Parser p;
    parser_init(&p, "-42");
    Expr *e = parser_parse_expr(&p);
    check(!parser_had_error(&p), "neg: no error");
    check(e->kind == EXPR_UNARY, "neg: unary");
    check(e->unary_op == UN_NEG, "neg: NEG");
    check(e->operand->kind == EXPR_INT_LIT, "neg: operand is int");
}

static void test_unary_not(void) {
    Parser p;
    parser_init(&p, "!flag");
    Expr *e = parser_parse_expr(&p);
    check(!parser_had_error(&p), "not: no error");
    check(e->kind == EXPR_UNARY, "not: unary");
    check(e->unary_op == UN_NOT, "not: NOT");
}

static void test_unary_addr_deref(void) {
    Parser p;
    parser_init(&p, "&x");
    Expr *e = parser_parse_expr(&p);
    check(!parser_had_error(&p), "addr: no error");
    check(e->kind == EXPR_UNARY && e->unary_op == UN_ADDR, "addr: &");

    parser_init(&p, "*p");
    e = parser_parse_expr(&p);
    check(!parser_had_error(&p), "deref: no error");
    check(e->kind == EXPR_UNARY && e->unary_op == UN_DEREF, "deref: *");
}

static void test_call(void) {
    Parser p;
    parser_init(&p, "add(1, 2)");
    Expr *e = parser_parse_expr(&p);
    check(!parser_had_error(&p), "call: no error");
    check(e->kind == EXPR_CALL, "call: kind");
    check(e->callee->kind == EXPR_IDENT, "call: callee is ident");
    check(e->arg_count == 2, "call: 2 args");
    check(e->args[0]->int_val == 1, "call: arg 0");
    check(e->args[1]->int_val == 2, "call: arg 1");
}

static void test_call_no_args(void) {
    Parser p;
    parser_init(&p, "foo()");
    Expr *e = parser_parse_expr(&p);
    check(!parser_had_error(&p), "call0: no error");
    check(e->kind == EXPR_CALL, "call0: kind");
    check(e->arg_count == 0, "call0: 0 args");
}

static void test_member_access(void) {
    Parser p;
    parser_init(&p, "point.x");
    Expr *e = parser_parse_expr(&p);
    check(!parser_had_error(&p), "member: no error");
    check(e->kind == EXPR_MEMBER, "member: kind");
    check(memcmp(e->member, "x", 1) == 0, "member: name x");
    check(e->object->kind == EXPR_IDENT, "member: object is ident");
}

static void test_index(void) {
    Parser p;
    parser_init(&p, "arr[0]");
    Expr *e = parser_parse_expr(&p);
    check(!parser_had_error(&p), "index: no error");
    check(e->kind == EXPR_INDEX, "index: kind");
    check(e->index_expr->kind == EXPR_INT_LIT, "index: idx is int");
}

static void test_nested_call(void) {
    Parser p;
    parser_init(&p, "a.b(1).c");
    Expr *e = parser_parse_expr(&p);
    check(!parser_had_error(&p), "nested: no error");
    check(e->kind == EXPR_MEMBER, "nested: top is member");
    check(memcmp(e->member, "c", 1) == 0, "nested: .c");
    check(e->object->kind == EXPR_CALL, "nested: call");
}

static void test_parenthesized(void) {
    /* (1 + 2) * 3  should parse as (1 + 2) * 3 */
    Parser p;
    parser_init(&p, "(1 + 2) * 3");
    Expr *e = parser_parse_expr(&p);
    check(!parser_had_error(&p), "paren: no error");
    check(e->kind == EXPR_BINARY, "paren: top binary");
    check(e->bin_op == BIN_MUL, "paren: top is *");
    check(e->lhs->kind == EXPR_BINARY && e->lhs->bin_op == BIN_ADD, "paren: lhs is +");
}

/* ── Statement tests ───────────────────────────────── */

static void test_let_stmt(void) {
    Parser p;
    parser_init(&p, "let x: i32 = 42;");
    Stmt *s = parser_parse_stmt(&p);
    check(!parser_had_error(&p), "let: no error");
    check(s->kind == STMT_LET, "let: kind");
    check(s->var_name_len == 1 && s->var_name[0] == 'x', "let: name x");
    check(s->var_type != NULL && s->var_type->kind == TYPE_I32, "let: type i32");
    check(s->var_init != NULL && s->var_init->int_val == 42, "let: init 42");
}

static void test_var_stmt(void) {
    Parser p;
    parser_init(&p, "var count: u64 = 0;");
    Stmt *s = parser_parse_stmt(&p);
    check(!parser_had_error(&p), "var: no error");
    check(s->kind == STMT_VAR, "var: kind");
    check(s->var_name_len == 5 && memcmp(s->var_name, "count", 5) == 0, "var: name count");
    check(s->var_type->kind == TYPE_U64, "var: type u64");
}

static void test_let_no_type(void) {
    Parser p;
    parser_init(&p, "let x = 42;");
    Stmt *s = parser_parse_stmt(&p);
    check(!parser_had_error(&p), "let_notype: no error");
    check(s->kind == STMT_LET, "let_notype: kind");
    check(s->var_type == NULL, "let_notype: no type");
    check(s->var_init->int_val == 42, "let_notype: init 42");
}

static void test_return_stmt(void) {
    Parser p;
    parser_init(&p, "return 0;");
    Stmt *s = parser_parse_stmt(&p);
    check(!parser_had_error(&p), "return: no error");
    check(s->kind == STMT_RETURN, "return: kind");
    check(s->ret_expr != NULL && s->ret_expr->int_val == 0, "return: value 0");
}

static void test_return_bare(void) {
    Parser p;
    parser_init(&p, "return;");
    Stmt *s = parser_parse_stmt(&p);
    check(!parser_had_error(&p), "return_bare: no error");
    check(s->kind == STMT_RETURN, "return_bare: kind");
    check(s->ret_expr == NULL, "return_bare: no expr");
}

static void test_if_stmt(void) {
    Parser p;
    parser_init(&p, "if x > 0 { return 1; }");
    Stmt *s = parser_parse_stmt(&p);
    check(!parser_had_error(&p), "if: no error");
    check(s->kind == STMT_IF, "if: kind");
    check(s->if_cond->kind == EXPR_BINARY, "if: cond is binary");
    check(s->if_then->kind == STMT_BLOCK, "if: then is block");
    check(s->if_else == NULL, "if: no else");
}

static void test_if_else(void) {
    Parser p;
    parser_init(&p, "if a { return 1; } else { return 2; }");
    Stmt *s = parser_parse_stmt(&p);
    check(!parser_had_error(&p), "ifelse: no error");
    check(s->if_else != NULL, "ifelse: has else");
    check(s->if_else->kind == STMT_BLOCK, "ifelse: else is block");
}

static void test_if_else_if(void) {
    Parser p;
    parser_init(&p, "if a { return 1; } else if b { return 2; }");
    Stmt *s = parser_parse_stmt(&p);
    check(!parser_had_error(&p), "ifelseif: no error");
    check(s->if_else != NULL, "ifelseif: has else");
    check(s->if_else->kind == STMT_IF, "ifelseif: else is another if");
}

static void test_while_stmt(void) {
    Parser p;
    parser_init(&p, "while x > 0 { x = x - 1; }");
    Stmt *s = parser_parse_stmt(&p);
    check(!parser_had_error(&p), "while: no error");
    check(s->kind == STMT_WHILE, "while: kind");
    check(s->while_cond->kind == EXPR_BINARY, "while: cond");
    check(s->while_body->kind == STMT_BLOCK, "while: body");
}

static void test_assign_stmt(void) {
    Parser p;
    parser_init(&p, "x = 42;");
    Stmt *s = parser_parse_stmt(&p);
    check(!parser_had_error(&p), "assign: no error");
    check(s->kind == STMT_ASSIGN, "assign: kind");
    check(s->assign_target->kind == EXPR_IDENT, "assign: target ident");
    check(s->assign_value->int_val == 42, "assign: value 42");
}

static void test_expr_stmt(void) {
    Parser p;
    parser_init(&p, "foo(1);");
    Stmt *s = parser_parse_stmt(&p);
    check(!parser_had_error(&p), "exprstmt: no error");
    check(s->kind == STMT_EXPR, "exprstmt: kind");
    check(s->expr->kind == EXPR_CALL, "exprstmt: expr is call");
}

static void test_free_stmt(void) {
    Parser p;
    parser_init(&p, "free(p);");
    Stmt *s = parser_parse_stmt(&p);
    check(!parser_had_error(&p), "free: no error");
    check(s->kind == STMT_FREE, "free: kind");
    check(s->free_expr->kind == EXPR_IDENT, "free: arg is ident");
}

/* ── Type tests ────────────────────────────────────── */

static void test_ptr_type(void) {
    Parser p;
    parser_init(&p, "let p: ptr<u8> = x;");
    Stmt *s = parser_parse_stmt(&p);
    check(!parser_had_error(&p), "ptr_type: no error");
    check(s->var_type != NULL, "ptr_type: has type");
    check(s->var_type->kind == TYPE_PTR, "ptr_type: is ptr");
    check(s->var_type->inner->kind == TYPE_U8, "ptr_type: inner is u8");
}

static void test_slice_type(void) {
    Parser p;
    parser_init(&p, "let s: []u8 = x;");
    Stmt *s = parser_parse_stmt(&p);
    check(!parser_had_error(&p), "slice_type: no error");
    check(s->var_type->kind == TYPE_SLICE, "slice_type: is slice");
    check(s->var_type->inner->kind == TYPE_U8, "slice_type: inner is u8");
}

static void test_array_type(void) {
    Parser p;
    parser_init(&p, "let a: [u8; 256] = x;");
    Stmt *s = parser_parse_stmt(&p);
    check(!parser_had_error(&p), "arr_type: no error");
    check(s->var_type->kind == TYPE_ARRAY, "arr_type: is array");
    check(s->var_type->inner->kind == TYPE_U8, "arr_type: inner is u8");
    check(s->var_type->array_size == 256, "arr_type: size 256");
}

static void test_named_type(void) {
    Parser p;
    parser_init(&p, "let p: Point = x;");
    Stmt *s = parser_parse_stmt(&p);
    check(!parser_had_error(&p), "named_type: no error");
    check(s->var_type->kind == TYPE_NAMED, "named_type: is named");
    check(s->var_type->name_len == 5 && memcmp(s->var_type->name, "Point", 5) == 0,
          "named_type: name Point");
}

/* ── Declaration tests ─────────────────────────────── */

static void test_fn_decl(void) {
    Parser p;
    parser_init(&p, "fn add(a: i32, b: i32) -> i32 { return a + b; }");
    Program *prog = parser_parse(&p);
    check(!parser_had_error(&p), "fn: no error");
    check(prog != NULL, "fn: program not null");
    check(prog->decl_count == 1, "fn: 1 decl");

    Decl *d = prog->decls[0];
    check(d->kind == DECL_FN, "fn: kind");
    check(d->fn_name_len == 3 && memcmp(d->fn_name, "add", 3) == 0, "fn: name add");
    check(d->param_count == 2, "fn: 2 params");
    check(d->params[0].name_len == 1 && d->params[0].name[0] == 'a', "fn: param a");
    check(d->params[0].type->kind == TYPE_I32, "fn: param a type");
    check(d->params[1].name_len == 1 && d->params[1].name[0] == 'b', "fn: param b");
    check(d->return_type != NULL && d->return_type->kind == TYPE_I32, "fn: returns i32");
    check(d->fn_body->kind == STMT_BLOCK, "fn: body is block");
    check(d->fn_body->stmt_count == 1, "fn: 1 stmt in body");
}

static void test_fn_no_params(void) {
    Parser p;
    parser_init(&p, "fn main() -> i32 { return 0; }");
    Program *prog = parser_parse(&p);
    check(!parser_had_error(&p), "fn0: no error");
    check(prog->decls[0]->param_count == 0, "fn0: 0 params");
}

static void test_fn_void(void) {
    Parser p;
    parser_init(&p, "fn noop() { return; }");
    Program *prog = parser_parse(&p);
    check(!parser_had_error(&p), "fn_void: no error");
    check(prog->decls[0]->return_type == NULL, "fn_void: no return type");
}

static void test_struct_decl(void) {
    Parser p;
    parser_init(&p, "struct Point { x: f64, y: f64, }");
    Program *prog = parser_parse(&p);
    check(!parser_had_error(&p), "struct: no error");
    check(prog->decl_count == 1, "struct: 1 decl");

    Decl *d = prog->decls[0];
    check(d->kind == DECL_STRUCT, "struct: kind");
    check(d->st_name_len == 5 && memcmp(d->st_name, "Point", 5) == 0, "struct: name Point");
    check(d->st_field_count == 2, "struct: 2 fields");
    check(d->st_fields[0].name_len == 1 && d->st_fields[0].name[0] == 'x', "struct: field x");
    check(d->st_fields[0].type->kind == TYPE_F64, "struct: x is f64");
    check(d->st_fields[1].name_len == 1 && d->st_fields[1].name[0] == 'y', "struct: field y");
}

/* ── Full program test ─────────────────────────────── */

static void test_full_program(void) {
    const char *src =
        "struct Point {\n"
        "    x: f64,\n"
        "    y: f64,\n"
        "}\n"
        "\n"
        "fn distance(a: Point, b: Point) -> f64 {\n"
        "    let dx: f64 = b.x - a.x;\n"
        "    let dy: f64 = b.y - a.y;\n"
        "    return dx * dx + dy * dy;\n"
        "}\n"
        "\n"
        "fn main() -> i32 {\n"
        "    let p: Point = Point { x: 1.0, y: 2.0 };\n"
        "    let q: Point = Point { x: 4.0, y: 6.0 };\n"
        "    let d: f64 = distance(p, q);\n"
        "    return 0;\n"
        "}\n";

    Parser p;
    parser_init(&p, src);
    Program *prog = parser_parse(&p);
    check(!parser_had_error(&p), "full: no error");
    check(prog != NULL, "full: program not null");
    check(prog->decl_count == 3, "full: 3 decls (struct + 2 fn)");
    check(prog->decls[0]->kind == DECL_STRUCT, "full: first is struct");
    check(prog->decls[1]->kind == DECL_FN, "full: second is fn");
    check(prog->decls[2]->kind == DECL_FN, "full: third is fn");

    /* Check main body has 4 statements */
    Decl *main_fn = prog->decls[2];
    check(main_fn->fn_body->stmt_count == 4, "full: main has 4 stmts");
}

static void test_struct_literal(void) {
    Parser p;
    parser_init(&p, "Point { x: 1.0, y: 2.0 }");
    Expr *e = parser_parse_expr(&p);
    check(!parser_had_error(&p), "struct_lit: no error");
    check(e->kind == EXPR_STRUCT_LIT, "struct_lit: kind");
    check(e->struct_name_len == 5 && memcmp(e->struct_name, "Point", 5) == 0,
          "struct_lit: name Point");
    check(e->field_count == 2, "struct_lit: 2 fields");
    check(e->fields[0].name_len == 1 && e->fields[0].name[0] == 'x', "struct_lit: field x");
    check(e->fields[1].name_len == 1 && e->fields[1].name[0] == 'y', "struct_lit: field y");
}

/* ── Error tests ───────────────────────────────────── */

static void test_error_missing_semi(void) {
    Parser p;
    parser_init(&p, "let x: i32 = 42");
    parser_parse_stmt(&p);
    check(parser_had_error(&p), "err_semi: detected error");
}

static void test_error_missing_brace(void) {
    Parser p;
    parser_init(&p, "fn foo() { return 1;");
    parser_parse(&p);
    check(parser_had_error(&p), "err_brace: detected error");
}

/* ── Main ──────────────────────────────────────────── */

int main(void) {
    printf("M parser tests\n");

    /* Expression tests */
    test_int_literal();
    test_float_literal();
    test_string_literal();
    test_bool_literal();
    test_identifier();
    test_binary_add();
    test_binary_precedence();
    test_comparison();
    test_logical();
    test_unary_neg();
    test_unary_not();
    test_unary_addr_deref();
    test_call();
    test_call_no_args();
    test_member_access();
    test_index();
    test_nested_call();
    test_parenthesized();
    test_struct_literal();

    /* Statement tests */
    test_let_stmt();
    test_var_stmt();
    test_let_no_type();
    test_return_stmt();
    test_return_bare();
    test_if_stmt();
    test_if_else();
    test_if_else_if();
    test_while_stmt();
    test_assign_stmt();
    test_expr_stmt();
    test_free_stmt();

    /* Type tests */
    test_ptr_type();
    test_slice_type();
    test_array_type();
    test_named_type();

    /* Declaration tests */
    test_fn_decl();
    test_fn_no_params();
    test_fn_void();
    test_struct_decl();

    /* Full program test */
    test_full_program();

    /* Error tests */
    test_error_missing_semi();
    test_error_missing_brace();

    printf("\n%d/%d tests passed\n", tests_passed, tests_run);
    return tests_passed == tests_run ? 0 : 1;
}
