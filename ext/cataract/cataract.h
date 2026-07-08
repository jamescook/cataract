#ifndef CATARACT_NEW_H
#define CATARACT_NEW_H

#include <ruby.h>
#include <ruby/encoding.h>

// ============================================================================
// Global struct class references
// ============================================================================

extern VALUE cRule;
extern VALUE cDeclaration;
extern VALUE cAtRule;
extern VALUE cStylesheet;
extern VALUE cImportStatement;
extern VALUE cMediaQuery;
extern VALUE cConditionalGroup;

// Error class references
extern VALUE eCataractError;
extern VALUE eDepthError;
extern VALUE eSizeError;
extern VALUE eParseError;

// ============================================================================
// Struct field indices
// ============================================================================

// Rule struct field indices (id, selector, declarations, specificity, parent_rule_id, nesting_style, selector_list_id, media_query_id, conditional_group_id)
#define RULE_ID 0
#define RULE_SELECTOR 1
#define RULE_DECLARATIONS 2
#define RULE_SPECIFICITY 3
#define RULE_PARENT_RULE_ID 4
#define RULE_NESTING_STYLE 5
#define RULE_SELECTOR_LIST_ID 6
#define RULE_MEDIA_QUERY_ID 7
#define RULE_CONDITIONAL_GROUP_ID 8

// Nesting style constants
#define NESTING_STYLE_IMPLICIT 0  // .parent { .child { } } - no &
#define NESTING_STYLE_EXPLICIT 1  // .parent { &.child { } } - has &

// Named constants for parse_css_recursive() call clarity
// (Makes call sites self-documenting)
#define NO_PARENT_MEDIA Qnil
#define NO_PARENT_SELECTOR Qnil
#define NO_PARENT_RULE_ID Qnil
#define NO_MEDIA_QUERY_ID (-1)
#define NO_CONDITIONAL_GROUP_ID (-1)

// Declaration struct field indices (property, value, important)
#define DECL_PROPERTY 0
#define DECL_VALUE 1
#define DECL_IMPORTANT 2

// AtRule struct field indices (id, selector, content, specificity, media_query_id, conditional_group_id)
// Matches Rule interface for duck-typing, but AtRule has fewer members - its
// indices do NOT line up with Rule's past AT_RULE_SPECIFICITY (e.g. index 4
// is media_query_id here but parent_rule_id on Rule), so never read a field
// off an AtRule using a RULE_* index beyond AT_RULE_SPECIFICITY.
#define AT_RULE_ID 0
#define AT_RULE_SELECTOR 1
#define AT_RULE_CONTENT 2
#define AT_RULE_SPECIFICITY 3
#define AT_RULE_MEDIA_QUERY_ID 4
#define AT_RULE_CONDITIONAL_GROUP_ID 5

// ConditionalGroup struct field indices (id, type, name, condition, parent_id)
#define CONDITIONAL_GROUP_ID 0
#define CONDITIONAL_GROUP_TYPE 1
#define CONDITIONAL_GROUP_NAME 2
#define CONDITIONAL_GROUP_CONDITION 3
#define CONDITIONAL_GROUP_PARENT_ID 4

// ============================================================================
// Macros
// ============================================================================

// Whitespace detection
#define IS_WHITESPACE(c) ((c) == ' ' || (c) == '\t' || (c) == '\n' || (c) == '\r')

// Debug output (disabled by default)
// #define CATARACT_DEBUG 1

#ifdef CATARACT_DEBUG
  #define DEBUG_PRINTF(...) printf(__VA_ARGS__)
#else
  #define DEBUG_PRINTF(...) ((void)0)
#endif

// Trim leading whitespace - modifies start pointer
static inline void trim_leading(const char **start, const char *end) {
    while (*start < end && IS_WHITESPACE(**start)) {
        (*start)++;
    }
}

// Trim trailing whitespace - modifies end pointer
static inline void trim_trailing(const char *start, const char **end) {
    while (*end > start && IS_WHITESPACE(*(*end - 1))) {
        (*end)--;
    }
}

// Detect and strip a trailing '!important' marker from a value range.
// Assumes [val_start, *val_end) has already had trailing whitespace trimmed.
// Shared by every declaration-value scanner (css_parser.c's parse_declarations
// and parse_mixed_block, and cataract.c's declaration-string parser) so they
// all agree on what counts as important.
//
// The CSS2.1 grammar defines the IMPORTANT_SYM lexical token as:
//   "!"({w}|{comment})*{I}{M}{P}{O}{R}{T}{A}{N}{T}
// (https://www.w3.org/TR/CSS2/grammar.html) - i.e. zero or more whitespace
// tokens are allowed between '!' and 'important'.
//
// On match, *val_end is updated to exclude the marker (not including any
// whitespace immediately before the '!' - callers should trim_trailing again)
// and 1 is returned. Otherwise *val_end is left untouched and 0 is returned.
static inline int extract_important(const char *val_start, const char **val_end) {
    const char *check = *val_end;
    if (check - val_start < 10) return 0;  // strlen("!important") = 10

    while (check > val_start && IS_WHITESPACE(*(check - 1))) check--;

    if (check - val_start < 9 || strncmp(check - 9, "important", 9) != 0) return 0;
    check -= 9;

    while (check > val_start && IS_WHITESPACE(*(check - 1))) check--;

    if (check <= val_start || *(check - 1) != '!') return 0;
    check--;

    *val_end = check;
    return 1;
}

// Property/value/important spans found by parse_one_declaration(), in terms
// of offsets into the original CSS buffer - callers build whatever VALUEs
// (Declaration structs, error messages, etc.) they need from these.
struct declaration_span {
    const char *prop_start;
    const char *prop_end;   // trimmed
    const char *val_start;
    const char *val_end;    // trimmed; excludes a trailing '!important' marker
    int is_important;
};

// Scans one "prop: value" declaration starting at *pos_ptr, stopping at
// `end` (never reads past it). On success, fills `span`, advances *pos_ptr
// past the terminating ';' (leaving it at a '}' or `end` if there wasn't
// one), and returns 1. On failure - no ':' found before a stop character -
// *pos_ptr is left at the stop character (or `end`) and 0 is returned,
// leaving recovery (skip-to-semicolon, raise, etc.) to the caller, since
// that differs by call site.
//
// stop_prop_scan_early: if true, ';' and '{' also terminate the property-name
// scan (used by the two block-oriented parsers, so a missing colon is
// detected without scanning past the declaration's boundary); if false,
// only ':' terminates it (used by the standalone declaration-list parser,
// whose input never contains braces).
//
// The value scan always tracks paren depth (so a ';' inside url(...) or
// rgba(...) doesn't end the value early) and always stops at an unguarded
// '}', which is harmless for callers whose `end` never contains one.
static inline int parse_one_declaration(const char **pos_ptr, const char *end,
                                         int stop_prop_scan_early,
                                         struct declaration_span *span) {
    const char *pos = *pos_ptr;
    const char *prop_start = pos;

    if (stop_prop_scan_early) {
        while (pos < end && *pos != ':' && *pos != ';' && *pos != '{') pos++;
    } else {
        while (pos < end && *pos != ':') pos++;
    }

    if (pos >= end || *pos != ':') {
        *pos_ptr = pos;
        return 0;
    }

    const char *prop_end = pos;
    trim_trailing(prop_start, &prop_end);
    trim_leading(&prop_start, prop_end);

    pos++;  // Skip ':'
    while (pos < end && IS_WHITESPACE(*pos)) pos++;

    const char *val_start = pos;
    int paren_depth = 0;
    while (pos < end && *pos != '}') {
        if (*pos == '(') paren_depth++;
        else if (*pos == ')') paren_depth--;
        else if (*pos == ';' && paren_depth == 0) break;
        pos++;
    }
    const char *val_end = pos;
    trim_trailing(val_start, &val_end);

    int is_important = extract_important(val_start, &val_end) ? 1 : 0;
    trim_trailing(val_start, &val_end);

    if (pos < end && *pos == ';') pos++;

    span->prop_start = prop_start;
    span->prop_end = prop_end;
    span->val_start = val_start;
    span->val_end = val_end;
    span->is_important = is_important;

    *pos_ptr = pos;
    return 1;
}

// Strip whitespace from both ends and return new string
static inline VALUE strip_string(const char *str, long len) {
    const char *start = str;
    const char *end = str + len;
    trim_leading(&start, end);
    trim_trailing(start, &end);
    return rb_str_new(start, end - start);
}

// US-ASCII string literal creation
// Only for compile-time string literals - uses sizeof() for length
// For runtime char*, use rb_usascii_str_new(ptr, len) directly
#define USASCII_STR(str) rb_usascii_str_new((str), sizeof(str) - 1)

// UTF-8 string literal creation
// Only for compile-time string literals - uses sizeof() for length
// For runtime char*, use rb_utf8_str_new(ptr, len) directly
#define UTF8_STR(str) rb_utf8_str_new((str), sizeof(str) - 1)

// String allocation macros (from old cataract.h)
#ifndef DISABLE_STR_BUF_OPTIMIZATION
  #define STR_NEW_WITH_CAPACITY(capacity) rb_str_buf_new(capacity)
  #define STR_NEW_CSTR(str) rb_str_new_cstr(str)
#else
  #define STR_NEW_WITH_CAPACITY(capacity) rb_str_new_cstr("")
  #define STR_NEW_CSTR(str) rb_str_new_cstr(str)
#endif

// String comparison macro - check if Ruby string equals C string literal
#define STR_EQ(val, lit) (RSTRING_LEN(val) == strlen(lit) && \
                          memcmp(RSTRING_PTR(val), lit, strlen(lit)) == 0)

// Safety limits
#ifndef MAX_PARSE_DEPTH
  #define MAX_PARSE_DEPTH 10  // Max recursion depth for nested @media/@supports blocks and CSS nesting
#endif

// Max buffer size for indent strings in serialization
// (MAX_PARSE_DEPTH + 1) * 2 spaces + null terminator, rounded up for safety
#define MAX_INDENT_BUFFER ((MAX_PARSE_DEPTH + 2) * 2 + 1)

#ifndef MAX_PROPERTY_NAME_LENGTH
  #define MAX_PROPERTY_NAME_LENGTH 256  // Max length of CSS property name
#endif

#ifndef MAX_PROPERTY_VALUE_LENGTH
  #define MAX_PROPERTY_VALUE_LENGTH 32768  // Max length of CSS property value (32KB)
#endif

#ifndef MAX_MEDIA_QUERIES
  #define MAX_MEDIA_QUERIES 1000  // Prevent symbol table exhaustion
#endif

// ============================================================================
// Function declarations
// ============================================================================

// CSS parser (css_parser_new.c)
VALUE parse_css_new(int argc, VALUE *argv, VALUE self);
VALUE parse_css_new_impl(VALUE css_string, VALUE parser_options, int rule_id_offset);

// Flatten (flatten.c)
VALUE cataract_flatten(VALUE self, VALUE rules_array);
void init_flatten_constants(void);

// Specificity (specificity.c)
VALUE calculate_specificity(VALUE self, VALUE selector);

// Shorthand expander (shorthand_expander_new.c)
VALUE cataract_split_value(VALUE self, VALUE value);
VALUE cataract_expand_margin(VALUE self, VALUE value, VALUE important);
VALUE cataract_expand_padding(VALUE self, VALUE value, VALUE important);
VALUE cataract_expand_border(VALUE self, VALUE value, VALUE important);
VALUE cataract_expand_border_color(VALUE self, VALUE value, VALUE important);
VALUE cataract_expand_border_style(VALUE self, VALUE value, VALUE important);
VALUE cataract_expand_border_width(VALUE self, VALUE value, VALUE important);
VALUE cataract_expand_border_side(VALUE self, VALUE side, VALUE value, VALUE important);
VALUE cataract_expand_font(VALUE self, VALUE value, VALUE important);
VALUE cataract_expand_list_style(VALUE self, VALUE value, VALUE important);
VALUE cataract_expand_background(VALUE self, VALUE value, VALUE important);
VALUE cataract_expand_shorthand(VALUE self, VALUE decl);
VALUE cataract_create_margin_shorthand(VALUE self, VALUE properties);
VALUE cataract_create_padding_shorthand(VALUE self, VALUE properties);
VALUE cataract_create_border_width_shorthand(VALUE self, VALUE properties);
VALUE cataract_create_border_style_shorthand(VALUE self, VALUE properties);
VALUE cataract_create_border_color_shorthand(VALUE self, VALUE properties);
VALUE cataract_create_border_shorthand(VALUE self, VALUE properties);
VALUE cataract_create_font_shorthand(VALUE self, VALUE properties);
VALUE cataract_create_list_style_shorthand(VALUE self, VALUE properties);
VALUE cataract_create_background_shorthand(VALUE self, VALUE properties);

// Helper (from css_parser_new.c)
VALUE lowercase_property(VALUE property_str);

#endif // CATARACT_NEW_H
