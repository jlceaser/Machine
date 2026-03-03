/*
 * bytecode.c — Chunk and Module operations
 */

#include "bytecode.h"
#include "../../core/tohum_memory.h"
#include <string.h>

/* ── Chunk ─────────────────────────────────────────── */

void chunk_init(Chunk *c) {
    memset(c, 0, sizeof(Chunk));
}

void chunk_free(Chunk *c) {
    if (c->code) tohum_free(c->code, c->code_cap);
    if (c->ints) tohum_free(c->ints, c->int_cap * sizeof(int64_t));
    if (c->floats) tohum_free(c->floats, c->float_cap * sizeof(double));
    if (c->strings) tohum_free(c->strings, c->string_cap * sizeof(c->strings[0]));
    if (c->lines) tohum_free(c->lines, c->code_cap * sizeof(int));
    memset(c, 0, sizeof(Chunk));
}

static void chunk_grow(Chunk *c) {
    int old_cap = c->code_cap;
    int new_cap = old_cap < 8 ? 8 : old_cap * 2;

    c->code = tohum_realloc(c->code, old_cap, new_cap);
    c->lines = tohum_realloc(c->lines, old_cap * sizeof(int), new_cap * sizeof(int));
    c->code_cap = new_cap;
}

void chunk_write(Chunk *c, uint8_t byte, int line) {
    if (c->code_len >= c->code_cap) chunk_grow(c);
    c->code[c->code_len] = byte;
    c->lines[c->code_len] = line;
    c->code_len++;
}

void chunk_write_u16(Chunk *c, uint16_t val, int line) {
    chunk_write(c, (uint8_t)(val >> 8), line);
    chunk_write(c, (uint8_t)(val & 0xFF), line);
}

void chunk_write_i16(Chunk *c, int16_t val, int line) {
    chunk_write_u16(c, (uint16_t)val, line);
}

void chunk_patch_u16(Chunk *c, int offset, uint16_t val) {
    c->code[offset] = (uint8_t)(val >> 8);
    c->code[offset + 1] = (uint8_t)(val & 0xFF);
}

void chunk_patch_i16(Chunk *c, int offset, int16_t val) {
    chunk_patch_u16(c, offset, (uint16_t)val);
}

int chunk_add_int(Chunk *c, int64_t val) {
    if (c->int_count >= c->int_cap) {
        int old = c->int_cap;
        c->int_cap = old < 8 ? 8 : old * 2;
        c->ints = tohum_realloc(c->ints, old * sizeof(int64_t),
                                c->int_cap * sizeof(int64_t));
    }
    c->ints[c->int_count] = val;
    return c->int_count++;
}

int chunk_add_float(Chunk *c, double val) {
    if (c->float_count >= c->float_cap) {
        int old = c->float_cap;
        c->float_cap = old < 8 ? 8 : old * 2;
        c->floats = tohum_realloc(c->floats, old * sizeof(double),
                                  c->float_cap * sizeof(double));
    }
    c->floats[c->float_count] = val;
    return c->float_count++;
}

int chunk_add_string(Chunk *c, const char *str, int len) {
    /* Check for existing string (interning) */
    for (int i = 0; i < c->string_count; i++) {
        if (c->strings[i].len == len &&
            memcmp(c->strings[i].str, str, len) == 0) {
            return i;
        }
    }

    if (c->string_count >= c->string_cap) {
        int old = c->string_cap;
        c->string_cap = old < 8 ? 8 : old * 2;
        c->strings = tohum_realloc(c->strings,
                                   old * sizeof(c->strings[0]),
                                   c->string_cap * sizeof(c->strings[0]));
    }
    c->strings[c->string_count].str = str;
    c->strings[c->string_count].len = len;
    return c->string_count++;
}

/* ── Module ────────────────────────────────────────── */

void module_init(Module *m) {
    memset(m, 0, sizeof(Module));
}

void module_free(Module *m) {
    for (int i = 0; i < m->func_count; i++) {
        chunk_free(&m->functions[i].chunk);
    }
    if (m->functions) tohum_free(m->functions, m->func_cap * sizeof(Function));
    if (m->names) tohum_free(m->names, m->name_cap * sizeof(m->names[0]));
    memset(m, 0, sizeof(Module));
}

int module_add_function(Module *m, Function fn) {
    if (m->func_count >= m->func_cap) {
        int old = m->func_cap;
        m->func_cap = old < 8 ? 8 : old * 2;
        m->functions = tohum_realloc(m->functions,
                                     old * sizeof(Function),
                                     m->func_cap * sizeof(Function));
    }
    m->functions[m->func_count] = fn;
    return m->func_count++;
}

int module_add_name(Module *m, const char *name, int len) {
    int idx = module_find_name(m, name, len);
    if (idx >= 0) return idx;

    if (m->name_count >= m->name_cap) {
        int old = m->name_cap;
        m->name_cap = old < 8 ? 8 : old * 2;
        m->names = tohum_realloc(m->names,
                                 old * sizeof(m->names[0]),
                                 m->name_cap * sizeof(m->names[0]));
    }
    m->names[m->name_count].name = name;
    m->names[m->name_count].len = len;
    return m->name_count++;
}

int module_find_name(Module *m, const char *name, int len) {
    for (int i = 0; i < m->name_count; i++) {
        if (m->names[i].len == len &&
            memcmp(m->names[i].name, name, len) == 0) {
            return i;
        }
    }
    return -1;
}
