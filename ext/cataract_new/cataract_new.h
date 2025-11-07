#ifndef CATARACT_NEW_H
#define CATARACT_NEW_H

#include <ruby.h>
#include <ruby/encoding.h>

// ============================================================================
// Global struct class references
// ============================================================================

extern VALUE cNewRule;
extern VALUE cNewDeclaration;

// Error class references
extern VALUE eCataractError;
extern VALUE eParseError;
extern VALUE eSizeError;

// ============================================================================
// Struct field indices
// ============================================================================

// NewRule struct field indices (selector, declarations, specificity, media_query_sym)
#define NEW_RULE_SELECTOR 0
#define NEW_RULE_DECLARATIONS 1
#define NEW_RULE_SPECIFICITY 2
#define NEW_RULE_MEDIA_QUERY_SYM 3

// NewDeclaration struct field indices (property, value, important)
#define NEW_DECL_PROPERTY 0
#define NEW_DECL_VALUE 1
#define NEW_DECL_IMPORTANT 2

// ============================================================================
// Macros
// ============================================================================

// Whitespace detection
#define IS_WHITESPACE(c) ((c) == ' ' || (c) == '\t' || (c) == '\n' || (c) == '\r')

// US-ASCII string literal creation
#define USASCII_STR(str) rb_usascii_str_new((str), sizeof(str) - 1)

// UTF-8 string literal creation
#define UTF8_STR(str) rb_utf8_str_new((str), sizeof(str) - 1)

// Safety limits
#ifndef MAX_MEDIA_QUERIES
  #define MAX_MEDIA_QUERIES 1000  // Prevent symbol table exhaustion
#endif

// ============================================================================
// Function declarations
// ============================================================================

// CSS parser (css_parser_new.c)
VALUE parse_css_new_impl(VALUE css_string);

#endif // CATARACT_NEW_H
