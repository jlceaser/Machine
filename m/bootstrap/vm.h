/*
 * vm.h — M language bootstrap virtual machine
 *
 * Executes M bytecode. Stack-based, no frills.
 * Exists only until M generates native code.
 */

#ifndef M_VM_H
#define M_VM_H

#include "bytecode.h"

#define VM_STACK_MAX 8192
#define VM_FRAMES_MAX 512

typedef struct {
    Function *function;
    uint8_t *ip;        /* instruction pointer */
    Val *slots;         /* pointer into VM stack (frame base) */
} CallFrame;

typedef struct {
    Module *module;

    Val stack[VM_STACK_MAX];
    int stack_top;

    CallFrame frames[VM_FRAMES_MAX];
    int frame_count;

    /* Output capture for testing */
    char output[4096];
    int output_len;

    /* Error state */
    int had_error;
    char error_msg[256];
} VM;

typedef enum {
    VM_OK,
    VM_ERROR,
    VM_HALT,
} VMResult;

/* Initialize VM with a compiled module */
void vm_init(VM *vm, Module *module);

/* Run the named function. Returns VM_OK or VM_ERROR. */
VMResult vm_run(VM *vm, const char *entry_name);

/* Get return value of last run (top of stack) */
Val vm_result(VM *vm);

/* Error info */
const char *vm_error(const VM *vm);

#endif /* M_VM_H */
