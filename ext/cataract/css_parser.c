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

// Forward declaration for recursion
VALUE parse_css_impl(VALUE css_string, int depth);

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

                    DEBUG_PRINTF("[pure_c] @rule detected: @%s at pos %ld\n", at_name, p - css_string_base);

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
                        VALUE sel = rb_str_new_cstr("@");
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
                        VALUE wrapped = rb_str_new_cstr("* { ");
                        rb_str_cat(wrapped, block_start, block_len);
                        rb_str_cat2(wrapped, " }");

                        VALUE dummy_rules = parse_css_impl(wrapped, depth + 1);
                        VALUE declarations = Qnil;

                        if (!NIL_P(dummy_rules) && RARRAY_LEN(dummy_rules) > 0) {
                            VALUE first_rule = RARRAY_AREF(dummy_rules, 0);
                            declarations = rb_struct_aref(first_rule, INT2FIX(1));

                            // Build selector: "@" + name + [" " + prelude]
                            VALUE sel = rb_str_new_cstr("@");
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
                    DEBUG_PRINTF("[pure_c] Starting selector at pos %ld\n", p - css_string_base);
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
                                    VALUE sel = rb_str_new(seg_start, seg_end - seg_start);
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
                    DEBUG_PRINTF("[pure_c] Starting declarations at pos %ld\n", p - css_string_base);
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
                    DEBUG_PRINTF("[pure_c] Finished rule, back to initial at pos %ld\n", p - css_string_base);
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
