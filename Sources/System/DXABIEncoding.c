#include "DXABIEncoding.h"
#include <stddef.h>
#include <string.h>

/* Deliberately conservative grammar. Unknown encodings fail, not guessed ABI aliases. */
static bool digit(char c) { return c >= '0' && c <= '9'; }
static bool quoted(const char **p) {
    if (*(*p)++ != '"') return false;
    while (**p && **p != '"') {
        if (**p == '\\') { ++*p; if (!**p) return false; }
        ++*p;
    }
    if (**p != '"') return false;
    ++*p; return true;
}
static bool type(const char **p, unsigned depth) {
    if (depth > 32 || !**p) return false;
    while (**p && strchr("rnNoORV", **p)) ++*p;
    char c = *(*p)++;
    if (c && strchr("cislqCISLQfdDBv*#:?", c)) return true;
    if (c == '@') {
        if (**p == '?') ++*p;
        else if (**p == '"' && !quoted(p)) return false;
        return true;
    }
    if (c == '^') return type(p, depth + 1);
    if (c == 'b') {
        if (!digit(**p)) return false;
        while (digit(**p)) ++*p;
        return true;
    }
    if (c == '[') {
        if (!digit(**p)) return false;
        while (digit(**p)) ++*p;
        if (!type(p, depth + 1) || **p != ']') return false;
        ++*p; return true;
    }
    if (c == '{' || c == '(') {
        char end = c == '{' ? '}' : ')';
        const char *name = *p;
        while (**p && **p != '=' && **p != end) {
            if (strchr("{}()[]\"", **p)) return false;
            ++*p;
        }
        if (*p == name || !**p) return false;
        if (**p == '=') {
            ++*p;
            while (**p && **p != end) {
                if (**p == '"' && !quoted(p)) return false;
                if (!type(p, depth + 1)) return false;
            }
        }
        if (**p != end) return false;
        ++*p; return true;
    }
    return false;
}
static bool offset(const char **p) {
    if (**p == '+' || **p == '-') { ++*p; if (!digit(**p)) return false; }
    while (digit(**p)) ++*p;
    return true;
}
bool DXABIEncodingMatches(const char *a, const char *b) {
    if (!a || !b || !*a || !*b || strlen(a) > 4096 || strlen(b) > 4096) return false;
    unsigned count = 0;
    while (*a && *b) {
        const char *aa = a, *bb = b;
        if (!type(&a, 0) || !type(&b, 0)) return false;
        size_t n = (size_t)(a - aa);
        if (n != (size_t)(b - bb) || memcmp(aa, bb, n) != 0) return false;
        if (!offset(&a) || !offset(&b)) return false;
        if (++count > 128) return false;
    }
    return count >= 3 && !*a && !*b; /* result, self, _cmd at minimum */
}
