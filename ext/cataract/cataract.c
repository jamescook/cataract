#include <ruby.h>
#include <stdio.h>
#include "cataract.h"

// Global struct class definitions
VALUE cRule;
VALUE cDeclaration;
VALUE cAtRule;
VALUE cStylesheet;
VALUE cImportStatement;
VALUE cMediaQuery;

// Error class definitions (shared with main extension)
VALUE eCataractError;
VALUE eDepthError;
VALUE eSizeError;

// ============================================================================
// Helper Functions
// ============================================================================

/*
 * Build media query text from MediaQuery struct
 * Implements the logic from MediaQuery#text in Ruby
 */
static void append_media_query_text(VALUE result, VALUE media_query) {
    DEBUG_PRINTF("[APPEND_MQ] Called with media_query=%s (class: %s)\n",
                RSTRING_PTR(rb_inspect(media_query)),
                rb_obj_classname(media_query));
    VALUE media_type = rb_struct_aref(media_query, INT2FIX(1)); // type field
    VALUE media_conditions = rb_struct_aref(media_query, INT2FIX(2)); // conditions field

    if (!NIL_P(media_conditions)) {
        // Has conditions
        ID all_id = rb_intern("all");
        if (SYM2ID(media_type) == all_id) {
            // Type is :all - just output conditions (don't say "all and ...")
            rb_str_append(result, media_conditions);
        } else {
            // Output "type and conditions"
            rb_str_append(result, rb_sym2str(media_type));
            rb_str_cat2(result, " and ");
            rb_str_append(result, media_conditions);
        }
    } else {
        // No conditions - just output type
        rb_str_append(result, rb_sym2str(media_type));
    }
}

// Build media query string from MediaQuery object, handling comma-separated lists
// Matches pure Ruby's build_media_query_string method
// @param result [String] String to append to
// @param media_query_id [VALUE] The media query ID from the rule (Fixnum)
// @param mq_id_to_list_id [Hash] Reverse map: media_query_id => list_id
// @param media_query_lists [Hash] Hash mapping list_id => array of MediaQuery IDs
// @param media_queries [Array] Array of all MediaQuery objects
static void append_media_query_string(VALUE result, VALUE media_query_id, VALUE mq_id_to_list_id, VALUE media_query_lists, VALUE media_queries) {
    // Check if this media_query_id is part of a comma-separated list
    VALUE list_id = rb_hash_aref(mq_id_to_list_id, media_query_id);

    if (!NIL_P(list_id)) {
        // Part of a list - serialize all media queries in the list with commas
        VALUE mq_ids = rb_hash_aref(media_query_lists, list_id);
        if (!NIL_P(mq_ids) && TYPE(mq_ids) == T_ARRAY) {
            long list_len = RARRAY_LEN(mq_ids);
            for (long i = 0; i < list_len; i++) {
                if (i > 0) {
                    rb_str_cat2(result, ", ");
                }
                VALUE mq_id = rb_ary_entry(mq_ids, i);
                int mq_id_int = FIX2INT(mq_id);
                VALUE mq = rb_ary_entry(media_queries, mq_id_int);
                if (!NIL_P(mq)) {
                    append_media_query_text(result, mq);
                }
            }
        }
    } else {
        // Single media query - just append it
        int mq_id_int = FIX2INT(media_query_id);
        VALUE mq = rb_ary_entry(media_queries, mq_id_int);
        if (!NIL_P(mq)) {
            append_media_query_text(result, mq);
        }
    }
    // No GC guards needed - we don't extract pointers from VALUEs, just pass them to functions
}

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
 * @param parser_options [Hash] Parser options (optional, defaults to {})
 * @return [Hash] { rules: [...], media_index: {...}, charset: "..." }
 */
VALUE parse_css_new(int argc, VALUE *argv, VALUE self) {
    VALUE css_string, parser_options;

    // Parse arguments: required css_string, optional parser_options hash
    rb_scan_args(argc, argv, "11", &css_string, &parser_options);

    // Default to empty hash if not provided
    if (NIL_P(parser_options)) {
        parser_options = rb_hash_new();
    }

    return parse_css_new_impl(css_string, parser_options, 0);
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

// Formatted version - each declaration on its own line with indentation
static void serialize_declarations_formatted(VALUE result, VALUE declarations, const char *indent) {
    long decl_len = RARRAY_LEN(declarations);
    for (long j = 0; j < decl_len; j++) {
        VALUE decl = rb_ary_entry(declarations, j);
        VALUE property = rb_struct_aref(decl, INT2FIX(DECL_PROPERTY));
        VALUE value = rb_struct_aref(decl, INT2FIX(DECL_VALUE));
        VALUE important = rb_struct_aref(decl, INT2FIX(DECL_IMPORTANT));

        rb_str_cat2(result, indent);
        rb_str_append(result, property);
        rb_str_cat2(result, ": ");
        rb_str_append(result, value);

        if (RTEST(important)) {
            rb_str_cat2(result, " !important");
        }

        rb_str_cat2(result, ";\n");
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

// Helper to "unresolve" a child selector back to its nested form
// Input: parent_selector=".button", child_selector=".button:hover", nesting_style=EXPLICIT
// Output: "&:hover"
// Input: parent_selector=".parent", child_selector=".parent .child", nesting_style=IMPLICIT
// Output: ".child"
static VALUE unresolve_selector(VALUE parent_selector, VALUE child_selector, VALUE nesting_style) {
    const char *parent = RSTRING_PTR(parent_selector);
    long parent_len = RSTRING_LEN(parent_selector);
    const char *child = RSTRING_PTR(child_selector);
    long child_len = RSTRING_LEN(child_selector);

    int style = NIL_P(nesting_style) ? NESTING_STYLE_IMPLICIT : FIX2INT(nesting_style);

    VALUE result;

    if (style == NESTING_STYLE_EXPLICIT) {
        // Explicit nesting: replace parent with &
        // ".button:hover" -> "&:hover"
        // ".button.primary" -> "&.primary"

        // Find where parent ends in child
        if (strncmp(child, parent, parent_len) == 0) {
            // Parent matches at start - replace with &
            result = rb_str_new_cstr("&");
            rb_str_cat(result, child + parent_len, child_len - parent_len);
        } else {
            // Fallback: just return child (shouldn't happen)
            result = child_selector;
        }
    } else {
        // Implicit nesting: strip parent + space from beginning
        // ".parent .child" -> ".child"

        if (strncmp(child, parent, parent_len) == 0) {
            // Check if followed by space
            if (child_len > parent_len && child[parent_len] == ' ') {
                // Strip "parent " prefix
                result = rb_str_new(child + parent_len + 1, child_len - parent_len - 1);
            } else {
                // Fallback: return child as-is
                result = child_selector;
            }
        } else {
            // Fallback: return child as-is
            result = child_selector;
        }
    }

    // Guard both selectors since we extracted C pointers and did allocations
    RB_GC_GUARD(parent_selector);
    RB_GC_GUARD(child_selector);

    return result;
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

                // Declarations (one per line) with 4-space indent
                VALUE nested_indent = rb_str_new_cstr(indent);
                rb_str_cat2(nested_indent, "    ");
                const char *nested_indent_ptr = RSTRING_PTR(nested_indent);
                serialize_declarations_formatted(result, nested_declarations, nested_indent_ptr);
                RB_GC_GUARD(nested_indent);

                // Closing brace (2-space indent)
                rb_str_cat2(result, indent);
                rb_str_cat2(result, "  }\n");
            }
        } else {
            // Serialize as declarations (e.g., @font-face, one per line)
            VALUE content_indent = rb_str_new_cstr(indent);
            rb_str_cat2(content_indent, "  ");
            const char *content_indent_ptr = RSTRING_PTR(content_indent);
            serialize_declarations_formatted(result, content, content_indent_ptr);
            RB_GC_GUARD(content_indent);
        }
    }

    rb_str_cat2(result, indent);
    rb_str_cat2(result, "}\n");
}

// Helper to serialize a single rule with formatting (indented, multi-line)
static void serialize_rule_formatted(VALUE result, VALUE rule, const char *indent, int is_last) {
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

    // Declarations (one per line) with extra indentation
    VALUE decl_indent = rb_str_new_cstr(indent);
    rb_str_cat2(decl_indent, "  ");
    const char *decl_indent_ptr = RSTRING_PTR(decl_indent);
    serialize_declarations_formatted(result, declarations, decl_indent_ptr);
    RB_GC_GUARD(decl_indent);

    // Closing brace - double newline for all except last rule
    rb_str_cat2(result, indent);
    if (is_last) {
        rb_str_cat2(result, "}\n");
    } else {
        rb_str_cat2(result, "}\n\n");
    }
}

// Context for building mq_id_to_list_id reverse map
struct build_mq_reverse_map_ctx {
    VALUE mq_id_to_list_id;
};

// Callback to build reverse map: media_query_id => list_id
// Iterates through media_query_lists hash: list_id => [mq_id1, mq_id2, ...]
static int build_mq_reverse_map_callback(VALUE list_id, VALUE mq_ids, VALUE arg) {
    struct build_mq_reverse_map_ctx *ctx = (struct build_mq_reverse_map_ctx *)arg;

    if (!NIL_P(mq_ids) && TYPE(mq_ids) == T_ARRAY) {
        long num_mq_ids = RARRAY_LEN(mq_ids);
        for (long i = 0; i < num_mq_ids; i++) {
            VALUE mq_id = rb_ary_entry(mq_ids, i);
            rb_hash_aset(ctx->mq_id_to_list_id, mq_id, list_id);
        }
    }

    return ST_CONTINUE;
}

// Formatting options for stylesheet serialization
// Avoids mode flags and if/else branches - all behavior controlled by struct values
struct format_opts {
    const char *opening_brace;      // " { " (compact) vs " {\n" (formatted)
    const char *closing_brace;      // " }\n" (compact) vs "}\n" (formatted)
    const char *media_indent;       // "" (compact) vs "  " (formatted)
    const char *decl_indent_base;   // NULL (compact) vs "  " (formatted base rules)
    const char *decl_indent_media;  // NULL (compact) vs "    " (formatted media rules)
    int add_blank_lines;            // 0 (compact) vs 1 (formatted)
};

// Private shared implementation for stylesheet serialization with optional selector list grouping
// All formatting behavior controlled by format_opts struct to avoid mode flags and if/else branches
static VALUE serialize_stylesheet_with_grouping(
    VALUE rules_array,
    VALUE media_queries,
    VALUE media_query_lists,
    VALUE result,
    VALUE selector_lists,
    const struct format_opts *opts
) {
    long total_rules = RARRAY_LEN(rules_array);

    // Check if selector list grouping is enabled (non-empty hash)
    int grouping_enabled = (!NIL_P(selector_lists) && TYPE(selector_lists) == T_HASH && RHASH_SIZE(selector_lists) > 0);

    // Build reverse map: media_query_id => list_id
    // This allows us to detect when multiple rules share a comma-separated media query list
    VALUE mq_id_to_list_id = rb_hash_new();
    if (!NIL_P(media_query_lists) && TYPE(media_query_lists) == T_HASH) {
        struct build_mq_reverse_map_ctx ctx = { mq_id_to_list_id };
        rb_hash_foreach(media_query_lists, build_mq_reverse_map_callback, (VALUE)&ctx);
    }

    // Build rule_to_media map from media_query_id fields
    // Map: rule_id => MediaQuery object
    VALUE rule_to_media = rb_hash_new();
    for (long i = 0; i < total_rules; i++) {
        VALUE rule = rb_ary_entry(rules_array, i);
        // Only process Rule objects, not AtRules (AtRule has 5 fields, can't access RULE_MEDIA_QUERY_ID at index 7)
        if (!rb_obj_is_kind_of(rule, cAtRule)) {
            VALUE media_query_id = rb_struct_aref(rule, INT2FIX(RULE_MEDIA_QUERY_ID));
            if (!NIL_P(media_query_id)) {
                VALUE rule_id = rb_struct_aref(rule, INT2FIX(RULE_ID));
                int mq_id = FIX2INT(media_query_id);
                VALUE media_query = rb_ary_entry(media_queries, mq_id);
                if (!NIL_P(media_query)) {
                    rb_hash_aset(rule_to_media, rule_id, media_query);
                }
            }
        }
    }

    // Track processed rules to avoid duplicates when grouping
    VALUE processed_rule_ids = rb_hash_new();

    // Iterate through rules in insertion order, grouping consecutive media queries
    VALUE current_media = Qnil;
    int in_media_block = 0;

    for (long i = 0; i < total_rules; i++) {
        VALUE rule = rb_ary_entry(rules_array, i);
        VALUE rule_id = rb_struct_aref(rule, INT2FIX(RULE_ID));

        // Skip if already processed (when grouped)
        if (RTEST(rb_hash_aref(processed_rule_ids, rule_id))) {
            continue;
        }

        VALUE rule_media = rb_hash_aref(rule_to_media, rule_id);
        int is_first_rule = (i == 0);

        if (NIL_P(rule_media)) {
            // Not in any media query - close any open media block first
            if (in_media_block) {
                rb_str_cat2(result, "}\n");
                in_media_block = 0;
                current_media = Qnil;
            }

            // Add blank line prefix for non-first rules (formatted only)
            if (opts->add_blank_lines && !is_first_rule) {
                rb_str_cat2(result, "\n");
            }

            // Try to group with other rules from same selector list
            // Check if this is a Rule (not AtRule) before accessing selector_list_id
            if (grouping_enabled && rb_obj_is_kind_of(rule, cRule)) {
                VALUE selector_list_id = rb_struct_aref(rule, INT2FIX(RULE_SELECTOR_LIST_ID));
                if (!NIL_P(selector_list_id)) {
                    // Get list of rule IDs in this selector list
                    VALUE rule_ids_in_list = rb_hash_aref(selector_lists, selector_list_id);

                    if (NIL_P(rule_ids_in_list) || RARRAY_LEN(rule_ids_in_list) <= 1) {
                        // Just this rule, serialize normally
                        if (opts->decl_indent_base) {
                            serialize_rule_formatted(result, rule, "", 1);
                        } else {
                            serialize_rule(result, rule);
                        }
                        rb_hash_aset(processed_rule_ids, rule_id, Qtrue);
                    } else {
                        // Find all rules with matching declarations and same media context
                        VALUE matching_selectors = rb_ary_new();
                        VALUE rule_declarations = rb_struct_aref(rule, INT2FIX(RULE_DECLARATIONS));

                        long list_len = RARRAY_LEN(rule_ids_in_list);
                        for (long j = 0; j < list_len; j++) {
                            VALUE other_rule_id = rb_ary_entry(rule_ids_in_list, j);

                            // Skip if already processed
                            if (RTEST(rb_hash_aref(processed_rule_ids, other_rule_id))) {
                                continue;
                            }

                            // Find the rule by ID
                            VALUE other_rule = rb_ary_entry(rules_array, FIX2INT(other_rule_id));
                            if (NIL_P(other_rule)) continue;

                            // Check same media context (both should be nil for base rules)
                            VALUE other_rule_media = rb_hash_aref(rule_to_media, other_rule_id);
                            if (!rb_equal(rule_media, other_rule_media)) {
                                continue;
                            }

                            // Check if declarations match
                            VALUE other_declarations = rb_struct_aref(other_rule, INT2FIX(RULE_DECLARATIONS));
                            if (rb_equal(rule_declarations, other_declarations)) {
                                VALUE other_selector = rb_struct_aref(other_rule, INT2FIX(RULE_SELECTOR));
                                rb_ary_push(matching_selectors, other_selector);
                                rb_hash_aset(processed_rule_ids, other_rule_id, Qtrue);
                            }
                        }

                        // Serialize grouped or single rule
                        if (RARRAY_LEN(matching_selectors) > 1) {
                            // Group selectors with comma-space separator
                            VALUE selector_str = rb_ary_join(matching_selectors, rb_str_new_cstr(", "));
                            rb_str_append(result, selector_str);
                            rb_str_cat2(result, opts->opening_brace);
                            if (opts->decl_indent_base) {
                                serialize_declarations_formatted(result, rule_declarations, opts->decl_indent_base);
                            } else {
                                serialize_declarations(result, rule_declarations);
                            }
                            rb_str_cat2(result, opts->closing_brace);
                            RB_GC_GUARD(selector_str);
                        } else {
                            // Just one rule, serialize normally
                            if (opts->decl_indent_base) {
                                serialize_rule_formatted(result, rule, "", 1);
                            } else {
                                serialize_rule(result, rule);
                            }
                        }
                    }
                } else {
                    // No selector_list_id, serialize normally
                    if (opts->decl_indent_base) {
                        serialize_rule_formatted(result, rule, "", 1);
                    } else {
                        serialize_rule(result, rule);
                    }
                    rb_hash_aset(processed_rule_ids, rule_id, Qtrue);
                }
            } else {
                // Grouping disabled, serialize normally
                if (opts->decl_indent_base) {
                    serialize_rule_formatted(result, rule, "", 1);
                } else {
                    serialize_rule(result, rule);
                }
                rb_hash_aset(processed_rule_ids, rule_id, Qtrue);
            }
        } else {
            // This rule is in a media query
            // Check if media query changed from previous rule
            if (NIL_P(current_media) || !rb_equal(current_media, rule_media)) {
                // Close previous media block if open
                if (in_media_block) {
                    rb_str_cat2(result, "}\n");
                }

                // Add blank line prefix for non-first rules (formatted only)
                if (opts->add_blank_lines && !is_first_rule) {
                    rb_str_cat2(result, "\n");
                }

                // Open new media block
                current_media = rule_media;
                rb_str_cat2(result, "@media ");

                // Get media_query_id from rule and serialize (handles comma-separated lists)
                VALUE media_query_id = rb_struct_aref(rule, INT2FIX(RULE_MEDIA_QUERY_ID));
                if (!NIL_P(media_query_id)) {
                    append_media_query_string(result, media_query_id, mq_id_to_list_id, media_query_lists, media_queries);
                }

                rb_str_cat2(result, " {\n");
                in_media_block = 1;
            }

            // Serialize rule inside media block (with grouping if enabled)
            // Check if this is a Rule (not AtRule) before accessing selector_list_id
            if (grouping_enabled && rb_obj_is_kind_of(rule, cRule)) {
                VALUE selector_list_id = rb_struct_aref(rule, INT2FIX(RULE_SELECTOR_LIST_ID));
                if (!NIL_P(selector_list_id)) {
                    VALUE rule_ids_in_list = rb_hash_aref(selector_lists, selector_list_id);

                    if (NIL_P(rule_ids_in_list) || RARRAY_LEN(rule_ids_in_list) <= 1) {
                        if (opts->decl_indent_media) {
                            serialize_rule_formatted(result, rule, opts->media_indent, 1);
                        } else {
                            serialize_rule(result, rule);
                        }
                        rb_hash_aset(processed_rule_ids, rule_id, Qtrue);
                    } else {
                        VALUE matching_selectors = rb_ary_new();
                        VALUE rule_declarations = rb_struct_aref(rule, INT2FIX(RULE_DECLARATIONS));

                        long list_len = RARRAY_LEN(rule_ids_in_list);
                        for (long j = 0; j < list_len; j++) {
                            VALUE other_rule_id = rb_ary_entry(rule_ids_in_list, j);
                            if (RTEST(rb_hash_aref(processed_rule_ids, other_rule_id))) continue;

                            VALUE other_rule = rb_ary_entry(rules_array, FIX2INT(other_rule_id));
                            if (NIL_P(other_rule)) continue;

                            VALUE other_rule_media = rb_hash_aref(rule_to_media, other_rule_id);
                            if (!rb_equal(rule_media, other_rule_media)) continue;

                            VALUE other_declarations = rb_struct_aref(other_rule, INT2FIX(RULE_DECLARATIONS));
                            if (rb_equal(rule_declarations, other_declarations)) {
                                VALUE other_selector = rb_struct_aref(other_rule, INT2FIX(RULE_SELECTOR));
                                rb_ary_push(matching_selectors, other_selector);
                                rb_hash_aset(processed_rule_ids, other_rule_id, Qtrue);
                            }
                        }

                        if (RARRAY_LEN(matching_selectors) > 1) {
                            VALUE selector_str = rb_ary_join(matching_selectors, rb_str_new_cstr(", "));
                            rb_str_cat2(result, opts->media_indent);
                            rb_str_append(result, selector_str);
                            rb_str_cat2(result, opts->opening_brace);
                            if (opts->decl_indent_media) {
                                serialize_declarations_formatted(result, rule_declarations, opts->decl_indent_media);
                            } else {
                                serialize_declarations(result, rule_declarations);
                            }
                            rb_str_cat2(result, opts->media_indent);
                            rb_str_cat2(result, opts->closing_brace);
                            RB_GC_GUARD(selector_str);
                        } else {
                            if (opts->decl_indent_media) {
                                serialize_rule_formatted(result, rule, opts->media_indent, 1);
                            } else {
                                serialize_rule(result, rule);
                            }
                        }
                    }
                } else {
                    if (opts->decl_indent_media) {
                        serialize_rule_formatted(result, rule, opts->media_indent, 1);
                    } else {
                        serialize_rule(result, rule);
                    }
                    rb_hash_aset(processed_rule_ids, rule_id, Qtrue);
                }
            } else {
                if (opts->decl_indent_media) {
                    serialize_rule_formatted(result, rule, opts->media_indent, 1);
                } else {
                    serialize_rule(result, rule);
                }
                rb_hash_aset(processed_rule_ids, rule_id, Qtrue);
            }
        }
    }

    // Close final media block if still open
    if (in_media_block) {
        rb_str_cat2(result, "}\n");
    }

    // Guard hash objects we created and used throughout
    RB_GC_GUARD(mq_id_to_list_id);
    RB_GC_GUARD(rule_to_media);
    RB_GC_GUARD(processed_rule_ids);
    return result;
}

// Original stylesheet serialization (no nesting support) - compact format
static VALUE stylesheet_to_s_original(VALUE rules_array, VALUE media_queries, VALUE media_query_lists, VALUE charset, VALUE selector_lists) {
    Check_Type(rules_array, T_ARRAY);
    Check_Type(media_queries, T_ARRAY);

    VALUE result = rb_str_new_cstr("");

    // Add charset if present
    if (!NIL_P(charset)) {
        rb_str_cat2(result, "@charset \"");
        rb_str_append(result, charset);
        rb_str_cat2(result, "\";\n");
    }

    // Compact formatting options
    struct format_opts opts = {
        .opening_brace = " { ",
        .closing_brace = " }\n",
        .media_indent = "",
        .decl_indent_base = NULL,
        .decl_indent_media = NULL,
        .add_blank_lines = 0
    };

    return serialize_stylesheet_with_grouping(rules_array, media_queries, media_query_lists, result, selector_lists, &opts);
}

// Forward declarations
static void serialize_children_only(VALUE result, VALUE rules_array, long rule_idx,
                                    VALUE rule_to_media, VALUE parent_to_children, VALUE parent_selector,
                                    VALUE parent_declarations, int formatted, int indent_level);
static void serialize_rule_with_children(VALUE result, VALUE rules_array, long rule_idx,
                                         VALUE rule_to_media, VALUE parent_to_children,
                                         int formatted, int indent_level);

// Helper: Only serialize children of a rule (not the rule itself)
static void serialize_children_only(VALUE result, VALUE rules_array, long rule_idx,
                                    VALUE rule_to_media, VALUE parent_to_children, VALUE parent_selector,
                                    VALUE parent_declarations, int formatted, int indent_level) {
    VALUE rule = rb_ary_entry(rules_array, rule_idx);
    VALUE rule_id = rb_struct_aref(rule, INT2FIX(RULE_ID));
    VALUE rule_media = rb_hash_aref(rule_to_media, rule_id);  // Look up by rule ID, not array index
    int parent_has_declarations = !NIL_P(parent_declarations) && RARRAY_LEN(parent_declarations) > 0;

    // Build indentation string for this level (only if formatted)
    VALUE indent_str = Qnil;
    if (formatted) {
        indent_str = rb_str_new_cstr("");
        for (int i = 0; i < indent_level; i++) {
            rb_str_cat2(indent_str, "  ");
        }
    }

    // Get children of this rule using the map
    VALUE children_indices = rb_hash_aref(parent_to_children, rule_id);

    DEBUG_PRINTF("[SERIALIZE] Looking up children for rule_id=%s\n",
                RSTRING_PTR(rb_inspect(rule_id)));

    if (!NIL_P(children_indices)) {
        long num_children = RARRAY_LEN(children_indices);
        DEBUG_PRINTF("[SERIALIZE] Found %ld children for rule %ld (id=%s)\n",
                    num_children, rule_idx, RSTRING_PTR(rb_inspect(rule_id)));

        // Serialize selector-nested children
        for (long i = 0; i < num_children; i++) {
            long child_idx = FIX2LONG(rb_ary_entry(children_indices, i));
            VALUE child = rb_ary_entry(rules_array, child_idx);
            VALUE child_id = rb_struct_aref(child, INT2FIX(RULE_ID));
            VALUE child_media = rb_hash_aref(rule_to_media, child_id);  // Look up by rule ID

            DEBUG_PRINTF("[SERIALIZE]   Child %ld: child_media=%s, rule_media=%s\n", child_idx,
                        NIL_P(child_media) ? "nil" : RSTRING_PTR(rb_inspect(child_media)),
                        NIL_P(rule_media) ? "nil" : RSTRING_PTR(rb_inspect(rule_media)));

            // Only serialize selector-nested children here (not @media nested)
            if (NIL_P(child_media) || rb_equal(child_media, rule_media)) {
                DEBUG_PRINTF("[SERIALIZE]   -> Serializing as selector-nested child\n");
                VALUE child_selector = rb_struct_aref(child, INT2FIX(RULE_SELECTOR));
                VALUE child_nesting_style = rb_struct_aref(child, INT2FIX(RULE_NESTING_STYLE));

                // Unresolve selector
                VALUE nested_selector = unresolve_selector(parent_selector, child_selector, child_nesting_style);

                if (formatted) {
                    // Formatted: indent before nested selector
                    rb_str_append(result, indent_str);
                    rb_str_append(result, nested_selector);
                    rb_str_cat2(result, " {\n");

                    // Serialize child declarations (each on its own line)
                    VALUE child_declarations = rb_struct_aref(child, INT2FIX(RULE_DECLARATIONS));
                    if (!NIL_P(child_declarations) && RARRAY_LEN(child_declarations) > 0) {
                        // Build child indent (one level deeper than current)
                        VALUE child_indent = rb_str_new_cstr("");
                        for (int j = 0; j <= indent_level; j++) {
                            rb_str_cat2(child_indent, "  ");
                        }
                        const char *child_indent_ptr = RSTRING_PTR(child_indent);
                        serialize_declarations_formatted(result, child_declarations, child_indent_ptr);
                        RB_GC_GUARD(child_indent);
                    }

                    // Recursively serialize grandchildren
                    serialize_children_only(result, rules_array, child_idx, rule_to_media, parent_to_children,
                                          child_selector, child_declarations, formatted, indent_level + 1);

                    // Closing brace with indentation and newline
                    rb_str_append(result, indent_str);
                    rb_str_cat2(result, "}\n");
                } else {
                    // Compact: space before nested selector only if parent has declarations
                    if (parent_has_declarations) {
                        rb_str_cat2(result, " ");
                    }
                    rb_str_append(result, nested_selector);
                    rb_str_cat2(result, " { ");

                    // Serialize child declarations
                    VALUE child_declarations = rb_struct_aref(child, INT2FIX(RULE_DECLARATIONS));
                    serialize_declarations(result, child_declarations);

                    // Recursively serialize grandchildren
                    serialize_children_only(result, rules_array, child_idx, rule_to_media, parent_to_children,
                                          child_selector, child_declarations, formatted, indent_level);

                    rb_str_cat2(result, " }");
                }
            }
        }

        // Serialize nested @media children (different media than parent)
        for (long i = 0; i < num_children; i++) {
            long child_idx = FIX2LONG(rb_ary_entry(children_indices, i));
            VALUE child = rb_ary_entry(rules_array, child_idx);
            VALUE child_id = rb_struct_aref(child, INT2FIX(RULE_ID));
            VALUE child_media = rb_hash_aref(rule_to_media, child_id);  // Look up by rule ID

            // Check if this is a different media than parent
            if (!NIL_P(child_media) && !rb_equal(rule_media, child_media)) {
                // Nested @media!
                if (formatted) {
                    rb_str_append(result, indent_str);
                    rb_str_cat2(result, "@media ");
                    append_media_query_text(result, child_media);
                    rb_str_cat2(result, " {\n");

                    VALUE child_declarations = rb_struct_aref(child, INT2FIX(RULE_DECLARATIONS));
                    if (!NIL_P(child_declarations) && RARRAY_LEN(child_declarations) > 0) {
                        // Build child indent (one level deeper than current)
                        VALUE child_indent = rb_str_new_cstr("");
                        for (int j = 0; j <= indent_level; j++) {
                            rb_str_cat2(child_indent, "  ");
                        }
                        const char *child_indent_ptr = RSTRING_PTR(child_indent);
                        serialize_declarations_formatted(result, child_declarations, child_indent_ptr);
                        RB_GC_GUARD(child_indent);
                    }

                    rb_str_append(result, indent_str);
                    rb_str_cat2(result, "}\n");
                } else {
                    rb_str_cat2(result, " @media ");
                    append_media_query_text(result, child_media);
                    rb_str_cat2(result, " { ");

                    VALUE child_declarations = rb_struct_aref(child, INT2FIX(RULE_DECLARATIONS));
                    serialize_declarations(result, child_declarations);

                    rb_str_cat2(result, " }");
                }
            }
        }
    }
}

// Recursive serializer for a rule and its nested children
static void serialize_rule_with_children(VALUE result, VALUE rules_array, long rule_idx,
                                         VALUE rule_to_media, VALUE parent_to_children,
                                         int formatted, int indent_level) {
    VALUE rule = rb_ary_entry(rules_array, rule_idx);
    VALUE selector = rb_struct_aref(rule, INT2FIX(RULE_SELECTOR));
    VALUE declarations = rb_struct_aref(rule, INT2FIX(RULE_DECLARATIONS));

    DEBUG_PRINTF("[SERIALIZE] Rule %ld: selector=%s\n", rule_idx, RSTRING_PTR(selector));

    if (formatted) {
        // Formatted output with indentation
        DEBUG_PRINTF("[SERIALIZE_RULE] Formatted mode, indent_level=%d, selector=%s\n", indent_level, RSTRING_PTR(selector));
        rb_str_append(result, selector);
        rb_str_cat2(result, " {\n");

        // Build indent strings based on indent_level
        // Declarations are inside the rule, so add 1 level (2 spaces per level)
        // Closing brace matches the opening selector level
        char decl_indent[MAX_INDENT_BUFFER];
        char closing_indent[MAX_INDENT_BUFFER];
        int decl_spaces = (indent_level + 1) * 2;
        int closing_spaces = indent_level * 2;
        memset(decl_indent, ' ', decl_spaces);
        decl_indent[decl_spaces] = '\0';
        memset(closing_indent, ' ', closing_spaces);
        closing_indent[closing_spaces] = '\0';

        // Serialize own declarations with indentation (each on its own line)
        if (!NIL_P(declarations) && RARRAY_LEN(declarations) > 0) {
            DEBUG_PRINTF("[SERIALIZE_RULE] Serializing %ld declarations with indent='%s' (%d spaces)\n",
                        RARRAY_LEN(declarations), decl_indent, decl_spaces);
            serialize_declarations_formatted(result, declarations, decl_indent);
        }

        // Serialize nested children
        serialize_children_only(result, rules_array, rule_idx, rule_to_media, parent_to_children,
                              selector, declarations, formatted, indent_level + 1);

        rb_str_cat2(result, closing_indent);
        rb_str_cat2(result, "}\n");
    } else {
        // Compact output
        rb_str_append(result, selector);
        rb_str_cat2(result, " { ");

        // Serialize own declarations
        serialize_declarations(result, declarations);

        // Serialize nested children
        serialize_children_only(result, rules_array, rule_idx, rule_to_media, parent_to_children,
                              selector, declarations, formatted, indent_level);

        rb_str_cat2(result, " }\n");
    }

    // Prevent compiler from optimizing away 'rule' before we're done with selector/declarations
    RB_GC_GUARD(rule);
}

// New stylesheet serialization entry point - checks for nesting and delegates
static VALUE stylesheet_to_s_new(VALUE self, VALUE rules_array, VALUE media_index, VALUE charset, VALUE has_nesting, VALUE selector_lists, VALUE media_queries, VALUE media_query_lists) {
    DEBUG_PRINTF("[STYLESHEET_TO_S] Called with:\n");
    DEBUG_PRINTF("  rules_array length: %ld\n", RARRAY_LEN(rules_array));
    DEBUG_PRINTF("  media_queries type: %s, length: %ld\n",
                rb_obj_classname(media_queries),
                TYPE(media_queries) == T_ARRAY ? RARRAY_LEN(media_queries) : -1);
    DEBUG_PRINTF("  media_queries inspect: %s\n", RSTRING_PTR(rb_inspect(media_queries)));
    DEBUG_PRINTF("  media_query_lists class: %s\n", rb_obj_classname(media_query_lists));
    DEBUG_PRINTF("  selector_lists class: %s\n", rb_obj_classname(selector_lists));

    DEBUG_PRINTF("[STYLESHEET_TO_S] About to Check_Type\n");
    Check_Type(rules_array, T_ARRAY);
    Check_Type(media_index, T_HASH);
    DEBUG_PRINTF("[STYLESHEET_TO_S] Check_Type passed\n");
    // TODO: Phase 2 - use selector_lists for grouping
    (void)selector_lists; // Suppress unused parameter warning

    // Fast path: if no nesting, use original implementation (zero overhead)
    if (!RTEST(has_nesting)) {
        DEBUG_PRINTF("[STYLESHEET_TO_S] Taking fast path (no nesting)\n");
        return stylesheet_to_s_original(rules_array, media_queries, media_query_lists, charset, selector_lists);
    }

    DEBUG_PRINTF("[STYLESHEET_TO_S] Taking slow path (has nesting)\n");
    // SLOW PATH: Has nesting - use lookahead approach
    long total_rules = RARRAY_LEN(rules_array);
    VALUE result = rb_str_new_cstr("");

    // Add charset if present
    if (!NIL_P(charset)) {
        rb_str_cat2(result, "@charset \"");
        rb_str_append(result, charset);
        rb_str_cat2(result, "\";\n");
    }

    // Build rule_to_media map from media_query_id fields
    // Map: rule_id => MediaQuery object (we'll call .text method for serialization)
    VALUE rule_to_media = rb_hash_new();
    DEBUG_PRINTF("[BUILD_MAP] media_queries array length: %ld\n", RARRAY_LEN(media_queries));
    for (long i = 0; i < total_rules; i++) {
        VALUE rule = rb_ary_entry(rules_array, i);
        // Only process Rule objects, not AtRules (AtRule has 5 fields, can't access RULE_MEDIA_QUERY_ID at index 7)
        if (!rb_obj_is_kind_of(rule, cAtRule)) {
            VALUE media_query_id = rb_struct_aref(rule, INT2FIX(RULE_MEDIA_QUERY_ID));
            if (!NIL_P(media_query_id)) {
                VALUE rule_id = rb_struct_aref(rule, INT2FIX(RULE_ID));
                // Get MediaQuery object from media_queries array
                int mq_id = FIX2INT(media_query_id);
                DEBUG_PRINTF("[BUILD_MAP] Rule %ld (id=%ld) has media_query_id=%d\n", i, FIX2LONG(rule_id), mq_id);
                VALUE media_query = rb_ary_entry(media_queries, mq_id);
                DEBUG_PRINTF("[BUILD_MAP]   media_query from array: %s (class: %s)\n",
                            RSTRING_PTR(rb_inspect(media_query)),
                            rb_obj_classname(media_query));
                if (!NIL_P(media_query)) {
                    // Store the MediaQuery object itself
                    rb_hash_aset(rule_to_media, rule_id, media_query);
                    DEBUG_PRINTF("[BUILD_MAP]   Stored in map: rule_id=%ld => %s\n",
                                FIX2LONG(rule_id), RSTRING_PTR(rb_inspect(media_query)));
                }
            }
        }
    }

    DEBUG_PRINTF("[STYLESHEET_TO_S] Built rule_to_media map, now building parent_to_children\n");
    // Build parent_to_children map (parent_rule_id -> array of child indices)
    // This allows O(1) lookup of children when serializing each parent
    VALUE parent_to_children = rb_hash_new();
    for (long i = 0; i < total_rules; i++) {
        VALUE rule = rb_ary_entry(rules_array, i);
        VALUE parent_id = rb_struct_aref(rule, INT2FIX(RULE_PARENT_RULE_ID));

        if (!NIL_P(parent_id)) {
            DEBUG_PRINTF("[MAP] Rule %ld has parent_id=%s, adding to map\n", i,
                        RSTRING_PTR(rb_inspect(parent_id)));

            VALUE children = rb_hash_aref(parent_to_children, parent_id);
            if (NIL_P(children)) {
                children = rb_ary_new();
                rb_hash_aset(parent_to_children, parent_id, children);
            }
            rb_ary_push(children, LONG2FIX(i));
        }
    }

    DEBUG_PRINTF("[MAP] parent_to_children map: %s\n", RSTRING_PTR(rb_inspect(parent_to_children)));

    // Track media block state for proper opening/closing
    VALUE current_media = Qnil;
    int in_media_block = 0;

    // Serialize only top-level rules (parent_rule_id == nil)
    // Children are serialized recursively
    DEBUG_PRINTF("[SERIALIZE] Starting serialization, total_rules=%ld\n", total_rules);
    for (long i = 0; i < total_rules; i++) {
        VALUE rule = rb_ary_entry(rules_array, i);
        VALUE parent_id = rb_struct_aref(rule, INT2FIX(RULE_PARENT_RULE_ID));

        DEBUG_PRINTF("[SERIALIZE] Rule %ld: selector=%s, parent_id=%s\n", i,
                    RSTRING_PTR(rb_struct_aref(rule, INT2FIX(RULE_SELECTOR))),
                    NIL_P(parent_id) ? "nil" : RSTRING_PTR(rb_inspect(parent_id)));

        // Skip child rules - they're serialized when we hit their parent
        if (!NIL_P(parent_id)) {
            DEBUG_PRINTF("[SERIALIZE]   Skipping (is child)\n");
            continue;
        }

        // Get media for this rule
        VALUE rule_id = rb_struct_aref(rule, INT2FIX(RULE_ID));
        VALUE rule_media = rb_hash_aref(rule_to_media, rule_id);
        DEBUG_PRINTF("[SERIALIZE]   rule_id=%ld, rule_media=%s (class: %s)\n",
                    FIX2LONG(rule_id),
                    RSTRING_PTR(rb_inspect(rule_media)),
                    NIL_P(rule_media) ? "NilClass" : rb_obj_classname(rule_media));

        // Handle media block transitions
        if (NIL_P(rule_media)) {
            // Not in media - close any open media block
            if (in_media_block) {
                rb_str_cat2(result, "}\n");
                in_media_block = 0;
                current_media = Qnil;
            }
        } else {
            // In media - check if we need to open/change block
            if (NIL_P(current_media) || !rb_equal(current_media, rule_media)) {
                // Close previous media block if open
                if (in_media_block) {
                    rb_str_cat2(result, "}\n");
                }
                // Open new media block
                current_media = rule_media;
                rb_str_cat2(result, "@media ");
                append_media_query_text(result, rule_media);
                rb_str_cat2(result, " {\n");
                in_media_block = 1;
            }
        }

        // Check if this is an AtRule
        if (rb_obj_is_kind_of(rule, cAtRule)) {
            serialize_at_rule(result, rule);
            continue;
        }

        // Serialize rule with nested children
        serialize_rule_with_children(
            result, rules_array, i, rule_to_media, parent_to_children,
            0,  // formatted (compact)
            0   // indent_level (top-level)
        );
    }

    // Close final media block if still open
    if (in_media_block) {
        rb_str_cat2(result, "}\n");
    }

    RB_GC_GUARD(rule_to_media);
    RB_GC_GUARD(parent_to_children);
    return result;
}

// Original formatted serialization (no nesting support)
static VALUE stylesheet_to_formatted_s_original(VALUE rules_array, VALUE media_queries, VALUE media_query_lists, VALUE charset, VALUE selector_lists) {
    Check_Type(rules_array, T_ARRAY);
    Check_Type(media_queries, T_ARRAY);

    VALUE result = rb_str_new_cstr("");

    // Add charset if present
    if (!NIL_P(charset)) {
        rb_str_cat2(result, "@charset \"");
        rb_str_append(result, charset);
        rb_str_cat2(result, "\";\n");
    }

    // Formatted output options
    struct format_opts opts = {
        .opening_brace = " {\n",
        .closing_brace = "}\n",
        .media_indent = "  ",
        .decl_indent_base = "  ",
        .decl_indent_media = "    ",
        .add_blank_lines = 1
    };

    return serialize_stylesheet_with_grouping(rules_array, media_queries, media_query_lists, result, selector_lists, &opts);
}

// Formatted version with indentation and newlines (with nesting support)
static VALUE stylesheet_to_formatted_s_new(VALUE self, VALUE rules_array, VALUE media_index, VALUE charset, VALUE has_nesting, VALUE selector_lists, VALUE media_queries, VALUE media_query_lists) {
    Check_Type(rules_array, T_ARRAY);
    Check_Type(media_index, T_HASH);

    // Fast path: if no nesting, use original implementation (zero overhead)
    if (!RTEST(has_nesting)) {
        return stylesheet_to_formatted_s_original(rules_array, media_queries, media_query_lists, charset, selector_lists);
    }

    // SLOW PATH: Has nesting - use parameterized serialization with formatted=1
    long total_rules = RARRAY_LEN(rules_array);
    VALUE result = rb_str_new_cstr("");

    // Add charset if present
    if (!NIL_P(charset)) {
        rb_str_cat2(result, "@charset \"");
        rb_str_append(result, charset);
        rb_str_cat2(result, "\";\n");
    }

    // Build rule_to_media map from media_query_id fields
    VALUE rule_to_media = rb_hash_new();
    for (long i = 0; i < total_rules; i++) {
        VALUE rule = rb_ary_entry(rules_array, i);
        // Only process Rule objects, not AtRules (AtRule has 5 fields, can't access RULE_MEDIA_QUERY_ID at index 7)
        if (!rb_obj_is_kind_of(rule, cAtRule)) {
            VALUE media_query_id = rb_struct_aref(rule, INT2FIX(RULE_MEDIA_QUERY_ID));
            if (!NIL_P(media_query_id)) {
                VALUE rule_id = rb_struct_aref(rule, INT2FIX(RULE_ID));
                int mq_id = FIX2INT(media_query_id);
                VALUE media_query = rb_ary_entry(media_queries, mq_id);
                if (!NIL_P(media_query)) {
                    rb_hash_aset(rule_to_media, rule_id, media_query);
                }
            }
        }
    }

    // Build parent_to_children map (parent_rule_id -> array of child indices)
    VALUE parent_to_children = rb_hash_new();
    for (long i = 0; i < total_rules; i++) {
        VALUE rule = rb_ary_entry(rules_array, i);
        VALUE parent_id = rb_struct_aref(rule, INT2FIX(RULE_PARENT_RULE_ID));

        if (!NIL_P(parent_id)) {
            VALUE children = rb_hash_aref(parent_to_children, parent_id);
            if (NIL_P(children)) {
                children = rb_ary_new();
                rb_hash_aset(parent_to_children, parent_id, children);
            }
            rb_ary_push(children, LONG2FIX(i));
        }
    }

    // Track media block state for proper opening/closing
    VALUE current_media = Qnil;
    int in_media_block = 0;

    // Serialize only top-level rules (parent_rule_id == nil)
    for (long i = 0; i < total_rules; i++) {
        VALUE rule = rb_ary_entry(rules_array, i);
        VALUE parent_id = rb_struct_aref(rule, INT2FIX(RULE_PARENT_RULE_ID));

        // Skip child rules - they're serialized when we hit their parent
        if (!NIL_P(parent_id)) {
            continue;
        }

        // Get media for this rule
        VALUE rule_id = rb_struct_aref(rule, INT2FIX(RULE_ID));
        VALUE rule_media = rb_hash_aref(rule_to_media, rule_id);

        // Handle media block transitions
        if (NIL_P(rule_media)) {
            // Not in media - close any open media block
            if (in_media_block) {
                rb_str_cat2(result, "}\n");
                in_media_block = 0;
                current_media = Qnil;

                // Add blank line after closing media block
                rb_str_cat2(result, "\n");
            }
        } else {
            // In media - check if we need to open/change block
            if (NIL_P(current_media) || !rb_equal(current_media, rule_media)) {
                // Close previous media block if open
                if (in_media_block) {
                    rb_str_cat2(result, "}\n");
                } else if (RSTRING_LEN(result) > 0) {
                    // Add blank line before new media block (except at start)
                    rb_str_cat2(result, "\n");
                }
                // Open new media block
                current_media = rule_media;
                rb_str_cat2(result, "@media ");
                append_media_query_text(result, rule_media);
                rb_str_cat2(result, " {\n");
                in_media_block = 1;
            }
        }

        // Check if this is an AtRule
        if (rb_obj_is_kind_of(rule, cAtRule)) {
            serialize_at_rule(result, rule);
            continue;
        }

        // Add indent if inside media block
        if (in_media_block) {
            DEBUG_PRINTF("[FORMATTED] Adding base indent for media block\n");
            rb_str_cat2(result, "  ");
        }

        // Serialize rule with nested children
        DEBUG_PRINTF("[FORMATTED] Calling serialize_rule_with_children, in_media_block=%d\n", in_media_block);
        serialize_rule_with_children(
            result, rules_array, i, rule_to_media, parent_to_children,
            1,  // formatted (with indentation)
            in_media_block ? 1 : 0   // indent_level (1 if inside media block, 0 otherwise)
        );
    }

    // Close final media block if still open
    if (in_media_block) {
        rb_str_cat2(result, "}\n");
    }

    RB_GC_GUARD(rule_to_media);
    RB_GC_GUARD(parent_to_children);
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

    // Note: Comments in declarations aren't stripped (copy_without_comments is in css_parser.c)
    // The parser is error-tolerant, so it just continues parsing as-is.

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

void Init_native_extension(void) {
    // Get Cataract module (should be defined by main extension)
    VALUE mCataract = rb_define_module("Cataract");

    // Define error classes (reuse from main extension if possible)
    if (rb_const_defined(mCataract, rb_intern("Error"))) {
        eCataractError = rb_const_get(mCataract, rb_intern("Error"));
    } else {
        eCataractError = rb_define_class_under(mCataract, "Error", rb_eStandardError);
    }

    if (rb_const_defined(mCataract, rb_intern("DepthError"))) {
        eDepthError = rb_const_get(mCataract, rb_intern("DepthError"));
    } else {
        eDepthError = rb_define_class_under(mCataract, "DepthError", eCataractError);
    }

    if (rb_const_defined(mCataract, rb_intern("SizeError"))) {
        eSizeError = rb_const_get(mCataract, rb_intern("SizeError"));
    } else {
        eSizeError = rb_define_class_under(mCataract, "SizeError", eCataractError);
    }

    // Reuse Ruby-defined structs (they must be defined before loading this extension)
    // If they don't exist, someone required the extension directly instead of via lib/cataract.rb
    if (rb_const_defined(mCataract, rb_intern("Rule"))) {
        cRule = rb_const_get(mCataract, rb_intern("Rule"));
    } else {
        rb_raise(rb_eLoadError, "Cataract::Rule not defined. Do not require 'cataract/native_extension' directly, use require 'cataract'");
    }

    if (rb_const_defined(mCataract, rb_intern("Declaration"))) {
        cDeclaration = rb_const_get(mCataract, rb_intern("Declaration"));
    } else {
        rb_raise(rb_eLoadError, "Cataract::Declaration not defined. Do not require 'cataract/native_extension' directly, use require 'cataract'");
    }

    if (rb_const_defined(mCataract, rb_intern("AtRule"))) {
        cAtRule = rb_const_get(mCataract, rb_intern("AtRule"));
    } else {
        rb_raise(rb_eLoadError, "Cataract::AtRule not defined. Do not require 'cataract/native_extension' directly, use require 'cataract'");
    }

    if (rb_const_defined(mCataract, rb_intern("ImportStatement"))) {
        cImportStatement = rb_const_get(mCataract, rb_intern("ImportStatement"));
    } else {
        rb_raise(rb_eLoadError, "Cataract::ImportStatement not defined. Do not require 'cataract/native_extension' directly, use require 'cataract'");
    }

    if (rb_const_defined(mCataract, rb_intern("MediaQuery"))) {
        cMediaQuery = rb_const_get(mCataract, rb_intern("MediaQuery"));
    } else {
        rb_raise(rb_eLoadError, "Cataract::MediaQuery not defined. Do not require 'cataract/native_extension' directly, use require 'cataract'");
    }

    // Define Declarations class and add to_s method
    VALUE cDeclarations = rb_define_class_under(mCataract, "Declarations", rb_cObject);
    rb_define_method(cDeclarations, "to_s", new_declarations_to_s_method, 0);

    // Define Stylesheet class (Ruby will add instance methods like each_selector)
    cStylesheet = rb_define_class_under(mCataract, "Stylesheet", rb_cObject);

    // Define module functions
    rb_define_module_function(mCataract, "_parse_css", parse_css_new, -1);
    rb_define_module_function(mCataract, "_stylesheet_to_s", stylesheet_to_s_new, 7);
    rb_define_module_function(mCataract, "_stylesheet_to_formatted_s", stylesheet_to_formatted_s_new, 7);
    rb_define_module_function(mCataract, "parse_media_types", parse_media_types, 1);
    rb_define_module_function(mCataract, "parse_declarations", new_parse_declarations, 1);
    rb_define_module_function(mCataract, "flatten", cataract_flatten, 1);
    rb_define_module_function(mCataract, "merge", cataract_flatten, 1); // Deprecated alias for backwards compatibility
    rb_define_module_function(mCataract, "calculate_specificity", calculate_specificity, 1);
    rb_define_module_function(mCataract, "_expand_shorthand", cataract_expand_shorthand, 1);

    // Initialize flatten constants (cached property strings)
    init_flatten_constants();

    // Export compile-time flags as a hash for runtime introspection
    VALUE compile_flags = rb_hash_new();

    #ifdef CATARACT_DEBUG
        rb_hash_aset(compile_flags, ID2SYM(rb_intern("debug")), Qtrue);
    #else
        rb_hash_aset(compile_flags, ID2SYM(rb_intern("debug")), Qfalse);
    #endif

    #ifdef DISABLE_STR_BUF_OPTIMIZATION
        rb_hash_aset(compile_flags, ID2SYM(rb_intern("str_buf_optimization")), Qfalse);
    #else
        rb_hash_aset(compile_flags, ID2SYM(rb_intern("str_buf_optimization")), Qtrue);
    #endif

    rb_define_const(mCataract, "COMPILE_FLAGS", compile_flags);

    // Flag to indicate native extension is loaded (for pure Ruby fallback detection)
    rb_define_const(mCataract, "NATIVE_EXTENSION_LOADED", Qtrue);

    // Implementation type constant
    rb_define_const(mCataract, "IMPLEMENTATION", ID2SYM(rb_intern("native")));
}
