/*
 * codegen.c — M language bytecode compiler
 *
 * Walks AST, emits bytecode. Each function gets its own Chunk.
 * Local variables are assigned stack slots at compile time.
 */

#include "codegen.h"
#include "../../core/tohum_memory.h"
#include <stdio.h>
#include <string.h>

/* ── Local variable tracking ───────────────────────── */

typedef struct {
    const char *name;
    int name_len;
    int slot;
    int depth;      /* scope depth (0 = function top) */
} Local;

#define MAX_LOCALS 256

typedef struct {
    Compiler *compiler;
    Chunk *chunk;           /* current chunk being written to */
    Local locals[MAX_LOCALS];
    int local_count;
    int scope_depth;
    int func_index;         /* index in module */
} CodegenCtx;

static void error(CodegenCtx *ctx, int line, const char *msg) {
    if (ctx->compiler->had_error) return;
    ctx->compiler->had_error = 1;
    ctx->compiler->error_line = line;
    snprintf(ctx->compiler->error_msg, sizeof(ctx->compiler->error_msg),
             "line %d: %s", line, msg);
}

/* ── Local variable resolution ─────────────────────── */

static int resolve_local(CodegenCtx *ctx, const char *name, int len) {
    for (int i = ctx->local_count - 1; i >= 0; i--) {
        if (ctx->locals[i].name_len == len &&
            memcmp(ctx->locals[i].name, name, len) == 0) {
            return ctx->locals[i].slot;
        }
    }
    return -1; /* not found = global */
}

static int add_local(CodegenCtx *ctx, const char *name, int name_len, int line) {
    if (ctx->local_count >= MAX_LOCALS) {
        error(ctx, line, "too many local variables");
        return -1;
    }
    int slot = ctx->local_count;
    Local *local = &ctx->locals[ctx->local_count++];
    local->name = name;
    local->name_len = name_len;
    local->slot = slot;
    local->depth = ctx->scope_depth;
    return slot;
}

static void begin_scope(CodegenCtx *ctx) {
    ctx->scope_depth++;
}

static void end_scope(CodegenCtx *ctx) {
    /* Pop locals from this scope */
    while (ctx->local_count > 0 &&
           ctx->locals[ctx->local_count - 1].depth == ctx->scope_depth) {
        chunk_write(ctx->chunk, OP_POP, 0);
        ctx->local_count--;
    }
    ctx->scope_depth--;
}

/* ── Emit helpers ──────────────────────────────────── */

static void emit(CodegenCtx *ctx, uint8_t op, int line) {
    chunk_write(ctx->chunk, op, line);
}

static void emit_u16(CodegenCtx *ctx, uint16_t val, int line) {
    chunk_write_u16(ctx->chunk, val, line);
}

static int emit_jump(CodegenCtx *ctx, uint8_t op, int line) {
    emit(ctx, op, line);
    int offset = ctx->chunk->code_len;
    emit_u16(ctx, 0, line); /* placeholder */
    return offset;
}

static void patch_jump(CodegenCtx *ctx, int offset) {
    int jump = ctx->chunk->code_len - offset - 2;
    if (jump > 32767 || jump < -32768) {
        error(ctx, 0, "jump too far");
        return;
    }
    chunk_patch_i16(ctx->chunk, offset, (int16_t)jump);
}

/* ── Expression codegen ────────────────────────────── */

static void gen_expr(CodegenCtx *ctx, Expr *e);
static void gen_stmt(CodegenCtx *ctx, Stmt *s);

static int find_function(Compiler *c, const char *name, int len) {
    for (int i = 0; i < c->module.func_count; i++) {
        if (c->module.functions[i].name_len == len &&
            memcmp(c->module.functions[i].name, name, len) == 0) {
            return i;
        }
    }
    return -1;
}

static void gen_expr(CodegenCtx *ctx, Expr *e) {
    if (!e) return;

    switch (e->kind) {
    case EXPR_INT_LIT: {
        int idx = chunk_add_int(ctx->chunk, e->int_val);
        emit(ctx, OP_CONST_INT, e->line);
        emit_u16(ctx, (uint16_t)idx, e->line);
        break;
    }

    case EXPR_FLOAT_LIT: {
        int idx = chunk_add_float(ctx->chunk, e->float_val);
        emit(ctx, OP_CONST_FLOAT, e->line);
        emit_u16(ctx, (uint16_t)idx, e->line);
        break;
    }

    case EXPR_STRING_LIT: {
        int idx = chunk_add_string(ctx->chunk, e->str, e->str_len);
        emit(ctx, OP_CONST_STRING, e->line);
        emit_u16(ctx, (uint16_t)idx, e->line);
        break;
    }

    case EXPR_BOOL_LIT:
        emit(ctx, e->bool_val ? OP_TRUE : OP_FALSE, e->line);
        break;

    case EXPR_IDENT: {
        int slot = resolve_local(ctx, e->ident, e->ident_len);
        if (slot >= 0) {
            emit(ctx, OP_LOCAL_GET, e->line);
            emit_u16(ctx, (uint16_t)slot, e->line);
        } else {
            /* Try as function name */
            int fi = find_function(ctx->compiler, e->ident, e->ident_len);
            if (fi >= 0) {
                /* Push function index as int — resolved at call site */
                int idx = chunk_add_int(ctx->chunk, fi);
                emit(ctx, OP_CONST_INT, e->line);
                emit_u16(ctx, (uint16_t)idx, e->line);
            } else {
                int ni = module_add_name(&ctx->compiler->module,
                                         e->ident, e->ident_len);
                emit(ctx, OP_GLOBAL_GET, e->line);
                emit_u16(ctx, (uint16_t)ni, e->line);
            }
        }
        break;
    }

    case EXPR_BINARY: {
        gen_expr(ctx, e->lhs);
        gen_expr(ctx, e->rhs);
        switch (e->bin_op) {
        case BIN_ADD:  emit(ctx, OP_ADD, e->line); break;
        case BIN_SUB:  emit(ctx, OP_SUB, e->line); break;
        case BIN_MUL:  emit(ctx, OP_MUL, e->line); break;
        case BIN_DIV:  emit(ctx, OP_DIV, e->line); break;
        case BIN_MOD:  emit(ctx, OP_MOD, e->line); break;
        case BIN_EQ:   emit(ctx, OP_EQ, e->line); break;
        case BIN_NEQ:  emit(ctx, OP_NEQ, e->line); break;
        case BIN_LT:   emit(ctx, OP_LT, e->line); break;
        case BIN_GT:   emit(ctx, OP_GT, e->line); break;
        case BIN_LTE:  emit(ctx, OP_LTE, e->line); break;
        case BIN_GTE:  emit(ctx, OP_GTE, e->line); break;
        case BIN_AND:  emit(ctx, OP_AND, e->line); break;
        case BIN_OR:   emit(ctx, OP_OR, e->line); break;
        default: break;
        }
        break;
    }

    case EXPR_UNARY:
        gen_expr(ctx, e->operand);
        switch (e->unary_op) {
        case UN_NEG:   emit(ctx, OP_NEG, e->line); break;
        case UN_NOT:   emit(ctx, OP_NOT, e->line); break;
        case UN_ADDR:  /* &x — address-of, handled later with pointers */
            break;
        case UN_DEREF: emit(ctx, OP_LOAD, e->line); break;
        default: break;
        }
        break;

    case EXPR_CALL: {
        /* Push callee first, then arguments */
        gen_expr(ctx, e->callee);
        for (int i = 0; i < e->arg_count; i++) {
            gen_expr(ctx, e->args[i]);
        }
        emit(ctx, OP_CALL, e->line);
        emit_u16(ctx, (uint16_t)e->arg_count, e->line);
        break;
    }

    case EXPR_MEMBER: {
        gen_expr(ctx, e->object);
        int fi = chunk_add_string(ctx->chunk, e->member, e->member_len);
        emit(ctx, OP_FIELD_GET, e->line);
        emit_u16(ctx, (uint16_t)fi, e->line);
        break;
    }

    case EXPR_INDEX:
        gen_expr(ctx, e->target);
        gen_expr(ctx, e->index_expr);
        emit(ctx, OP_LOAD, e->line); /* array[idx] = pointer arithmetic + load */
        break;

    case EXPR_STRUCT_LIT: {
        /* Push field values in order, then create struct */
        for (int i = 0; i < e->field_count; i++) {
            gen_expr(ctx, e->fields[i].value);
        }
        int ti = chunk_add_string(ctx->chunk, e->struct_name, e->struct_name_len);
        emit(ctx, OP_STRUCT_NEW, e->line);
        emit_u16(ctx, (uint16_t)ti, e->line);
        emit_u16(ctx, (uint16_t)e->field_count, e->line);
        break;
    }
    }
}

/* ── Statement codegen ─────────────────────────────── */

static void gen_stmt(CodegenCtx *ctx, Stmt *s) {
    if (!s) return;

    switch (s->kind) {
    case STMT_LET:
    case STMT_VAR: {
        if (s->var_init) {
            gen_expr(ctx, s->var_init);
        } else {
            emit(ctx, OP_NIL, s->line);
        }
        int slot = add_local(ctx, s->var_name, s->var_name_len, s->line);
        emit(ctx, OP_LOCAL_SET, s->line);
        emit_u16(ctx, (uint16_t)slot, s->line);
        break;
    }

    case STMT_RETURN:
        if (s->ret_expr) {
            gen_expr(ctx, s->ret_expr);
        } else {
            emit(ctx, OP_NIL, s->line);
        }
        emit(ctx, OP_RETURN, s->line);
        break;

    case STMT_IF: {
        gen_expr(ctx, s->if_cond);
        int else_jump = emit_jump(ctx, OP_JUMP_FALSE, s->line);

        gen_stmt(ctx, s->if_then);

        if (s->if_else) {
            int end_jump = emit_jump(ctx, OP_JUMP, s->line);
            patch_jump(ctx, else_jump);
            gen_stmt(ctx, s->if_else);
            patch_jump(ctx, end_jump);
        } else {
            patch_jump(ctx, else_jump);
        }
        break;
    }

    case STMT_WHILE: {
        int loop_start = ctx->chunk->code_len;
        gen_expr(ctx, s->while_cond);
        int exit_jump = emit_jump(ctx, OP_JUMP_FALSE, s->line);

        gen_stmt(ctx, s->while_body);

        /* Jump back to loop start */
        emit(ctx, OP_JUMP, s->line);
        int back = ctx->chunk->code_len;
        emit_u16(ctx, 0, s->line);
        int offset = loop_start - back - 2;
        chunk_patch_i16(ctx->chunk, back, (int16_t)offset);

        patch_jump(ctx, exit_jump);
        break;
    }

    case STMT_BLOCK:
        begin_scope(ctx);
        for (int i = 0; i < s->stmt_count; i++) {
            gen_stmt(ctx, s->stmts[i]);
        }
        end_scope(ctx);
        break;

    case STMT_ASSIGN: {
        gen_expr(ctx, s->assign_value);

        /* Simple identifier assignment */
        if (s->assign_target->kind == EXPR_IDENT) {
            int slot = resolve_local(ctx, s->assign_target->ident,
                                     s->assign_target->ident_len);
            if (slot >= 0) {
                emit(ctx, OP_LOCAL_SET, s->line);
                emit_u16(ctx, (uint16_t)slot, s->line);
            } else {
                int ni = module_add_name(&ctx->compiler->module,
                                         s->assign_target->ident,
                                         s->assign_target->ident_len);
                emit(ctx, OP_GLOBAL_SET, s->line);
                emit_u16(ctx, (uint16_t)ni, s->line);
            }
        } else if (s->assign_target->kind == EXPR_MEMBER) {
            /* obj.field = value → push obj, push value, field_set */
            gen_expr(ctx, s->assign_target->object);
            int fi = chunk_add_string(ctx->chunk,
                                      s->assign_target->member,
                                      s->assign_target->member_len);
            emit(ctx, OP_FIELD_SET, s->line);
            emit_u16(ctx, (uint16_t)fi, s->line);
        }
        break;
    }

    case STMT_EXPR:
        gen_expr(ctx, s->expr);
        emit(ctx, OP_POP, s->line); /* discard result */
        break;

    case STMT_FREE:
        gen_expr(ctx, s->free_expr);
        emit(ctx, OP_FREE, s->line);
        break;
    }
}

/* ── Declaration codegen ───────────────────────────── */

static void gen_function(Compiler *c, Decl *d) {
    Function fn;
    memset(&fn, 0, sizeof(fn));
    fn.name = d->fn_name;
    fn.name_len = d->fn_name_len;
    fn.param_count = d->param_count;
    chunk_init(&fn.chunk);

    /* Reserve slot in module first so recursive calls can find it */
    int fi = module_add_function(&c->module, fn);

    CodegenCtx ctx;
    memset(&ctx, 0, sizeof(ctx));
    ctx.compiler = c;
    ctx.chunk = &c->module.functions[fi].chunk;
    ctx.scope_depth = 0;
    ctx.func_index = fi;

    /* Parameters are the first locals */
    for (int i = 0; i < d->param_count; i++) {
        add_local(&ctx, d->params[i].name, d->params[i].name_len, d->line);
    }

    /* Compile body */
    if (d->fn_body && d->fn_body->kind == STMT_BLOCK) {
        for (int i = 0; i < d->fn_body->stmt_count; i++) {
            gen_stmt(&ctx, d->fn_body->stmts[i]);
        }
    }

    /* Implicit return at end */
    emit(&ctx, OP_NIL, d->line);
    emit(&ctx, OP_RETURN, d->line);

    c->module.functions[fi].local_count = ctx.local_count;
}

/* ── Public API ────────────────────────────────────── */

void compiler_init(Compiler *c) {
    memset(c, 0, sizeof(Compiler));
    module_init(&c->module);
}

int compiler_compile(Compiler *c, Program *prog) {
    if (!prog) return -1;

    /* First pass: register all function names so forward calls work */
    for (int i = 0; i < prog->decl_count; i++) {
        if (prog->decls[i]->kind == DECL_FN) {
            /* Pre-register: actual compilation in second pass */
        }
    }

    /* Compile each declaration */
    for (int i = 0; i < prog->decl_count; i++) {
        Decl *d = prog->decls[i];
        switch (d->kind) {
        case DECL_FN:
            gen_function(c, d);
            break;
        case DECL_STRUCT:
            /* Struct layout tracked but no bytecode emitted */
            break;
        }

        if (c->had_error) return -1;
    }

    return 0;
}

Module *compiler_module(Compiler *c) {
    return &c->module;
}

int compiler_had_error(const Compiler *c) {
    return c->had_error;
}

const char *compiler_error(const Compiler *c) {
    return c->error_msg;
}
