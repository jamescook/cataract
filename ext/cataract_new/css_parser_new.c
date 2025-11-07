/*
 * css_parser_new.c - New CSS parser implementation with flat rule array
 *
 * Key difference from original: stores media_query_sym directly on each rule
 * instead of grouping rules by media query.
 */

#include "cataract_new.h"
#include <string.h>

// Helper functions from cataract.h
static inline void trim_leading(const char **start, const char *end) {
    while (*start < end && IS_WHITESPACE(**start)) {
        (*start)++;
    }
}

static inline void trim_trailing(const char *start, const char **end) {
    while (*end > start && IS_WHITESPACE(*(*end - 1))) {
        (*end)--;
    }
}

// Lowercase property name (CSS property names are ASCII-only)
static inline VALUE lowercase_property(VALUE property_str) {
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
 * Parse declaration block into array of NewDeclaration structs
 * Input: "color: red; background: blue !important"
 * Output: [NewDeclaration(...), NewDeclaration(...)]
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

            // Create NewDeclaration struct
            VALUE decl = rb_struct_new(cNewDeclaration,
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

// Forward declaration for recursive parsing
static VALUE parse_css_with_media(const char *css, const char *pe, VALUE media_sym, int *media_count);

/*
 * Intern media query string to symbol with safety check
 */
static VALUE intern_media_query(const char *query_str, long query_len, int *media_count) {
    if (query_str == NULL || query_len == 0) {
        return Qnil;
    }

    // Safety check - prevent symbol table exhaustion
    if (*media_count >= MAX_MEDIA_QUERIES) {
        rb_raise(eSizeError,
                "Exceeded maximum unique media queries (%d). This prevents symbol table exhaustion.",
                MAX_MEDIA_QUERIES);
    }

    // Create string and intern to symbol (automatic deduplication)
    VALUE query_string = rb_utf8_str_new(query_str, query_len);
    VALUE sym = ID2SYM(rb_intern_str(query_string));

    (*media_count)++;

    return sym;
}

/*
 * Parse CSS string into flat array of NewRule structs
 * Returns: { rules: [NewRule, ...], charset: "..." | nil }
 */
VALUE parse_css_new_impl(VALUE css_string) {
    Check_Type(css_string, T_STRING);

    const char *css = RSTRING_PTR(css_string);
    const char *pe = css + RSTRING_LEN(css_string);
    const char *p = css;

    VALUE charset = Qnil;
    int media_count = 0;

    // Extract @charset if present at very start
    if (RSTRING_LEN(css_string) > 10 && strncmp(css, "@charset ", 9) == 0) {
        char *quote_start = strchr(css + 9, '"');
        if (quote_start != NULL) {
            char *quote_end = strchr(quote_start + 1, '"');
            if (quote_end != NULL) {
                charset = rb_str_new(quote_start + 1, quote_end - quote_start - 1);
                // Skip past the charset declaration
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

    // Parse CSS recursively (starting with no media query context)
    VALUE rules = parse_css_with_media(p, pe, Qnil, &media_count);

    // Build result hash
    VALUE result = rb_hash_new();
    rb_hash_aset(result, ID2SYM(rb_intern("rules")), rules);
    rb_hash_aset(result, ID2SYM(rb_intern("charset")), charset);

    return result;
}

/*
 * Parse CSS with optional media query context
 * This function handles both top-level CSS and @media block contents
 */
static VALUE parse_css_with_media(const char *css, const char *pe, VALUE media_sym, int *media_count) {
    VALUE rules = rb_ary_new();
    const char *p = css;

    const char *selector_start = NULL;
    const char *decl_start = NULL;
    int brace_depth = 0;

    while (p < pe) {
        // Skip whitespace
        while (p < pe && IS_WHITESPACE(*p)) p++;
        if (p >= pe) break;

        // Skip comments
        if (p + 1 < pe && *p == '/' && *(p + 1) == '*') {
            p += 2;
            while (p + 1 < pe && !(*p == '*' && *(p + 1) == '/')) {
                p++;
            }
            if (p + 1 < pe) p += 2;  // Skip */
            continue;
        }

        // Check for @media at-rule (only at depth 0)
        if (brace_depth == 0 && p + 6 < pe && *p == '@' &&
            strncmp(p + 1, "media", 5) == 0 && IS_WHITESPACE(p[6])) {
            p += 6;  // Skip "@media"

            // Skip whitespace
            while (p < pe && IS_WHITESPACE(*p)) p++;

            // Find the media query (up to opening brace)
            const char *mq_start = p;
            while (p < pe && *p != '{') p++;
            const char *mq_end = p;

            // Trim whitespace from media query
            trim_trailing(mq_start, &mq_end);

            if (p >= pe || *p != '{') {
                // No opening brace - skip malformed @media
                continue;
            }

            // Intern media query to symbol
            VALUE inner_media_sym = intern_media_query(mq_start, mq_end - mq_start, media_count);

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

            // Recursively parse @media block contents
            VALUE inner_rules = parse_css_with_media(block_start, block_end, inner_media_sym, media_count);

            // Append all inner rules to our rules array (maintains insertion order)
            long inner_len = RARRAY_LEN(inner_rules);
            for (long i = 0; i < inner_len; i++) {
                rb_ary_push(rules, rb_ary_entry(inner_rules, i));
            }

            if (p < pe && *p == '}') p++;  // Skip closing }
            continue;
        }

        // Opening brace - start of declaration block
        if (*p == '{') {
            if (brace_depth == 0 && selector_start != NULL) {
                decl_start = p + 1;  // Start of declarations
            }
            brace_depth++;
            p++;
            continue;
        }

        // Closing brace - end of declaration block
        if (*p == '}') {
            brace_depth--;
            if (brace_depth == 0 && selector_start != NULL && decl_start != NULL) {
                // Parse declarations
                VALUE declarations = parse_declarations(decl_start, p);

                // Get selector string and trim
                const char *sel_end = decl_start - 1;  // Before the {
                while (sel_end > selector_start && IS_WHITESPACE(*(sel_end - 1))) {
                    sel_end--;
                }

                // Split selector list on commas and create a rule for each
                const char *seg_start = selector_start;
                const char *seg = selector_start;

                while (seg <= sel_end) {
                    if (seg == sel_end || *seg == ',') {
                        // Trim leading whitespace from segment
                        while (seg_start < seg && IS_WHITESPACE(*seg_start)) {
                            seg_start++;
                        }

                        // Trim trailing whitespace from segment
                        const char *seg_end = seg;
                        while (seg_end > seg_start && IS_WHITESPACE(*(seg_end - 1))) {
                            seg_end--;
                        }

                        // Create selector if not empty
                        if (seg_end > seg_start) {
                            VALUE selector = rb_utf8_str_new(seg_start, seg_end - seg_start);

                            // Create NewRule with current media_sym
                            VALUE rule = rb_struct_new(cNewRule,
                                selector,
                                rb_ary_dup(declarations),  // Duplicate declarations for each selector
                                Qnil,       // specificity (calculated on demand)
                                media_sym   // media_query_sym from context
                            );

                            rb_ary_push(rules, rule);
                        }

                        seg_start = seg + 1;  // Skip comma
                    }
                    seg++;
                }

                // Reset for next rule
                selector_start = NULL;
                decl_start = NULL;
            }
            p++;
            continue;
        }

        // If we're at depth 0 and haven't found a selector yet, this is the start
        if (brace_depth == 0 && selector_start == NULL) {
            selector_start = p;
        }

        p++;
    }

    return rules;
}
