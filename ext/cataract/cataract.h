#ifndef CATARACT_H
#define CATARACT_H

#include <ruby.h>

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

// ============================================================================
// Function declarations (implemented in various .c/.rl files)
// ============================================================================

// Serialization functions (cataract.rl)
VALUE declarations_to_s(VALUE self, VALUE declarations_array);

// Stylesheet serialization (stylesheet.c)
VALUE stylesheet_to_s_c(VALUE self, VALUE rules_array, VALUE charset);

// Merge/cascade functions (merge.c)
VALUE cataract_merge(VALUE self, VALUE rules_array);

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

#endif // CATARACT_H
