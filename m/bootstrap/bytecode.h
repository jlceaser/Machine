/*
 * bytecode.h — M language bytecode format
 *
 * Stack-based instruction set for the bootstrap VM.
 * This is NOT Machine VM. This is M's execution engine.
 * Once M self-hosts and generates native code, this disappears.
 */

#ifndef M_BYTECODE_H
#define M_BYTECODE_H

#include <stdint.h>
#include <stddef.h>

typedef enum {
    /* Constants */
    OP_CONST_INT,       /* push i64: [u16 index into int pool] */
    OP_CONST_FLOAT,     /* push f64: [u16 index into float pool] */
    OP_CONST_STRING,    /* push string: [u16 index into string pool] */
    OP_TRUE,            /* push 1 */
    OP_FALSE,           /* push 0 */
    OP_NIL,             /* push 0 (void) */

    /* Stack */
    OP_POP,             /* discard TOS */

    /* Local variables (slot-based) */
    OP_LOCAL_GET,       /* push local: [u16 slot] */
    OP_LOCAL_SET,       /* set local: [u16 slot] */

    /* Global variables */
    OP_GLOBAL_GET,      /* push global: [u16 name_index] */
    OP_GLOBAL_SET,      /* set global: [u16 name_index] */

    /* Arithmetic */
    OP_ADD,
    OP_SUB,
    OP_MUL,
    OP_DIV,
    OP_MOD,
    OP_NEG,             /* unary negate */

    /* Comparison */
    OP_EQ,
    OP_NEQ,
    OP_LT,
    OP_GT,
    OP_LTE,
    OP_GTE,

    /* Logic */
    OP_AND,
    OP_OR,
    OP_NOT,

    /* Control flow */
    OP_JUMP,            /* unconditional: [i16 offset] */
    OP_JUMP_FALSE,      /* conditional: [i16 offset] */

    /* Functions */
    OP_CALL,            /* call: [u16 arg_count] */
    OP_RETURN,          /* return from function */

    /* Struct operations */
    OP_STRUCT_NEW,      /* allocate struct: [u16 type_index] [u16 field_count] */
    OP_FIELD_GET,       /* get field: [u16 field_index] */
    OP_FIELD_SET,       /* set field: [u16 field_index] */

    /* Memory */
    OP_ALLOC,           /* allocate: size on stack */
    OP_FREE,            /* free: pointer on stack */
    OP_LOAD,            /* dereference pointer */
    OP_STORE,           /* store through pointer: [value] [ptr] */

    /* Built-in functions */
    OP_PRINT,           /* print TOS */
    OP_BUILTIN_LEN,     /* len(string) -> int */
    OP_BUILTIN_CHAR_AT, /* char_at(string, int) -> int */
    OP_BUILTIN_SUBSTR,  /* substr(string, start, len) -> string */
    OP_BUILTIN_STR_CONCAT, /* str_concat(a, b) -> string */
    OP_BUILTIN_INT_TO_STR, /* int_to_str(int) -> string */
    OP_BUILTIN_STR_EQ,    /* str_eq(a, b) -> bool */

    /* System */
    OP_HALT,            /* stop execution */
} OpCode;

/* --- Value types in the VM --- */

typedef enum {
    VAL_INT,
    VAL_FLOAT,
    VAL_BOOL,
    VAL_STRING,
    VAL_PTR,
    VAL_STRUCT,
    VAL_VOID,
} ValType;

typedef struct {
    ValType type;
    union {
        int64_t i;
        double f;
        int b;
        struct { const char *s; int s_len; };
        void *ptr;
        struct { int64_t *fields; int n_fields; int type_id; };
    };
} Val;

/* --- Chunk: a sequence of bytecode --- */

typedef struct {
    uint8_t *code;
    int code_len;
    int code_cap;

    /* Constant pools */
    int64_t *ints;
    int int_count;
    int int_cap;

    double *floats;
    int float_count;
    int float_cap;

    /* String pool: interned strings */
    struct { const char *str; int len; } *strings;
    int string_count;
    int string_cap;

    /* Line info for error messages */
    int *lines;     /* parallel to code: source line per byte */
} Chunk;

/* --- Function object --- */

typedef struct {
    const char *name;
    int name_len;
    int param_count;
    int local_count;    /* total locals including params */
    Chunk chunk;
} Function;

/* --- Module: compilation result --- */

typedef struct {
    Function *functions;
    int func_count;
    int func_cap;

    /* Name table: maps string index to name */
    struct { const char *name; int len; } *names;
    int name_count;
    int name_cap;
} Module;

/* --- Chunk operations --- */

void chunk_init(Chunk *c);
void chunk_free(Chunk *c);
void chunk_write(Chunk *c, uint8_t byte, int line);
void chunk_write_u16(Chunk *c, uint16_t val, int line);
void chunk_write_i16(Chunk *c, int16_t val, int line);
int chunk_add_int(Chunk *c, int64_t val);
int chunk_add_float(Chunk *c, double val);
int chunk_add_string(Chunk *c, const char *str, int len);

/* Patch a u16 at a given offset */
void chunk_patch_u16(Chunk *c, int offset, uint16_t val);
void chunk_patch_i16(Chunk *c, int offset, int16_t val);

/* --- Module operations --- */

void module_init(Module *m);
void module_free(Module *m);
int module_add_function(Module *m, Function fn);
int module_add_name(Module *m, const char *name, int len);
int module_find_name(Module *m, const char *name, int len);

#endif /* M_BYTECODE_H */
