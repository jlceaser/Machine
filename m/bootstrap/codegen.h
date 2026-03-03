/*
 * codegen.h — M language code generator
 *
 * Walks the AST, emits bytecode into a Module.
 */

#ifndef M_CODEGEN_H
#define M_CODEGEN_H

#include "ast.h"
#include "bytecode.h"

typedef struct {
    Module module;
    int had_error;
    char error_msg[256];
    int error_line;
} Compiler;

/* Initialize compiler */
void compiler_init(Compiler *c);

/* Compile a parsed program into bytecode. Returns 0 on success. */
int compiler_compile(Compiler *c, Program *prog);

/* Get the compiled module (only valid after successful compile) */
Module *compiler_module(Compiler *c);

/* Error info */
int compiler_had_error(const Compiler *c);
const char *compiler_error(const Compiler *c);

#endif /* M_CODEGEN_H */
