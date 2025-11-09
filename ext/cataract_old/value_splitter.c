/*
 * value_splitter.c - CSS value splitting utility
 *
 * Purpose: Split CSS declaration values on whitespace while preserving content
 *          inside functions and quoted strings.
 *
 * Examples:
 *   "1px 2px 3px 4px"              => ["1px", "2px", "3px", "4px"]
 *   "10px calc(100% - 20px)"       => ["10px", "calc(100% - 20px)"]
 *   "rgb(255, 0, 0) blue"          => ["rgb(255, 0, 0)", "blue"]
 *   "'Helvetica Neue', sans-serif" => ["'Helvetica Neue',", "sans-serif"]
 */

#include "cataract.h"

/*
 * Split a CSS declaration value on whitespace while preserving content
 * inside functions and quoted strings.
 *
 * Algorithm:
 *   - Track parenthesis depth for functions like calc(), rgb()
 *   - Track quote state for strings like 'Helvetica Neue'
 *   - Split on whitespace only when depth=0 and not in quotes
 *
 * @param value [String] Pre-parsed CSS declaration value (assumed well-formed)
 * @return [Array<String>] Array of value tokens
 */
VALUE cataract_split_value(VALUE self, VALUE value) {
    Check_Type(value, T_STRING);
    const char *str = RSTRING_PTR(value);
    long len = RSTRING_LEN(value);

    // Sanity check: reject unreasonably long values (DoS protection)
    if (len > 65536) {
        rb_raise(rb_eArgError, "CSS value too long (max 64KB)");
    }

    // Result array
    VALUE result = rb_ary_new();

    // State tracking
    int paren_depth = 0;
    int in_quotes = 0;
    char quote_char = '\0';
    const char *token_start = NULL;
    const char *p = str;
    const char *pe = str + len;

    while (p < pe) {
        char c = *p;

        // Handle quotes
        if ((c == '"' || c == '\'') && !in_quotes) {
            // Opening quote
            in_quotes = 1;
            quote_char = c;
            if (token_start == NULL) token_start = p;
            p++;
            continue;
        }

        if (in_quotes && c == quote_char) {
            // Closing quote
            in_quotes = 0;
            p++;
            continue;
        }

        // Handle parentheses (only when not in quotes)
        if (!in_quotes) {
            if (c == '(') {
                paren_depth++;
                if (token_start == NULL) token_start = p;
                p++;
                continue;
            }

            if (c == ')') {
                paren_depth--;
                p++;
                continue;
            }

            // Handle whitespace (delimiter when depth=0 and not quoted)
            if (IS_WHITESPACE(c)) {
                if (paren_depth == 0 && !in_quotes) {
                    // Emit token if we have one
                    if (token_start != NULL) {
                        size_t token_len = p - token_start;
                        VALUE token = rb_str_new(token_start, token_len);
                        rb_ary_push(result, token);
                        token_start = NULL;
                    }
                    p++;
                    continue;
                }
                // else: whitespace inside function/quotes, part of token
            }
        }

        // Regular character - mark start if needed
        if (token_start == NULL) {
            token_start = p;
        }
        p++;
    }

    // Emit final token if any
    if (token_start != NULL) {
        size_t token_len = pe - token_start;
        VALUE token = rb_str_new(token_start, token_len);
        rb_ary_push(result, token);
    }

    return result;
}
