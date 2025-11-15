/*
 * css_parser_new.c - New CSS parser implementation with flat rule array
 *
 * Key differences from original:
 * - Flat @rules array with rule IDs (0-indexed)
 * - Separate @media_index hash mapping media queries to rule ID arrays
 * - Handles nested @media queries by combining conditions
 *
 * TODO: Unify !important detection into a macro/helper function
 *       Currently duplicated in parse_declarations() and parse_mixed_block()
 */

#include "cataract.h"
#include <string.h>

// Parser context passed through recursive calls
typedef struct {
    VALUE rules_array;        // Array of Rule structs
    VALUE media_index;        // Hash: Symbol => Array of rule IDs
    VALUE selector_lists;     // Hash: list_id => Array of rule IDs
    VALUE imports_array;      // Array of ImportStatement structs
    int rule_id_counter;      // Next rule ID (0-indexed)
    int next_selector_list_id; // Next selector list ID (0-indexed)
    int media_query_count;    // Safety limit for media queries
    st_table *media_cache;    // Parse-time cache: string => parsed media types
    int has_nesting;          // Set to 1 if any nested rules are created
    int selector_lists_enabled; // Parser option: track selector lists (1=enabled, 0=disabled)
    int depth;                // Current recursion depth (safety limit)
} ParserContext;

// Macro to skip CSS comments /* ... */
// Usage: SKIP_COMMENT(p, end) where p is current position, end is limit
// Side effect: advances p past the comment and continues to next iteration
// Note: Uses RB_UNLIKELY since comments are rare in typical CSS
#define SKIP_COMMENT(ptr, limit) \
    if (RB_UNLIKELY((ptr) + 1 < (limit) && *(ptr) == '/' && *((ptr) + 1) == '*')) { \
        (ptr) += 2; \
        while ((ptr) + 1 < (limit) && !(*(ptr) == '*' && *((ptr) + 1) == '/')) (ptr)++; \
        if ((ptr) + 1 < (limit)) (ptr) += 2; \
        continue; \
    }

// Find matching closing brace for a block
// Input: start = position after opening '{', end = limit
// Returns: pointer to matching '}' (or end if not found)
// Note: Handles nested braces by tracking depth
static inline const char* find_matching_brace(const char *start, const char *end) {
    int depth = 1;
    const char *p = start;
    while (p < end && depth > 0) {
        if (*p == '{') depth++;
        else if (*p == '}') depth--;
        if (depth > 0) p++;
    }
    return p;
}

// Find matching closing paren
// Input: start = position after opening '(', end = limit
// Returns: pointer to matching ')' (or end if not found)
// Note: Handles nested parens by tracking depth
static inline const char* find_matching_paren(const char *start, const char *end) {
    int depth = 1;
    const char *p = start;
    while (p < end && depth > 0) {
        if (*p == '(') depth++;
        else if (*p == ')') depth--;
        if (depth > 0) p++;
    }
    return p;
}

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
 * Check if a block contains nested selectors (not just declarations)
 *
 * Per W3C spec, nested selectors cannot start with identifiers to avoid ambiguity.
 * They must start with: &, ., #, [, :, *, >, +, ~, or @media/@supports/etc
 *
 * Example CSS blocks:
 *   "color: red; font-size: 14px;"     -> 0 (declarations only)
 *   "color: red; & .child { ... }"     -> 1 (has nested selector)
 *   "color: red; @media (...) { ... }" -> 1 (has nested @media)
 *
 * Returns: 1 if nested selectors found, 0 if only declarations
 */
static int has_nested_selectors(const char *start, const char *end) {
    const char *p = start;

    while (p < end) {
        // Skip whitespace
        trim_leading(&p, end);
        if (p >= end) break;

        // Skip comments
        SKIP_COMMENT(p, end);

        // Check for nested selector indicators
        // Example: "color: red; & .child { font: 14px; }"
        //                       ^p (at &) - nested selector indicator
        char c = *p;
        if (c == '&' || c == '.' || c == '#' || c == '[' || c == ':' ||
            c == '*' || c == '>' || c == '+' || c == '~') {
            // Look ahead - if followed by {, it's likely a nested selector
            // Example: "& .child { font: 14px; }"
            //           ^p      ^lookahead (at {) - confirms nested selector
            const char *lookahead = p + 1;
            while (lookahead < end && *lookahead != '{' && *lookahead != ';' && *lookahead != '\n') {
                lookahead++;
            }
            if (lookahead < end && *lookahead == '{') {
                return 1;  // Found nested selector
            }
        }

        // Check for @media, @supports, etc nested inside
        // Example: "color: red; @media (min-width: 768px) { ... }"
        //                       ^p (at @) - nested at-rule
        if (c == '@') {
            return 1;  // Nested at-rule
        }

        // Skip to next line or semicolon
        // Example: "color: red; font-size: 14px;"
        //                    ^p              ^p (after skip) - continue checking
        while (p < end && *p != ';' && *p != '\n') p++;
        if (p < end) p++;
    }

    return 0;  // No nested selectors found
}

/*
 * Resolve nested selector against parent selector
 *
 * Examples:
 *   resolve_nested_selector(".parent", "& .child")     => ".parent .child"  (explicit)
 *   resolve_nested_selector(".parent", "&:hover")      => ".parent:hover"   (explicit)
 *   resolve_nested_selector(".parent", "&.active")     => ".parent.active"  (explicit)
 *   resolve_nested_selector(".parent", ".child")       => ".parent .child"  (implicit)
 *   resolve_nested_selector(".parent", "> .child")     => ".parent > .child" (implicit combinator)
 *
 * Returns: [resolved_selector (String), nesting_style (Fixnum)]
 *   nesting_style: 0 = NESTING_STYLE_IMPLICIT, 1 = NESTING_STYLE_EXPLICIT
 */
static VALUE resolve_nested_selector(VALUE parent_selector, const char *nested_sel, long nested_len) {
    const char *parent = RSTRING_PTR(parent_selector);
    long parent_len = RSTRING_LEN(parent_selector);

    // Check if nested selector contains &
    int has_ampersand = 0;
    for (long i = 0; i < nested_len; i++) {
        if (nested_sel[i] == '&') {
            has_ampersand = 1;
            break;
        }
    }

    VALUE resolved;
    int nesting_style;

    if (has_ampersand) {
        // Explicit nesting - replace & with parent
        // Example: parent=".button", nested="&:hover" => ".button:hover"
        //          &:hover
        //          ^       - Replace & with ".button"
        //           ^^^^^^ - Copy rest as-is
        nesting_style = NESTING_STYLE_EXPLICIT;

        // Check if selector starts with a combinator (relative selector)
        // Example: "+ .bar + &" should become ".foo + .bar + .foo"
        const char *nested_trimmed = nested_sel;
        const char *nested_trimmed_end = nested_sel + nested_len;
        trim_leading(&nested_trimmed, nested_trimmed_end);

        int starts_with_combinator = 0;
        if (nested_trimmed < nested_trimmed_end) {
            char first_char = *nested_trimmed;
            if (first_char == '+' || first_char == '>' || first_char == '~') {
                starts_with_combinator = 1;
            }
        }

        // Build result by replacing & with parent (add extra space if starts with combinator)
        VALUE result = rb_str_buf_new(parent_len + nested_len + (starts_with_combinator ? parent_len + 2 : 0));
        rb_enc_associate(result, rb_utf8_encoding());

        // If starts with combinator, prepend parent first with space
        // Example: "+ .bar + &" => ".foo + .bar + .foo"
        if (starts_with_combinator) {
            rb_str_buf_cat(result, parent, parent_len);
            rb_str_buf_cat(result, " ", 1);
        }

        long i = 0;
        while (i < nested_len) {
            if (nested_sel[i] == '&') {                                        // At: '&'
                // Replace & with parent selector
                rb_str_buf_cat(result, parent, parent_len);                   // Output: ".button"
                i++;                                                           // Move to: ':'
            } else {
                // Copy character as-is
                rb_str_buf_cat(result, &nested_sel[i], 1);                    // Output: ':hover'
                i++;
            }
        }

        resolved = result;
    } else {
        // Implicit nesting - prepend parent with appropriate spacing
        // Example: parent=".parent", nested=".child" => ".parent .child"
        //          .child
        //          - Prepend ".parent " before ".child"
        // Example: parent=".parent", nested="> .child" => ".parent > .child"
        //          > .child
        //          - Prepend ".parent " before "> .child"
        nesting_style = NESTING_STYLE_IMPLICIT;

        const char *nested_trimmed = nested_sel;
        const char *nested_end = nested_sel + nested_len;

        // Trim leading whitespace from nested selector
        trim_leading(&nested_trimmed, nested_end);
        long trimmed_len = nested_end - nested_trimmed;

        VALUE result = rb_str_buf_new(parent_len + 1 + trimmed_len);
        rb_enc_associate(result, rb_utf8_encoding());

        // Add parent                                                          // Output: ".parent"
        rb_str_buf_cat(result, parent, parent_len);

        // Add separator space (before combinator or for implicit descendant) // Output: " "
        rb_str_buf_cat(result, " ", 1);

        // Add nested selector (trimmed)                                       // Output: ".child"
        rb_str_buf_cat(result, nested_trimmed, trimmed_len);

        resolved = result;
    }

    // Return array [resolved_selector, nesting_style]
    VALUE result_array = rb_ary_new_from_args(2, resolved, INT2FIX(nesting_style));

    // Guard parent_selector since we extracted C pointer and did allocations
    RB_GC_GUARD(parent_selector);

    return result_array;
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
            const char *closing = find_matching_paren(p, end);
            p = (closing < end) ? closing + 1 : closing;
            continue;
        }

        // Find end of word (media type or keyword)
        const char *word_start = p;
        while (p < end && !IS_WHITESPACE(*p) && *p != ',' && *p != '(' && *p != ':') {
            p++;
        }

        if (p > word_start) {
            long word_len = p - word_start;

            // Check if this is a media feature (followed by ':')
            // Example: "orientation" in "orientation: landscape" is not a media type
            int is_media_feature = (p < end && *p == ':');

            // Check if it's a keyword (and, or, not, only)
            int is_keyword = (word_len == 3 && strncmp(word_start, "and", 3) == 0) ||
                           (word_len == 2 && strncmp(word_start, "or", 2) == 0) ||
                           (word_len == 3 && strncmp(word_start, "not", 3) == 0) ||
                           (word_len == 4 && strncmp(word_start, "only", 4) == 0);

            if (!is_keyword && !is_media_feature) {
                // This is a media type - add it as symbol
                VALUE type_sym = ID2SYM(rb_intern2(word_start, word_len));
                rb_ary_push(types, type_sym);
            }
        }

        // Skip to comma or end
        while (p < end && *p != ',') {
            if (*p == '(') {
                // Skip condition
                const char *closing = find_matching_paren(p, end);
                p = (closing < end) ? closing + 1 : closing;
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

    // Extract media types and add to each first (if different from full query)
    // We add these BEFORE the full query so that when iterating the media_index hash,
    // the full query comes last and takes precedence during serialization
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

    // Add to full query symbol (after media types for insertion order)
    add_to_media_index(ctx->media_index, media_sym, rule_id);

    // Guard media_str since we extracted C pointer and called extract_media_types (which allocates)
    RB_GC_GUARD(media_str);
}

/*
 * Parse declaration block into array of Declaration structs
 *
 * Example input: "color: red; background: url(image.png); font-size: 14px !important"
 * Example output: [Declaration("color", "red", false),
 *                  Declaration("background", "url(image.png)", false),
 *                  Declaration("font-size", "14px", true)]
 *
 * Handles:
 *   - Multiple declarations separated by semicolons
 *   - Values containing parentheses (e.g., url(...), rgba(...))
 *   - !important flag
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
        // Example: "color: red; ..."
        //           ^pos  ^pos (at :)
        const char *prop_start = pos;
        while (pos < end && *pos != ':' && *pos != ';') pos++;

        // Malformed declaration - skip to next semicolon to recover
        if (pos >= end || *pos != ':') {
            while (pos < end && *pos != ';') pos++;
            if (pos < end) pos++;  // Skip the semicolon
            continue;
        }

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
        // Must track paren depth to avoid breaking on semicolons inside url() or rgba()
        // Example: "url(data:image/svg+xml;base64,...); next-prop: ..."
        //           ^val_start                        ^pos (at ; outside parens)
        const char *val_start = pos;
        int paren_depth = 0;
        while (pos < end) {
            if (*pos == '(') {                      // At: '('
                paren_depth++;                       // Depth: 1
            } else if (*pos == ')') {                // At: ')'
                paren_depth--;                       // Depth: 0
            } else if (*pos == ';' && paren_depth == 0) {  // At: ';' (outside parens)
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
                // strncmp safely handles remaining length check
                if (check + 9 <= val_end && strncmp(check, "important", 9) == 0) {
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
            long prop_len = prop_end - prop_start;
            long val_len = val_end - val_start;

            // Check property name length
            if (prop_len > MAX_PROPERTY_NAME_LENGTH) {
                rb_raise(eSizeError,
                         "Property name too long: %ld bytes (max %d)",
                         prop_len, MAX_PROPERTY_NAME_LENGTH);
            }

            // Check property value length
            if (val_len > MAX_PROPERTY_VALUE_LENGTH) {
                rb_raise(eSizeError,
                         "Property value too long: %ld bytes (max %d)",
                         val_len, MAX_PROPERTY_VALUE_LENGTH);
            }

            // Create property string and lowercase it
            VALUE property_raw = rb_usascii_str_new(prop_start, prop_len);
            VALUE property = lowercase_property(property_raw);
            VALUE value = rb_utf8_str_new(val_start, val_len);

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
static void parse_css_recursive(ParserContext *ctx, const char *css, const char *pe,
                                 VALUE parent_media_sym, VALUE parent_selector, VALUE parent_rule_id);
static VALUE combine_media_queries(VALUE parent, VALUE child);

/*
 * Combine parent and child media queries
 * Examples:
 *   parent="screen", child="min-width: 500px" => "screen and (min-width: 500px)"
 *   parent=nil, child="print" => "print"
 * Note: child may have had outer parens stripped, so we re-add them for conditions
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

    // If child is a condition (contains ':'), wrap it in parentheses
    // Example: "min-width: 500px" => "(min-width: 500px)"
    const char *child_ptr = RSTRING_PTR(child_str);
    long child_len = RSTRING_LEN(child_str);
    int has_colon = 0;
    int already_wrapped = (child_len >= 2 && child_ptr[0] == '(' && child_ptr[child_len - 1] == ')');

    for (long i = 0; i < child_len && !has_colon; i++) {
        if (child_ptr[i] == ':') {
            has_colon = 1;
        }
    }

    if (has_colon && !already_wrapped) {
        rb_str_cat2(combined, "(");
        rb_str_append(combined, child_str);
        rb_str_cat2(combined, ")");
    } else {
        rb_str_append(combined, child_str);
    }

    return ID2SYM(rb_intern_str(combined));
}

/*
 * Intern media query string to symbol with safety check
 * Keeps media query exactly as written - parentheses are required per CSS spec
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

    // Keep media query exactly as written - parentheses are required per CSS spec
    const char *start = query_str;
    const char *end = query_str + query_len;

    // Trim whitespace only
    while (start < end && IS_WHITESPACE(*start)) start++;
    while (end > start && IS_WHITESPACE(*(end - 1))) end--;

    long final_len = end - start;
    VALUE query_string = rb_usascii_str_new(start, final_len);
    VALUE sym = ID2SYM(rb_intern_str(query_string));
    ctx->media_query_count++;

    return sym;
}

/*
 * Parse mixed declarations and nested selectors from a block
 * Used when a CSS rule block contains both declarations and nested rules
 *
 * Example CSS block being parsed:
 *   .parent {
 *     color: red;           <- declaration
 *     & .child {            <- nested selector
 *       font-size: 14px;
 *     }
 *     @media (min-width: 768px) {  <- nested @media
 *       padding: 10px;
 *     }
 *   }
 *
 * Returns: Array of declarations (only the declarations, not nested rules)
 */
static VALUE parse_mixed_block(ParserContext *ctx, const char *start, const char *end,
                                VALUE parent_selector, VALUE parent_rule_id, VALUE parent_media_sym) {
    // Check recursion depth to prevent stack overflow
    if (ctx->depth > MAX_PARSE_DEPTH) {
        rb_raise(eDepthError,
                 "CSS nesting too deep: exceeded maximum depth of %d",
                 MAX_PARSE_DEPTH);
    }

    VALUE declarations = rb_ary_new();
    const char *p = start;

    while (p < end) {
        trim_leading(&p, end);
        if (p >= end) break;

        SKIP_COMMENT(p, end);

        // Check if this is a nested @media query
        if (*p == '@' && p + 6 < end && strncmp(p, "@media", 6) == 0 &&
            (p + 6 == end || IS_WHITESPACE(p[6]))) {
            // Nested @media - parse with parent selector as context
            const char *media_start = p + 6;
            trim_leading(&media_start, end);

            // Find opening brace
            const char *media_query_end = media_start;
            while (media_query_end < end && *media_query_end != '{') {
                media_query_end++;
            }
            if (media_query_end >= end) break;

            // Extract media query
            const char *media_query_start = media_start;
            const char *media_query_end_trimmed = media_query_end;
            trim_trailing(media_query_start, &media_query_end_trimmed);
            VALUE media_sym = intern_media_query_safe(ctx, media_query_start, media_query_end_trimmed - media_query_start);

            p = media_query_end + 1;  // Skip {

            // Find matching closing brace
            const char *media_block_start = p;
            const char *media_block_end = find_matching_brace(p, end);
            p = media_block_end;

            if (p < end) p++;  // Skip }

            // Combine media queries: parent + child
            VALUE combined_media_sym = combine_media_queries(parent_media_sym, media_sym);

            // Parse the block with parse_mixed_block to support further nesting
            // Create a rule ID for this media rule
            int media_rule_id = ctx->rule_id_counter++;

            // Reserve position for parent rule
            long parent_pos = RARRAY_LEN(ctx->rules_array);
            rb_ary_push(ctx->rules_array, Qnil);

            // Parse mixed block (may contain declarations and/or nested @media)
            ctx->depth++;
            VALUE media_declarations = parse_mixed_block(ctx, media_block_start, media_block_end,
                                                        parent_selector, INT2FIX(media_rule_id), combined_media_sym);
            ctx->depth--;

            // Create rule with the parent selector and declarations, associated with combined media query
            VALUE rule = rb_struct_new(cRule,
                INT2FIX(media_rule_id),
                parent_selector,
                media_declarations,
                Qnil,  // specificity
                parent_rule_id,  // Link to parent for nested @media serialization
                Qnil,  // nesting_style (nil for @media nesting)
                Qnil   // selector_list_id
            );

            // Mark that we have nesting (only set once)
            if (!ctx->has_nesting && !NIL_P(parent_rule_id)) {
                ctx->has_nesting = 1;
            }

            // Replace placeholder with actual rule
            rb_ary_store(ctx->rules_array, parent_pos, rule);
            update_media_index(ctx, combined_media_sym, media_rule_id);

            continue;
        }

        // Check if this is a nested selector (starts with nesting indicators)
        // Example within parse_mixed_block:
        //   Input block: "color: red; & .child { font: 14px; }"
        //                              ^p (at &) - nested selector detected
        char c = *p;
        if (c == '&' || c == '.' || c == '#' || c == '[' || c == ':' ||
            c == '*' || c == '>' || c == '+' || c == '~' || c == '@') {
            // This is likely a nested selector - find the opening brace
            // Example: "& .child { font: 14px; }"
            //           ^nested_sel_start  ^p (at {)
            const char *nested_sel_start = p;
            while (p < end && *p != '{') p++;
            if (p >= end) break;

            const char *nested_sel_end = p;
            trim_trailing(nested_sel_start, &nested_sel_end);

            p++;  // Skip {

            // Find matching closing brace
            // Example: "& .child { font: 14px; }"
            //                     ^nested_block_start  ^nested_block_end (at })
            const char *nested_block_start = p;
            const char *nested_block_end = find_matching_brace(p, end);
            p = nested_block_end;

            if (p < end) p++;  // Skip }

            // Split nested selector on commas and create a rule for each
            // Example: "& .child, & .sibling { ... }" creates 2 nested rules
            const char *seg_start = nested_sel_start;
            const char *seg = nested_sel_start;

            while (seg <= nested_sel_end) {
                if (seg == nested_sel_end || *seg == ',') {  // At: ',' or end
                    // Trim segment
                    while (seg_start < seg && IS_WHITESPACE(*seg_start)) {
                        seg_start++;
                    }

                    const char *seg_end_ptr = seg;
                    while (seg_end_ptr > seg_start && IS_WHITESPACE(*(seg_end_ptr - 1))) {
                        seg_end_ptr--;
                    }

                    if (seg_end_ptr > seg_start) {
                        // Resolve nested selector
                        VALUE result = resolve_nested_selector(parent_selector, seg_start, seg_end_ptr - seg_start);
                        VALUE resolved_selector = rb_ary_entry(result, 0);
                        VALUE nesting_style = rb_ary_entry(result, 1);

                        // Get rule ID
                        int rule_id = ctx->rule_id_counter++;

                        // Recursively parse nested block
                        ctx->depth++;
                        VALUE nested_declarations = parse_mixed_block(ctx, nested_block_start, nested_block_end,
                                                                     resolved_selector, INT2FIX(rule_id), parent_media_sym);
                        ctx->depth--;

                        // Create rule for nested selector
                        VALUE rule = rb_struct_new(cRule,
                            INT2FIX(rule_id),
                            resolved_selector,
                            nested_declarations,
                            Qnil,  // specificity
                            parent_rule_id,
                            nesting_style,
                            Qnil   // selector_list_id
                        );

                        // Mark that we have nesting (only set once)
                        if (!ctx->has_nesting && !NIL_P(parent_rule_id)) {
                            ctx->has_nesting = 1;
                        }

                        rb_ary_push(ctx->rules_array, rule);
                        update_media_index(ctx, parent_media_sym, rule_id);
                    }

                    seg_start = seg + 1;
                }
                seg++;
            }

            continue;
        }

        // This is a declaration - parse it
        const char *prop_start = p;
        while (p < end && *p != ':' && *p != ';' && *p != '{') p++;
        if (p >= end || *p != ':') {
            // Malformed - skip to semicolon
            while (p < end && *p != ';') p++;
            if (p < end) p++;
            continue;
        }

        const char *prop_end = p;
        trim_trailing(prop_start, &prop_end);

        p++;  // Skip :
        trim_leading(&p, end);

        const char *val_start = p;
        int important = 0;

        // Find end of value (semicolon or closing brace or end)
        while (p < end && *p != ';' && *p != '}') p++;
        const char *val_end = p;

        // Check for !important
        const char *important_check = val_end - 10;  // " !important"
        if (important_check >= val_start) {
            trim_trailing(val_start, &val_end);
            if (val_end - val_start >= 10) {
                if (strncmp(val_end - 10, "!important", 10) == 0) {
                    important = 1;
                    val_end -= 10;
                    trim_trailing(val_start, &val_end);
                }
            }
        } else {
            trim_trailing(val_start, &val_end);
        }

        if (p < end && *p == ';') p++;

        // Create declaration
        if (prop_end > prop_start && val_end > val_start) {
            long prop_len = prop_end - prop_start;
            long val_len = val_end - val_start;

            // Check property name length
            if (prop_len > MAX_PROPERTY_NAME_LENGTH) {
                rb_raise(eSizeError,
                         "Property name too long: %ld bytes (max %d)",
                         prop_len, MAX_PROPERTY_NAME_LENGTH);
            }

            // Check property value length
            if (val_len > MAX_PROPERTY_VALUE_LENGTH) {
                rb_raise(eSizeError,
                         "Property value too long: %ld bytes (max %d)",
                         val_len, MAX_PROPERTY_VALUE_LENGTH);
            }

            VALUE property_raw = rb_usascii_str_new(prop_start, prop_len);
            VALUE property = lowercase_property(property_raw);
            VALUE value = rb_utf8_str_new(val_start, val_len);

            VALUE decl = rb_struct_new(cDeclaration,
                property,
                value,
                important ? Qtrue : Qfalse
            );

            rb_ary_push(declarations, decl);
        }
    }

    return declarations;
}

/*
 * Parse @import statement
 * @import "url" [media-query];
 * @import url("url") [media-query];
 *
 * Modifies ctx->imports_array and ctx->rule_id_counter
 */
static void parse_import_statement(ParserContext *ctx, const char **p_ptr, const char *pe) {
    const char *p = *p_ptr;

    DEBUG_PRINTF("[IMPORT_STMT] Starting parse, input: %.50s\n", p);

    // Skip whitespace
    while (p < pe && IS_WHITESPACE(*p)) p++;

    // Check for optional url(
    int has_url_function = 0;
    if (p + 4 <= pe && strncmp(p, "url(", 4) == 0) {
        has_url_function = 1;
        p += 4;

        // Skip whitespace after url(
        while (p < pe && IS_WHITESPACE(*p)) p++;
    }

    // Find opening quote
    if (p >= pe || (*p != '"' && *p != '\'')) {
        // Invalid @import, skip to semicolon
        while (p < pe && *p != ';') p++;
        if (p < pe) p++;
        *p_ptr = p;
        return;
    }

    char quote_char = *p;
    p++; // Skip opening quote

    const char *url_start = p;

    // Find closing quote (handle escaped quotes)
    while (p < pe && *p != quote_char) {
        if (*p == '\\' && p + 1 < pe) {
            p += 2; // Skip escaped character
        } else {
            p++;
        }
    }

    if (p >= pe) {
        // Unterminated string
        *p_ptr = p;
        return;
    }

    long url_len = p - url_start;
    VALUE url = rb_utf8_str_new(url_start, url_len);
    p++; // Skip closing quote

    // Skip closing paren if we had url(
    if (has_url_function) {
        while (p < pe && IS_WHITESPACE(*p)) p++;
        if (p < pe && *p == ')') p++;
    }

    // Skip whitespace
    while (p < pe && IS_WHITESPACE(*p)) p++;

    // Check for optional media query (everything until semicolon)
    VALUE media = Qnil;
    if (p < pe && *p != ';') {
        const char *media_start = p;

        // Find semicolon
        while (p < pe && *p != ';') p++;

        const char *media_end = p;

        // Trim trailing whitespace from media query
        while (media_end > media_start && IS_WHITESPACE(*(media_end - 1))) {
            media_end--;
        }

        if (media_end > media_start) {
            VALUE media_str = rb_utf8_str_new(media_start, media_end - media_start);
            media = ID2SYM(rb_intern_str(media_str));
        }
    }

    // Skip semicolon
    if (p < pe && *p == ';') p++;

    // Create ImportStatement (resolved: false by default)
    VALUE import_stmt = rb_struct_new(cImportStatement,
        INT2FIX(ctx->rule_id_counter),
        url,
        media,
        Qfalse);

    DEBUG_PRINTF("[IMPORT_STMT] Created import: id=%d, url=%s, media=%s\n",
                 ctx->rule_id_counter,
                 RSTRING_PTR(url),
                 NIL_P(media) ? "nil" : RSTRING_PTR(rb_sym2str(media)));

    rb_ary_push(ctx->imports_array, import_stmt);
    ctx->rule_id_counter++;

    *p_ptr = p;

    RB_GC_GUARD(url);
    RB_GC_GUARD(media);
    RB_GC_GUARD(import_stmt);
}

/*
 * Parse CSS recursively with media query context and optional parent selector for nesting
 *
 * parent_media_sym: Parent media query symbol (or Qnil for no media context)
 * parent_selector:  Parent selector string for nested rules (or Qnil for top-level)
 * parent_rule_id:   Parent rule ID (Fixnum) for nested rules (or Qnil for top-level)
 */
static void parse_css_recursive(ParserContext *ctx, const char *css, const char *pe,
                                 VALUE parent_media_sym, VALUE parent_selector, VALUE parent_rule_id) {
    // Check recursion depth to prevent stack overflow
    if (ctx->depth > MAX_PARSE_DEPTH) {
        rb_raise(eDepthError,
                 "CSS nesting too deep: exceeded maximum depth of %d",
                 MAX_PARSE_DEPTH);
    }

    const char *p = css;

    const char *selector_start = NULL;
    const char *decl_start = NULL;
    int brace_depth = 0;

    while (p < pe) {
        // Skip whitespace
        while (p < pe && IS_WHITESPACE(*p)) p++;
        if (p >= pe) break;

        // Skip comments (rare in typical CSS)
        SKIP_COMMENT(p, pe);

        // Hail mary ...
        // DEBUG_PRINTF("[LOOP] At position, char='%c' (0x%02x), brace_depth=%d, next 20 chars: %.20s\n",
        //            *p >= 32 && *p <= 126 ? *p : '?', (unsigned char)*p, brace_depth, p);

        // Check for @import at-rule (only at top level, before any rules)
        if (RB_UNLIKELY(brace_depth == 0 && p + 7 < pe && *p == '@' &&
            strncmp(p + 1, "import", 6) == 0 && IS_WHITESPACE(p[7]))) {
            DEBUG_PRINTF("[IMPORT] Found @import at position, rules_count=%ld\n", RARRAY_LEN(ctx->rules_array));
            // Check if we've already seen a rule
            if (RARRAY_LEN(ctx->rules_array) > 0) {
                // Warn and skip - @import must come before rules
                rb_warn("CSS @import ignored: @import must appear before all rules (found import after rules)");
                // Skip to semicolon
                while (p < pe && *p != ';') p++;
                if (p < pe) p++;
                continue;
            }

            p += 7;  // Skip "@import "
            parse_import_statement(ctx, &p, pe);
            DEBUG_PRINTF("[IMPORT] After parsing, imports_count=%ld\n", RARRAY_LEN(ctx->imports_array));
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
            const char *block_end = find_matching_brace(p, pe);
            p = block_end;

            // Recursively parse @media block with combined media context
            ctx->depth++;
            parse_css_recursive(ctx, block_start, block_end, combined_media_sym, NO_PARENT_SELECTOR, NO_PARENT_RULE_ID);
            ctx->depth--;

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
                const char *block_end = find_matching_brace(p, pe);
                p = block_end;

                // Recursively parse block content (preserve parent media context)
                ctx->depth++;
                parse_css_recursive(ctx, block_start, block_end, parent_media_sym, parent_selector, parent_rule_id);
                ctx->depth--;

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
                const char *block_end = find_matching_brace(p, pe);
                p = block_end;

                // Parse keyframe blocks as rules (from/to/0%/50% etc)
                ParserContext nested_ctx = {
                    .rules_array = rb_ary_new(),
                    .media_index = rb_hash_new(),
                    .selector_lists = rb_hash_new(),
                    .imports_array = rb_ary_new(),
                    .rule_id_counter = 0,
                    .next_selector_list_id = 0,
                    .media_query_count = 0,
                    .media_cache = NULL,
                    .has_nesting = 0,
                    .selector_lists_enabled = ctx->selector_lists_enabled,
                    .depth = 0
                };
                parse_css_recursive(&nested_ctx, block_start, block_end, NO_PARENT_MEDIA, NO_PARENT_SELECTOR, NO_PARENT_RULE_ID);

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
                const char *decl_end = find_matching_brace(p, pe);
                p = decl_end;

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
                // We've found a complete CSS rule block - now determine if it has nesting
                // Example: .parent { color: red; & .child { font-size: 14px; } }
                //          ^selector_start    ^decl_start                    ^p (at })
                int has_nesting = has_nested_selectors(decl_start, p);

                // Get selector string
                const char *sel_end = decl_start - 1;
                while (sel_end > selector_start && IS_WHITESPACE(*(sel_end - 1))) {
                    sel_end--;
                }

                if (!has_nesting) {
                    // FAST PATH: No nesting - parse as pure declarations
                    VALUE declarations = parse_declarations(decl_start, p);

                    // Split on commas to handle multi-selector rules
                    // Example: ".a, .b, .c { color: red; }" creates 3 separate rules
                    //           ^selector_start      ^sel_end
                    //              ^seg_start=seg (scanning for commas)

                    // Count selectors for selector list tracking
                    int selector_count = 1;
                    if (ctx->selector_lists_enabled) {
                        const char *count_ptr = selector_start;
                        while (count_ptr < sel_end) {
                            if (*count_ptr == ',') {
                                selector_count++;
                            }
                            count_ptr++;
                        }
                    }

                    // Create selector list if enabled and multiple selectors
                    int list_id = -1;
                    VALUE rule_ids_array = Qnil;
                    if (ctx->selector_lists_enabled && selector_count > 1) {
                        list_id = ctx->next_selector_list_id++;
                        rule_ids_array = rb_ary_new();
                        rb_hash_aset(ctx->selector_lists, INT2FIX(list_id), rule_ids_array);
                    }

                    const char *seg_start = selector_start;
                    const char *seg = selector_start;

                    while (seg <= sel_end) {
                        if (seg == sel_end || *seg == ',') {  // At: ',' or end
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

                                // Resolve against parent if nested
                                VALUE resolved_selector;
                                VALUE nesting_style_val;
                                VALUE parent_id_val;

                                if (!NIL_P(parent_selector)) {
                                    // This is a nested rule - resolve selector
                                    VALUE result = resolve_nested_selector(parent_selector, RSTRING_PTR(selector), RSTRING_LEN(selector));
                                    resolved_selector = rb_ary_entry(result, 0);
                                    nesting_style_val = rb_ary_entry(result, 1);
                                    parent_id_val = parent_rule_id;
                                } else {
                                    // Top-level rule
                                    resolved_selector = selector;
                                    nesting_style_val = Qnil;
                                    parent_id_val = Qnil;
                                }

                                // Get rule ID and increment
                                int rule_id = ctx->rule_id_counter++;

                                // Determine selector_list_id value
                                VALUE selector_list_id_val = (list_id >= 0) ? INT2FIX(list_id) : Qnil;

                                // Create Rule
                                VALUE rule = rb_struct_new(cRule,
                                    INT2FIX(rule_id),
                                    resolved_selector,
                                    rb_ary_dup(declarations),
                                    Qnil,  // specificity
                                    parent_id_val,
                                    nesting_style_val,
                                    selector_list_id_val
                                );

                                // Track rule in selector list if applicable
                                if (list_id >= 0) {
                                    rb_ary_push(rule_ids_array, INT2FIX(rule_id));
                                }

                                // Mark that we have nesting (only set once)
                                if (!ctx->has_nesting && !NIL_P(parent_id_val)) {
                                    ctx->has_nesting = 1;
                                }

                                rb_ary_push(ctx->rules_array, rule);

                                // Update media index
                                update_media_index(ctx, parent_media_sym, rule_id);
                            }

                            seg_start = seg + 1;
                        }
                        seg++;
                    }
                } else {
                    // NESTED PATH: Parse mixed declarations + nested rules
                    // For each comma-separated parent selector, parse the block with that parent
                    //
                    // Example: ".a, .b { color: red; & .child { font: 14px; } }"
                    //           ^selector_start ^sel_end
                    // Creates:
                    //   - .a with declarations [color: red]
                    //   - .a .child with declarations [font: 14px]
                    //   - .b with declarations [color: red]
                    //   - .b .child with declarations [font: 14px]

                    // Count selectors for selector list tracking
                    int selector_count = 1;
                    if (ctx->selector_lists_enabled) {
                        const char *count_ptr = selector_start;
                        while (count_ptr < sel_end) {
                            if (*count_ptr == ',') {
                                selector_count++;
                            }
                            count_ptr++;
                        }
                    }

                    // Create selector list if enabled and multiple selectors
                    int list_id = -1;
                    VALUE rule_ids_array = Qnil;
                    if (ctx->selector_lists_enabled && selector_count > 1) {
                        list_id = ctx->next_selector_list_id++;
                        rule_ids_array = rb_ary_new();
                        rb_hash_aset(ctx->selector_lists, INT2FIX(list_id), rule_ids_array);
                    }

                    const char *seg_start = selector_start;
                    const char *seg = selector_start;

                    while (seg <= sel_end) {
                        if (seg == sel_end || *seg == ',') {  // At: ',' or end
                            // Trim segment
                            while (seg_start < seg && IS_WHITESPACE(*seg_start)) {
                                seg_start++;
                            }

                            const char *seg_end_ptr = seg;
                            while (seg_end_ptr > seg_start && IS_WHITESPACE(*(seg_end_ptr - 1))) {
                                seg_end_ptr--;
                            }

                            if (seg_end_ptr > seg_start) {
                                VALUE current_selector = rb_utf8_str_new(seg_start, seg_end_ptr - seg_start);

                                // Resolve against parent if we're already nested
                                VALUE resolved_current;
                                VALUE current_nesting_style;
                                VALUE current_parent_id;

                                if (!NIL_P(parent_selector)) {
                                    VALUE result = resolve_nested_selector(parent_selector, RSTRING_PTR(current_selector), RSTRING_LEN(current_selector));
                                    resolved_current = rb_ary_entry(result, 0);
                                    current_nesting_style = rb_ary_entry(result, 1);
                                    current_parent_id = parent_rule_id;
                                } else {
                                    resolved_current = current_selector;
                                    current_nesting_style = Qnil;
                                    current_parent_id = Qnil;
                                }

                                // Get rule ID for current selector (increment to reserve it)
                                int current_rule_id = ctx->rule_id_counter++;

                                // Reserve parent's position in rules array with placeholder
                                // This ensures parent comes before nested rules in array order (per W3C spec)
                                long parent_position = RARRAY_LEN(ctx->rules_array);
                                rb_ary_push(ctx->rules_array, Qnil);

                                // Parse mixed block (declarations + nested selectors)
                                // Nested rules will be added AFTER the placeholder
                                ctx->depth++;
                                VALUE parent_declarations = parse_mixed_block(ctx, decl_start, p,
                                                                             resolved_current, INT2FIX(current_rule_id), parent_media_sym);
                                ctx->depth--;

                                // Determine selector_list_id value
                                VALUE selector_list_id_val = (list_id >= 0) ? INT2FIX(list_id) : Qnil;

                                // Create parent rule and replace placeholder
                                // Always create the rule (even if empty) to avoid edge cases
                                VALUE rule = rb_struct_new(cRule,
                                    INT2FIX(current_rule_id),
                                    resolved_current,
                                    parent_declarations,
                                    Qnil,  // specificity
                                    current_parent_id,
                                    current_nesting_style,
                                    selector_list_id_val
                                );

                                // Track rule in selector list if applicable
                                if (list_id >= 0) {
                                    rb_ary_push(rule_ids_array, INT2FIX(current_rule_id));
                                }

                                // Mark that we have nesting (only set once)
                                if (!ctx->has_nesting && !NIL_P(current_parent_id)) {
                                    ctx->has_nesting = 1;
                                }

                                // Replace placeholder with actual rule - just pointer assignment, fast!
                                rb_ary_store(ctx->rules_array, parent_position, rule);
                                update_media_index(ctx, parent_media_sym, current_rule_id);
                            }

                            seg_start = seg + 1;
                        }
                        seg++;
                    }
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
            DEBUG_PRINTF("[SELECTOR] Starting selector at: %.50s\n", selector_start);
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
VALUE parse_css_new_impl(VALUE css_string, VALUE parser_options, int rule_id_offset) {
    Check_Type(css_string, T_STRING);
    Check_Type(parser_options, T_HASH);

    DEBUG_PRINTF("\n[PARSE_NEW] ========== NEW PARSE CALL ==========\n");
    DEBUG_PRINTF("[PARSE_NEW] Input CSS (first 100 chars): %.100s\n", RSTRING_PTR(css_string));

    // Read parser options
    VALUE selector_lists_opt = rb_hash_aref(parser_options, ID2SYM(rb_intern("selector_lists")));
    int selector_lists_enabled = (NIL_P(selector_lists_opt) || RTEST(selector_lists_opt)) ? 1 : 0;

    const char *css = RSTRING_PTR(css_string);
    const char *pe = css + RSTRING_LEN(css_string);
    const char *p = css;

    VALUE charset = Qnil;

    // Extract @charset
    if (RSTRING_LEN(css_string) > 10 && strncmp(css, "@charset ", 9) == 0) {
        DEBUG_PRINTF("[CHARSET] Found @charset at start\n");
        char *quote_start = strchr(css + 9, '"');
        if (quote_start != NULL) {
            char *quote_end = strchr(quote_start + 1, '"');
            if (quote_end != NULL) {
                charset = rb_str_new(quote_start + 1, quote_end - quote_start - 1);
                DEBUG_PRINTF("[CHARSET] Extracted charset: %s\n", RSTRING_PTR(charset));
                char *semicolon = quote_end + 1;
                while (semicolon < pe && IS_WHITESPACE(*semicolon)) {
                    semicolon++;
                }
                if (semicolon < pe && *semicolon == ';') {
                    p = semicolon + 1;
                    DEBUG_PRINTF("[CHARSET] Advanced past semicolon, remaining: %.50s\n", p);
                }
            }
        }
    }

    // @import statements are now handled in parse_css_recursive
    // They must come before all rules (except @charset) per CSS spec

    // Initialize parser context with offset
    ParserContext ctx;
    ctx.rules_array = rb_ary_new();
    ctx.media_index = rb_hash_new();
    ctx.selector_lists = rb_hash_new();
    ctx.imports_array = rb_ary_new();
    ctx.rule_id_counter = rule_id_offset;  // Start from offset
    ctx.next_selector_list_id = 0;  // Start from 0
    ctx.media_query_count = 0;
    ctx.media_cache = NULL;  // Removed - no perf benefit
    ctx.has_nesting = 0;  // Will be set to 1 if any nested rules are created
    ctx.selector_lists_enabled = selector_lists_enabled;
    ctx.depth = 0;  // Start at depth 0

    // Parse CSS (top-level, no parent context)
    DEBUG_PRINTF("[PARSE] Starting parse_css_recursive from: %.80s\n", p);
    parse_css_recursive(&ctx, p, pe, NO_PARENT_MEDIA, NO_PARENT_SELECTOR, NO_PARENT_RULE_ID);

    // Build result hash
    VALUE result = rb_hash_new();
    rb_hash_aset(result, ID2SYM(rb_intern("rules")), ctx.rules_array);
    rb_hash_aset(result, ID2SYM(rb_intern("_media_index")), ctx.media_index);
    rb_hash_aset(result, ID2SYM(rb_intern("_selector_lists")), ctx.selector_lists);
    rb_hash_aset(result, ID2SYM(rb_intern("imports")), ctx.imports_array);
    rb_hash_aset(result, ID2SYM(rb_intern("charset")), charset);
    rb_hash_aset(result, ID2SYM(rb_intern("last_rule_id")), INT2FIX(ctx.rule_id_counter));
    rb_hash_aset(result, ID2SYM(rb_intern("_has_nesting")), ctx.has_nesting ? Qtrue : Qfalse);

    RB_GC_GUARD(charset);
    RB_GC_GUARD(ctx.rules_array);
    RB_GC_GUARD(ctx.media_index);
    RB_GC_GUARD(ctx.selector_lists);
    RB_GC_GUARD(ctx.imports_array);
    RB_GC_GUARD(result);

    return result;
}
