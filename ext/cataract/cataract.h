#ifndef CATARACT_H
#define CATARACT_H

#include <ruby.h>
#include <ruby/encoding.h>

// ============================================================================
// Global struct class references (defined in cataract.c, declared extern here)
// ============================================================================

extern VALUE cDeclarationsValue;
extern VALUE cRule;

// Error class references
extern VALUE eCataractError;
extern VALUE eParseError;
extern VALUE eDepthError;
extern VALUE eSizeError;

// ============================================================================
// Struct field indices
// ============================================================================

// Rule struct field indices (selector, declarations, specificity)
#define RULE_SELECTOR 0
#define RULE_DECLARATIONS 1
#define RULE_SPECIFICITY 2

// Declarations::Value struct field indices (property, value, important)
#define DECL_PROPERTY 0
#define DECL_VALUE 1
#define DECL_IMPORTANT 2

// ============================================================================
// Macros
// ============================================================================

// Whitespace detection
#define IS_WHITESPACE(c) ((c) == ' ' || (c) == '\t' || (c) == '\n' || (c) == '\r')

// US-ASCII string literal creation (compile-time length for efficiency)
// Use this for string literals like "margin-top" to avoid strlen() at runtime
// Example: USASCII_STR("margin-top") expands to rb_usascii_str_new("margin-top", 10)
#define USASCII_STR(str) rb_usascii_str_new((str), sizeof(str) - 1)

// UTF-8 string literal creation (compile-time length for efficiency)
// Use this for string literals that may be concatenated with UTF-8 content
// Example: UTF8_STR("@") expands to rb_utf8_str_new("@", 1)
#define UTF8_STR(str) rb_utf8_str_new((str), sizeof(str) - 1)

// Debug output (disabled by default)
// #define CATARACT_DEBUG 1

#ifdef CATARACT_DEBUG
  #define DEBUG_PRINTF(...) printf(__VA_ARGS__)
#else
  #define DEBUG_PRINTF(...) ((void)0)
#endif

// String allocation optimization (enabled by default)
// Uses rb_str_buf_new for pre-allocation when building selector strings
//
// Disable for benchmarking baseline:
//   Development: DISABLE_STR_BUF_OPTIMIZATION=1 rake compile
//   Gem install: gem install cataract -- --disable-str-buf-optimization
//
#ifndef DISABLE_STR_BUF_OPTIMIZATION
  #define STR_NEW_WITH_CAPACITY(capacity) rb_str_buf_new(capacity)
  #define STR_NEW_CSTR(str) rb_str_new_cstr(str)
#else
  #define STR_NEW_WITH_CAPACITY(capacity) rb_str_new_cstr("")
  #define STR_NEW_CSTR(str) rb_str_new_cstr(str)
#endif

// Sanity limits for CSS properties and values
// These prevent crashes from pathological inputs (fuzzer-found edge cases)
// Override at compile time if needed: -DMAX_PROPERTY_NAME_LENGTH=512
#ifndef MAX_PROPERTY_NAME_LENGTH
  #define MAX_PROPERTY_NAME_LENGTH 256  // Reasonable max for property names (e.g., "background-position-x")
#endif

#ifndef MAX_PROPERTY_VALUE_LENGTH
  #define MAX_PROPERTY_VALUE_LENGTH 32768  // 32KB - handles large data URLs and complex values
#endif

#ifndef MAX_AT_RULE_BLOCK_LENGTH
  #define MAX_AT_RULE_BLOCK_LENGTH 1048576  // 1MB - max size for @media, @supports, etc. block content
#endif

#ifndef MAX_PARSE_DEPTH
  #define MAX_PARSE_DEPTH 10  // Max recursion depth for nested @media/@supports blocks
#endif

// ============================================================================
// Inline helper functions
// ============================================================================

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

// Strip whitespace from both ends and return new string
static inline VALUE strip_string(const char *str, long len) {
    const char *start = str;
    const char *end = str + len;
    trim_leading(&start, end);
    trim_trailing(start, &end);
    return rb_str_new(start, end - start);
}

// Lowercase property name (CSS property names are ASCII-only)
//
// Performance: Manual loop unrolling (USE_LOOP_UNROLL) provides ~6.6% speedup
// on Apple Silicon M1 (tested with bootstrap.css parsing benchmark).
static inline VALUE lowercase_property(VALUE property_str) {
    Check_Type(property_str, T_STRING);

    long len = RSTRING_LEN(property_str);
    const char *src = RSTRING_PTR(property_str);

    // Create new US-ASCII string with same length (CSS property names are ASCII-only)
    VALUE result = rb_str_buf_new(len);
    rb_enc_associate(result, rb_usascii_encoding());

#ifndef DISABLE_LOOP_UNROLL
    // Manual loop unrolling: process 4 chars at a time (default, ~6.6% faster on M1)
    // Benefits: Fewer loop iterations, better ILP, fewer rb_str_buf_cat calls
    long i = 0;

    // Process 4 characters at a time
    for (; i + 3 < len; i += 4) {
        char c0 = src[i];
        char c1 = src[i+1];
        char c2 = src[i+2];
        char c3 = src[i+3];

        // Lowercase each character
        if (c0 >= 'A' && c0 <= 'Z') c0 += 32;
        if (c1 >= 'A' && c1 <= 'Z') c1 += 32;
        if (c2 >= 'A' && c2 <= 'Z') c2 += 32;
        if (c3 >= 'A' && c3 <= 'Z') c3 += 32;

        char buf[4] = {c0, c1, c2, c3};
        rb_str_buf_cat(result, buf, 4);
    }

    // Handle remaining characters (0-3)
    for (; i < len; i++) {
        char c = src[i];
        if (c >= 'A' && c <= 'Z') {
            c += 32;
        }
        rb_str_buf_cat(result, &c, 1);
    }
#else
    // Unrolling disabled: process one character at a time
    for (long i = 0; i < len; i++) {
        char c = src[i];
        // Lowercase ASCII letters only (CSS properties are ASCII)
        if (c >= 'A' && c <= 'Z') {
            c = c + ('a' - 'A');
        }
        rb_str_buf_cat(result, &c, 1);
    }
#endif

    return result;
}

// ============================================================================
// Function declarations (implemented in various .c/.rl files)
// ============================================================================

// Serialization functions (cataract.rl)
VALUE declarations_to_s(VALUE self, VALUE declarations_array);

// Stylesheet serialization (stylesheet.c)
VALUE stylesheet_to_s_c(VALUE self, VALUE rules_array, VALUE charset);
VALUE stylesheet_to_formatted_s_c(VALUE self, VALUE rules_array, VALUE charset);

// Import scanning (import_scanner.c)
VALUE extract_imports(VALUE self, VALUE css_string);

// Merge/cascade functions (merge.c)
VALUE cataract_merge(VALUE self, VALUE rules_array);
VALUE cataract_merge_wrapper(VALUE self, VALUE input);

// Shorthand expansion (shorthand_expander.rl)
VALUE cataract_split_value(VALUE self, VALUE value);
VALUE cataract_expand_margin(VALUE self, VALUE value);
VALUE cataract_expand_padding(VALUE self, VALUE value);
VALUE cataract_expand_border_color(VALUE self, VALUE value);
VALUE cataract_expand_border_style(VALUE self, VALUE value);
VALUE cataract_expand_border_width(VALUE self, VALUE value);
VALUE cataract_expand_border(VALUE self, VALUE value);
VALUE cataract_expand_border_side(VALUE self, VALUE side, VALUE value);
VALUE cataract_expand_font(VALUE self, VALUE value);
VALUE cataract_expand_list_style(VALUE self, VALUE value);
VALUE cataract_expand_background(VALUE self, VALUE value);

// Shorthand creation (shorthand_expander.rl)
VALUE cataract_create_margin_shorthand(VALUE self, VALUE properties);
VALUE cataract_create_padding_shorthand(VALUE self, VALUE properties);
VALUE cataract_create_border_width_shorthand(VALUE self, VALUE properties);
VALUE cataract_create_border_style_shorthand(VALUE self, VALUE properties);
VALUE cataract_create_border_color_shorthand(VALUE self, VALUE properties);
VALUE cataract_create_border_shorthand(VALUE self, VALUE properties);
VALUE cataract_create_background_shorthand(VALUE self, VALUE properties);
VALUE cataract_create_font_shorthand(VALUE self, VALUE properties);
VALUE cataract_create_list_style_shorthand(VALUE self, VALUE properties);

// CSS parser implementation (css_parser.c)
VALUE parse_css_impl(VALUE css_string, int depth, VALUE parent_media_query);

// CSS parsing helper functions (css_parser.c)
VALUE parse_media_query(const char *query_str, long query_len);
VALUE parse_declarations_string(const char *start, const char *end);
void capture_declarations_fn(
    const char **decl_start_ptr,
    const char *p,
    VALUE *current_declarations,
    const char *css_string_base
);
void finish_rule_fn(
    int inside_at_rule_block,
    VALUE *current_selectors,
    VALUE *current_declarations,
    VALUE *current_media_types,
    VALUE rules_array,
    const char **mark_ptr
);

// Specificity calculator (specificity.c)
VALUE calculate_specificity(VALUE self, VALUE selector_string);

#endif // CATARACT_H
