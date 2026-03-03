/*
 * parser.c — M language recursive descent parser
 *
 * Reads tokens, builds AST.
 * No dynamic allocation except through ast_alloc / tohum_alloc.
 */

#include "parser.h"
#include "../../core/tohum_memory.h"
#include <stdio.h>
#include <string.h>
#include <stdlib.h>

/* ── AST allocation ────────────────────────────────── */

Expr *ast_alloc_expr(void) {
    return (Expr *)tohum_alloc(sizeof(Expr));
}

Stmt *ast_alloc_stmt(void) {
    return (Stmt *)tohum_alloc(sizeof(Stmt));
}

Decl *ast_alloc_decl(void) {
    return (Decl *)tohum_alloc(sizeof(Decl));
}

TypeNode *ast_alloc_type(void) {
    return (TypeNode *)tohum_alloc(sizeof(TypeNode));
}

void *ast_alloc(size_t size) {
    return tohum_alloc(size);
}

void ast_free_program(Program *prog) {
    /* For now: leak. Bootstrap compiler doesn't need cleanup.
     * Once M self-hosts, this gets proper deallocation. */
    (void)prog;
}

/* ── Parser internals ──────────────────────────────── */

static void advance_token(Parser *p) {
    p->previous = p->current;
    p->current = lexer_next(&p->lex);

    if (p->current.type == TOK_ERROR) {
        if (!p->panic_mode) {
            p->panic_mode = 1;
            p->had_error = 1;
            p->error_line = p->current.line;
            p->error_col = p->current.col;
            snprintf(p->error_msg, sizeof(p->error_msg),
                     "lexer error: %.*s",
                     p->current.length, p->current.start);
        }
    }
}

static int check(Parser *p, TokenType type) {
    return p->current.type == type;
}

static int match(Parser *p, TokenType type) {
    if (!check(p, type)) return 0;
    advance_token(p);
    return 1;
}

static void error_at(Parser *p, const char *msg) {
    if (p->panic_mode) return;
    p->panic_mode = 1;
    p->had_error = 1;
    p->error_line = p->current.line;
    p->error_col = p->current.col;
    snprintf(p->error_msg, sizeof(p->error_msg),
             "%d:%d: %s (got '%s')",
             p->current.line, p->current.col, msg,
             token_type_name(p->current.type));
}

static void consume(Parser *p, TokenType type, const char *msg) {
    if (p->current.type == type) {
        advance_token(p);
        return;
    }
    error_at(p, msg);
}

static void synchronize(Parser *p) {
    p->panic_mode = 0;

    while (p->current.type != TOK_EOF) {
        if (p->previous.type == TOK_SEMICOLON) return;
        if (p->previous.type == TOK_RBRACE) return;

        switch (p->current.type) {
        case TOK_FN:
        case TOK_STRUCT:
        case TOK_LET:
        case TOK_VAR:
        case TOK_IF:
        case TOK_WHILE:
        case TOK_RETURN:
            return;
        default:
            break;
        }

        advance_token(p);
    }
}

/* ── Type parsing ──────────────────────────────────── */

static TypeNode *parse_type(Parser *p);

static TypeNode *make_primitive(TypeKind kind, int line, int col) {
    TypeNode *t = ast_alloc_type();
    t->kind = kind;
    t->line = line;
    t->col = col;
    return t;
}

static TypeNode *parse_type(Parser *p) {
    int line = p->current.line, col = p->current.col;

    /* Primitive types */
    if (match(p, TOK_U8))   return make_primitive(TYPE_U8, line, col);
    if (match(p, TOK_U16))  return make_primitive(TYPE_U16, line, col);
    if (match(p, TOK_U32))  return make_primitive(TYPE_U32, line, col);
    if (match(p, TOK_U64))  return make_primitive(TYPE_U64, line, col);
    if (match(p, TOK_I8))   return make_primitive(TYPE_I8, line, col);
    if (match(p, TOK_I16))  return make_primitive(TYPE_I16, line, col);
    if (match(p, TOK_I32))  return make_primitive(TYPE_I32, line, col);
    if (match(p, TOK_I64))  return make_primitive(TYPE_I64, line, col);
    if (match(p, TOK_F64))  return make_primitive(TYPE_F64, line, col);
    if (match(p, TOK_BOOL)) return make_primitive(TYPE_BOOL, line, col);
    if (match(p, TOK_VOID)) return make_primitive(TYPE_VOID, line, col);

    /* ptr<T> */
    if (match(p, TOK_PTR)) {
        consume(p, TOK_LT, "expected '<' after 'ptr'");
        TypeNode *inner = parse_type(p);
        consume(p, TOK_GT, "expected '>' after ptr type");
        TypeNode *t = ast_alloc_type();
        t->kind = TYPE_PTR;
        t->inner = inner;
        t->line = line;
        t->col = col;
        return t;
    }

    /* []T (slice) or [T; N] (array) */
    if (match(p, TOK_LBRACKET)) {
        if (match(p, TOK_RBRACKET)) {
            /* []T — slice */
            TypeNode *inner = parse_type(p);
            TypeNode *t = ast_alloc_type();
            t->kind = TYPE_SLICE;
            t->inner = inner;
            t->line = line;
            t->col = col;
            return t;
        }

        /* [T; N] — fixed array */
        TypeNode *inner = parse_type(p);
        consume(p, TOK_SEMICOLON, "expected ';' in array type");
        if (!check(p, TOK_INT_LIT)) {
            error_at(p, "expected array size");
            return NULL;
        }
        int size = (int)p->current.int_val;
        advance_token(p);
        consume(p, TOK_RBRACKET, "expected ']' after array size");
        TypeNode *t = ast_alloc_type();
        t->kind = TYPE_ARRAY;
        t->inner = inner;
        t->array_size = size;
        t->line = line;
        t->col = col;
        return t;
    }

    /* Named type (struct name) */
    if (check(p, TOK_IDENT)) {
        TypeNode *t = ast_alloc_type();
        t->kind = TYPE_NAMED;
        t->name = p->current.start;
        t->name_len = p->current.length;
        t->line = line;
        t->col = col;
        advance_token(p);
        return t;
    }

    error_at(p, "expected type");
    return NULL;
}

/* ── Expression parsing (Pratt-style precedence) ───── */

typedef enum {
    PREC_NONE,
    PREC_ASSIGN,    /* = */
    PREC_OR,        /* || */
    PREC_AND,       /* && */
    PREC_EQUALITY,  /* == != */
    PREC_COMPARE,   /* < > <= >= */
    PREC_TERM,      /* + - */
    PREC_FACTOR,    /* * / % */
    PREC_UNARY,     /* ! - & * */
    PREC_CALL,      /* . () [] */
    PREC_PRIMARY,
} Precedence;

static Expr *parse_expression(Parser *p);
static Expr *parse_precedence(Parser *p, Precedence min_prec);
static Expr *parse_postfix(Parser *p);

static Expr *make_int_lit(long long val, int line, int col) {
    Expr *e = ast_alloc_expr();
    e->kind = EXPR_INT_LIT;
    e->int_val = val;
    e->line = line;
    e->col = col;
    return e;
}

static Expr *make_float_lit(double val, int line, int col) {
    Expr *e = ast_alloc_expr();
    e->kind = EXPR_FLOAT_LIT;
    e->float_val = val;
    e->line = line;
    e->col = col;
    return e;
}

static Expr *make_string_lit(const char *s, int len, int line, int col) {
    Expr *e = ast_alloc_expr();
    e->kind = EXPR_STRING_LIT;
    e->str = s;
    e->str_len = len;
    e->line = line;
    e->col = col;
    return e;
}

static Expr *make_bool_lit(int val, int line, int col) {
    Expr *e = ast_alloc_expr();
    e->kind = EXPR_BOOL_LIT;
    e->bool_val = val;
    e->line = line;
    e->col = col;
    return e;
}

static Expr *make_ident(const char *name, int len, int line, int col) {
    Expr *e = ast_alloc_expr();
    e->kind = EXPR_IDENT;
    e->ident = name;
    e->ident_len = len;
    e->line = line;
    e->col = col;
    return e;
}

static Expr *make_binary(OpKind op, Expr *lhs, Expr *rhs, int line, int col) {
    Expr *e = ast_alloc_expr();
    e->kind = EXPR_BINARY;
    e->bin_op = op;
    e->lhs = lhs;
    e->rhs = rhs;
    e->line = line;
    e->col = col;
    return e;
}

static Expr *make_unary(OpKind op, Expr *operand, int line, int col) {
    Expr *e = ast_alloc_expr();
    e->kind = EXPR_UNARY;
    e->unary_op = op;
    e->operand = operand;
    e->line = line;
    e->col = col;
    return e;
}

/* Parse primary expressions */
static Expr *parse_primary(Parser *p) {
    int line = p->current.line, col = p->current.col;

    if (match(p, TOK_INT_LIT)) {
        return make_int_lit(p->previous.int_val, line, col);
    }

    if (match(p, TOK_FLOAT_LIT)) {
        return make_float_lit(p->previous.float_val, line, col);
    }

    if (match(p, TOK_STRING_LIT)) {
        return make_string_lit(p->previous.start, p->previous.length, line, col);
    }

    if (match(p, TOK_TRUE))  return make_bool_lit(1, line, col);
    if (match(p, TOK_FALSE)) return make_bool_lit(0, line, col);

    if (match(p, TOK_IDENT)) {
        const char *name = p->previous.start;
        int name_len = p->previous.length;

        /* Check for struct literal: Name { field: val, ... } */
        if (check(p, TOK_LBRACE)) {
            /* Peek: is this { field: ... } or just a block?
             * We look for IDENT COLON pattern after brace */
            Lexer saved_lex = p->lex;
            Token saved_cur = p->current;
            Token saved_prev = p->previous;

            advance_token(p); /* consume { */
            int is_struct_lit = 0;
            if (check(p, TOK_IDENT)) {
                Token id = p->current;
                advance_token(p);
                if (check(p, TOK_COLON)) {
                    is_struct_lit = 1;
                }
                (void)id;
            }

            /* Restore parser state */
            p->lex = saved_lex;
            p->current = saved_cur;
            p->previous = saved_prev;

            if (is_struct_lit) {
                advance_token(p); /* consume { */

                /* Parse field initializers */
                int cap = 8;
                FieldInit *fields = ast_alloc(cap * sizeof(FieldInit));
                int count = 0;

                while (!check(p, TOK_RBRACE) && !check(p, TOK_EOF)) {
                    if (count > 0) {
                        consume(p, TOK_COMMA, "expected ',' between fields");
                    }
                    if (check(p, TOK_RBRACE)) break; /* trailing comma */

                    if (!check(p, TOK_IDENT)) {
                        error_at(p, "expected field name");
                        return NULL;
                    }
                    const char *fname = p->current.start;
                    int flen = p->current.length;
                    advance_token(p);
                    consume(p, TOK_COLON, "expected ':' after field name");
                    Expr *val = parse_expression(p);

                    if (count >= cap) {
                        cap *= 2;
                        FieldInit *new_fields = ast_alloc(cap * sizeof(FieldInit));
                        memcpy(new_fields, fields, count * sizeof(FieldInit));
                        fields = new_fields;
                    }
                    fields[count].name = fname;
                    fields[count].name_len = flen;
                    fields[count].value = val;
                    count++;
                }

                consume(p, TOK_RBRACE, "expected '}' after struct literal");

                Expr *e = ast_alloc_expr();
                e->kind = EXPR_STRUCT_LIT;
                e->struct_name = name;
                e->struct_name_len = name_len;
                e->fields = fields;
                e->field_count = count;
                e->line = line;
                e->col = col;
                return e;
            }
        }

        return make_ident(name, name_len, line, col);
    }

    /* Parenthesized expression */
    if (match(p, TOK_LPAREN)) {
        Expr *e = parse_expression(p);
        consume(p, TOK_RPAREN, "expected ')' after expression");
        return e;
    }

    error_at(p, "expected expression");
    return NULL;
}

/* Parse unary: - ! & * */
static Expr *parse_unary(Parser *p) {
    int line = p->current.line, col = p->current.col;

    if (match(p, TOK_MINUS)) {
        Expr *operand = parse_unary(p);
        return make_unary(UN_NEG, operand, line, col);
    }
    if (match(p, TOK_NOT)) {
        Expr *operand = parse_unary(p);
        return make_unary(UN_NOT, operand, line, col);
    }
    if (match(p, TOK_AMPERSAND)) {
        Expr *operand = parse_unary(p);
        return make_unary(UN_ADDR, operand, line, col);
    }
    if (match(p, TOK_STAR)) {
        Expr *operand = parse_unary(p);
        return make_unary(UN_DEREF, operand, line, col);
    }

    return parse_postfix(p);
}

/* Parse postfix: call(), member.access, index[i] */
static Expr *parse_postfix(Parser *p) {
    Expr *left = parse_primary(p);
    if (p->had_error) return left;

    for (;;) {
        int line = p->current.line, col = p->current.col;

        /* Function call */
        if (check(p, TOK_LPAREN)) {
            advance_token(p); /* consume ( */

            int cap = 8;
            Expr **args = ast_alloc(cap * sizeof(Expr *));
            int count = 0;

            while (!check(p, TOK_RPAREN) && !check(p, TOK_EOF)) {
                if (count > 0) {
                    consume(p, TOK_COMMA, "expected ',' between arguments");
                }
                if (count >= cap) {
                    cap *= 2;
                    Expr **new_args = ast_alloc(cap * sizeof(Expr *));
                    memcpy(new_args, args, count * sizeof(Expr *));
                    args = new_args;
                }
                args[count] = parse_expression(p);
                count++;
            }

            consume(p, TOK_RPAREN, "expected ')' after arguments");

            Expr *e = ast_alloc_expr();
            e->kind = EXPR_CALL;
            e->callee = left;
            e->args = args;
            e->arg_count = count;
            e->line = line;
            e->col = col;
            left = e;
            continue;
        }

        /* Member access: a.b */
        if (check(p, TOK_DOT)) {
            advance_token(p);
            if (!check(p, TOK_IDENT)) {
                error_at(p, "expected member name after '.'");
                return left;
            }
            Expr *e = ast_alloc_expr();
            e->kind = EXPR_MEMBER;
            e->object = left;
            e->member = p->current.start;
            e->member_len = p->current.length;
            e->line = line;
            e->col = col;
            advance_token(p);
            left = e;
            continue;
        }

        /* Index: a[i] */
        if (check(p, TOK_LBRACKET)) {
            advance_token(p);
            Expr *idx = parse_expression(p);
            consume(p, TOK_RBRACKET, "expected ']' after index");

            Expr *e = ast_alloc_expr();
            e->kind = EXPR_INDEX;
            e->target = left;
            e->index_expr = idx;
            e->line = line;
            e->col = col;
            left = e;
            continue;
        }

        break;
    }

    return left;
}

/* Get binary operator precedence */
static Precedence get_precedence(TokenType type) {
    switch (type) {
    case TOK_OR:                            return PREC_OR;
    case TOK_AND:                           return PREC_AND;
    case TOK_EQ: case TOK_NEQ:             return PREC_EQUALITY;
    case TOK_LT: case TOK_GT:
    case TOK_LTE: case TOK_GTE:           return PREC_COMPARE;
    case TOK_PLUS: case TOK_MINUS:         return PREC_TERM;
    case TOK_STAR: case TOK_SLASH:
    case TOK_PERCENT:                      return PREC_FACTOR;
    /* call/member/index now handled in parse_postfix */
    default:                                return PREC_NONE;
    }
}

static OpKind token_to_binop(TokenType type) {
    switch (type) {
    case TOK_PLUS:    return BIN_ADD;
    case TOK_MINUS:   return BIN_SUB;
    case TOK_STAR:    return BIN_MUL;
    case TOK_SLASH:   return BIN_DIV;
    case TOK_PERCENT: return BIN_MOD;
    case TOK_EQ:      return BIN_EQ;
    case TOK_NEQ:     return BIN_NEQ;
    case TOK_LT:      return BIN_LT;
    case TOK_GT:      return BIN_GT;
    case TOK_LTE:     return BIN_LTE;
    case TOK_GTE:     return BIN_GTE;
    case TOK_AND:     return BIN_AND;
    case TOK_OR:      return BIN_OR;
    default:          return BIN_ADD; /* unreachable */
    }
}

static Expr *parse_precedence(Parser *p, Precedence min_prec) {
    Expr *left = parse_unary(p);
    if (p->had_error) return left;

    for (;;) {
        Precedence prec = get_precedence(p->current.type);
        if (prec < min_prec) break;

        int line = p->current.line, col = p->current.col;

        /* Binary operators (call/member/index handled in parse_postfix) */
        OpKind op = token_to_binop(p->current.type);
        advance_token(p);
        Expr *right = parse_precedence(p, prec + 1);
        left = make_binary(op, left, right, line, col);
    }

    return left;
}

static Expr *parse_expression(Parser *p) {
    return parse_precedence(p, PREC_OR);
}

/* ── Statement parsing ─────────────────────────────── */

static Stmt *parse_statement(Parser *p);
static Stmt *parse_block(Parser *p);

static Stmt *parse_block(Parser *p) {
    int line = p->current.line, col = p->current.col;
    consume(p, TOK_LBRACE, "expected '{'");

    int cap = 16;
    Stmt **stmts = ast_alloc(cap * sizeof(Stmt *));
    int count = 0;

    while (!check(p, TOK_RBRACE) && !check(p, TOK_EOF)) {
        Stmt *s = parse_statement(p);
        if (p->had_error) {
            synchronize(p);
            continue;
        }
        if (s) {
            if (count >= cap) {
                cap *= 2;
                Stmt **new_stmts = ast_alloc(cap * sizeof(Stmt *));
                memcpy(new_stmts, stmts, count * sizeof(Stmt *));
                stmts = new_stmts;
            }
            stmts[count++] = s;
        }
    }

    consume(p, TOK_RBRACE, "expected '}'");

    Stmt *block = ast_alloc_stmt();
    block->kind = STMT_BLOCK;
    block->stmts = stmts;
    block->stmt_count = count;
    block->line = line;
    block->col = col;
    return block;
}

static Stmt *parse_let_var(Parser *p, int is_var) {
    int line = p->previous.line, col = p->previous.col;

    if (!check(p, TOK_IDENT)) {
        error_at(p, "expected variable name");
        return NULL;
    }

    const char *name = p->current.start;
    int name_len = p->current.length;
    advance_token(p);

    /* Optional type annotation */
    TypeNode *type = NULL;
    if (match(p, TOK_COLON)) {
        type = parse_type(p);
    }

    /* Optional initializer */
    Expr *init = NULL;
    if (match(p, TOK_ASSIGN)) {
        init = parse_expression(p);
    }

    consume(p, TOK_SEMICOLON, "expected ';' after declaration");

    Stmt *s = ast_alloc_stmt();
    s->kind = is_var ? STMT_VAR : STMT_LET;
    s->var_name = name;
    s->var_name_len = name_len;
    s->var_type = type;
    s->var_init = init;
    s->line = line;
    s->col = col;
    return s;
}

static Stmt *parse_return(Parser *p) {
    int line = p->previous.line, col = p->previous.col;

    Expr *expr = NULL;
    if (!check(p, TOK_SEMICOLON)) {
        expr = parse_expression(p);
    }

    consume(p, TOK_SEMICOLON, "expected ';' after return");

    Stmt *s = ast_alloc_stmt();
    s->kind = STMT_RETURN;
    s->ret_expr = expr;
    s->line = line;
    s->col = col;
    return s;
}

static Stmt *parse_if(Parser *p) {
    int line = p->previous.line, col = p->previous.col;

    Expr *cond = parse_expression(p);
    Stmt *then_block = parse_block(p);

    Stmt *else_block = NULL;
    if (match(p, TOK_ELSE)) {
        if (check(p, TOK_IF)) {
            advance_token(p);
            else_block = parse_if(p);
        } else {
            else_block = parse_block(p);
        }
    }

    Stmt *s = ast_alloc_stmt();
    s->kind = STMT_IF;
    s->if_cond = cond;
    s->if_then = then_block;
    s->if_else = else_block;
    s->line = line;
    s->col = col;
    return s;
}

static Stmt *parse_while(Parser *p) {
    int line = p->previous.line, col = p->previous.col;

    Expr *cond = parse_expression(p);
    Stmt *body = parse_block(p);

    Stmt *s = ast_alloc_stmt();
    s->kind = STMT_WHILE;
    s->while_cond = cond;
    s->while_body = body;
    s->line = line;
    s->col = col;
    return s;
}

static Stmt *parse_free(Parser *p) {
    int line = p->previous.line, col = p->previous.col;

    consume(p, TOK_LPAREN, "expected '(' after 'free'");
    Expr *expr = parse_expression(p);
    consume(p, TOK_RPAREN, "expected ')' after free argument");
    consume(p, TOK_SEMICOLON, "expected ';' after free");

    Stmt *s = ast_alloc_stmt();
    s->kind = STMT_FREE;
    s->free_expr = expr;
    s->line = line;
    s->col = col;
    return s;
}

static Stmt *parse_statement(Parser *p) {
    if (match(p, TOK_LET))    return parse_let_var(p, 0);
    if (match(p, TOK_VAR))    return parse_let_var(p, 1);
    if (match(p, TOK_RETURN)) return parse_return(p);
    if (match(p, TOK_IF))     return parse_if(p);
    if (match(p, TOK_WHILE))  return parse_while(p);
    if (match(p, TOK_FREE))   return parse_free(p);

    if (check(p, TOK_LBRACE)) return parse_block(p);

    /* Expression statement (or assignment) */
    int line = p->current.line, col = p->current.col;
    Expr *expr = parse_expression(p);

    if (match(p, TOK_ASSIGN)) {
        Expr *value = parse_expression(p);
        consume(p, TOK_SEMICOLON, "expected ';' after assignment");

        Stmt *s = ast_alloc_stmt();
        s->kind = STMT_ASSIGN;
        s->assign_target = expr;
        s->assign_value = value;
        s->line = line;
        s->col = col;
        return s;
    }

    consume(p, TOK_SEMICOLON, "expected ';' after expression");

    Stmt *s = ast_alloc_stmt();
    s->kind = STMT_EXPR;
    s->expr = expr;
    s->line = line;
    s->col = col;
    return s;
}

/* ── Declaration parsing ───────────────────────────── */

static Decl *parse_fn(Parser *p) {
    int line = p->previous.line, col = p->previous.col;

    if (!check(p, TOK_IDENT)) {
        error_at(p, "expected function name");
        return NULL;
    }
    const char *name = p->current.start;
    int name_len = p->current.length;
    advance_token(p);

    consume(p, TOK_LPAREN, "expected '(' after function name");

    /* Parse parameters */
    int cap = 8;
    Param *params = ast_alloc(cap * sizeof(Param));
    int count = 0;

    while (!check(p, TOK_RPAREN) && !check(p, TOK_EOF)) {
        if (count > 0) {
            consume(p, TOK_COMMA, "expected ',' between parameters");
        }
        if (!check(p, TOK_IDENT)) {
            error_at(p, "expected parameter name");
            return NULL;
        }
        Param param;
        param.name = p->current.start;
        param.name_len = p->current.length;
        advance_token(p);
        consume(p, TOK_COLON, "expected ':' after parameter name");
        param.type = parse_type(p);

        if (count >= cap) {
            cap *= 2;
            Param *new_params = ast_alloc(cap * sizeof(Param));
            memcpy(new_params, params, count * sizeof(Param));
            params = new_params;
        }
        params[count++] = param;
    }

    consume(p, TOK_RPAREN, "expected ')' after parameters");

    /* Return type */
    TypeNode *ret_type = NULL;
    if (match(p, TOK_ARROW)) {
        ret_type = parse_type(p);
    }

    /* Body */
    Stmt *body = parse_block(p);

    Decl *d = ast_alloc_decl();
    d->kind = DECL_FN;
    d->fn_name = name;
    d->fn_name_len = name_len;
    d->params = params;
    d->param_count = count;
    d->return_type = ret_type;
    d->fn_body = body;
    d->line = line;
    d->col = col;
    return d;
}

static Decl *parse_struct(Parser *p) {
    int line = p->previous.line, col = p->previous.col;

    if (!check(p, TOK_IDENT)) {
        error_at(p, "expected struct name");
        return NULL;
    }
    const char *name = p->current.start;
    int name_len = p->current.length;
    advance_token(p);

    consume(p, TOK_LBRACE, "expected '{' after struct name");

    int cap = 8;
    StructField *fields = ast_alloc(cap * sizeof(StructField));
    int count = 0;

    while (!check(p, TOK_RBRACE) && !check(p, TOK_EOF)) {
        if (!check(p, TOK_IDENT)) {
            error_at(p, "expected field name");
            return NULL;
        }
        StructField field;
        field.name = p->current.start;
        field.name_len = p->current.length;
        advance_token(p);
        consume(p, TOK_COLON, "expected ':' after field name");
        field.type = parse_type(p);

        if (count >= cap) {
            cap *= 2;
            StructField *new_fields = ast_alloc(cap * sizeof(StructField));
            memcpy(new_fields, fields, count * sizeof(StructField));
            fields = new_fields;
        }
        fields[count++] = field;

        if (!check(p, TOK_RBRACE)) {
            consume(p, TOK_COMMA, "expected ',' after field");
        }
    }

    consume(p, TOK_RBRACE, "expected '}' after struct fields");

    Decl *d = ast_alloc_decl();
    d->kind = DECL_STRUCT;
    d->st_name = name;
    d->st_name_len = name_len;
    d->st_fields = fields;
    d->st_field_count = count;
    d->line = line;
    d->col = col;
    return d;
}

static Decl *parse_declaration(Parser *p) {
    if (match(p, TOK_FN))     return parse_fn(p);
    if (match(p, TOK_STRUCT)) return parse_struct(p);

    error_at(p, "expected 'fn' or 'struct' at top level");
    return NULL;
}

/* ── Public API ────────────────────────────────────── */

void parser_init(Parser *p, const char *source) {
    lexer_init(&p->lex, source);
    p->had_error = 0;
    p->panic_mode = 0;
    p->error_msg[0] = '\0';
    p->error_line = 0;
    p->error_col = 0;
    advance_token(p); /* prime the parser with first token */
}

Program *parser_parse(Parser *p) {
    int cap = 16;
    Decl **decls = ast_alloc(cap * sizeof(Decl *));
    int count = 0;

    while (!check(p, TOK_EOF)) {
        Decl *d = parse_declaration(p);
        if (p->had_error) {
            synchronize(p);
            continue;
        }
        if (d) {
            if (count >= cap) {
                cap *= 2;
                Decl **new_decls = ast_alloc(cap * sizeof(Decl *));
                memcpy(new_decls, decls, count * sizeof(Decl *));
                decls = new_decls;
            }
            decls[count++] = d;
        }
    }

    if (p->had_error) return NULL;

    Program *prog = ast_alloc(sizeof(Program));
    prog->decls = decls;
    prog->decl_count = count;
    return prog;
}

Expr *parser_parse_expr(Parser *p) {
    return parse_expression(p);
}

Stmt *parser_parse_stmt(Parser *p) {
    return parse_statement(p);
}

int parser_had_error(const Parser *p) {
    return p->had_error;
}

const char *parser_error(const Parser *p) {
    return p->error_msg;
}
