/*
 * css_parser.c - CSS parser implementation
 *
 * Handles: selectors, declaration blocks, @media, @supports, @keyframes, @font-face, etc.
 *
 * This is a character-by-character state machine parser.
 */

#include "cataract.h"
#include <string.h>

// Parser states
typedef enum {
    STATE_INITIAL,       // Start of parsing or after closing }
    STATE_SELECTOR,      // Parsing selector
    STATE_DECLARATIONS   // Inside { } parsing declarations
} ParserState;

// Forward declarations
VALUE parse_css_impl(VALUE css_string, int depth);
VALUE parse_media_query(const char *query_str, long query_len);
VALUE parse_declarations_string(const char *start, const char *end);

// ============================================================================
// CSS Parsing Helper Functions
// ============================================================================

// Parse declaration block and extract Declaration::Value structs
void capture_declarations_fn(
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

    DEBUG_PRINTF("[capture_declarations] Parsing declarations from %td to %td: '%.*s'\n",
                 (ptrdiff_t)(decl_start - css_string_base), (ptrdiff_t)(p - css_string_base),
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
        // Look backwards for "!important"
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
            VALUE property_raw = rb_usascii_str_new(prop_start, prop_len);
            VALUE property = lowercase_property(property_raw);
            VALUE value = rb_utf8_str_new(val_start, val_end - val_start);

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
            DEBUG_PRINTF("[capture_declarations] Skipping empty value for property at pos %td\n",
                         (ptrdiff_t)(prop_start - css_string_base));
        }

        if (pos < end && *pos == ';') pos++;  // Skip semicolon if present
    }

    // Reset for next rule
    *decl_start_ptr = NULL;
}

// Create Rule structs from current selectors and declarations
void finish_rule_fn(
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

// Parse media query string and return array of media types
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

// Parse declarations string into array of Declarations::Value structs
// Used by parse_declarations Ruby wrapper
VALUE parse_declarations_string(const char *start, const char *end) {
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
            VALUE property_raw = rb_usascii_str_new(prop_start, prop_len);
            VALUE property = lowercase_property(property_raw);
            VALUE value = rb_utf8_str_new(val_start, val_len);

            // Create Declarations::Value struct
            VALUE decl = rb_struct_new(cDeclarationsValue,
                property, value, is_important ? Qtrue : Qfalse);

            rb_ary_push(declarations, decl);
        }
    }

    return declarations;
}

// ============================================================================
// Main CSS Parser
// ============================================================================

/*
 * CSS parser implementation
 *
 * Parses selectors, declarations, and @rules. Creates Rule structs.
 *
 * @param css_string [String] CSS to parse
 * @param depth [Integer] Recursion depth (for error handling)
 * @return [Array<Rule>] Array of Rule structs
 */
VALUE parse_css_impl(VALUE css_string, int depth) {
    Check_Type(css_string, T_STRING);

    const char *p = RSTRING_PTR(css_string);
    const char *pe = p + RSTRING_LEN(css_string);
    const char *css_string_base = p;

    // State variables
    ParserState state = STATE_INITIAL;
    const char *mark = NULL;
    const char *decl_start = NULL;
    const char *selector_start = NULL;

    // Ruby objects
    VALUE rules_array = rb_ary_new();
    VALUE current_selectors = Qnil;
    VALUE current_declarations = Qnil;
    VALUE selector = Qnil;
    VALUE current_media_types = Qnil;  // Set from @media queries

    while (p < pe) {
        char c = *p;

        // Skip whitespace in most states
        if (IS_WHITESPACE(c) && state != STATE_DECLARATIONS && state != STATE_SELECTOR) {
            p++;
            continue;
        }

        // Skip comments everywhere
        if (c == '/' && p + 1 < pe && *(p + 1) == '*') {
            // Find end of comment
            p += 2;
            while (p + 1 < pe) {
                if (*p == '*' && *(p + 1) == '/') {
                    p += 2;
                    break;
                }
                p++;
            }
            continue;
        }

        switch (state) {
            case STATE_INITIAL:
                if (c == '@') {
                    // @rule detected - parse it
                    const char *at_start = p + 1;  // Skip @
                    const char *at_end = at_start;

                    // Find end of @rule name (until space or {)
                    while (at_end < pe && !IS_WHITESPACE(*at_end) && *at_end != '{' && *at_end != ';') {
                        at_end++;
                    }

                    long name_len = at_end - at_start;
                    char at_name[256];
                    if (name_len > 255) name_len = 255;
                    strncpy(at_name, at_start, name_len);
                    at_name[name_len] = '\0';

                    DEBUG_PRINTF("[pure_c] @rule detected: @%s at pos %td\n", at_name, (ptrdiff_t)(p - css_string_base));

                    // Skip to prelude start (after name, before {)
                    p = at_end;
                    while (p < pe && IS_WHITESPACE(*p)) p++;

                    const char *prelude_start = p;

                    // Check for statement-style @rule (ends with ;)
                    const char *check = p;
                    while (check < pe && *check != '{' && *check != ';') check++;

                    if (check >= pe) {
                        // Incomplete - skip
                        p = pe;
                        break;
                    }

                    if (*check == ';') {
                        // Statement-style @rule (@charset, @import, etc.) - skip it
                        p = check + 1;
                        DEBUG_PRINTF("[pure_c] Skipped statement @rule @%s\n", at_name);
                        break;
                    }

                    // Block-style @rule - find prelude end (the {)
                    while (p < pe && *p != '{') p++;

                    if (p >= pe) break;  // Incomplete

                    const char *prelude_end = p;

                    // Trim whitespace from prelude
                    while (prelude_end > prelude_start && IS_WHITESPACE(*(prelude_end - 1))) {
                        prelude_end--;
                    }

                    long prelude_len = prelude_end - prelude_start;

                    p++;  // Skip opening {

                    // Find matching closing brace
                    int brace_depth = 1;
                    const char *block_start = p;

                    while (p < pe && brace_depth > 0) {
                        if (*p == '{') {
                            brace_depth++;
                        } else if (*p == '}') {
                            brace_depth--;
                        } else if (*p == '/' && p + 1 < pe && *(p + 1) == '*') {
                            // Skip comments when counting braces
                            p += 2;
                            while (p + 1 < pe && !(*p == '*' && *(p + 1) == '/')) p++;
                            if (p + 1 < pe) p += 2;
                            continue;
                        }
                        p++;
                    }

                    const char *block_end = p - 1;  // Before closing }
                    long block_len = block_end - block_start;

                    DEBUG_PRINTF("[pure_c] @%s block: %ld bytes\n", at_name, block_len);

                    // Process based on @rule type
                    if (strcmp(at_name, "media") == 0) {
                        // Parse media query
                        VALUE media_types = parse_media_query(prelude_start, prelude_len);

                        // Recursively parse block content
                        VALUE block_content = rb_str_new(block_start, block_len);
                        VALUE inner_rules = parse_css_impl(block_content, depth + 1);

                        // Set media_query on all inner rules
                        if (!NIL_P(media_types) && RARRAY_LEN(media_types) > 0) {
                            for (long i = 0; i < RARRAY_LEN(inner_rules); i++) {
                                VALUE rule = RARRAY_AREF(inner_rules, i);
                                rb_struct_aset(rule, INT2FIX(3), rb_ary_dup(media_types));
                            }
                        }

                        // Add to main rules array
                        for (long i = 0; i < RARRAY_LEN(inner_rules); i++) {
                            rb_ary_push(rules_array, RARRAY_AREF(inner_rules, i));
                        }

                        RB_GC_GUARD(media_types);
                        RB_GC_GUARD(block_content);
                        RB_GC_GUARD(inner_rules);

                    } else if (strcmp(at_name, "supports") == 0 || strcmp(at_name, "layer") == 0 ||
                               strcmp(at_name, "container") == 0 || strcmp(at_name, "scope") == 0) {
                        // Conditional group rules - recursively parse and add rules
                        VALUE block_content = rb_str_new(block_start, block_len);
                        VALUE inner_rules = parse_css_impl(block_content, depth + 1);

                        for (long i = 0; i < RARRAY_LEN(inner_rules); i++) {
                            rb_ary_push(rules_array, RARRAY_AREF(inner_rules, i));
                        }

                        RB_GC_GUARD(block_content);
                        RB_GC_GUARD(inner_rules);

                    } else if (strstr(at_name, "keyframes") != NULL) {
                        // @keyframes - create dummy rule with animation name
                        VALUE animation_name = rb_str_new(prelude_start, prelude_len);
                        animation_name = rb_funcall(animation_name, rb_intern("strip"), 0);

                        // Build selector: "@keyframes " + name
                        VALUE sel = UTF8_STR("@");
                        rb_str_cat(sel, at_name, strlen(at_name));
                        rb_str_cat2(sel, " ");
                        rb_str_append(sel, animation_name);

                        VALUE rule = rb_struct_new(cRule,
                            sel,                                    // selector
                            rb_ary_new(),                          // declarations (empty)
                            Qnil,                                   // specificity
                            rb_ary_new3(1, ID2SYM(rb_intern("all")))  // media_query
                        );

                        rb_ary_push(rules_array, rule);

                        RB_GC_GUARD(animation_name);
                        RB_GC_GUARD(sel);
                        RB_GC_GUARD(rule);

                    } else if (strcmp(at_name, "font-face") == 0 || strcmp(at_name, "property") == 0 ||
                               strcmp(at_name, "page") == 0 || strcmp(at_name, "counter-style") == 0) {
                        // Descriptor-based @rules - parse block as declarations
                        // Wrap in dummy selector for parsing
                        VALUE wrapped = UTF8_STR("* { ");
                        rb_str_cat(wrapped, block_start, block_len);
                        rb_str_cat2(wrapped, " }");

                        VALUE dummy_rules = parse_css_impl(wrapped, depth + 1);
                        VALUE declarations = Qnil;

                        if (!NIL_P(dummy_rules) && RARRAY_LEN(dummy_rules) > 0) {
                            VALUE first_rule = RARRAY_AREF(dummy_rules, 0);
                            declarations = rb_struct_aref(first_rule, INT2FIX(1));

                            // Build selector: "@" + name + [" " + prelude]
                            VALUE sel = UTF8_STR("@");
                            rb_str_cat(sel, at_name, strlen(at_name));

                            if (prelude_len > 0) {
                                VALUE prelude_val = rb_str_new(prelude_start, prelude_len);
                                prelude_val = rb_funcall(prelude_val, rb_intern("strip"), 0);
                                if (RSTRING_LEN(prelude_val) > 0) {
                                    rb_str_cat2(sel, " ");
                                    rb_str_append(sel, prelude_val);
                                }
                                RB_GC_GUARD(prelude_val);
                            }

                            VALUE rule = rb_struct_new(cRule,
                                sel,                                    // selector
                                declarations,                           // declarations
                                Qnil,                                   // specificity
                                rb_ary_new3(1, ID2SYM(rb_intern("all")))  // media_query
                            );

                            rb_ary_push(rules_array, rule);

                            RB_GC_GUARD(sel);
                            RB_GC_GUARD(rule);
                        }

                        RB_GC_GUARD(wrapped);
                        RB_GC_GUARD(dummy_rules);
                        RB_GC_GUARD(declarations);

                    } else {
                        // Unknown @rule - skip it
                        DEBUG_PRINTF("[pure_c] Skipping unknown @rule: @%s\n", at_name);
                    }

                } else if (c == '}') {
                    // Stray closing brace - ignore
                    p++;
                } else if (!IS_WHITESPACE(c)) {
                    // Start of selector
                    selector_start = p;
                    state = STATE_SELECTOR;
                    DEBUG_PRINTF("[pure_c] Starting selector at pos %td\n", (ptrdiff_t)(p - css_string_base));
                }
                break;

            case STATE_SELECTOR:
                if (c == '{') {
                    // End of selector, start of declarations
                    if (selector_start != NULL) {
                        const char *selector_end = p;

                        // Trim trailing whitespace
                        while (selector_end > selector_start && IS_WHITESPACE(*(selector_end - 1))) {
                            selector_end--;
                        }

                        // Split on comma and capture each selector
                        const char *seg_start = selector_start;
                        const char *seg = selector_start;

                        if (NIL_P(current_selectors)) {
                            current_selectors = rb_ary_new();
                        }

                        while (seg <= selector_end) {
                            if (seg == selector_end || *seg == ',') {
                                // Capture segment
                                const char *seg_end = seg;

                                // Trim whitespace from segment
                                while (seg_end > seg_start && IS_WHITESPACE(*(seg_end - 1))) {
                                    seg_end--;
                                }
                                while (seg_start < seg_end && IS_WHITESPACE(*seg_start)) {
                                    seg_start++;
                                }

                                if (seg_end > seg_start) {
                                    VALUE sel = rb_utf8_str_new(seg_start, seg_end - seg_start);
                                    rb_ary_push(current_selectors, sel);
                                    DEBUG_PRINTF("[pure_c] Captured selector: '%s'\n", RSTRING_PTR(sel));
                                }

                                seg_start = seg + 1;  // Skip comma
                            }
                            seg++;
                        }

                        selector_start = NULL;
                    }

                    p++;  // Skip {
                    decl_start = p;
                    state = STATE_DECLARATIONS;
                    DEBUG_PRINTF("[pure_c] Starting declarations at pos %td\n", (ptrdiff_t)(p - css_string_base));
                } else {
                    // Continue parsing selector
                    p++;
                }
                break;

            case STATE_DECLARATIONS:
                if (c == '}') {
                    // End of declaration block
                    // Capture declarations
                    capture_declarations_fn(&decl_start, p, &current_declarations, css_string_base);

                    // Create rule(s)
                    finish_rule_fn(0, &current_selectors, &current_declarations,
                                   &current_media_types, rules_array, &mark);

                    p++;  // Skip }
                    state = STATE_INITIAL;
                    DEBUG_PRINTF("[pure_c] Finished rule, back to initial at pos %td\n", (ptrdiff_t)(p - css_string_base));
                } else {
                    // Continue parsing declarations
                    p++;
                }
                break;
        }
    }

    // Cleanup: if we ended in the middle of parsing, try to finish
    if (state == STATE_DECLARATIONS && decl_start != NULL) {
        capture_declarations_fn(&decl_start, p, &current_declarations, css_string_base);
        finish_rule_fn(0, &current_selectors, &current_declarations,
                       &current_media_types, rules_array, &mark);
    }

    return rules_array;
}
