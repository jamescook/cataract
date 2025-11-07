#include <ruby.h>
#include <stdio.h>
#include "cataract_new.h"

// Global struct class definitions
VALUE cNewRule;
VALUE cNewDeclaration;

// Error class definitions (shared with main extension)
VALUE eCataractError;
VALUE eParseError;
VALUE eSizeError;

// ============================================================================
// Stubbed Implementation - Phase 1
// ============================================================================

/*
 * Parse CSS string into NewRule structs
 *
 * @param css_string [String] CSS string to parse
 * @return [Hash] { rules: [NewRule, ...], charset: "..." | nil }
 */
static VALUE parse_css_new(VALUE self, VALUE css_string) {
    return parse_css_new_impl(css_string);
}

/*
 * Serialize rules array to CSS string with proper media query grouping
 *
 * @param rules_array [Array<NewRule>] Flat array of rules in insertion order
 * @param charset [String, nil] Optional @charset value
 * @return [String] CSS string
 */
static VALUE stylesheet_to_s_new(VALUE self, VALUE rules_array, VALUE charset) {
    Check_Type(rules_array, T_ARRAY);

    VALUE result = rb_str_new_cstr("");

    // Add charset if present
    if (!NIL_P(charset)) {
        rb_str_cat2(result, "@charset \"");
        rb_str_append(result, charset);
        rb_str_cat2(result, "\";\n");
    }

    // Track current media query to group consecutive rules
    VALUE current_media = Qundef;  // Undefined means not set yet
    long len = RARRAY_LEN(rules_array);

    for (long i = 0; i < len; i++) {
        VALUE rule = rb_ary_entry(rules_array, i);

        // Extract fields
        VALUE selector = rb_struct_aref(rule, INT2FIX(NEW_RULE_SELECTOR));
        VALUE declarations = rb_struct_aref(rule, INT2FIX(NEW_RULE_DECLARATIONS));
        VALUE media_sym = rb_struct_aref(rule, INT2FIX(NEW_RULE_MEDIA_QUERY_SYM));

        // Check if media query changed
        if (current_media == Qundef ||
            (NIL_P(current_media) && !NIL_P(media_sym)) ||
            (!NIL_P(current_media) && NIL_P(media_sym)) ||
            (!NIL_P(current_media) && !NIL_P(media_sym) && !rb_equal(current_media, media_sym))) {

            // Close previous @media block if needed
            if (current_media != Qundef && !NIL_P(current_media)) {
                rb_str_cat2(result, "}\n");
            }

            // Open new @media block if needed
            if (!NIL_P(media_sym)) {
                rb_str_cat2(result, "@media ");
                rb_str_append(result, rb_sym2str(media_sym));
                rb_str_cat2(result, " {\n");
            }

            current_media = media_sym;
        }

        // Serialize rule
        rb_str_append(result, selector);
        rb_str_cat2(result, " { ");

        // Serialize declarations
        long decl_len = RARRAY_LEN(declarations);
        for (long j = 0; j < decl_len; j++) {
            VALUE decl = rb_ary_entry(declarations, j);
            VALUE property = rb_struct_aref(decl, INT2FIX(NEW_DECL_PROPERTY));
            VALUE value = rb_struct_aref(decl, INT2FIX(NEW_DECL_VALUE));
            VALUE important = rb_struct_aref(decl, INT2FIX(NEW_DECL_IMPORTANT));

            rb_str_append(result, property);
            rb_str_cat2(result, ": ");
            rb_str_append(result, value);

            if (RTEST(important)) {
                rb_str_cat2(result, " !important");
            }

            rb_str_cat2(result, "; ");
        }

        rb_str_cat2(result, "}\n");
    }

    // Close final @media block if needed
    if (current_media != Qundef && !NIL_P(current_media)) {
        rb_str_cat2(result, "}\n");
    }

    return result;
}

// ============================================================================
// Ruby Module Initialization
// ============================================================================

void Init_cataract_new(void) {
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

    // Define NewRule struct: (selector, declarations, specificity, media_query_sym)
    cNewRule = rb_struct_define_under(
        mCataract,
        "NewRule",
        "selector",           // String
        "declarations",       // Array of NewDeclaration
        "specificity",        // Integer (nil = not calculated yet)
        "media_query_sym",    // Symbol or nil
        NULL
    );

    // Define NewDeclaration struct: (property, value, important)
    cNewDeclaration = rb_struct_define_under(
        mCataract,
        "NewDeclaration",
        "property",    // String
        "value",       // String
        "important",   // Boolean
        NULL
    );

    // Define module functions
    rb_define_module_function(mCataract, "parse_css_new", parse_css_new, 1);
    rb_define_module_function(mCataract, "_stylesheet_to_s_new", stylesheet_to_s_new, 2);
}
