#include "cataract.h"
#include <stdio.h>

/*
 * C implementation of Stylesheet#to_s with no rb_funcall
 * Uses rb_hash_foreach callbacks instead of extracting keys
 *
 * This provides ~36% speedup over the Ruby implementation for serialization,
 * which is important since to_s is a hot path in the premailer use case.
 */

// Context for merge callback
struct merge_groups_ctx {
    VALUE merged_rules;
    VALUE self;
};

// Callback for merging each group
static int merge_groups_callback(VALUE key, VALUE group_rules, VALUE arg) {
    struct merge_groups_ctx *ctx = (struct merge_groups_ctx *)arg;

    VALUE first_rule = RARRAY_AREF(group_rules, 0);
    VALUE selector = rb_struct_aref(first_rule, INT2FIX(0));
    VALUE specificity = rb_struct_aref(first_rule, INT2FIX(2));
    VALUE media_query = rb_struct_aref(first_rule, INT2FIX(3));

    // Merge declarations for this group (C function, no rb_funcall)
    VALUE merged_declarations = cataract_merge(ctx->self, group_rules);

    // Create new Rule struct
    VALUE new_rule = rb_struct_new(cRule, selector, merged_declarations, specificity, media_query);
    rb_ary_push(ctx->merged_rules, new_rule);

    return ST_CONTINUE;
}

// Context for serialization callback
struct serialize_media_ctx {
    VALUE result;
    VALUE self;
};

// Callback for serializing each media type
static int serialize_media_callback(VALUE media_type, VALUE rules_for_media, VALUE arg) {
    struct serialize_media_ctx *ctx = (struct serialize_media_ctx *)arg;

    // Check if this is a media block
    VALUE all_sym = ID2SYM(rb_intern("all"));
    int is_media_block = (media_type != all_sym);

    if (is_media_block) {
        rb_str_buf_cat2(ctx->result, "@media ");
        // Use rb_sym2str instead of to_s (no rb_funcall)
        VALUE media_str = rb_sym2str(media_type);
        rb_str_buf_append(ctx->result, media_str);
        rb_str_buf_cat2(ctx->result, " {\n");
    }

    long rules_len = RARRAY_LEN(rules_for_media);
    for (long j = 0; j < rules_len; j++) {
        VALUE rule = RARRAY_AREF(rules_for_media, j);
        VALUE selector = rb_struct_aref(rule, INT2FIX(0));
        VALUE declarations = rb_struct_aref(rule, INT2FIX(1));

        if (is_media_block) {
            rb_str_buf_cat2(ctx->result, "  ");
        }

        rb_str_buf_append(ctx->result, selector);
        rb_str_buf_cat2(ctx->result, " { ");

        // C function, no rb_funcall
        VALUE decls_str = declarations_to_s(ctx->self, declarations);
        rb_str_buf_append(ctx->result, decls_str);

        rb_str_buf_cat2(ctx->result, " }\n");
    }

    if (is_media_block) {
        rb_str_buf_cat2(ctx->result, "}\n");
    }

    return ST_CONTINUE;
}

VALUE stylesheet_to_s_c(VALUE self, VALUE rules_array) {
    Check_Type(rules_array, T_ARRAY);

    long len = RARRAY_LEN(rules_array);
    if (len == 0) {
        return rb_str_new_cstr("");
    }

    // Step 1: Group rules by [selector, media_query]
    // Use array as hash key (Ruby compares arrays by value)
    VALUE groups = rb_hash_new();

    for (long i = 0; i < len; i++) {
        VALUE rule = RARRAY_AREF(rules_array, i);
        Check_Type(rule, T_STRUCT);

        VALUE selector = rb_struct_aref(rule, INT2FIX(0));
        VALUE media_query = rb_struct_aref(rule, INT2FIX(3));

        // Create array key [selector, media_query] - no string conversion!
        VALUE key = rb_ary_new_from_args(2, selector, media_query);

        VALUE group = rb_hash_aref(groups, key);
        if (NIL_P(group)) {
            group = rb_ary_new();
            rb_hash_aset(groups, key, group);
        }
        rb_ary_push(group, rule);
    }

    // Step 2: Merge each group using rb_hash_foreach (no .keys call)
    VALUE merged_rules = rb_ary_new();
    struct merge_groups_ctx merge_ctx = { merged_rules, self };
    rb_hash_foreach(groups, merge_groups_callback, (VALUE)&merge_ctx);

    // Step 3: Group merged rules by media_type
    VALUE styles_by_media = rb_hash_new();
    long merged_len = RARRAY_LEN(merged_rules);

    for (long i = 0; i < merged_len; i++) {
        VALUE rule = RARRAY_AREF(merged_rules, i);
        VALUE media_query = rb_struct_aref(rule, INT2FIX(3));

        long media_len = RARRAY_LEN(media_query);
        for (long j = 0; j < media_len; j++) {
            VALUE media_type = RARRAY_AREF(media_query, j);

            VALUE rules_for_media = rb_hash_aref(styles_by_media, media_type);
            if (NIL_P(rules_for_media)) {
                rules_for_media = rb_ary_new();
                rb_hash_aset(styles_by_media, media_type, rules_for_media);
            }
            rb_ary_push(rules_for_media, rule);
        }
    }

    // Step 4: Serialize to string using rb_hash_foreach (no .keys call)
    VALUE result = rb_str_buf_new(merged_len * 100);
    struct serialize_media_ctx serialize_ctx = { result, self };
    rb_hash_foreach(styles_by_media, serialize_media_callback, (VALUE)&serialize_ctx);

    RB_GC_GUARD(groups);
    RB_GC_GUARD(merged_rules);
    RB_GC_GUARD(styles_by_media);
    RB_GC_GUARD(result);

    return result;
}
