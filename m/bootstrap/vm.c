/*
 * vm.c — M bootstrap virtual machine
 *
 * Executes bytecode from the M compiler.
 * Stack-based, function calls via frames.
 */

#include "vm.h"
#include "../../core/tohum_memory.h"
#include <stdio.h>
#include <string.h>
#include <stdarg.h>

/* ── Helpers ───────────────────────────────────────── */

static void vm_set_error(VM *vm, const char *fmt, ...) {
    if (vm->had_error) return;
    vm->had_error = 1;
    va_list args;
    va_start(args, fmt);
    vsnprintf(vm->error_msg, sizeof(vm->error_msg), fmt, args);
    va_end(args);
}

static void push(VM *vm, Val v) {
    if (vm->stack_top >= VM_STACK_MAX) {
        vm_set_error(vm, "stack overflow");
        return;
    }
    vm->stack[vm->stack_top++] = v;
}

static Val pop(VM *vm) {
    if (vm->stack_top <= 0) {
        vm_set_error(vm, "stack underflow");
        Val v = {0};
        v.type = VAL_VOID;
        return v;
    }
    return vm->stack[--vm->stack_top];
}

static Val peek(VM *vm, int distance) {
    return vm->stack[vm->stack_top - 1 - distance];
}

static uint8_t read_byte(CallFrame *frame) {
    return *frame->ip++;
}

static uint16_t read_u16(CallFrame *frame) {
    uint16_t hi = *frame->ip++;
    uint16_t lo = *frame->ip++;
    return (hi << 8) | lo;
}

static int16_t read_i16(CallFrame *frame) {
    return (int16_t)read_u16(frame);
}

static Val make_int(int64_t v) {
    Val val = {0};
    val.type = VAL_INT;
    val.i = v;
    return val;
}

static Val make_float(double v) {
    Val val = {0};
    val.type = VAL_FLOAT;
    val.f = v;
    return val;
}

static Val make_bool(int v) {
    Val val = {0};
    val.type = VAL_BOOL;
    val.b = v;
    return val;
}

static Val make_void(void) {
    Val val = {0};
    val.type = VAL_VOID;
    return val;
}

/* Coerce to numeric for arithmetic */
static double to_number(Val v) {
    switch (v.type) {
    case VAL_INT:   return (double)v.i;
    case VAL_FLOAT: return v.f;
    case VAL_BOOL:  return (double)v.b;
    default:        return 0.0;
    }
}

static int is_truthy(Val v) {
    switch (v.type) {
    case VAL_BOOL:  return v.b;
    case VAL_INT:   return v.i != 0;
    case VAL_FLOAT: return v.f != 0.0;
    case VAL_VOID:  return 0;
    default:        return 1;
    }
}

static void vm_output(VM *vm, const char *fmt, ...) {
    va_list args;
    va_start(args, fmt);
    int remaining = (int)sizeof(vm->output) - vm->output_len;
    if (remaining > 0) {
        int n = vsnprintf(vm->output + vm->output_len, remaining, fmt, args);
        if (n > 0) vm->output_len += n;
    }
    va_end(args);
}

/* ── Execution loop ────────────────────────────────── */

static VMResult run(VM *vm) {
    CallFrame *frame = &vm->frames[vm->frame_count - 1];
    Chunk *chunk = &frame->function->chunk;

    for (;;) {
        if (vm->had_error) return VM_ERROR;

        uint8_t op = read_byte(frame);

        switch (op) {
        case OP_CONST_INT: {
            uint16_t idx = read_u16(frame);
            push(vm, make_int(chunk->ints[idx]));
            break;
        }
        case OP_CONST_FLOAT: {
            uint16_t idx = read_u16(frame);
            push(vm, make_float(chunk->floats[idx]));
            break;
        }
        case OP_CONST_STRING: {
            uint16_t idx = read_u16(frame);
            Val v = {0};
            v.type = VAL_STRING;
            v.s = chunk->strings[idx].str;
            v.s_len = chunk->strings[idx].len;
            push(vm, v);
            break;
        }
        case OP_TRUE:  push(vm, make_bool(1)); break;
        case OP_FALSE: push(vm, make_bool(0)); break;
        case OP_NIL:   push(vm, make_void()); break;
        case OP_POP:   pop(vm); break;

        case OP_LOCAL_GET: {
            uint16_t slot = read_u16(frame);
            push(vm, frame->slots[slot]);
            break;
        }
        case OP_LOCAL_SET: {
            uint16_t slot = read_u16(frame);
            frame->slots[slot] = peek(vm, 0);
            break;
        }

        case OP_GLOBAL_GET:
        case OP_GLOBAL_SET:
            /* Globals not yet implemented — skip index */
            read_u16(frame);
            if (op == OP_GLOBAL_GET) push(vm, make_void());
            break;

        /* Arithmetic */
        case OP_ADD: {
            Val b = pop(vm), a = pop(vm);
            if (a.type == VAL_INT && b.type == VAL_INT)
                push(vm, make_int(a.i + b.i));
            else
                push(vm, make_float(to_number(a) + to_number(b)));
            break;
        }
        case OP_SUB: {
            Val b = pop(vm), a = pop(vm);
            if (a.type == VAL_INT && b.type == VAL_INT)
                push(vm, make_int(a.i - b.i));
            else
                push(vm, make_float(to_number(a) - to_number(b)));
            break;
        }
        case OP_MUL: {
            Val b = pop(vm), a = pop(vm);
            if (a.type == VAL_INT && b.type == VAL_INT)
                push(vm, make_int(a.i * b.i));
            else
                push(vm, make_float(to_number(a) * to_number(b)));
            break;
        }
        case OP_DIV: {
            Val b = pop(vm), a = pop(vm);
            if (b.type == VAL_INT && b.i == 0) {
                vm_set_error(vm, "division by zero");
                return VM_ERROR;
            }
            if (a.type == VAL_INT && b.type == VAL_INT && a.i % b.i == 0)
                push(vm, make_int(a.i / b.i));
            else
                push(vm, make_float(to_number(a) / to_number(b)));
            break;
        }
        case OP_MOD: {
            Val b = pop(vm), a = pop(vm);
            if (a.type == VAL_INT && b.type == VAL_INT) {
                if (b.i == 0) { vm_set_error(vm, "modulo by zero"); return VM_ERROR; }
                push(vm, make_int(a.i % b.i));
            } else {
                vm_set_error(vm, "modulo requires integers");
                return VM_ERROR;
            }
            break;
        }
        case OP_NEG: {
            Val a = pop(vm);
            if (a.type == VAL_INT) push(vm, make_int(-a.i));
            else push(vm, make_float(-to_number(a)));
            break;
        }

        /* Comparison */
        case OP_EQ: {
            Val b = pop(vm), a = pop(vm);
            push(vm, make_bool(to_number(a) == to_number(b)));
            break;
        }
        case OP_NEQ: {
            Val b = pop(vm), a = pop(vm);
            push(vm, make_bool(to_number(a) != to_number(b)));
            break;
        }
        case OP_LT: {
            Val b = pop(vm), a = pop(vm);
            push(vm, make_bool(to_number(a) < to_number(b)));
            break;
        }
        case OP_GT: {
            Val b = pop(vm), a = pop(vm);
            push(vm, make_bool(to_number(a) > to_number(b)));
            break;
        }
        case OP_LTE: {
            Val b = pop(vm), a = pop(vm);
            push(vm, make_bool(to_number(a) <= to_number(b)));
            break;
        }
        case OP_GTE: {
            Val b = pop(vm), a = pop(vm);
            push(vm, make_bool(to_number(a) >= to_number(b)));
            break;
        }

        /* Logic */
        case OP_AND: {
            Val b = pop(vm), a = pop(vm);
            push(vm, make_bool(is_truthy(a) && is_truthy(b)));
            break;
        }
        case OP_OR: {
            Val b = pop(vm), a = pop(vm);
            push(vm, make_bool(is_truthy(a) || is_truthy(b)));
            break;
        }
        case OP_NOT: {
            Val a = pop(vm);
            push(vm, make_bool(!is_truthy(a)));
            break;
        }

        /* Control flow */
        case OP_JUMP: {
            int16_t offset = read_i16(frame);
            frame->ip += offset;
            break;
        }
        case OP_JUMP_FALSE: {
            int16_t offset = read_i16(frame);
            Val cond = pop(vm);
            if (!is_truthy(cond)) {
                frame->ip += offset;
            }
            break;
        }

        /* Function calls */
        case OP_CALL: {
            uint16_t argc = read_u16(frame);
            Val callee_val = vm->stack[vm->stack_top - 1 - argc];

            if (callee_val.type != VAL_INT) {
                vm_set_error(vm, "cannot call non-function");
                return VM_ERROR;
            }

            int func_idx = (int)callee_val.i;
            if (func_idx < 0 || func_idx >= vm->module->func_count) {
                vm_set_error(vm, "invalid function index %d", func_idx);
                return VM_ERROR;
            }

            Function *target = &vm->module->functions[func_idx];
            if (target->param_count != argc) {
                vm_set_error(vm, "expected %d args, got %d",
                         target->param_count, argc);
                return VM_ERROR;
            }

            if (vm->frame_count >= VM_FRAMES_MAX) {
                vm_set_error(vm, "call stack overflow");
                return VM_ERROR;
            }

            /* Remove callee from stack: shift args down */
            Val *arg_start = &vm->stack[vm->stack_top - 1 - argc];
            for (int i = 0; i < argc; i++) {
                arg_start[i] = arg_start[i + 1];
            }
            vm->stack_top--; /* pop the callee value */

            CallFrame *new_frame = &vm->frames[vm->frame_count++];
            new_frame->function = target;
            new_frame->ip = target->chunk.code;
            new_frame->slots = &vm->stack[vm->stack_top - argc];
            frame = new_frame;
            chunk = &frame->function->chunk;

            /* Reserve space for remaining locals */
            int extra_locals = target->local_count - argc;
            for (int i = 0; i < extra_locals; i++) {
                push(vm, make_void());
            }
            break;
        }

        case OP_RETURN: {
            Val result = pop(vm);

            vm->frame_count--;
            if (vm->frame_count == 0) {
                /* Return from top-level: done */
                push(vm, result);
                return VM_OK;
            }

            /* Discard callee's stack space */
            vm->stack_top = (int)(frame->slots - vm->stack);
            push(vm, result);

            frame = &vm->frames[vm->frame_count - 1];
            chunk = &frame->function->chunk;
            break;
        }

        /* Struct */
        case OP_STRUCT_NEW: {
            read_u16(frame); /* type_index — not used yet */
            uint16_t n_fields = read_u16(frame);
            /* For now: struct = array of fields on stack */
            /* Leave fields on stack, push count as marker */
            /* Simplified: just leave the top n values as-is */
            /* A real impl would allocate a struct object */
            (void)n_fields;
            break;
        }
        case OP_FIELD_GET:
            read_u16(frame); /* field index */
            /* Stub: just leave value on stack */
            break;
        case OP_FIELD_SET:
            read_u16(frame);
            pop(vm); /* value */
            /* Stub */
            break;

        /* Memory */
        case OP_ALLOC:
        case OP_FREE:
        case OP_LOAD:
        case OP_STORE:
            /* Stubs for now */
            break;

        /* I/O */
        case OP_PRINT: {
            Val v = pop(vm);
            switch (v.type) {
            case VAL_INT:   vm_output(vm, "%lld", (long long)v.i); break;
            case VAL_FLOAT: vm_output(vm, "%g", v.f); break;
            case VAL_BOOL:  vm_output(vm, "%s", v.b ? "true" : "false"); break;
            case VAL_STRING:vm_output(vm, "%.*s", v.s_len, v.s); break;
            case VAL_VOID:  vm_output(vm, "void"); break;
            default:        vm_output(vm, "?"); break;
            }
            break;
        }

        case OP_HALT:
            return VM_HALT;

        /* NOP removed from opcode set */

        default:
            vm_set_error(vm, "unknown opcode: %d", op);
            return VM_ERROR;
        }
    }
}

/* ── Public API ────────────────────────────────────── */

void vm_init(VM *vm, Module *module) {
    memset(vm, 0, sizeof(VM));
    vm->module = module;
}

VMResult vm_run(VM *vm, const char *entry_name) {
    int name_len = (int)strlen(entry_name);
    int fi = -1;
    for (int i = 0; i < vm->module->func_count; i++) {
        if (vm->module->functions[i].name_len == name_len &&
            memcmp(vm->module->functions[i].name, entry_name, name_len) == 0) {
            fi = i;
            break;
        }
    }

    if (fi < 0) {
        vm->had_error = 1;
        snprintf(vm->error_msg, sizeof(vm->error_msg),
                 "function '%s' not found", entry_name);
        return VM_ERROR;
    }

    Function *entry = &vm->module->functions[fi];

    /* Set up initial frame */
    CallFrame *frame = &vm->frames[0];
    frame->function = entry;
    frame->ip = entry->chunk.code;
    frame->slots = vm->stack;
    vm->frame_count = 1;

    /* Reserve space for locals */
    for (int i = 0; i < entry->local_count; i++) {
        push(vm, make_void());
    }

    return run(vm);
}

Val vm_result(VM *vm) {
    if (vm->stack_top > 0) {
        return vm->stack[vm->stack_top - 1];
    }
    return make_void();
}

const char *vm_error(const VM *vm) {
    return vm->error_msg;
}
