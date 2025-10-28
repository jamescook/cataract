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
// Ruby Bindings and Public API
// ============================================================================

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
    const char *css_start = RSTRING_PTR(css_string);
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
                    DEBUG_PRINTF("[@charset] Extracted: '%s'\n", RSTRING_PTR(charset));
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

    // Export compile-time optimization flags as a hash for runtime introspection
    VALUE compile_flags = rb_hash_new();

    #ifdef DISABLE_STR_BUF_OPTIMIZATION
        rb_hash_aset(compile_flags, ID2SYM(rb_intern("str_buf_optimization")), Qfalse);
    #else
        rb_hash_aset(compile_flags, ID2SYM(rb_intern("str_buf_optimization")), Qtrue);
    #endif

    #ifdef CATARACT_DEBUG
        rb_hash_aset(compile_flags, ID2SYM(rb_intern("debug")), Qtrue);
    #else
        rb_hash_aset(compile_flags, ID2SYM(rb_intern("debug")), Qfalse);
    #endif

    #ifdef DISABLE_LOOP_UNROLL
        rb_hash_aset(compile_flags, ID2SYM(rb_intern("loop_unroll")), Qfalse);
    #else
        rb_hash_aset(compile_flags, ID2SYM(rb_intern("loop_unroll")), Qtrue);
    #endif

    // Note: Compiler flags like -O3, -march=native, -funroll-loops don't have
    // preprocessor defines, so we can't detect them at runtime. They're purely
    // compiler optimizations that affect the generated code.

    rb_define_const(module, "COMPILE_FLAGS", compile_flags);
}

// NOTE: shorthand_expander.c and value_splitter.c are now compiled separately (not included)

