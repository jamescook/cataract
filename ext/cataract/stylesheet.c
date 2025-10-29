#include "cataract.h"
#include <stdio.h>

/*
 * C implementation of Stylesheet#to_s with no rb_funcall
 * Optimized for new hash structure: {query_string => {media_types: [...], rules: [...]}}
 *
 * This provides ~36% speedup over the Ruby implementation for serialization,
 * which is important since to_s is a hot path in the premailer use case.
 */

// Context for merge callback within a group
struct merge_selector_ctx {
    VALUE merged_rules;
    VALUE self;
};

// Callback for merging rules with the same selector within a media group
static int merge_selector_callback(VALUE selector, VALUE selector_rules, VALUE arg) {
    struct merge_selector_ctx *ctx = (struct merge_selector_ctx *)arg;

    // If only one rule, use it directly
    if (RARRAY_LEN(selector_rules) == 1) {
        rb_ary_push(ctx->merged_rules, RARRAY_AREF(selector_rules, 0));
        return ST_CONTINUE;
    }

    // Multiple rules with same selector - merge them
    VALUE first_rule = RARRAY_AREF(selector_rules, 0);
    VALUE specificity = rb_struct_aref(first_rule, INT2FIX(2));

    // Merge declarations for this selector (C function, no rb_funcall)
    VALUE merged_declarations = cataract_merge(ctx->self, selector_rules);

    // Create new merged Rule struct
    VALUE merged_rule = rb_struct_new(cRule, selector, merged_declarations, specificity);
    rb_ary_push(ctx->merged_rules, merged_rule);

    return ST_CONTINUE;
}

// Context for processing each media group
struct process_group_ctx {
    VALUE result;
    VALUE self;
};

// Callback for processing each media query group
static int process_group_callback(VALUE query_string, VALUE group_hash, VALUE arg) {
    struct process_group_ctx *ctx = (struct process_group_ctx *)arg;

    // Extract rules array from group hash
    VALUE rules_array = rb_hash_aref(group_hash, ID2SYM(rb_intern("rules")));
    if (NIL_P(rules_array) || RARRAY_LEN(rules_array) == 0) {
        return ST_CONTINUE; // Skip empty groups
    }

    // Group rules by selector for merging
    VALUE rules_by_selector = rb_hash_new();
    long rules_len = RARRAY_LEN(rules_array);

    for (long i = 0; i < rules_len; i++) {
        VALUE rule = RARRAY_AREF(rules_array, i);
        VALUE selector = rb_struct_aref(rule, INT2FIX(0));

        VALUE selector_group = rb_hash_aref(rules_by_selector, selector);
        if (NIL_P(selector_group)) {
            selector_group = rb_ary_new();
            rb_hash_aset(rules_by_selector, selector, selector_group);
        }
        rb_ary_push(selector_group, rule);
    }

    // Merge rules with same selector
    VALUE merged_rules = rb_ary_new();
    struct merge_selector_ctx merge_ctx = { merged_rules, ctx->self };
    rb_hash_foreach(rules_by_selector, merge_selector_callback, (VALUE)&merge_ctx);

    // Check if this is a media query or not
    int has_media_query = !NIL_P(query_string);

    if (has_media_query) {
        // Output @media wrapper
        rb_str_buf_cat2(ctx->result, "@media ");
        rb_str_buf_append(ctx->result, query_string);
        rb_str_buf_cat2(ctx->result, " {\n");
    }

    // Output each merged rule
    long merged_len = RARRAY_LEN(merged_rules);
    for (long j = 0; j < merged_len; j++) {
        VALUE rule = RARRAY_AREF(merged_rules, j);
        VALUE selector = rb_struct_aref(rule, INT2FIX(0));
        VALUE declarations = rb_struct_aref(rule, INT2FIX(1));

        if (has_media_query) {
            rb_str_buf_cat2(ctx->result, "  ");
        }

        rb_str_buf_append(ctx->result, selector);
        rb_str_buf_cat2(ctx->result, " { ");

        // C function, no rb_funcall
        VALUE decls_str = declarations_to_s(ctx->self, declarations);
        rb_str_buf_append(ctx->result, decls_str);

        rb_str_buf_cat2(ctx->result, " }\n");
    }

    if (has_media_query) {
        rb_str_buf_cat2(ctx->result, "}\n");
    }

    RB_GC_GUARD(rules_array);
    RB_GC_GUARD(rules_by_selector);
    RB_GC_GUARD(merged_rules);

    return ST_CONTINUE;
}

// Main function: stylesheet_to_s_c(rule_groups_hash, charset)
// New signature: takes hash structure {query_string => {media_types: [...], rules: [...]}}
VALUE stylesheet_to_s_c(VALUE self, VALUE rule_groups, VALUE charset) {
    Check_Type(rule_groups, T_HASH);

    long num_groups = RHASH_SIZE(rule_groups);

    // Handle empty stylesheet
    if (num_groups == 0) {
        if (!NIL_P(charset)) {
            // Even empty stylesheet should emit @charset if present
            VALUE result = UTF8_STR("@charset \"");
            rb_str_buf_append(result, charset);
            rb_str_buf_cat2(result, "\";\n");
            return result;
        }
        return UTF8_STR("");
    }

    // Allocate result string with reasonable capacity
    VALUE result = rb_str_buf_new(num_groups * 100);

    // Emit @charset first if present (must be first per W3C spec)
    if (!NIL_P(charset)) {
        rb_str_buf_cat2(result, "@charset \"");
        rb_str_buf_append(result, charset);
        rb_str_buf_cat2(result, "\";\n");
    }

    // Process each media query group
    struct process_group_ctx ctx = { result, self };
    rb_hash_foreach(rule_groups, process_group_callback, (VALUE)&ctx);

    RB_GC_GUARD(result);

    return result;
}

// ============================================================================
// Formatted output (to_formatted_s)
// ============================================================================

// Context for formatted processing
struct format_group_ctx {
    VALUE result;
    VALUE self;
};

// Callback for formatted output with newlines and 2-space indentation
static int format_group_callback(VALUE query_string, VALUE group_hash, VALUE arg) {
    struct format_group_ctx *ctx = (struct format_group_ctx *)arg;

    // Extract rules array from group hash
    VALUE rules_array = rb_hash_aref(group_hash, ID2SYM(rb_intern("rules")));
    if (NIL_P(rules_array) || RARRAY_LEN(rules_array) == 0) {
        return ST_CONTINUE; // Skip empty groups
    }

    // Group rules by selector for merging
    VALUE rules_by_selector = rb_hash_new();
    long rules_len = RARRAY_LEN(rules_array);

    for (long i = 0; i < rules_len; i++) {
        VALUE rule = RARRAY_AREF(rules_array, i);
        VALUE selector = rb_struct_aref(rule, INT2FIX(0));

        VALUE selector_group = rb_hash_aref(rules_by_selector, selector);
        if (NIL_P(selector_group)) {
            selector_group = rb_ary_new();
            rb_hash_aset(rules_by_selector, selector, selector_group);
        }
        rb_ary_push(selector_group, rule);
    }

    // Merge rules with same selector
    VALUE merged_rules = rb_ary_new();
    struct merge_selector_ctx merge_ctx = { merged_rules, ctx->self };
    rb_hash_foreach(rules_by_selector, merge_selector_callback, (VALUE)&merge_ctx);

    // Check if this is a media query or not
    int has_media_query = !NIL_P(query_string);

    if (has_media_query) {
        // Output @media wrapper
        rb_str_buf_cat2(ctx->result, "@media ");
        rb_str_buf_append(ctx->result, query_string);
        rb_str_buf_cat2(ctx->result, " {\n");
    }

    // Output each merged rule with formatting
    long merged_len = RARRAY_LEN(merged_rules);
    for (long j = 0; j < merged_len; j++) {
        VALUE rule = RARRAY_AREF(merged_rules, j);
        VALUE selector = rb_struct_aref(rule, INT2FIX(0));
        VALUE declarations = rb_struct_aref(rule, INT2FIX(1));

        // Indent selector if inside media query
        if (has_media_query) {
            rb_str_buf_cat2(ctx->result, "  ");
        }

        // Selector on its own line
        rb_str_buf_append(ctx->result, selector);
        rb_str_buf_cat2(ctx->result, " {\n");

        // Declarations indented with 2 spaces (or 4 if inside media query)
        const char *indent = has_media_query ? "    " : "  ";
        rb_str_buf_cat2(ctx->result, indent);

        // Get declarations string
        VALUE decls_str = declarations_to_s(ctx->self, declarations);
        rb_str_buf_append(ctx->result, decls_str);

        rb_str_buf_cat2(ctx->result, "\n");

        // Closing brace
        if (has_media_query) {
            rb_str_buf_cat2(ctx->result, "  ");
        }
        rb_str_buf_cat2(ctx->result, "}\n");
    }

    if (has_media_query) {
        rb_str_buf_cat2(ctx->result, "}\n");
    }

    RB_GC_GUARD(rules_array);
    RB_GC_GUARD(rules_by_selector);
    RB_GC_GUARD(merged_rules);

    return ST_CONTINUE;
}

// stylesheet_to_formatted_s_c(rule_groups_hash, charset)
// Returns formatted multi-line output with 2-space indentation
// Not optimized for performance since it's not in the hot path
VALUE stylesheet_to_formatted_s_c(VALUE self, VALUE rule_groups, VALUE charset) {
    Check_Type(rule_groups, T_HASH);

    long num_groups = RHASH_SIZE(rule_groups);

    // Handle empty stylesheet
    if (num_groups == 0) {
        if (!NIL_P(charset)) {
            VALUE result = UTF8_STR("@charset \"");
            rb_str_buf_append(result, charset);
            rb_str_buf_cat2(result, "\";\n");
            return result;
        }
        return UTF8_STR("");
    }

    // Simple allocation - let Ruby resize as needed (not in hot path)
    VALUE result = UTF8_STR("");

    // Emit @charset first if present
    if (!NIL_P(charset)) {
        rb_str_buf_cat2(result, "@charset \"");
        rb_str_buf_append(result, charset);
        rb_str_buf_cat2(result, "\";\n");
    }

    // Process each media query group with formatting
    struct format_group_ctx ctx = { result, self };
    rb_hash_foreach(rule_groups, format_group_callback, (VALUE)&ctx);

    RB_GC_GUARD(result);

    return result;
}
