#include <ruby.h>
#include <stdio.h>
#include "cataract.h"

// Global struct class definitions
VALUE cRule;
VALUE cDeclaration;
VALUE cAtRule;
VALUE cStylesheet;

// Error class definitions (shared with main extension)
VALUE eCataractError;
VALUE eParseError;
VALUE eSizeError;

// ============================================================================
// Stubbed Implementation - Phase 1
// ============================================================================

/*
 * Parse CSS string into Rule structs
 * Manages @_last_rule_id, @rules, @media_index, and @charset ivars on stylesheet_obj
 *
 * @param module [Module] Cataract module (unused, required for module function)
 * @param stylesheet_obj [Stylesheet] The stylesheet instance
 * @param css_string [String] CSS string to parse
 * @return [VALUE] stylesheet_obj (for method chaining)
 */
/*
 * Parse CSS and return hash with parsed data
 * This matches the old parse_css API
 *
 * @param css_string [String] CSS to parse
 * @return [Hash] { rules: [...], media_index: {...}, charset: "..." }
 */
VALUE parse_css_new(VALUE self, VALUE css_string) {
    return parse_css_new_impl(css_string, 0);
}

/*
 * Serialize rules array to CSS string
 * Note: Media query grouping now handled in Ruby layer using @media_index
 *
 * @param rules_array [Array<Rule>] Flat array of rules in insertion order
 * @param charset [String, nil] Optional @charset value
 * @return [String] CSS string
 */
// Helper to serialize a single rule's declarations
static void serialize_declarations(VALUE result, VALUE declarations) {
    long decl_len = RARRAY_LEN(declarations);
    for (long j = 0; j < decl_len; j++) {
        VALUE decl = rb_ary_entry(declarations, j);
        VALUE property = rb_struct_aref(decl, INT2FIX(DECL_PROPERTY));
        VALUE value = rb_struct_aref(decl, INT2FIX(DECL_VALUE));
        VALUE important = rb_struct_aref(decl, INT2FIX(DECL_IMPORTANT));

        rb_str_append(result, property);
        rb_str_cat2(result, ": ");
        rb_str_append(result, value);

        if (RTEST(important)) {
            rb_str_cat2(result, " !important");
        }

        rb_str_cat2(result, ";");

        // Add space after semicolon except for last declaration
        if (j < decl_len - 1) {
            rb_str_cat2(result, " ");
        }
    }
}

// Helper to serialize an AtRule (@keyframes, @font-face, etc)
static void serialize_at_rule(VALUE result, VALUE at_rule) {
    VALUE selector = rb_struct_aref(at_rule, INT2FIX(AT_RULE_SELECTOR));
    VALUE content = rb_struct_aref(at_rule, INT2FIX(AT_RULE_CONTENT));

    rb_str_append(result, selector);
    rb_str_cat2(result, " {\n");

    // Check if content is rules or declarations
    if (RARRAY_LEN(content) > 0) {
        VALUE first = rb_ary_entry(content, 0);

        if (rb_obj_is_kind_of(first, cRule)) {
            // Serialize as nested rules (e.g., @keyframes)
            for (long i = 0; i < RARRAY_LEN(content); i++) {
                VALUE nested_rule = rb_ary_entry(content, i);
                VALUE nested_selector = rb_struct_aref(nested_rule, INT2FIX(RULE_SELECTOR));
                VALUE nested_declarations = rb_struct_aref(nested_rule, INT2FIX(RULE_DECLARATIONS));

                rb_str_cat2(result, "  ");
                rb_str_append(result, nested_selector);
                rb_str_cat2(result, " { ");
                serialize_declarations(result, nested_declarations);
                rb_str_cat2(result, " }\n");
            }
        } else {
            // Serialize as declarations (e.g., @font-face)
            rb_str_cat2(result, "  ");
            serialize_declarations(result, content);
            rb_str_cat2(result, "\n");
        }
    }

    rb_str_cat2(result, "}\n");
}

// Helper to serialize a single rule (dispatches to at-rule serializer if needed)
static void serialize_rule(VALUE result, VALUE rule) {
    // Check if this is an AtRule
    if (rb_obj_is_kind_of(rule, cAtRule)) {
        serialize_at_rule(result, rule);
        return;
    }

    // Regular Rule serialization
    VALUE selector = rb_struct_aref(rule, INT2FIX(RULE_SELECTOR));
    VALUE declarations = rb_struct_aref(rule, INT2FIX(RULE_DECLARATIONS));

    rb_str_append(result, selector);
    rb_str_cat2(result, " { ");
    serialize_declarations(result, declarations);
    rb_str_cat2(result, " }\n");
}

// Helper to serialize an AtRule with formatting (@keyframes, @font-face, etc)
static void serialize_at_rule_formatted(VALUE result, VALUE at_rule, const char *indent) {
    VALUE selector = rb_struct_aref(at_rule, INT2FIX(AT_RULE_SELECTOR));
    VALUE content = rb_struct_aref(at_rule, INT2FIX(AT_RULE_CONTENT));

    rb_str_cat2(result, indent);
    rb_str_append(result, selector);
    rb_str_cat2(result, " {\n");

    // Check if content is rules or declarations
    if (RARRAY_LEN(content) > 0) {
        VALUE first = rb_ary_entry(content, 0);

        if (rb_obj_is_kind_of(first, cRule)) {
            // Serialize as nested rules (e.g., @keyframes) with formatting
            for (long i = 0; i < RARRAY_LEN(content); i++) {
                VALUE nested_rule = rb_ary_entry(content, i);
                VALUE nested_selector = rb_struct_aref(nested_rule, INT2FIX(RULE_SELECTOR));
                VALUE nested_declarations = rb_struct_aref(nested_rule, INT2FIX(RULE_DECLARATIONS));

                // Nested selector with opening brace (2-space indent)
                rb_str_cat2(result, indent);
                rb_str_cat2(result, "  ");
                rb_str_append(result, nested_selector);
                rb_str_cat2(result, " {\n");

                // Declarations on their own line (4-space indent)
                rb_str_cat2(result, indent);
                rb_str_cat2(result, "    ");
                serialize_declarations(result, nested_declarations);
                rb_str_cat2(result, "\n");

                // Closing brace (2-space indent)
                rb_str_cat2(result, indent);
                rb_str_cat2(result, "  }\n");
            }
        } else {
            // Serialize as declarations (e.g., @font-face)
            rb_str_cat2(result, indent);
            rb_str_cat2(result, "  ");
            serialize_declarations(result, content);
            rb_str_cat2(result, "\n");
        }
    }

    rb_str_cat2(result, indent);
    rb_str_cat2(result, "}\n");
}

// Helper to serialize a single rule with formatting (indented, multi-line)
static void serialize_rule_formatted(VALUE result, VALUE rule, const char *indent) {
    // Check if this is an AtRule
    if (rb_obj_is_kind_of(rule, cAtRule)) {
        serialize_at_rule_formatted(result, rule, indent);
        return;
    }

    // Regular Rule serialization with formatting
    VALUE selector = rb_struct_aref(rule, INT2FIX(RULE_SELECTOR));
    VALUE declarations = rb_struct_aref(rule, INT2FIX(RULE_DECLARATIONS));

    // Selector line with opening brace
    rb_str_cat2(result, indent);
    rb_str_append(result, selector);
    rb_str_cat2(result, " {\n");

    // Declarations on their own line with extra indentation
    rb_str_cat2(result, indent);
    rb_str_cat2(result, "  ");
    serialize_declarations(result, declarations);
    rb_str_cat2(result, "\n");

    // Closing brace
    rb_str_cat2(result, indent);
    rb_str_cat2(result, "}\n");
}

// Context for building rule_to_media map
struct build_rule_map_ctx {
    VALUE rule_to_media;
};

// Callback to build reverse map from rule_id to media_sym
static int build_rule_map_callback(VALUE media_sym, VALUE rule_ids, VALUE arg) {
    struct build_rule_map_ctx *ctx = (struct build_rule_map_ctx *)arg;

    Check_Type(rule_ids, T_ARRAY);
    long ids_len = RARRAY_LEN(rule_ids);

    for (long i = 0; i < ids_len; i++) {
        VALUE id = rb_ary_entry(rule_ids, i);
        VALUE existing = rb_hash_aref(ctx->rule_to_media, id);

        if (NIL_P(existing)) {
            rb_hash_aset(ctx->rule_to_media, id, media_sym);
        } else {
            // Keep the longer/more specific media query
            VALUE existing_str = rb_sym2str(existing);
            VALUE new_str = rb_sym2str(media_sym);
            if (RSTRING_LEN(new_str) > RSTRING_LEN(existing_str)) {
                rb_hash_aset(ctx->rule_to_media, id, media_sym);
            }
        }
    }

    return ST_CONTINUE;
}

static VALUE stylesheet_to_s_new(VALUE self, VALUE rules_array, VALUE media_index, VALUE charset) {
    Check_Type(rules_array, T_ARRAY);
    Check_Type(media_index, T_HASH);

    VALUE result = rb_str_new_cstr("");

    // Add charset if present
    if (!NIL_P(charset)) {
        rb_str_cat2(result, "@charset \"");
        rb_str_append(result, charset);
        rb_str_cat2(result, "\";\n");
    }

    long total_rules = RARRAY_LEN(rules_array);

    // Build a map from rule_id to media query symbol using rb_hash_foreach
    VALUE rule_to_media = rb_hash_new();
    struct build_rule_map_ctx map_ctx = { rule_to_media };
    rb_hash_foreach(media_index, build_rule_map_callback, (VALUE)&map_ctx);

    // Iterate through rules in insertion order, grouping consecutive media queries
    VALUE current_media = Qnil;
    int in_media_block = 0;

    for (long i = 0; i < total_rules; i++) {
        VALUE rule_id = INT2FIX(i);
        VALUE rule_media = rb_hash_aref(rule_to_media, rule_id);
        VALUE rule = rb_ary_entry(rules_array, i);

        if (NIL_P(rule_media)) {
            // Not in any media query - close any open media block first
            if (in_media_block) {
                rb_str_cat2(result, "}\n");
                in_media_block = 0;
                current_media = Qnil;
            }

            // Output rule directly
            serialize_rule(result, rule);
        } else {
            // This rule is in a media query
            // Check if media query changed from previous rule
            if (NIL_P(current_media) || !rb_equal(current_media, rule_media)) {
                // Close previous media block if open
                if (in_media_block) {
                    rb_str_cat2(result, "}\n");
                    in_media_block = 0;
                }

                // Open new media block
                current_media = rule_media;
                rb_str_cat2(result, "@media ");
                rb_str_append(result, rb_sym2str(rule_media));
                rb_str_cat2(result, " {\n");
                in_media_block = 1;
            }

            // Serialize rule inside media block
            serialize_rule(result, rule);
        }
    }

    // Close final media block if still open
    if (in_media_block) {
        rb_str_cat2(result, "}\n");
    }

    return result;
}

// Formatted version with indentation and newlines
static VALUE stylesheet_to_formatted_s_new(VALUE self, VALUE rules_array, VALUE media_index, VALUE charset) {
    Check_Type(rules_array, T_ARRAY);
    Check_Type(media_index, T_HASH);

    VALUE result = rb_str_new_cstr("");

    // Add charset if present
    if (!NIL_P(charset)) {
        rb_str_cat2(result, "@charset \"");
        rb_str_append(result, charset);
        rb_str_cat2(result, "\";\n");
    }

    long total_rules = RARRAY_LEN(rules_array);

    // Build a map from rule_id to media query symbol using rb_hash_foreach
    VALUE rule_to_media = rb_hash_new();
    struct build_rule_map_ctx map_ctx = { rule_to_media };
    rb_hash_foreach(media_index, build_rule_map_callback, (VALUE)&map_ctx);

    // Iterate through rules in insertion order, grouping consecutive media queries
    VALUE current_media = Qnil;
    int in_media_block = 0;

    for (long i = 0; i < total_rules; i++) {
        VALUE rule_id = INT2FIX(i);
        VALUE rule_media = rb_hash_aref(rule_to_media, rule_id);
        VALUE rule = rb_ary_entry(rules_array, i);

        if (NIL_P(rule_media)) {
            // Not in any media query - close any open media block first
            if (in_media_block) {
                rb_str_cat2(result, "}\n");
                in_media_block = 0;
                current_media = Qnil;
            }

            // Output rule with no indentation
            serialize_rule_formatted(result, rule, "");
        } else {
            // This rule is in a media query
            // Check if media query changed from previous rule
            if (NIL_P(current_media) || !rb_equal(current_media, rule_media)) {
                // Close previous media block if open
                if (in_media_block) {
                    rb_str_cat2(result, "}\n");
                    in_media_block = 0;
                }

                // Open new media block
                current_media = rule_media;
                rb_str_cat2(result, "@media ");
                rb_str_append(result, rb_sym2str(rule_media));
                rb_str_cat2(result, " {\n");
                in_media_block = 1;
            }

            // Serialize rule inside media block with 2-space indentation
            serialize_rule_formatted(result, rule, "  ");
        }
    }

    // Close final media block if still open
    if (in_media_block) {
        rb_str_cat2(result, "}\n");
    }

    return result;
}

/*
 * Parse declarations string into array of Declaration structs
 *
 * This is a copy of parse_declarations_string from css_parser.c,
 * but creates Declaration structs instead of Declaration structs
 */
static VALUE new_parse_declarations_string(const char *start, const char *end) {
    VALUE declarations = rb_ary_new();

    // Fast path: check if there are any comments
    int has_comments = 0;
    for (const char *check = start; check + 1 < end; check++) {
        if (*check == '/' && *(check + 1) == '*') {
            has_comments = 1;
            break;
        }
    }

    // If there are comments, strip them first (rare case)
    // For now, skip comment stripping since it requires copy_without_comments
    // which is in css_parser.c - we can add it later if needed
    if (has_comments) {
        rb_raise(eParseError, "Comments in declaration strings not yet supported in new parser");
    }

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
        // Trim trailing whitespace
        while (prop_end > prop_start && IS_WHITESPACE(*(prop_end-1))) prop_end--;
        // Trim leading whitespace
        while (prop_start < prop_end && IS_WHITESPACE(*prop_start)) prop_start++;

        pos++;  // Skip colon
        // Trim leading whitespace
        while (pos < end && IS_WHITESPACE(*pos)) pos++;

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
        // Trim trailing whitespace
        while (val_end > val_start && IS_WHITESPACE(*(val_end-1))) val_end--;

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
                    // Trim trailing whitespace again
                    while (val_end > val_start && IS_WHITESPACE(*(val_end-1))) val_end--;
                }
            }
        }

        // Skip if value is empty
        if (val_end > val_start) {
            long prop_len = prop_end - prop_start;
            long val_len = val_end - val_start;

            // Create property string (US-ASCII, lowercased)
            VALUE property = rb_usascii_str_new(prop_start, prop_len);
            // Lowercase it inline
            char *prop_ptr = RSTRING_PTR(property);
            for (long i = 0; i < prop_len; i++) {
                if (prop_ptr[i] >= 'A' && prop_ptr[i] <= 'Z') {
                    prop_ptr[i] += 32;
                }
            }

            VALUE value = rb_utf8_str_new(val_start, val_len);

            // Create Declaration struct
            VALUE decl = rb_struct_new(cDeclaration,
                property, value, is_important ? Qtrue : Qfalse);

            rb_ary_push(declarations, decl);
        }
    }

    return declarations;
}

/*
 * Convert array of Declaration structs to CSS string
 * Format: "prop: value; prop2: value2 !important; "
 *
 * This is a copy of declarations_array_to_s from cataract.c,
 * but works with Declaration structs instead of Declaration structs
 */
static VALUE new_declarations_array_to_s(VALUE declarations_array) {
    Check_Type(declarations_array, T_ARRAY);

    long len = RARRAY_LEN(declarations_array);
    if (len == 0) {
        return rb_str_new_cstr("");
    }

    // Use rb_str_buf_new for efficient string building
    VALUE result = rb_str_buf_new(len * 32); // Estimate 32 chars per declaration

    for (long i = 0; i < len; i++) {
        VALUE decl = rb_ary_entry(declarations_array, i);

        // Validate this is a Declaration struct
        if (!RB_TYPE_P(decl, T_STRUCT) || rb_obj_class(decl) != cDeclaration) {
            rb_raise(rb_eTypeError,
                     "Expected array of Declaration structs, got %s at index %ld",
                     rb_obj_classname(decl), i);
        }

        // Extract struct fields
        VALUE property = rb_struct_aref(decl, INT2FIX(DECL_PROPERTY));
        VALUE value = rb_struct_aref(decl, INT2FIX(DECL_VALUE));
        VALUE important = rb_struct_aref(decl, INT2FIX(DECL_IMPORTANT));

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

/*
 * Instance method: Declarations#to_s
 * Converts declarations to CSS string
 *
 * @return [String] CSS declarations like "color: red; margin: 10px !important;"
 */
static VALUE new_declarations_to_s_method(VALUE self) {
    // Get @values instance variable (array of Declaration structs)
    VALUE values = rb_ivar_get(self, rb_intern("@values"));

    // Call core serialization function
    return new_declarations_array_to_s(values);
}

/*
 * Ruby-facing wrapper for new_parse_declarations
 *
 * @param declarations_string [String] CSS declarations like "color: red; margin: 10px"
 * @return [Array<Declaration>] Array of parsed declaration structs
 */
static VALUE new_parse_declarations(VALUE self, VALUE declarations_string) {
    Check_Type(declarations_string, T_STRING);

    const char *input = RSTRING_PTR(declarations_string);
    long input_len = RSTRING_LEN(declarations_string);

    // Strip outer braces and whitespace (css_parser compatibility)
    const char *start = input;
    const char *end = input + input_len;

    while (start < end && (IS_WHITESPACE(*start) || *start == '{')) start++;
    while (end > start && (IS_WHITESPACE(*(end-1)) || *(end-1) == '}')) end--;

    VALUE result = new_parse_declarations_string(start, end);

    RB_GC_GUARD(result);
    return result;
}

// ============================================================================
// Ruby Module Initialization
// ============================================================================

void Init_cataract(void) {
    // Get Cataract module (should be defined by main extension)
    VALUE mCataract = rb_define_module("Cataract");

    // Define error classes (reuse from main extension if possible)
    if (rb_const_defined(mCataract, rb_intern("Error"))) {
        eCataractError = rb_const_get(mCataract, rb_intern("Error"));
    } else {
        eCataractError = rb_define_class_under(mCataract, "Error", rb_eStandardError);
    }

    if (rb_const_defined(mCataract, rb_intern("ParseError"))) {
        eParseError = rb_const_get(mCataract, rb_intern("ParseError"));
    } else {
        eParseError = rb_define_class_under(mCataract, "ParseError", eCataractError);
    }

    if (rb_const_defined(mCataract, rb_intern("SizeError"))) {
        eSizeError = rb_const_get(mCataract, rb_intern("SizeError"));
    } else {
        eSizeError = rb_define_class_under(mCataract, "SizeError", eCataractError);
    }

    // Define Rule struct: (id, selector, declarations, specificity)
    cRule = rb_struct_define_under(
        mCataract,
        "Rule",
        "id",                 // Integer (0-indexed position in @rules array)
        "selector",           // String
        "declarations",       // Array of Declaration
        "specificity",        // Integer (nil = not calculated yet)
        NULL
    );

    // Define Declaration struct: (property, value, important)
    cDeclaration = rb_struct_define_under(
        mCataract,
        "Declaration",
        "property",    // String
        "value",       // String
        "important",   // Boolean
        NULL
    );

    // Define AtRule struct: (id, selector, content, specificity)
    // Matches Rule interface for duck-typing
    // - For @keyframes: content is Array of Rule (keyframe blocks)
    // - For @font-face: content is Array of Declaration
    cAtRule = rb_struct_define_under(
        mCataract,
        "AtRule",
        "id",                 // Integer (0-indexed position in @rules array)
        "selector",           // String (e.g., "@keyframes fade", "@font-face")
        "content",            // Array of Rule or Declaration
        "specificity",        // Always nil for at-rules
        NULL
    );

    // Define Declarations class and add to_s method
    VALUE cDeclarations = rb_define_class_under(mCataract, "Declarations", rb_cObject);
    rb_define_method(cDeclarations, "to_s", new_declarations_to_s_method, 0);

    // Define Stylesheet class (Ruby will add instance methods like each_selector)
    cStylesheet = rb_define_class_under(mCataract, "Stylesheet", rb_cObject);

    // Define module functions
    rb_define_module_function(mCataract, "_parse_css", parse_css_new, 1);
    rb_define_module_function(mCataract, "_stylesheet_to_s", stylesheet_to_s_new, 3);
    rb_define_module_function(mCataract, "_stylesheet_to_formatted_s", stylesheet_to_formatted_s_new, 3);
    rb_define_module_function(mCataract, "parse_media_types", parse_media_types, 1);
    rb_define_module_function(mCataract, "parse_declarations", new_parse_declarations, 1);
    rb_define_module_function(mCataract, "merge", cataract_merge_new, 1);
    rb_define_module_function(mCataract, "extract_imports", extract_imports, 1);
    rb_define_module_function(mCataract, "calculate_specificity", calculate_specificity, 1);

    // Initialize merge constants (cached property strings)
    init_merge_constants();
}
