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

// Error class references
extern VALUE eCataractError;
extern VALUE eDepthError;
extern VALUE eSizeError;

// ============================================================================
// Struct field indices
// ============================================================================

// Rule struct field indices (id, selector, declarations, specificity, parent_rule_id, nesting_style)
#define RULE_ID 0
#define RULE_SELECTOR 1
#define RULE_DECLARATIONS 2
#define RULE_SPECIFICITY 3
#define RULE_PARENT_RULE_ID 4
#define RULE_NESTING_STYLE 5

// Nesting style constants
#define NESTING_STYLE_IMPLICIT 0  // .parent { .child { } } - no &
#define NESTING_STYLE_EXPLICIT 1  // .parent { &.child { } } - has &

// Named constants for parse_css_recursive() call clarity
// (Makes call sites self-documenting)
#define NO_PARENT_MEDIA Qnil
#define NO_PARENT_SELECTOR Qnil
#define NO_PARENT_RULE_ID Qnil

// Declaration struct field indices (property, value, important)
#define DECL_PROPERTY 0
#define DECL_VALUE 1
#define DECL_IMPORTANT 2

// AtRule struct field indices (id, selector, content, specificity)
// Matches Rule interface for duck-typing
#define AT_RULE_ID 0
#define AT_RULE_SELECTOR 1
#define AT_RULE_CONTENT 2
#define AT_RULE_SPECIFICITY 3

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

// Safety limits
#ifndef MAX_PARSE_DEPTH
  #define MAX_PARSE_DEPTH 10  // Max recursion depth for nested @media/@supports blocks and CSS nesting
#endif

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
VALUE parse_css_new(VALUE self, VALUE css_string);
VALUE parse_css_new_impl(VALUE css_string, int rule_id_offset);
VALUE parse_media_types(VALUE self, VALUE media_query_sym);

// Merge (merge_new.c)
VALUE cataract_merge_new(VALUE self, VALUE rules_array);
void init_merge_constants(void);

// Specificity (specificity.c)
VALUE calculate_specificity(VALUE self, VALUE selector);

// Import scanner (import_scanner.c)
VALUE extract_imports(VALUE self, VALUE css_string);

// Shorthand expander (shorthand_expander_new.c)
VALUE cataract_split_value(VALUE self, VALUE value);
VALUE cataract_expand_margin(VALUE self, VALUE value);
VALUE cataract_expand_padding(VALUE self, VALUE value);
VALUE cataract_expand_border(VALUE self, VALUE value);
VALUE cataract_expand_border_color(VALUE self, VALUE value);
VALUE cataract_expand_border_style(VALUE self, VALUE value);
VALUE cataract_expand_border_width(VALUE self, VALUE value);
VALUE cataract_expand_border_side(VALUE self, VALUE side, VALUE value);
VALUE cataract_expand_font(VALUE self, VALUE value);
VALUE cataract_expand_list_style(VALUE self, VALUE value);
VALUE cataract_expand_background(VALUE self, VALUE value);
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
