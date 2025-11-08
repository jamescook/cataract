/*
 * css_parser_new.c - New CSS parser implementation with flat rule array
 *
 * Key differences from original:
 * - Flat @rules array with rule IDs (0-indexed)
 * - Separate @media_index hash mapping media queries to rule ID arrays
 * - Handles nested @media queries by combining conditions
 */

#include "cataract.h"
#include <string.h>

// Parser context passed through recursive calls
typedef struct {
    VALUE rules_array;        // Array of Rule structs
    VALUE media_index;        // Hash: Symbol => Array of rule IDs
    int rule_id_counter;      // Next rule ID (0-indexed)
    int media_query_count;    // Safety limit for media queries
    st_table *media_cache;    // Parse-time cache: string => parsed media types
} ParserContext;

// Lowercase property name (CSS property names are ASCII-only)
// Non-static so merge_new.c can use it
VALUE lowercase_property(VALUE property_str) {
    Check_Type(property_str, T_STRING);

    long len = RSTRING_LEN(property_str);
    const char *src = RSTRING_PTR(property_str);

    VALUE result = rb_str_buf_new(len);
    rb_enc_associate(result, rb_usascii_encoding());

    for (long i = 0; i < len; i++) {
        char c = src[i];
        if (c >= 'A' && c <= 'Z') {
            c += 32;  // Lowercase
        }
        rb_str_buf_cat(result, &c, 1);
    }

    return result;
}

/*
 * Extract media types from a media query string
 * Examples:
 *   "screen" => [:screen]
 *   "screen, print" => [:screen, :print]
 *   "screen and (min-width: 768px)" => [:screen]
 *   "(min-width: 768px)" => []  // No media type, just condition
 *
 * Returns: Ruby array of symbols
 */
static VALUE extract_media_types(const char *query, long query_len) {
    VALUE types = rb_ary_new();

    const char *p = query;
    const char *end = query + query_len;

    while (p < end) {
        // Skip whitespace
        while (p < end && IS_WHITESPACE(*p)) p++;
        if (p >= end) break;

        // Check for opening paren (skip conditions like "(min-width: 768px)")
        if (*p == '(') {
            // Skip to matching closing paren
            int depth = 1;
            p++;
            while (p < end && depth > 0) {
                if (*p == '(') depth++;
                else if (*p == ')') depth--;
                p++;
            }
            continue;
        }

        // Find end of word (media type or keyword)
        const char *word_start = p;
        while (p < end && !IS_WHITESPACE(*p) && *p != ',' && *p != '(') {
            p++;
        }

        if (p > word_start) {
            long word_len = p - word_start;

            // Check if it's a keyword (and, or, not, only)
            int is_keyword = (word_len == 3 && strncmp(word_start, "and", 3) == 0) ||
                           (word_len == 2 && strncmp(word_start, "or", 2) == 0) ||
                           (word_len == 3 && strncmp(word_start, "not", 3) == 0) ||
                           (word_len == 4 && strncmp(word_start, "only", 4) == 0);

            if (!is_keyword) {
                // This is a media type - add it as symbol
                VALUE type_sym = ID2SYM(rb_intern2(word_start, word_len));
                rb_ary_push(types, type_sym);
            }
        }

        // Skip to comma or end
        while (p < end && *p != ',') {
            if (*p == '(') {
                // Skip condition
                int depth = 1;
                p++;
                while (p < end && depth > 0) {
                    if (*p == '(') depth++;
                    else if (*p == ')') depth--;
                    p++;
                }
            } else {
                p++;
            }
        }

        if (p < end && *p == ',') p++;  // Skip comma
    }

    return types;
}

/*
 * Add rule ID to media index for a given media query symbol
 * Creates array if it doesn't exist yet
 */
static void add_to_media_index(VALUE media_index, VALUE media_sym, int rule_id) {
    VALUE rule_ids = rb_hash_aref(media_index, media_sym);

    if (NIL_P(rule_ids)) {
        rule_ids = rb_ary_new();
        rb_hash_aset(media_index, media_sym, rule_ids);
    }

    rb_ary_push(rule_ids, INT2FIX(rule_id));
}

/*
 * Update media index with rule ID for given media query
 * Extracts media types and adds rule to each type's array
 * Also adds to the full query symbol
 */
static void update_media_index(ParserContext *ctx, VALUE media_sym, int rule_id) {
    if (NIL_P(media_sym)) {
        return;  // No media query - rule applies to all media
    }

    // Add to full query symbol
    add_to_media_index(ctx->media_index, media_sym, rule_id);

    // Extract media types and add to each (if different from full query)
    VALUE media_str = rb_sym2str(media_sym);
    const char *query = RSTRING_PTR(media_str);
    long query_len = RSTRING_LEN(media_str);

    VALUE media_types = extract_media_types(query, query_len);
    long types_len = RARRAY_LEN(media_types);

    for (long i = 0; i < types_len; i++) {
        VALUE type_sym = rb_ary_entry(media_types, i);
        // Only add if different from full query (avoid duplicates)
        if (type_sym != media_sym) {
            add_to_media_index(ctx->media_index, type_sym, rule_id);
        }
    }
}

/*
 * Parse declaration block into array of Declaration structs
 * Input: "color: red; background: blue !important"
 * Output: [Declaration(...), Declaration(...)]
 */
static VALUE parse_declarations(const char *start, const char *end) {
    VALUE declarations = rb_ary_new();

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
                }
            }
        }

        // Final trim
        trim_trailing(val_start, &val_end);

        // Skip if value is empty
        if (val_end > val_start) {
            // Create property string and lowercase it
            VALUE property_raw = rb_usascii_str_new(prop_start, prop_end - prop_start);
            VALUE property = lowercase_property(property_raw);
            VALUE value = rb_utf8_str_new(val_start, val_end - val_start);

            // Create Declaration struct
            VALUE decl = rb_struct_new(cDeclaration,
                property,
                value,
                is_important ? Qtrue : Qfalse
            );

            rb_ary_push(declarations, decl);
        }

        if (pos < end && *pos == ';') pos++;  // Skip semicolon if present
    }

    return declarations;
}

// Forward declarations
static void parse_css_recursive(ParserContext *ctx, const char *css, const char *pe, VALUE parent_media_sym);
static VALUE combine_media_queries(VALUE parent, VALUE child);

/*
 * Combine parent and child media queries
 * Examples:
 *   parent="screen", child="(min-width: 500px)" => "screen and (min-width: 500px)"
 *   parent=nil, child="print" => "print"
 */
static VALUE combine_media_queries(VALUE parent, VALUE child) {
    if (NIL_P(parent)) {
        return child;
    }
    if (NIL_P(child)) {
        return parent;
    }

    // Combine: "parent and child"
    VALUE parent_str = rb_sym2str(parent);
    VALUE child_str = rb_sym2str(child);

    VALUE combined = rb_str_dup(parent_str);
    rb_str_cat2(combined, " and ");
    rb_str_append(combined, child_str);

    return ID2SYM(rb_intern_str(combined));
}

/*
 * Intern media query string to symbol with safety check
 */
static VALUE intern_media_query_safe(ParserContext *ctx, const char *query_str, long query_len) {
    if (query_len == 0) {
        return Qnil;
    }

    // Safety check
    if (ctx->media_query_count >= MAX_MEDIA_QUERIES) {
        rb_raise(eSizeError,
                "Exceeded maximum unique media queries (%d)",
                MAX_MEDIA_QUERIES);
    }

    VALUE query_string = rb_usascii_str_new(query_str, query_len);
    VALUE sym = ID2SYM(rb_intern_str(query_string));
    ctx->media_query_count++;

    return sym;
}

/*
 * Parse CSS recursively with media query context
 */
static void parse_css_recursive(ParserContext *ctx, const char *css, const char *pe, VALUE parent_media_sym) {
    const char *p = css;

    const char *selector_start = NULL;
    const char *decl_start = NULL;
    int brace_depth = 0;

    while (p < pe) {
        // Skip whitespace
        while (p < pe && IS_WHITESPACE(*p)) p++;
        if (p >= pe) break;

        // Skip comments (rare in typical CSS)
        if (RB_UNLIKELY(p + 1 < pe && *p == '/' && *(p + 1) == '*')) {
            p += 2;
            while (p + 1 < pe && !(*p == '*' && *(p + 1) == '/')) {
                p++;
            }
            if (p + 1 < pe) p += 2;
            continue;
        }

        // Check for @media at-rule (only at depth 0)
        if (RB_UNLIKELY(brace_depth == 0 && p + 6 < pe && *p == '@' &&
            strncmp(p + 1, "media", 5) == 0 && IS_WHITESPACE(p[6]))) {
            p += 6;  // Skip "@media"

            // Skip whitespace
            while (p < pe && IS_WHITESPACE(*p)) p++;

            // Find media query (up to opening brace)
            const char *mq_start = p;
            while (p < pe && *p != '{') p++;
            const char *mq_end = p;

            // Trim
            trim_trailing(mq_start, &mq_end);

            if (p >= pe || *p != '{') {
                continue;  // Malformed
            }

            // Intern media query
            VALUE child_media_sym = intern_media_query_safe(ctx, mq_start, mq_end - mq_start);

            // Combine with parent
            VALUE combined_media_sym = combine_media_queries(parent_media_sym, child_media_sym);

            p++;  // Skip opening {

            // Find matching closing brace
            const char *block_start = p;
            int depth = 1;
            while (p < pe && depth > 0) {
                if (*p == '{') depth++;
                else if (*p == '}') depth--;
                if (depth > 0) p++;
            }
            const char *block_end = p;

            // Recursively parse @media block with combined media context
            parse_css_recursive(ctx, block_start, block_end, combined_media_sym);

            if (p < pe && *p == '}') p++;
            continue;
        }

        // Check for conditional group at-rules: @supports, @layer, @container, @scope
        // AND nested block at-rules: @keyframes, @font-face, @page
        // These behave like @media but don't affect media context
        if (RB_UNLIKELY(brace_depth == 0 && *p == '@')) {
            const char *at_start = p + 1;
            const char *at_name_end = at_start;

            // Find end of at-rule name (stop at whitespace or opening brace)
            while (at_name_end < pe && !IS_WHITESPACE(*at_name_end) && *at_name_end != '{') {
                at_name_end++;
            }

            long at_name_len = at_name_end - at_start;

            // Check if this is a conditional group rule
            int is_conditional_group =
                (at_name_len == 8 && strncmp(at_start, "supports", 8) == 0) ||
                (at_name_len == 5 && strncmp(at_start, "layer", 5) == 0) ||
                (at_name_len == 9 && strncmp(at_start, "container", 9) == 0) ||
                (at_name_len == 5 && strncmp(at_start, "scope", 5) == 0);

            if (is_conditional_group) {
                // Skip to opening brace
                p = at_name_end;
                while (p < pe && *p != '{') p++;

                if (p >= pe || *p != '{') {
                    continue;  // Malformed
                }

                p++;  // Skip opening {

                // Find matching closing brace
                const char *block_start = p;
                int depth = 1;
                while (p < pe && depth > 0) {
                    if (*p == '{') depth++;
                    else if (*p == '}') depth--;
                    if (depth > 0) p++;
                }
                const char *block_end = p;

                // Recursively parse block content (preserve parent media context)
                parse_css_recursive(ctx, block_start, block_end, parent_media_sym);

                if (p < pe && *p == '}') p++;
                continue;
            }

            // Check for @keyframes (contains <rule-list>)
            // TODO: Test perf gains by using RB_UNLIKELY(is_keyframes) wrapper
            int is_keyframes =
                (at_name_len == 9 && strncmp(at_start, "keyframes", 9) == 0) ||
                (at_name_len == 17 && strncmp(at_start, "-webkit-keyframes", 17) == 0) ||
                (at_name_len == 13 && strncmp(at_start, "-moz-keyframes", 13) == 0);

            if (is_keyframes) {
                // Build full selector string: "@keyframes fade"
                const char *selector_start = p;  // Points to '@'
                p = at_name_end;
                while (p < pe && *p != '{') p++;

                if (p >= pe || *p != '{') {
                    continue;  // Malformed
                }

                const char *selector_end = p;
                while (selector_end > selector_start && IS_WHITESPACE(*(selector_end - 1))) {
                    selector_end--;
                }
                VALUE selector = rb_utf8_str_new(selector_start, selector_end - selector_start);

                p++;  // Skip opening {

                // Find matching closing brace
                const char *block_start = p;
                int depth = 1;
                while (p < pe && depth > 0) {
                    if (*p == '{') depth++;
                    else if (*p == '}') depth--;
                    if (depth > 0) p++;
                }
                const char *block_end = p;

                // Parse keyframe blocks as rules (from/to/0%/50% etc)
                ParserContext nested_ctx = {
                    .rules_array = rb_ary_new(),
                    .media_index = rb_hash_new(),
                    .rule_id_counter = 0,
                    .media_query_count = 0,
                    .media_cache = NULL
                };
                parse_css_recursive(&nested_ctx, block_start, block_end, Qnil);

                // Get rule ID and increment
                int rule_id = ctx->rule_id_counter++;

                // Create AtRule with nested rules
                VALUE at_rule = rb_struct_new(cAtRule,
                    INT2FIX(rule_id),
                    selector,
                    nested_ctx.rules_array,  // Array of Rule (keyframe blocks)
                    Qnil);

                // Add to rules array
                rb_ary_push(ctx->rules_array, at_rule);

                // Add to media index if in media query
                if (!NIL_P(parent_media_sym)) {
                    VALUE rule_ids = rb_hash_aref(ctx->media_index, parent_media_sym);
                    if (NIL_P(rule_ids)) {
                        rule_ids = rb_ary_new();
                        rb_hash_aset(ctx->media_index, parent_media_sym, rule_ids);
                    }
                    rb_ary_push(rule_ids, INT2FIX(rule_id));
                }

                if (p < pe && *p == '}') p++;
                continue;
            }

            // Check for @font-face (contains <declaration-list>)
            int is_font_face = (at_name_len == 9 && strncmp(at_start, "font-face", 9) == 0);

            if (is_font_face) {
                // Build selector string: "@font-face"
                const char *selector_start = p;  // Points to '@'
                p = at_name_end;
                while (p < pe && *p != '{') p++;

                if (p >= pe || *p != '{') {
                    continue;  // Malformed
                }

                const char *selector_end = p;
                while (selector_end > selector_start && IS_WHITESPACE(*(selector_end - 1))) {
                    selector_end--;
                }
                VALUE selector = rb_utf8_str_new(selector_start, selector_end - selector_start);

                p++;  // Skip opening {

                // Find matching closing brace
                const char *decl_start = p;
                int depth = 1;
                while (p < pe && depth > 0) {
                    if (*p == '{') depth++;
                    else if (*p == '}') depth--;
                    if (depth > 0) p++;
                }
                const char *decl_end = p;

                // Parse declarations
                VALUE declarations = parse_declarations(decl_start, decl_end);

                // Get rule ID and increment
                int rule_id = ctx->rule_id_counter++;

                // Create AtRule with declarations
                VALUE at_rule = rb_struct_new(cAtRule,
                    INT2FIX(rule_id),
                    selector,
                    declarations,  // Array of Declaration
                    Qnil);

                // Add to rules array
                rb_ary_push(ctx->rules_array, at_rule);

                // Add to media index if in media query
                if (!NIL_P(parent_media_sym)) {
                    VALUE rule_ids = rb_hash_aref(ctx->media_index, parent_media_sym);
                    if (NIL_P(rule_ids)) {
                        rule_ids = rb_ary_new();
                        rb_hash_aset(ctx->media_index, parent_media_sym, rule_ids);
                    }
                    rb_ary_push(rule_ids, INT2FIX(rule_id));
                }

                if (p < pe && *p == '}') p++;
                continue;
            }
        }

        // Opening brace
        if (*p == '{') {
            if (brace_depth == 0 && selector_start != NULL) {
                decl_start = p + 1;
            }
            brace_depth++;
            p++;
            continue;
        }

        // Closing brace
        if (*p == '}') {
            brace_depth--;
            if (brace_depth == 0 && selector_start != NULL && decl_start != NULL) {
                // Parse declarations
                VALUE declarations = parse_declarations(decl_start, p);

                // Get selector string
                const char *sel_end = decl_start - 1;
                while (sel_end > selector_start && IS_WHITESPACE(*(sel_end - 1))) {
                    sel_end--;
                }

                // Split on commas
                const char *seg_start = selector_start;
                const char *seg = selector_start;

                while (seg <= sel_end) {
                    if (seg == sel_end || *seg == ',') {
                        // Trim segment
                        while (seg_start < seg && IS_WHITESPACE(*seg_start)) {
                            seg_start++;
                        }

                        const char *seg_end_ptr = seg;
                        while (seg_end_ptr > seg_start && IS_WHITESPACE(*(seg_end_ptr - 1))) {
                            seg_end_ptr--;
                        }

                        if (seg_end_ptr > seg_start) {
                            VALUE selector = rb_utf8_str_new(seg_start, seg_end_ptr - seg_start);

                            // Get rule ID and increment
                            int rule_id = ctx->rule_id_counter++;

                            // Create Rule (id, selector, declarations, specificity)
                            VALUE rule = rb_struct_new(cRule,
                                INT2FIX(rule_id),
                                selector,
                                rb_ary_dup(declarations),
                                Qnil  // specificity
                            );

                            rb_ary_push(ctx->rules_array, rule);

                            // Update media index
                            update_media_index(ctx, parent_media_sym, rule_id);
                        }

                        seg_start = seg + 1;
                    }
                    seg++;
                }

                selector_start = NULL;
                decl_start = NULL;
            }
            p++;
            continue;
        }

        // Start of selector
        if (brace_depth == 0 && selector_start == NULL) {
            selector_start = p;
        }

        p++;
    }
}

/*
 * Parse media query string and extract media types (Ruby-facing function)
 * Example: "screen, print" => [:screen, :print]
 * Example: "screen and (min-width: 768px)" => [:screen]
 *
 * @param media_query_sym [Symbol] Media query as symbol
 * @return [Array<Symbol>] Array of media type symbols
 */
VALUE parse_media_types(VALUE self, VALUE media_query_sym) {
    Check_Type(media_query_sym, T_SYMBOL);

    VALUE query_string = rb_sym2str(media_query_sym);
    const char *query_str = RSTRING_PTR(query_string);
    long query_len = RSTRING_LEN(query_string);

    return extract_media_types(query_str, query_len);
}

/*
 * Main parse entry point
 * Returns: { rules: [...], media_index: {...}, charset: "..." | nil, last_rule_id: N }
 */
VALUE parse_css_new_impl(VALUE css_string, int rule_id_offset) {
    Check_Type(css_string, T_STRING);

    const char *css = RSTRING_PTR(css_string);
    const char *pe = css + RSTRING_LEN(css_string);
    const char *p = css;

    VALUE charset = Qnil;

    // Extract @charset
    if (RSTRING_LEN(css_string) > 10 && strncmp(css, "@charset ", 9) == 0) {
        char *quote_start = strchr(css + 9, '"');
        if (quote_start != NULL) {
            char *quote_end = strchr(quote_start + 1, '"');
            if (quote_end != NULL) {
                charset = rb_str_new(quote_start + 1, quote_end - quote_start - 1);
                char *semicolon = quote_end + 1;
                while (semicolon < pe && IS_WHITESPACE(*semicolon)) {
                    semicolon++;
                }
                if (semicolon < pe && *semicolon == ';') {
                    p = semicolon + 1;
                }
            }
        }
    }

    // Skip @import statements - they should be handled by ImportResolver at Ruby level
    // Per CSS spec, @import must come before all rules (except @charset)
    while (p < pe) {
        // Skip whitespace
        while (p < pe && IS_WHITESPACE(*p)) p++;
        if (p >= pe) break;

        // Skip comments
        if (p + 1 < pe && p[0] == '/' && p[1] == '*') {
            p += 2;
            while (p + 1 < pe) {
                if (p[0] == '*' && p[1] == '/') {
                    p += 2;
                    break;
                }
                p++;
            }
            continue;
        }

        // Check for @import
        if (p + 7 <= pe && *p == '@' && strncasecmp(p + 1, "import", 6) == 0 &&
            (p + 7 >= pe || IS_WHITESPACE(p[7]) || p[7] == '\'' || p[7] == '"')) {
            // Skip to semicolon
            while (p < pe && *p != ';') p++;
            if (p < pe) p++; // Skip semicolon
            continue;
        }

        // Hit non-@import content, stop skipping
        break;
    }

    // Initialize parser context with offset
    ParserContext ctx;
    ctx.rules_array = rb_ary_new();
    ctx.media_index = rb_hash_new();
    ctx.rule_id_counter = rule_id_offset;  // Start from offset
    ctx.media_query_count = 0;
    ctx.media_cache = NULL;  // Removed - no perf benefit

    // Parse CSS
    parse_css_recursive(&ctx, p, pe, Qnil);

    // Build result hash
    VALUE result = rb_hash_new();
    rb_hash_aset(result, ID2SYM(rb_intern("rules")), ctx.rules_array);
    rb_hash_aset(result, ID2SYM(rb_intern("media_index")), ctx.media_index);
    rb_hash_aset(result, ID2SYM(rb_intern("charset")), charset);
    rb_hash_aset(result, ID2SYM(rb_intern("last_rule_id")), INT2FIX(ctx.rule_id_counter));

    return result;
}
