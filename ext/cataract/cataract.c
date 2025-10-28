#include <ruby.h>
#include <stdio.h>
#include "cataract.h"

// Global struct class definitions (declared extern in cataract.h)
VALUE cDeclarationsValue;
VALUE cRule;

// Error class definitions (declared extern in cataract.h)
VALUE eCataractError;
VALUE eParseError;
VALUE eDepthError;
VALUE eSizeError;

// ============================================================================
// Helper Functions (used by pure C parser)
// ============================================================================
// These functions encapsulate common parsing logic for the pure C parser.

// Parse declaration block and extract Declaration::Value structs
// Non-static so css_parser.c can call it
inline void capture_declarations_fn(
    const char **decl_start_ptr,
    const char *p,
    VALUE *current_declarations,
    const char *css_string_base
) {
    // Guard against multiple firings - only process if decl_start is set
    if (*decl_start_ptr == NULL) {
        DEBUG_PRINTF("[capture_declarations] SKIPPED: decl_start is NULL\n");
        return;
    }

    const char *decl_start = *decl_start_ptr;

    // Initialize declarations array if needed
    if (NIL_P(*current_declarations)) {
        *current_declarations = rb_ary_new();
    }

    const char *start = decl_start;
    const char *end = p;

    DEBUG_PRINTF("[capture_declarations] Parsing declarations from %ld to %ld: '%.*s'\n",
                 decl_start - css_string_base, p - css_string_base,
                 (int)(end - start), start);

    // Simple C-level parser for declarations
    // Input: "color: red; background: blue !important"
    // Output: Array of Declarations::Value structs
    const char *pos = start;
    while (pos < end) {
        // Skip whitespace and semicolons
        while (pos < end && (IS_WHITESPACE(*pos) || *pos == ';')) {
            pos++;
        }
        if (pos >= end) break;

        // Find property (up to colon)
        const char *prop_start = pos;
        while (pos < end && *pos != ':') pos++;
        if (pos >= end) break;  // No colon found

        const char *prop_end = pos;
        // Trim whitespace from property
        trim_trailing(prop_start, &prop_end);
        trim_leading(&prop_start, prop_end);

        pos++;  // Skip colon

        // Skip whitespace after colon
        while (pos < end && IS_WHITESPACE(*pos)) {
            pos++;
        }

        // Find value (up to semicolon or end)
        // Handle parentheses: semicolons inside () don't terminate the value
        const char *val_start = pos;
        int paren_depth = 0;
        while (pos < end) {
            if (*pos == '(') {
                paren_depth++;
            } else if (*pos == ')') {
                paren_depth--;
            } else if (*pos == ';' && paren_depth == 0) {
                break;  // Found terminating semicolon
            }
            pos++;
        }
        const char *val_end = pos;

        // Trim trailing whitespace from value
        trim_trailing(val_start, &val_end);

        // Check for !important
        int is_important = 0;
        const char *important_pos = val_end;
        // Look backwards for "!important"
        if (val_end - val_start >= 10) {  // strlen("!important") = 10
            const char *check = val_end - 10;
            while (check < val_end && IS_WHITESPACE(*check)) check++;
            if (check < val_end && *check == '!') {
                check++;
                while (check < val_end && IS_WHITESPACE(*check)) check++;
                if ((val_end - check) >= 9 && strncmp(check, "important", 9) == 0) {
                    is_important = 1;
                    important_pos = check - 1;
                    while (important_pos > val_start && (IS_WHITESPACE(*(important_pos-1)) || *(important_pos-1) == '!')) {
                        important_pos--;
                    }
                    val_end = important_pos;
                }
            }
        }

        // Final trim of trailing whitespace/newlines from value (after !important removal)
        trim_trailing(val_start, &val_end);

        // Skip if value is empty (e.g., "color: !important" with no actual value)
        if (val_end > val_start) {
            // Sanity check: property name length
            long prop_len = prop_end - prop_start;
            if (prop_len > MAX_PROPERTY_NAME_LENGTH) {
                DEBUG_PRINTF("[capture_declarations] Skipping property: name too long (%ld > %d)\n",
                             prop_len, MAX_PROPERTY_NAME_LENGTH);
                continue;
            }

            // Sanity check: value length
            long val_len = val_end - val_start;
            if (val_len > MAX_PROPERTY_VALUE_LENGTH) {
                DEBUG_PRINTF("[capture_declarations] Skipping property: value too long (%ld > %d)\n",
                             val_len, MAX_PROPERTY_VALUE_LENGTH);
                continue;
            }

            // Create property string and lowercase it (CSS property names are ASCII-only)
            VALUE property_raw = rb_str_new(prop_start, prop_len);
            VALUE property = lowercase_property(property_raw);
            VALUE value = rb_str_new(val_start, val_end - val_start);

            DEBUG_PRINTF("[capture_declarations] Found: property='%s' value='%s' important=%d\n",
                         RSTRING_PTR(property), RSTRING_PTR(value), is_important);

            // Create Declarations::Value struct
            VALUE decl = rb_struct_new(
                cDeclarationsValue,
                property,
                value,
                is_important ? Qtrue : Qfalse
            );

            rb_ary_push(*current_declarations, decl);

            // Protect temporaries from GC (in case compiler optimizes them to registers)
            RB_GC_GUARD(property);
            RB_GC_GUARD(value);
            RB_GC_GUARD(decl);
        } else {
            DEBUG_PRINTF("[capture_declarations] Skipping empty value for property at pos %ld\n",
                         prop_start - css_string_base);
        }

        if (pos < end && *pos == ';') pos++;  // Skip semicolon if present
    }

    // Reset for next rule
    *decl_start_ptr = NULL;
}

// Create Rule structs from current selectors and declarations
// Non-static so css_parser.c can call it
inline void finish_rule_fn(
    int inside_at_rule_block,
    VALUE *current_selectors,
    VALUE *current_declarations,
    VALUE *current_media_types,
    VALUE rules_array,
    const char **mark_ptr
) {
    // Skip if we're scanning at-rule block content (will be parsed recursively)
    if (inside_at_rule_block) {
        DEBUG_PRINTF("[finish_rule] SKIPPED (inside media block)\n");
        goto cleanup;
    }

    // Create one rule for each selector in the list
    if (NIL_P(*current_selectors) || NIL_P(*current_declarations)) {
        goto cleanup;
    }

    long len = RARRAY_LEN(*current_selectors);
    DEBUG_PRINTF("[finish_rule] Creating %ld rule(s)\n", len);

    for (long i = 0; i < len; i++) {
        VALUE sel = RARRAY_AREF(*current_selectors, i);
        DEBUG_PRINTF("[finish_rule] Rule %ld: selector='%s'\n", i, RSTRING_PTR(sel));

        // Determine media query: use current_media_types if inside @media block, otherwise default to [:all]
        VALUE media_query;
        if (!NIL_P(*current_media_types) && RARRAY_LEN(*current_media_types) > 0) {
            media_query = rb_ary_dup(*current_media_types);
            DEBUG_PRINTF("[finish_rule] Using current media types\n");
        } else {
            media_query = rb_ary_new3(1, ID2SYM(rb_intern("all")));
        }

        VALUE rule = rb_struct_new(cRule,
            sel,                                // selector
            rb_ary_dup(*current_declarations),   // declarations
            Qnil,                               // specificity (calculated on demand)
            media_query                         // media_query
        );

        rb_ary_push(rules_array, rule);
    }

cleanup:
    *current_selectors = Qnil;
    *current_declarations = Qnil;
    // Reset mark for next rule (in case it wasn't reset by capture action)
    *mark_ptr = NULL;
}

// Parse media query string and return array of media types (pure C version)
// Example: "screen and (min-width: 768px)" -> [:screen]
// Example: "screen, print" -> [:screen, :print]
//
// Algorithm: Scan for identifiers (alphanumeric + dash), skip keywords and parens
VALUE parse_media_query(const char *query_str, long query_len) {
    VALUE mq_types = rb_ary_new();

    const char *p = query_str;
    const char *pe = query_str + query_len;
    int in_parens = 0;

    while (p < pe) {
        // Skip whitespace
        while (p < pe && IS_WHITESPACE(*p)) p++;
        if (p >= pe) break;

        // Track parentheses (skip content inside parens like "(min-width: 768px)")
        if (*p == '(') {
            in_parens++;
            p++;
            continue;
        }
        if (*p == ')') {
            if (in_parens > 0) in_parens--;
            p++;
            continue;
        }

        // Skip non-identifier characters when not in parens
        if (!in_parens && (*p == ',' || *p == ':' || *p == ';')) {
            p++;
            continue;
        }

        // Inside parens - skip everything
        if (in_parens) {
            p++;
            continue;
        }

        // Check if this looks like an identifier start (letter or dash)
        if ((*p >= 'a' && *p <= 'z') || (*p >= 'A' && *p <= 'Z') || *p == '-') {
            const char *ident_start = p;

            // Scan identifier (letters, digits, dashes)
            while (p < pe && ((*p >= 'a' && *p <= 'z') || (*p >= 'A' && *p <= 'Z') ||
                              (*p >= '0' && *p <= '9') || *p == '-')) {
                p++;
            }

            long ident_len = p - ident_start;

            // Check if it's a keyword to skip
            int is_keyword =
                (ident_len == 3 && (strncmp(ident_start, "and", 3) == 0 || strncmp(ident_start, "not", 3) == 0)) ||
                (ident_len == 2 && strncmp(ident_start, "or", 2) == 0) ||
                (ident_len == 4 && strncmp(ident_start, "only", 4) == 0);

            if (!is_keyword) {
                // Capture as media type
                ID media_id = rb_intern2(ident_start, ident_len);
                VALUE media_sym = ID2SYM(media_id);
                rb_ary_push(mq_types, media_sym);
                DEBUG_PRINTF("[mq_parser] captured media type: %.*s\n", (int)ident_len, ident_start);
            } else {
                DEBUG_PRINTF("[mq_parser] skipped keyword: %.*s\n", (int)ident_len, ident_start);
            }
        } else {
            // Not an identifier, skip character
            p++;
        }
    }

    return mq_types;
}

static VALUE parse_css_internal(VALUE self, VALUE css_string, int depth) {
    // Check recursion depth to prevent stack overflow and memory exhaustion
    if (depth > MAX_PARSE_DEPTH) {
        rb_raise(eDepthError,
                 "CSS nesting too deep: exceeded maximum depth of %d",
                 MAX_PARSE_DEPTH);
    }

    Check_Type(css_string, T_STRING);

    // Extract @charset if present (must be at very start per W3C spec)
    // Handled separately because @charset must be at the absolute start
    // and can be processed with simple string operations
    VALUE charset = Qnil;
    char *css_start = RSTRING_PTR(css_string);
    long css_len = RSTRING_LEN(css_string);

    // Check for @charset at very start: @charset "UTF-8";
    // Per spec: exact syntax with double quotes required
    if (css_len > 10 && strncmp(css_start, "@charset ", 9) == 0) {
        // Find opening quote
        char *quote_start = strchr(css_start + 9, '"');
        if (quote_start != NULL) {
            // Find closing quote and semicolon
            char *quote_end = strchr(quote_start + 1, '"');
            if (quote_end != NULL) {
                char *semicolon = quote_end + 1;
                // Skip whitespace between quote and semicolon
                while (semicolon < css_start + css_len && IS_WHITESPACE(*semicolon)) {
                    semicolon++;
                }
                if (semicolon < css_start + css_len && *semicolon == ';') {
                    // Valid @charset rule found
                    charset = rb_str_new(quote_start + 1, quote_end - quote_start - 1);
                    // Skip past the entire @charset rule for parsing
                    css_start = semicolon + 1;
                    css_len = RSTRING_LEN(css_string) - (css_start - RSTRING_PTR(css_string));
                    DEBUG_PRINTF("[@charset] Extracted: '%s', remaining CSS: %ld bytes\n",
                                RSTRING_PTR(charset), css_len);
                }
            }
        }
    }

    // Parse CSS using our C parser implementation
    VALUE rules_array = parse_css_impl(css_string, depth);

    // GC Guard: Protect Ruby objects from garbage collection
    RB_GC_GUARD(css_string);
    RB_GC_GUARD(rules_array);
    RB_GC_GUARD(charset);

    // At depth 0 (top-level parse), return hash with rules and charset (may be nil)
    // Nested parses (depth > 0) return array for backwards compatibility
    if (depth == 0) {
        VALUE result = rb_hash_new();
        rb_hash_aset(result, ID2SYM(rb_intern("rules")), rules_array);
        rb_hash_aset(result, ID2SYM(rb_intern("charset")), charset);
        return result;
    }
    return rules_array;
}

// Calculate CSS specificity for a selector string (wrapper for public API)
VALUE calculate_specificity(VALUE self, VALUE selector_string) {
    return calculate_specificity_impl(self, selector_string);
}

/*
 * Parse declarations string into array of Declarations::Value structs
 * Extracted from capture_declarations action - same logic, reusable
 *
 * @param start Pointer to start of declarations string
 * @param end Pointer to end of declarations string
 * @return Array of Declarations::Value structs
 */
static VALUE parse_declarations_string(const char *start, const char *end) {
    VALUE declarations = rb_ary_new();

    const char *pos = start;
    while (pos < end) {
        // Skip whitespace and semicolons
        while (pos < end && (IS_WHITESPACE(*pos) || *pos == ';')) pos++;
        if (pos >= end) break;

        // Find property (up to colon)
        const char *prop_start = pos;
        while (pos < end && *pos != ':') pos++;
        if (pos >= end) break;  // No colon found

        const char *prop_end = pos;
        trim_trailing(prop_start, &prop_end);
        trim_leading(&prop_start, prop_end);

        pos++;  // Skip colon
        trim_leading(&pos, end);

        // Find value (up to semicolon or end), handling parentheses
        const char *val_start = pos;
        int paren_depth = 0;
        while (pos < end) {
            if (*pos == '(') paren_depth++;
            else if (*pos == ')') paren_depth--;
            else if (*pos == ';' && paren_depth == 0) break;
            pos++;
        }
        const char *val_end = pos;
        trim_trailing(val_start, &val_end);

        // Check for !important
        int is_important = 0;
        if (val_end - val_start >= 10) {  // strlen("!important") = 10
            const char *check = val_end - 10;
            while (check < val_end && IS_WHITESPACE(*check)) check++;
            if (check < val_end && *check == '!') {
                check++;
                while (check < val_end && IS_WHITESPACE(*check)) check++;
                if ((val_end - check) >= 9 && strncmp(check, "important", 9) == 0) {
                    is_important = 1;
                    const char *important_pos = check - 1;
                    while (important_pos > val_start && (IS_WHITESPACE(*(important_pos-1)) || *(important_pos-1) == '!')) {
                        important_pos--;
                    }
                    val_end = important_pos;
                    trim_trailing(val_start, &val_end);
                }
            }
        }

        // Skip if value is empty
        if (val_end > val_start) {
            long prop_len = prop_end - prop_start;
            if (prop_len > MAX_PROPERTY_NAME_LENGTH) continue;

            long val_len = val_end - val_start;
            if (val_len > MAX_PROPERTY_VALUE_LENGTH) continue;

            // Create property string and lowercase it
            VALUE property_raw = rb_str_new(prop_start, prop_len);
            VALUE property = lowercase_property(property_raw);
            VALUE value = rb_str_new(val_start, val_len);

            // Create Declarations::Value struct
            VALUE decl = rb_struct_new(cDeclarationsValue,
                property, value, is_important ? Qtrue : Qfalse);

            rb_ary_push(declarations, decl);
        }
    }

    return declarations;
}

/*
 * Ruby-facing wrapper for parse_declarations
 *
 * @param declarations_string [String] CSS declarations like "color: red; margin: 10px"
 * @return [Array<Declarations::Value>] Array of parsed declaration structs
 */
static VALUE parse_declarations(VALUE self, VALUE declarations_string) {
    Check_Type(declarations_string, T_STRING);

    const char *input = RSTRING_PTR(declarations_string);
    long input_len = RSTRING_LEN(declarations_string);

    // Strip outer braces and whitespace (css_parser compatibility)
    const char *start = input;
    const char *end = input + input_len;

    while (start < end && (IS_WHITESPACE(*start) || *start == '{')) start++;
    while (end > start && (IS_WHITESPACE(*(end-1)) || *(end-1) == '}')) end--;

    VALUE result = parse_declarations_string(start, end);

    RB_GC_GUARD(result);
    return result;
}

// Public wrapper for Ruby - starts at depth 0
static VALUE parse_css(VALUE self, VALUE css_string) {
    // Verify that cRule was initialized in Init_cataract
    if (cRule == Qnil || cRule == 0) {
        rb_raise(rb_eRuntimeError, "cRule struct class not initialized - Init_cataract may have failed");
    }
    return parse_css_internal(self, css_string, 0);
}

/*
 * Convert array of Rule structs to full CSS string
 * Format: "selector { prop: value; }\nselector2 { prop: value; }"
 */
static VALUE rules_to_s(VALUE self, VALUE rules_array) {
    Check_Type(rules_array, T_ARRAY);

    long len = RARRAY_LEN(rules_array);
    if (len == 0) {
        return rb_str_new_cstr("");
    }

    // Estimate: ~100 chars per rule (selector + declarations)
    VALUE result = rb_str_buf_new(len * 100);

    for (long i = 0; i < len; i++) {
        VALUE rule = rb_ary_entry(rules_array, i);

        // Validate this is a Rule struct
        if (!RB_TYPE_P(rule, T_STRUCT)) {
            rb_raise(rb_eTypeError,
                     "Expected array of Rule structs, got %s at index %ld",
                     rb_obj_classname(rule), i);
        }

        // Extract: selector, declarations, specificity, media_query
        VALUE selector = rb_struct_aref(rule, INT2FIX(0));
        VALUE declarations = rb_struct_aref(rule, INT2FIX(1));

        // Append selector
        rb_str_buf_append(result, selector);
        rb_str_buf_cat2(result, " { ");

        // Serialize each declaration
        long decl_len = RARRAY_LEN(declarations);
        for (long j = 0; j < decl_len; j++) {
            VALUE decl = rb_ary_entry(declarations, j);

            VALUE property = rb_struct_aref(decl, INT2FIX(0));
            VALUE value = rb_struct_aref(decl, INT2FIX(1));
            VALUE important = rb_struct_aref(decl, INT2FIX(2));

            rb_str_buf_append(result, property);
            rb_str_buf_cat2(result, ": ");
            rb_str_buf_append(result, value);

            if (RTEST(important)) {
                rb_str_buf_cat2(result, " !important");
            }

            rb_str_buf_cat2(result, "; ");
        }

        rb_str_buf_cat2(result, "}\n");

        RB_GC_GUARD(rule);
        RB_GC_GUARD(selector);
        RB_GC_GUARD(declarations);
    }

    RB_GC_GUARD(result);
    return result;
}

/*
 * Convert array of Declarations::Value structs to CSS string (internal)
 * Format: "prop: value; prop2: value2 !important; "
 */
VALUE declarations_to_s(VALUE self, VALUE declarations_array) {
    Check_Type(declarations_array, T_ARRAY);

    long len = RARRAY_LEN(declarations_array);
    if (len == 0) {
        return rb_str_new_cstr("");
    }

    // Use rb_str_buf_new for efficient string building
    VALUE result = rb_str_buf_new(len * 32); // Estimate 32 chars per declaration

    for (long i = 0; i < len; i++) {
        VALUE decl = rb_ary_entry(declarations_array, i);

        // Validate this is a Declarations::Value struct
        if (!RB_TYPE_P(decl, T_STRUCT) || rb_obj_class(decl) != cDeclarationsValue) {
            rb_raise(rb_eTypeError,
                     "Expected array of Declarations::Value structs, got %s at index %ld",
                     rb_obj_classname(decl), i);
        }

        // Extract struct fields
        VALUE property = rb_struct_aref(decl, INT2FIX(0));
        VALUE value = rb_struct_aref(decl, INT2FIX(1));
        VALUE important = rb_struct_aref(decl, INT2FIX(2));

        // Append: "property: value"
        rb_str_buf_append(result, property);
        rb_str_buf_cat2(result, ": ");
        rb_str_buf_append(result, value);

        // Append " !important" if needed
        if (RTEST(important)) {
            rb_str_buf_cat2(result, " !important");
        }

        rb_str_buf_cat2(result, "; ");

        RB_GC_GUARD(decl);
        RB_GC_GUARD(property);
        RB_GC_GUARD(value);
        RB_GC_GUARD(important);
    }

    // Strip trailing space
    rb_str_set_len(result, RSTRING_LEN(result) - 1);

    RB_GC_GUARD(result);
    return result;
}

void Init_cataract() {
    VALUE module = rb_define_module("Cataract");

    // Define error class hierarchy
    eCataractError = rb_define_class_under(module, "Error", rb_eStandardError);
    eParseError = rb_define_class_under(module, "ParseError", eCataractError);
    eDepthError = rb_define_class_under(module, "DepthError", eCataractError);
    eSizeError = rb_define_class_under(module, "SizeError", eCataractError);

    // Define Cataract::Declarations class (Ruby side will add methods)
    VALUE cDeclarations = rb_define_class_under(module, "Declarations", rb_cObject);

    // Define Cataract::Declarations::Value = Struct.new(:property, :value, :important)
    cDeclarationsValue = rb_struct_define_under(
        cDeclarations,
        "Value",
        "property",
        "value",
        "important",
        NULL
    );

    // Define Cataract::Rule = Struct.new(:selector, :declarations, :specificity, :media_query)
    cRule = rb_struct_define_under(
        module,
        "Rule",
        "selector",
        "declarations",
        "specificity",
        "media_query",
        NULL
    );

    rb_define_module_function(module, "parse_css", parse_css, 1);
    rb_define_module_function(module, "parse_declarations", parse_declarations, 1);
    rb_define_module_function(module, "calculate_specificity", calculate_specificity, 1);
    rb_define_module_function(module, "merge_rules", cataract_merge, 1);
    rb_define_module_function(module, "apply_cascade", cataract_merge, 1);  // Alias with better name
    rb_define_module_function(module, "rules_to_s", rules_to_s, 1);
    rb_define_module_function(module, "split_value", cataract_split_value, 1);
    rb_define_module_function(module, "expand_margin", cataract_expand_margin, 1);
    rb_define_module_function(module, "expand_padding", cataract_expand_padding, 1);
    rb_define_module_function(module, "expand_border_color", cataract_expand_border_color, 1);
    rb_define_module_function(module, "expand_border_style", cataract_expand_border_style, 1);
    rb_define_module_function(module, "expand_border_width", cataract_expand_border_width, 1);
    rb_define_module_function(module, "expand_border", cataract_expand_border, 1);
    rb_define_module_function(module, "expand_border_side", cataract_expand_border_side, 2);
    rb_define_module_function(module, "expand_font", cataract_expand_font, 1);
    rb_define_module_function(module, "expand_list_style", cataract_expand_list_style, 1);
    rb_define_module_function(module, "expand_background", cataract_expand_background, 1);

    // Shorthand creation (inverse of expansion)
    rb_define_module_function(module, "create_margin_shorthand", cataract_create_margin_shorthand, 1);
    rb_define_module_function(module, "create_padding_shorthand", cataract_create_padding_shorthand, 1);
    rb_define_module_function(module, "create_border_width_shorthand", cataract_create_border_width_shorthand, 1);
    rb_define_module_function(module, "create_border_style_shorthand", cataract_create_border_style_shorthand, 1);
    rb_define_module_function(module, "create_border_color_shorthand", cataract_create_border_color_shorthand, 1);
    rb_define_module_function(module, "create_border_shorthand", cataract_create_border_shorthand, 1);
    rb_define_module_function(module, "create_background_shorthand", cataract_create_background_shorthand, 1);
    rb_define_module_function(module, "create_font_shorthand", cataract_create_font_shorthand, 1);
    rb_define_module_function(module, "create_list_style_shorthand", cataract_create_list_style_shorthand, 1);

    // Serialization
    rb_define_module_function(module, "declarations_to_s", declarations_to_s, 1);
    rb_define_module_function(module, "stylesheet_to_s_c", stylesheet_to_s_c, 2);

    // Export string allocation mode as a constant for verification in benchmarks
    #ifdef DISABLE_STR_BUF_OPTIMIZATION
        rb_define_const(module, "STRING_ALLOC_MODE", ID2SYM(rb_intern("dynamic")));
    #else
        rb_define_const(module, "STRING_ALLOC_MODE", ID2SYM(rb_intern("buffer")));
    #endif
}

// NOTE: shorthand_expander.c and value_splitter.c are now compiled separately (not included)

