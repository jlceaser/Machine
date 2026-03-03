/*
 * ast.h — M language abstract syntax tree
 *
 * Every M program becomes a tree of these nodes.
 * All memory goes through tohum_alloc.
 */

#ifndef M_AST_H
#define M_AST_H

#include "lexer.h"
#include <stddef.h>

/* --- Type representation --- */

typedef enum {
    TYPE_U8, TYPE_U16, TYPE_U32, TYPE_U64,
    TYPE_I8, TYPE_I16, TYPE_I32, TYPE_I64,
    TYPE_F64, TYPE_BOOL, TYPE_VOID,
    TYPE_PTR,       /* ptr<inner> */
    TYPE_ARRAY,     /* [inner; size] */
    TYPE_SLICE,     /* []inner */
    TYPE_NAMED,     /* struct name */
} TypeKind;

typedef struct TypeNode {
    TypeKind kind;
    struct TypeNode *inner;     /* for PTR, ARRAY, SLICE */
    const char *name;           /* for NAMED */
    int name_len;
    int array_size;             /* for ARRAY */
    int line, col;
} TypeNode;

/* --- Expressions --- */

typedef enum {
    EXPR_INT_LIT,
    EXPR_FLOAT_LIT,
    EXPR_STRING_LIT,
    EXPR_BOOL_LIT,
    EXPR_IDENT,
    EXPR_BINARY,
    EXPR_UNARY,
    EXPR_CALL,
    EXPR_MEMBER,        /* a.b */
    EXPR_INDEX,         /* a[i] */
    EXPR_STRUCT_LIT,    /* Point { x: 1, y: 2 } */
} ExprKind;

typedef enum {
    BIN_ADD, BIN_SUB, BIN_MUL, BIN_DIV, BIN_MOD,
    BIN_EQ, BIN_NEQ, BIN_LT, BIN_GT, BIN_LTE, BIN_GTE,
    BIN_AND, BIN_OR,
    UN_NEG, UN_NOT,     /* unary */
    UN_ADDR,            /* &x */
    UN_DEREF,           /* *x */
} OpKind;

typedef struct Expr Expr;
typedef struct Stmt Stmt;

/* Named expression pair: for struct literals and call args */
typedef struct {
    const char *name;
    int name_len;
    Expr *value;
} FieldInit;

struct Expr {
    ExprKind kind;
    int line, col;

    union {
        /* INT_LIT */
        long long int_val;

        /* FLOAT_LIT */
        double float_val;

        /* STRING_LIT */
        struct { const char *str; int str_len; };

        /* BOOL_LIT */
        int bool_val;

        /* IDENT */
        struct { const char *ident; int ident_len; };

        /* BINARY */
        struct { OpKind bin_op; Expr *lhs; Expr *rhs; };

        /* UNARY */
        struct { OpKind unary_op; Expr *operand; };

        /* CALL: callee(args...) */
        struct { Expr *callee; Expr **args; int arg_count; };

        /* MEMBER: object.member_name */
        struct { Expr *object; const char *member; int member_len; };

        /* INDEX: target[index_expr] */
        struct { Expr *target; Expr *index_expr; };

        /* STRUCT_LIT: TypeName { field: val, ... } */
        struct {
            const char *struct_name;
            int struct_name_len;
            FieldInit *fields;
            int field_count;
        };
    };
};

/* --- Statements --- */

typedef enum {
    STMT_LET,       /* let x: T = expr; */
    STMT_VAR,       /* var x: T = expr; */
    STMT_RETURN,    /* return expr; */
    STMT_IF,        /* if cond { ... } else { ... } */
    STMT_WHILE,     /* while cond { ... } */
    STMT_EXPR,      /* expression; */
    STMT_BLOCK,     /* { stmts... } */
    STMT_ASSIGN,    /* target = expr; */
    STMT_FREE,      /* free(expr); */
} StmtKind;

struct Stmt {
    StmtKind kind;
    int line, col;

    union {
        /* LET / VAR */
        struct {
            const char *var_name;
            int var_name_len;
            TypeNode *var_type;     /* NULL if inferred */
            Expr *var_init;         /* NULL if no initializer */
        };

        /* RETURN */
        Expr *ret_expr;     /* NULL for bare return */

        /* IF */
        struct {
            Expr *if_cond;
            Stmt *if_then;          /* always a BLOCK */
            Stmt *if_else;          /* NULL or BLOCK or another IF */
        };

        /* WHILE */
        struct { Expr *while_cond; Stmt *while_body; };

        /* EXPR */
        Expr *expr;

        /* BLOCK */
        struct { Stmt **stmts; int stmt_count; };

        /* ASSIGN */
        struct { Expr *assign_target; Expr *assign_value; };

        /* FREE */
        Expr *free_expr;
    };
};

/* --- Top-level declarations --- */

typedef struct {
    const char *name;
    int name_len;
    TypeNode *type;
} Param;

typedef enum {
    DECL_FN,
    DECL_STRUCT,
} DeclKind;

typedef struct {
    const char *name;
    int name_len;
    TypeNode *type;
} StructField;

typedef struct Decl {
    DeclKind kind;
    int line, col;

    union {
        /* FN */
        struct {
            const char *fn_name;
            int fn_name_len;
            Param *params;
            int param_count;
            TypeNode *return_type;  /* NULL for void */
            Stmt *fn_body;          /* BLOCK */
        };

        /* STRUCT */
        struct {
            const char *st_name;
            int st_name_len;
            StructField *st_fields;
            int st_field_count;
        };
    };
} Decl;

/* --- Program (root) --- */

typedef struct {
    Decl **decls;
    int decl_count;
} Program;

/* --- AST memory management --- */

Expr *ast_alloc_expr(void);
Stmt *ast_alloc_stmt(void);
Decl *ast_alloc_decl(void);
TypeNode *ast_alloc_type(void);
void *ast_alloc(size_t size);

/* Free entire program tree */
void ast_free_program(Program *prog);

#endif /* M_AST_H */
