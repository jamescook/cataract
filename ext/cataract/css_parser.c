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
#include <stdint.h>

// Use uint8_t for boolean flags to reduce struct size and improve cache efficiency
// (int is 4 bytes, uint8_t is 1 byte - saves 27 bytes across 9 flags)
// #define BOOLEAN uint8_t
#define BOOLEAN int

// Parser context passed through recursive calls
typedef struct {
    VALUE rules_array;        // Array of Rule structs
    VALUE media_index;        // Hash: Symbol => Array of rule IDs
    VALUE selector_lists;     // Hash: list_id => Array of rule IDs
    VALUE imports_array;      // Array of ImportStatement structs
    VALUE media_queries;      // Array of MediaQuery structs
    VALUE media_query_lists;  // Hash: list_id => Array of MediaQuery IDs
    int rule_id_counter;      // Next rule ID (0-indexed)
    int next_selector_list_id; // Next selector list ID (0-indexed)
    int media_query_id_counter; // Next MediaQuery ID (0-indexed)
    int next_media_query_list_id; // Next media query list ID (0-indexed)
    int media_query_count;    // Safety limit for media queries
    st_table *media_cache;    // Parse-time cache: string => parsed media types
    BOOLEAN has_nesting;      // Set to 1 if any nested rules are created
    BOOLEAN selector_lists_enabled; // Parser option: track selector lists (1=enabled, 0=disabled)
    BOOLEAN depth;            // Current recursion depth (safety limit)
    // URL conversion options
    VALUE base_uri;           // Base URI for resolving relative URLs (Qnil if disabled)
    VALUE uri_resolver;       // Proc to call for URL resolution (Qnil for default)
    BOOLEAN absolute_paths;   // Whether to convert relative URLs to absolute
    // Parse error checking options
    VALUE css_string;         // Full CSS string for error position calculation
    BOOLEAN check_empty_values; // Raise error on empty declaration values
    BOOLEAN check_malformed_declarations; // Raise error on declarations without colons
    BOOLEAN check_invalid_selectors; // Raise error on empty/malformed selectors
    BOOLEAN check_invalid_selector_syntax; // Raise error on syntax violations (.. ## etc)
    BOOLEAN check_malformed_at_rules; // Raise error on @media/@supports without conditions
    BOOLEAN check_unclosed_blocks; // Raise error on missing closing braces
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

// Find matching closing brace with strict error checking
// Input: start = position after opening '{', end = limit, check_unclosed = whether to raise error
// Returns: pointer to matching '}' (raises error if not found and check_unclosed is true)
static inline const char* find_matching_brace_strict(const char *start, const char *end, int check_unclosed) {
    const char *closing_brace = find_matching_brace(start, end);

    // Check if we found the closing brace
    if (check_unclosed && closing_brace >= end) {
        rb_raise(eParseError, "Unclosed block: missing closing brace");
    }

    return closing_brace;
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

// Helper function to raise ParseError with automatic position calculation
// Does not return - raises error and exits
__attribute__((noreturn))
static void raise_parse_error_at(ParserContext *ctx, const char *error_pos, const char *message, const char *error_type) {
    const char *css = RSTRING_PTR(ctx->css_string);
    long pos = error_pos - css;

    // Build keyword args hash
    VALUE kwargs = rb_hash_new();
    rb_hash_aset(kwargs, ID2SYM(rb_intern("css")), ctx->css_string);
    rb_hash_aset(kwargs, ID2SYM(rb_intern("pos")), LONG2NUM(pos));
    rb_hash_aset(kwargs, ID2SYM(rb_intern("type")), ID2SYM(rb_intern(error_type)));

    // Create ParseError instance
    VALUE msg_str = rb_str_new_cstr(message);
    VALUE argv[2] = {msg_str, kwargs};
    VALUE error = rb_funcallv_kw(eParseError, rb_intern("new"), 2, argv, RB_PASS_KEYWORDS);

    // Raise the error
    rb_exc_raise(error);
}

// Check if a selector contains only valid CSS selector characters and sequences
// Returns 1 if valid, 0 if invalid
// Valid characters: a-z A-Z 0-9 - _ . # [ ] : * > + ~ ( ) ' " = ^ $ | \ & % / whitespace
static inline int is_valid_selector(const char *start, const char *end) {
    const char *p = start;
    while (p < end) {
        unsigned char c = (unsigned char)*p;

        // Check for invalid character sequences
        if (p + 1 < end) {
            // Double dot (..) is invalid
            if (c == '.' && *(p + 1) == '.') {
                return 0;
            }
            // Double hash (##) is invalid
            if (c == '#' && *(p + 1) == '#') {
                return 0;
            }
        }

        // Alphanumeric
        if ((c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || (c >= '0' && c <= '9')) {
            p++;
            continue;
        }

        // Whitespace
        if (c == ' ' || c == '\t' || c == '\n' || c == '\r') {
            p++;
            continue;
        }

        // Valid CSS selector special characters
        switch (c) {
            case '-':  // Hyphen (in identifiers, attribute selectors)
            case '_':  // Underscore (in identifiers)
            case '.':  // Class selector
            case '#':  // ID selector
            case '[':  // Attribute selector start
            case ']':  // Attribute selector end
            case ':':  // Pseudo-class/element (:: is valid for pseudo-elements)
            case '*':  // Universal selector, attribute operator
            case '>':  // Child combinator
            case '+':  // Adjacent sibling combinator
            case '~':  // General sibling combinator
            case '(':  // Pseudo-class function
            case ')':  // Pseudo-class function end
            case '\'': // String in attribute selector
            case '"':  // String in attribute selector
            case '=':  // Attribute operator
            case '^':  // Attribute operator ^=
            case '$':  // Attribute operator $=
            case '|':  // Attribute operator |=, namespace separator
            case '\\': // Escape character
            case '&':  // Nesting selector
            case '%':  // Sometimes used in selectors
            case '/':  // Sometimes used in selectors
            case '!':  // Negation (though rare)
            case ',':  // List separator (shouldn't be here after splitting, but allow it)
                p++;
                break;

            default:
                // Invalid character found
                return 0;
        }
    }

    return 1;
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
    BOOLEAN has_ampersand = 0;
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
    // BUT: skip if it contains a comma (comma-separated list like "screen, print")
    // because we already added each individual type above
    int has_comma = 0;
    for (long i = 0; i < query_len; i++) {
        if (query[i] == ',') {
            has_comma = 1;
            break;
        }
    }
    if (!has_comma) {
        add_to_media_index(ctx->media_index, media_sym, rule_id);
    }

    // Guard media_str since we extracted C pointer and called extract_media_types (which allocates)
    RB_GC_GUARD(media_str);
}

// Helper struct for passing arguments to resolver callback
typedef struct {
    VALUE uri_resolver;
    VALUE base_uri;
    VALUE url_str;
} ResolverArgs;

// Callback for rb_protect to call the resolver proc
static VALUE call_resolver(VALUE arg) {
    ResolverArgs *args = (ResolverArgs *)arg;
    return rb_funcall(args->uri_resolver, rb_intern("call"), 2, args->base_uri, args->url_str);
}

/*
 * Convert relative URLs in a CSS value to absolute URLs
 *
 * Scans for url() patterns and resolves relative URLs using the resolver proc.
 * Returns a new Ruby string with resolved URLs, or the original if no conversion needed.
 */
static VALUE convert_urls_in_value(VALUE value_str, VALUE base_uri, VALUE uri_resolver) {
    const char *val = RSTRING_PTR(value_str);
    long len = RSTRING_LEN(value_str);

    // Quick check: does value contain 'url('?
    const char *url_check = val;
    int has_url = 0;
    while (url_check < val + len - 3) {
        if ((*url_check == 'u' || *url_check == 'U') &&
            (*(url_check + 1) == 'r' || *(url_check + 1) == 'R') &&
            (*(url_check + 2) == 'l' || *(url_check + 2) == 'L') &&
            *(url_check + 3) == '(') {
            has_url = 1;
            break;
        }
        url_check++;
    }
    if (!has_url) return value_str;

    // Build result string
    VALUE result = rb_str_new("", 0);
    const char *pos = val;

    while (pos < val + len) {
        // Look for 'url(' - case insensitive
        if (pos + 3 < val + len &&
            (*pos == 'u' || *pos == 'U') &&
            (*(pos + 1) == 'r' || *(pos + 1) == 'R') &&
            (*(pos + 2) == 'l' || *(pos + 2) == 'L') &&
            *(pos + 3) == '(') {

            // Append 'url('
            rb_str_cat(result, "url(", 4);
            pos += 4;

            // Skip whitespace after (
            while (pos < val + len && IS_WHITESPACE(*pos)) pos++;

            // Determine quote character (if any)
            char quote = 0;
            if (pos < val + len && (*pos == '\'' || *pos == '"')) {
                quote = *pos;
                pos++;
            }

            // Find end of URL
            const char *url_start = pos;
            if (quote) {
                // Quoted URL - find closing quote
                while (pos < val + len && *pos != quote) {
                    if (*pos == '\\' && pos + 1 < val + len) {
                        pos += 2;  // Skip escaped char
                    } else {
                        pos++;
                    }
                }
            } else {
                // Unquoted URL - find ) or whitespace
                while (pos < val + len && *pos != ')' && !IS_WHITESPACE(*pos)) {
                    pos++;
                }
            }
            const char *url_end = pos;

            // Extract URL string
            long url_len = url_end - url_start;
            VALUE url_str = rb_str_new(url_start, url_len);

            // Check if URL needs resolution (is relative)
            int needs_resolution = 0;
            if (url_len > 0) {
                // Check for absolute URLs or data URIs that don't need resolution
                const char *u = url_start;
                if ((url_len >= 5 && strncmp(u, "data:", 5) == 0) ||
                    (url_len >= 7 && strncmp(u, "http://", 7) == 0) ||
                    (url_len >= 8 && strncmp(u, "https://", 8) == 0) ||
                    (url_len >= 2 && strncmp(u, "//", 2) == 0) ||
                    (url_len >= 1 && *u == '#')) {  // Fragment reference
                    needs_resolution = 0;
                } else {
                    needs_resolution = 1;
                }
            }

            if (needs_resolution) {
                // Resolve using the resolver proc (always provided by Ruby side)
                // Wrap in rb_protect to catch exceptions
                ResolverArgs args = { uri_resolver, base_uri, url_str };
                int state = 0;
                VALUE resolved = rb_protect(call_resolver, (VALUE)&args, &state);

                if (state) {
                    // Exception occurred - preserve original URL
                    rb_set_errinfo(Qnil);  // Clear exception
                    if (quote) {
                        rb_str_cat(result, &quote, 1);
                        rb_str_append(result, url_str);
                        rb_str_cat(result, &quote, 1);
                    } else {
                        rb_str_append(result, url_str);
                    }
                } else {
                    // Output with single quotes (canonical format)
                    rb_str_cat(result, "'", 1);
                    rb_str_append(result, resolved);
                    rb_str_cat(result, "'", 1);
                }

                RB_GC_GUARD(resolved);
            } else {
                // Keep original URL with original quoting
                if (quote) {
                    rb_str_cat(result, &quote, 1);
                    rb_str_append(result, url_str);
                    rb_str_cat(result, &quote, 1);
                } else {
                    rb_str_append(result, url_str);
                }
            }

            RB_GC_GUARD(url_str);

            // Skip closing quote if present
            if (quote && pos < val + len && *pos == quote) {
                pos++;
            }

            // Skip whitespace before )
            while (pos < val + len && IS_WHITESPACE(*pos)) pos++;

            // Skip closing )
            if (pos < val + len && *pos == ')') {
                rb_str_cat(result, ")", 1);
                pos++;
            }
        } else {
            // Regular character - append to result
            rb_str_cat(result, pos, 1);
            pos++;
        }
    }

    RB_GC_GUARD(result);
    return result;
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
static VALUE parse_declarations(const char *start, const char *end, ParserContext *ctx) {
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
            if (ctx->check_malformed_declarations) {
                // Extract property text for error message
                const char *prop_text_end = pos;
                trim_trailing(prop_start, &prop_text_end);
                long prop_text_len = prop_text_end - prop_start;

                const char *css = RSTRING_PTR(ctx->css_string);
                long error_pos = prop_start - css;

                if (prop_text_len == 0) {
                    // Build keyword args hash
                    VALUE kwargs = rb_hash_new();
                    rb_hash_aset(kwargs, ID2SYM(rb_intern("css")), ctx->css_string);
                    rb_hash_aset(kwargs, ID2SYM(rb_intern("pos")), LONG2NUM(error_pos));
                    rb_hash_aset(kwargs, ID2SYM(rb_intern("type")), ID2SYM(rb_intern("malformed_declaration")));

                    VALUE msg_str = rb_str_new_cstr("Malformed declaration: missing property name");
                    VALUE argv[2] = {msg_str, kwargs};
                    VALUE error = rb_funcallv_kw(eParseError, rb_intern("new"), 2, argv, RB_PASS_KEYWORDS);
                    rb_exc_raise(error);
                } else {
                    // Limit property name to 200 chars in error message
                    int display_len = (prop_text_len > 200) ? 200 : (int)prop_text_len;
                    char error_msg[256];
                    snprintf(error_msg, sizeof(error_msg),
                           "Malformed declaration: missing colon after '%.*s'",
                           display_len, prop_start);

                    // Build keyword args hash
                    VALUE kwargs = rb_hash_new();
                    rb_hash_aset(kwargs, ID2SYM(rb_intern("css")), ctx->css_string);
                    rb_hash_aset(kwargs, ID2SYM(rb_intern("pos")), LONG2NUM(error_pos));
                    rb_hash_aset(kwargs, ID2SYM(rb_intern("type")), ID2SYM(rb_intern("malformed_declaration")));

                    VALUE msg_str = rb_str_new_cstr(error_msg);
                    VALUE argv[2] = {msg_str, kwargs};
                    VALUE error = rb_funcallv_kw(eParseError, rb_intern("new"), 2, argv, RB_PASS_KEYWORDS);
                    rb_exc_raise(error);
                }
            }
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
        BOOLEAN is_important = 0;
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

        // Check for empty value
        if (val_end <= val_start && ctx->check_empty_values) {
            long prop_len = prop_end - prop_start;
            const char *css = RSTRING_PTR(ctx->css_string);
            long error_pos = val_start - css;

            // Build error message
            int display_len = (prop_len > 200) ? 200 : (int)prop_len;
            char error_msg[256];
            snprintf(error_msg, sizeof(error_msg),
                   "Empty value for property '%.*s'",
                   display_len, prop_start);

            // Build keyword args hash
            VALUE kwargs = rb_hash_new();
            rb_hash_aset(kwargs, ID2SYM(rb_intern("css")), ctx->css_string);
            rb_hash_aset(kwargs, ID2SYM(rb_intern("pos")), LONG2NUM(error_pos));
            rb_hash_aset(kwargs, ID2SYM(rb_intern("type")), ID2SYM(rb_intern("empty_value")));

            // Create ParseError instance: ParseError.new(message, **kwargs)
            VALUE msg_str = rb_str_new_cstr(error_msg);
            VALUE argv[2] = {msg_str, kwargs};
            VALUE error = rb_funcallv_kw(eParseError, rb_intern("new"), 2, argv, RB_PASS_KEYWORDS);

            // Raise the error
            rb_exc_raise(error);
        }

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

            // Create property string - use UTF-8 to support custom properties with Unicode
            VALUE property = rb_utf8_str_new(prop_start, prop_len);
            // Custom properties (--foo) are case-sensitive and can contain Unicode
            // Regular properties are ASCII-only and case-insensitive
            if (!(prop_len >= 2 && prop_start[0] == '-' && prop_start[1] == '-')) {
                // Regular property: force ASCII encoding and lowercase
                rb_enc_associate(property, rb_usascii_encoding());
                property = lowercase_property(property);
            }
            VALUE value = rb_utf8_str_new(val_start, val_len);

            // Convert relative URLs to absolute if enabled
            if (ctx && ctx->absolute_paths && !NIL_P(ctx->base_uri)) {
                value = convert_urls_in_value(value, ctx->base_uri, ctx->uri_resolver);
            }

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
                                 VALUE parent_media_sym, VALUE parent_selector, VALUE parent_rule_id, int parent_media_query_id);
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
                                VALUE parent_selector, VALUE parent_rule_id, VALUE parent_media_sym, int parent_media_query_id) {
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

            // Extract media query string
            const char *media_query_start = media_start;
            const char *media_query_end_trimmed = media_query_end;
            trim_trailing(media_query_start, &media_query_end_trimmed);

            // Parse media query and create MediaQuery object
            const char *mq_ptr = media_query_start;
            VALUE media_type;
            VALUE media_conditions = Qnil;

            if (*mq_ptr == '(') {
                // Starts with '(' - just conditions, type defaults to :all
                media_type = ID2SYM(rb_intern("all"));
                media_conditions = rb_utf8_str_new(mq_ptr, media_query_end_trimmed - mq_ptr);
            } else {
                // Extract media type (first word)
                const char *type_start = mq_ptr;
                while (mq_ptr < media_query_end_trimmed && !IS_WHITESPACE(*mq_ptr) && *mq_ptr != '(') mq_ptr++;
                VALUE type_str = rb_utf8_str_new(type_start, mq_ptr - type_start);
                media_type = ID2SYM(rb_intern_str(type_str));

                // Skip "and" keyword if present
                while (mq_ptr < media_query_end_trimmed && IS_WHITESPACE(*mq_ptr)) mq_ptr++;
                if (mq_ptr + 3 <= media_query_end_trimmed && strncmp(mq_ptr, "and", 3) == 0) {
                    mq_ptr += 3;
                    while (mq_ptr < media_query_end_trimmed && IS_WHITESPACE(*mq_ptr)) mq_ptr++;
                }
                if (mq_ptr < media_query_end_trimmed) {
                    media_conditions = rb_utf8_str_new(mq_ptr, media_query_end_trimmed - mq_ptr);
                }
            }

            // Create MediaQuery object
            VALUE media_query = rb_struct_new(cMediaQuery,
                INT2FIX(ctx->media_query_id_counter),
                media_type,
                media_conditions
            );
            rb_ary_push(ctx->media_queries, media_query);
            int nested_media_query_id = ctx->media_query_id_counter;
            ctx->media_query_id_counter++;

            p = media_query_end + 1;  // Skip {

            // Find matching closing brace
            const char *media_block_start = p;
            const char *media_block_end = find_matching_brace_strict(p, end, ctx->check_unclosed_blocks);
            p = media_block_end;

            if (p < end) p++;  // Skip }

            // Handle combining media queries when parent has media too
            int combined_media_query_id = nested_media_query_id;
            if (parent_media_query_id >= 0) {
                // Get parent MediaQuery
                VALUE parent_mq = rb_ary_entry(ctx->media_queries, parent_media_query_id);

                // This should never happen - parent_media_query_id should always be valid
                if (NIL_P(parent_mq)) {
                    rb_raise(eParseError,
                        "Invalid parent_media_query_id: %d (not found in media_queries array)",
                        parent_media_query_id);
                }

                VALUE parent_type = rb_struct_aref(parent_mq, INT2FIX(1)); // type field
                VALUE parent_conditions = rb_struct_aref(parent_mq, INT2FIX(2)); // conditions field

                // Combine: parent conditions + " and " + child conditions
                VALUE combined_conditions;
                if (!NIL_P(parent_conditions) && !NIL_P(media_conditions)) {
                    combined_conditions = rb_str_new_cstr("");
                    rb_str_append(combined_conditions, parent_conditions);
                    rb_str_cat2(combined_conditions, " and ");
                    rb_str_append(combined_conditions, media_conditions);
                } else if (!NIL_P(parent_conditions)) {
                    combined_conditions = parent_conditions;
                } else {
                    combined_conditions = media_conditions;
                }

                // Determine combined type (if parent is :all, use child type; if child is :all, use parent type; if both have types, use parent type)
                VALUE combined_type;
                ID all_id = rb_intern("all");
                if (SYM2ID(parent_type) == all_id) {
                    combined_type = media_type;
                } else {
                    combined_type = parent_type;
                }

                // Create combined MediaQuery
                VALUE combined_mq = rb_struct_new(cMediaQuery,
                    INT2FIX(ctx->media_query_id_counter),
                    combined_type,
                    combined_conditions
                );
                rb_ary_push(ctx->media_queries, combined_mq);
                combined_media_query_id = ctx->media_query_id_counter;
                ctx->media_query_id_counter++;

                // Guard combined_conditions since we built it with rb_str_new_cstr/rb_str_append
                // and it's used in rb_struct_new above (rb_ary_push could trigger GC)
                RB_GC_GUARD(combined_conditions);
            }

            // Parse the block with parse_mixed_block to support further nesting
            // Create a rule ID for this media rule
            int media_rule_id = ctx->rule_id_counter++;

            // Reserve position for parent rule
            long parent_pos = RARRAY_LEN(ctx->rules_array);
            rb_ary_push(ctx->rules_array, Qnil);

            // Parse mixed block (may contain declarations and/or nested @media)
            ctx->depth++;
            VALUE media_declarations = parse_mixed_block(ctx, media_block_start, media_block_end,
                                                        parent_selector, INT2FIX(media_rule_id), Qnil, combined_media_query_id);
            ctx->depth--;

            // Create rule with the parent selector and declarations, associated with combined media query
            VALUE media_query_id_val = INT2FIX(combined_media_query_id);
            VALUE rule = rb_struct_new(cRule,
                INT2FIX(media_rule_id),
                parent_selector,
                media_declarations,
                Qnil,  // specificity
                parent_rule_id,  // Link to parent for nested @media serialization
                Qnil,  // nesting_style (nil for @media nesting)
                Qnil,  // selector_list_id
                media_query_id_val  // media_query_id from parent context
            );

            // Mark that we have nesting (only set once)
            if (!ctx->has_nesting && !NIL_P(parent_rule_id)) {
                ctx->has_nesting = 1;
            }

            // Replace placeholder with actual rule
            rb_ary_store(ctx->rules_array, parent_pos, rule);

            // Update media_index using the MediaQuery's type symbol
            VALUE combined_mq = rb_ary_entry(ctx->media_queries, combined_media_query_id);
            if (!NIL_P(combined_mq)) {
                VALUE mq_type = rb_struct_aref(combined_mq, INT2FIX(1)); // type field
                update_media_index(ctx, mq_type, media_rule_id);
            }

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
            const char *nested_block_end = find_matching_brace_strict(p, end, ctx->check_unclosed_blocks);
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

                        // Reserve position in rules array (ensures sequential IDs match array indices)
                        long rule_position = RARRAY_LEN(ctx->rules_array);
                        rb_ary_push(ctx->rules_array, Qnil);  // Placeholder

                        // Recursively parse nested block
                        ctx->depth++;
                        VALUE nested_declarations = parse_mixed_block(ctx, nested_block_start, nested_block_end,
                                                                     resolved_selector, INT2FIX(rule_id), parent_media_sym, parent_media_query_id);
                        ctx->depth--;

                        // Create rule for nested selector
                        VALUE media_query_id_val = (parent_media_query_id >= 0) ? INT2FIX(parent_media_query_id) : Qnil;
                        VALUE rule = rb_struct_new(cRule,
                            INT2FIX(rule_id),
                            resolved_selector,
                            nested_declarations,
                            Qnil,  // specificity
                            parent_rule_id,
                            nesting_style,
                            Qnil,  // selector_list_id
                            media_query_id_val  // media_query_id from parent context
                        );

                        // Mark that we have nesting (only set once)
                        if (!ctx->has_nesting && !NIL_P(parent_rule_id)) {
                            ctx->has_nesting = 1;
                        }

                        // Replace placeholder with actual rule
                        rb_ary_store(ctx->rules_array, rule_position, rule);
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
        BOOLEAN important = 0;

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

            // Create property string - use UTF-8 to support custom properties with Unicode
            VALUE property = rb_utf8_str_new(prop_start, prop_len);
            // Custom properties (--foo) are case-sensitive and can contain Unicode
            // Regular properties are ASCII-only and case-insensitive
            if (!(prop_len >= 2 && prop_start[0] == '-' && prop_start[1] == '-')) {
                // Regular property: force ASCII encoding and lowercase
                rb_enc_associate(property, rb_usascii_encoding());
                property = lowercase_property(property);
            }
            VALUE value = rb_utf8_str_new(val_start, val_len);

            // Convert relative URLs to absolute if enabled
            if (ctx->absolute_paths && !NIL_P(ctx->base_uri)) {
                value = convert_urls_in_value(value, ctx->base_uri, ctx->uri_resolver);
            }

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
    VALUE media_query_id_val = Qnil;
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
            // media field should be a String, not a Symbol
            media = rb_utf8_str_new(media_start, media_end - media_start);

            // Split comma-separated media queries (same as @media blocks)
            VALUE media_query_ids = rb_ary_new();

            const char *query_start = media_start;
            for (const char *p_comma = media_start; p_comma <= media_end; p_comma++) {
                if (p_comma == media_end || *p_comma == ',') {
                    const char *query_end = p_comma;

                    // Trim whitespace from this query
                    while (query_start < query_end && IS_WHITESPACE(*query_start)) query_start++;
                    while (query_end > query_start && IS_WHITESPACE(*(query_end - 1))) query_end--;

                    if (query_start < query_end) {
                        // Parse this individual media query
                        const char *mq_ptr = query_start;
                        VALUE media_type;
                        VALUE media_conditions = Qnil;

                        if (*mq_ptr == '(') {
                            // Starts with '(' - just conditions, type defaults to :all
                            media_type = ID2SYM(rb_intern("all"));
                            media_conditions = rb_utf8_str_new(mq_ptr, query_end - mq_ptr);
                        } else {
                            // Extract media type (first word)
                            const char *type_start = mq_ptr;
                            while (mq_ptr < query_end && !IS_WHITESPACE(*mq_ptr) && *mq_ptr != '(') mq_ptr++;
                            VALUE type_str = rb_utf8_str_new(type_start, mq_ptr - type_start);
                            media_type = ID2SYM(rb_intern_str(type_str));

                            // Skip whitespace
                            while (mq_ptr < query_end && IS_WHITESPACE(*mq_ptr)) mq_ptr++;

                            // Check if there are conditions (rest of string)
                            if (mq_ptr < query_end) {
                                media_conditions = rb_utf8_str_new(mq_ptr, query_end - mq_ptr);
                            }
                        }

                        // Create MediaQuery struct
                        VALUE media_query = rb_struct_new(cMediaQuery,
                            INT2FIX(ctx->media_query_id_counter),
                            media_type,
                            media_conditions
                        );

                        rb_ary_push(ctx->media_queries, media_query);
                        rb_ary_push(media_query_ids, INT2FIX(ctx->media_query_id_counter));
                        ctx->media_query_id_counter++;
                    }

                    // Move to start of next query
                    query_start = p_comma + 1;
                }
            }

            // If multiple queries, track them as a list
            if (RARRAY_LEN(media_query_ids) > 1) {
                int media_query_list_id = ctx->next_media_query_list_id;
                rb_hash_aset(ctx->media_query_lists, INT2FIX(media_query_list_id), media_query_ids);
                ctx->next_media_query_list_id++;
            }

            // Use first query ID for the import statement
            media_query_id_val = rb_ary_entry(media_query_ids, 0);
        }
    }

    // Skip semicolon
    if (p < pe && *p == ';') p++;

    // Create ImportStatement (resolved: false by default)
    VALUE import_stmt = rb_struct_new(cImportStatement,
        INT2FIX(ctx->rule_id_counter),
        url,
        media,
        media_query_id_val,
        Qfalse);

    DEBUG_PRINTF("[IMPORT_STMT] Created import: id=%d, url=%s, media=%s\n",
                 ctx->rule_id_counter,
                 RSTRING_PTR(url),
                 NIL_P(media) ? "nil" : RSTRING_PTR(media));

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
                                 VALUE parent_media_sym, VALUE parent_selector, VALUE parent_rule_id, int parent_media_query_id) {
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

            // Check for empty media query
            if (mq_end <= mq_start) {
                if (ctx->check_malformed_at_rules) {
                    raise_parse_error_at(ctx, mq_start, "Malformed @media: missing media query", "malformed_at_rule");
                } else {
                    // Empty media query with check disabled - skip @media wrapper and parse contents as regular rules
                    if (p >= pe || *p != '{') {
                        continue;  // Malformed structure
                    }
                    p++;  // Skip opening {
                    const char *block_start = p;
                    const char *block_end = find_matching_brace_strict(p, pe, ctx->check_unclosed_blocks);
                    p = block_end;

                    // Parse block contents with NO media query context
                    ctx->depth++;
                    parse_css_recursive(ctx, block_start, block_end, parent_media_sym, NO_PARENT_SELECTOR, NO_PARENT_RULE_ID, parent_media_query_id);
                    ctx->depth--;

                    if (p < pe && *p == '}') p++;
                    continue;
                }
            }

            if (p >= pe || *p != '{') {
                continue;  // Malformed
            }

            // Split comma-separated media queries (e.g., "screen, print" -> ["screen", "print"])
            // Per W3C spec, comma acts as logical OR - each query is independent
            VALUE media_query_ids = rb_ary_new();

            const char *query_start = mq_start;
            for (const char *p_comma = mq_start; p_comma <= mq_end; p_comma++) {
                if (p_comma == mq_end || *p_comma == ',') {
                    const char *query_end = p_comma;

                    // Trim whitespace from this query
                    while (query_start < query_end && IS_WHITESPACE(*query_start)) query_start++;
                    while (query_end > query_start && IS_WHITESPACE(*(query_end - 1))) query_end--;

                    if (query_start < query_end) {
                        // Parse this individual media query
                        const char *mq_ptr = query_start;
                        VALUE media_type;
                        VALUE media_conditions = Qnil;

                        if (*mq_ptr == '(') {
                            // Starts with '(' - just conditions, type defaults to :all
                            media_type = ID2SYM(rb_intern("all"));
                            media_conditions = rb_utf8_str_new(mq_ptr, query_end - mq_ptr);
                        } else {
                            // Extract media type (first word, stopping at whitespace, comma, or '(')
                            const char *type_start = mq_ptr;
                            while (mq_ptr < query_end && !IS_WHITESPACE(*mq_ptr) && *mq_ptr != '(') mq_ptr++;
                            VALUE type_str = rb_utf8_str_new(type_start, mq_ptr - type_start);
                            media_type = ID2SYM(rb_intern_str(type_str));

                            // Skip whitespace and "and" keyword if present
                            while (mq_ptr < query_end && IS_WHITESPACE(*mq_ptr)) mq_ptr++;
                            if (mq_ptr + 3 <= query_end && strncmp(mq_ptr, "and", 3) == 0) {
                                mq_ptr += 3;
                                while (mq_ptr < query_end && IS_WHITESPACE(*mq_ptr)) mq_ptr++;
                            }

                            // Rest is conditions
                            if (mq_ptr < query_end) {
                                media_conditions = rb_utf8_str_new(mq_ptr, query_end - mq_ptr);
                            }
                        }

                        // Create MediaQuery object for this query
                        VALUE media_query = rb_struct_new(cMediaQuery,
                            INT2FIX(ctx->media_query_id_counter),
                            media_type,
                            media_conditions
                        );
                        rb_ary_push(ctx->media_queries, media_query);
                        rb_ary_push(media_query_ids, INT2FIX(ctx->media_query_id_counter));
                        ctx->media_query_id_counter++;
                    }

                    // Move to start of next query
                    query_start = p_comma + 1;
                }
            }

            // If multiple queries, track them as a list for serialization
            int media_query_list_id = -1;
            if (RARRAY_LEN(media_query_ids) > 1) {
                media_query_list_id = ctx->next_media_query_list_id;
                rb_hash_aset(ctx->media_query_lists, INT2FIX(media_query_list_id), media_query_ids);
                ctx->next_media_query_list_id++;
            }

            // Use first query ID as the primary one for rules in this block
            int current_media_query_id = FIX2INT(rb_ary_entry(media_query_ids, 0));

            // Handle nested @media by combining with parent
            if (parent_media_query_id >= 0) {
                VALUE parent_mq = rb_ary_entry(ctx->media_queries, parent_media_query_id);
                VALUE parent_type = rb_struct_aref(parent_mq, INT2FIX(1)); // type field
                VALUE parent_conditions = rb_struct_aref(parent_mq, INT2FIX(2)); // conditions field

                // Get child media query (first one in the list)
                VALUE child_mq = rb_ary_entry(ctx->media_queries, current_media_query_id);
                VALUE child_conditions = rb_struct_aref(child_mq, INT2FIX(2)); // conditions field

                // Combined type is parent's type (outermost wins, child type ignored)
                VALUE combined_type = parent_type;
                VALUE combined_conditions;

                if (!NIL_P(parent_conditions) && !NIL_P(child_conditions)) {
                    combined_conditions = rb_sprintf("%"PRIsVALUE" and %"PRIsVALUE, parent_conditions, child_conditions);
                } else if (!NIL_P(parent_conditions)) {
                    combined_conditions = parent_conditions;
                } else {
                    combined_conditions = child_conditions;
                }

                VALUE combined_mq = rb_struct_new(cMediaQuery,
                    INT2FIX(ctx->media_query_id_counter),
                    combined_type,
                    combined_conditions
                );
                rb_ary_push(ctx->media_queries, combined_mq);
                current_media_query_id = ctx->media_query_id_counter;
                ctx->media_query_id_counter++;
            }

            // For backwards compat, also create symbol (will be removed later)
            VALUE child_media_sym = intern_media_query_safe(ctx, mq_start, mq_end - mq_start);
            VALUE combined_media_sym = combine_media_queries(parent_media_sym, child_media_sym);

            p++;  // Skip opening {

            // Find matching closing brace
            const char *block_start = p;
            const char *block_end = find_matching_brace_strict(p, pe, ctx->check_unclosed_blocks);
            p = block_end;

            // Recursively parse @media block with new media query context
            ctx->depth++;
            parse_css_recursive(ctx, block_start, block_end, combined_media_sym, NO_PARENT_SELECTOR, NO_PARENT_RULE_ID, current_media_query_id);
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
            BOOLEAN is_conditional_group =
                (at_name_len == 8 && strncmp(at_start, "supports", 8) == 0) ||
                (at_name_len == 5 && strncmp(at_start, "layer", 5) == 0) ||
                (at_name_len == 9 && strncmp(at_start, "container", 9) == 0) ||
                (at_name_len == 5 && strncmp(at_start, "scope", 5) == 0);

            if (is_conditional_group) {
                // Check if this rule requires a condition
                BOOLEAN requires_condition =
                    (at_name_len == 8 && strncmp(at_start, "supports", 8) == 0) ||
                    (at_name_len == 9 && strncmp(at_start, "container", 9) == 0);

                // Extract condition (between at-rule name and opening brace)
                const char *cond_start = at_name_end;
                while (cond_start < pe && IS_WHITESPACE(*cond_start)) cond_start++;

                // Skip to opening brace
                p = at_name_end;
                while (p < pe && *p != '{') p++;

                if (p >= pe || *p != '{') {
                    continue;  // Malformed
                }

                // Trim condition
                const char *cond_end = p;
                while (cond_end > cond_start && IS_WHITESPACE(*(cond_end - 1))) cond_end--;

                // Check for missing condition
                if (requires_condition && cond_end <= cond_start && ctx->check_malformed_at_rules) {
                    char error_msg[100];
                    snprintf(error_msg, sizeof(error_msg), "Malformed @%.*s: missing condition", (int)at_name_len, at_start);
                    raise_parse_error_at(ctx, at_start - 1, error_msg, "malformed_at_rule");
                }

                p++;  // Skip opening {

                // Find matching closing brace
                const char *block_start = p;
                const char *block_end = find_matching_brace_strict(p, pe, ctx->check_unclosed_blocks);
                p = block_end;

                // Recursively parse block content (preserve parent media context)
                ctx->depth++;
                parse_css_recursive(ctx, block_start, block_end, parent_media_sym, parent_selector, parent_rule_id, parent_media_query_id);
                ctx->depth--;

                if (p < pe && *p == '}') p++;
                continue;
            }

            // Check for @keyframes (contains <rule-list>)
            // TODO: Test perf gains by using RB_UNLIKELY(is_keyframes) wrapper
            BOOLEAN is_keyframes =
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
                const char *block_end = find_matching_brace_strict(p, pe, ctx->check_unclosed_blocks);
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
                parse_css_recursive(&nested_ctx, block_start, block_end, NO_PARENT_MEDIA, NO_PARENT_SELECTOR, NO_PARENT_RULE_ID, NO_MEDIA_QUERY_ID);

                // Get rule ID and increment
                int rule_id = ctx->rule_id_counter++;

                // Create AtRule with nested rules
                VALUE at_rule = rb_struct_new(cAtRule,
                    INT2FIX(rule_id),
                    selector,
                    nested_ctx.rules_array,  // Array of Rule (keyframe blocks)
                    Qnil,  // specificity
                    Qnil   // media_query_id
                );

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
            BOOLEAN is_font_face = (at_name_len == 9 && strncmp(at_start, "font-face", 9) == 0);

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
                const char *decl_end = find_matching_brace_strict(p, pe, ctx->check_unclosed_blocks);
                p = decl_end;

                // Parse declarations
                VALUE declarations = parse_declarations(decl_start, decl_end, ctx);

                // Get rule ID and increment
                int rule_id = ctx->rule_id_counter++;

                // Create AtRule with declarations
                VALUE at_rule = rb_struct_new(cAtRule,
                    INT2FIX(rule_id),
                    selector,
                    declarations,  // Array of Declaration
                    Qnil,  // specificity
                    Qnil   // media_query_id
                );

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
            // Check for empty selector (opening brace with no selector before it)
            if (ctx->check_invalid_selectors && brace_depth == 0 && selector_start == NULL) {
                raise_parse_error_at(ctx, p, "Invalid selector: empty selector", "invalid_selector");
            }
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
                BOOLEAN has_nesting = has_nested_selectors(decl_start, p);

                // Get selector string
                const char *sel_end = decl_start - 1;
                while (sel_end > selector_start && IS_WHITESPACE(*(sel_end - 1))) {
                    sel_end--;
                }

                // Check for empty selector
                if (ctx->check_invalid_selectors && sel_end <= selector_start) {
                    const char *css = RSTRING_PTR(ctx->css_string);
                    long error_pos = selector_start - css;

                    // Build keyword args hash
                    VALUE kwargs = rb_hash_new();
                    rb_hash_aset(kwargs, ID2SYM(rb_intern("css")), ctx->css_string);
                    rb_hash_aset(kwargs, ID2SYM(rb_intern("pos")), LONG2NUM(error_pos));
                    rb_hash_aset(kwargs, ID2SYM(rb_intern("type")), ID2SYM(rb_intern("invalid_selector")));

                    VALUE msg_str = rb_str_new_cstr("Invalid selector: empty selector");
                    VALUE argv[2] = {msg_str, kwargs};
                    VALUE error = rb_funcallv_kw(eParseError, rb_intern("new"), 2, argv, RB_PASS_KEYWORDS);
                    rb_exc_raise(error);
                }

                if (!has_nesting) {
                    // FAST PATH: No nesting - parse as pure declarations
                    VALUE declarations = parse_declarations(decl_start, p, ctx);

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
                                // Check for invalid selectors
                                if (ctx->check_invalid_selectors) {
                                    // Check if selector starts with combinator
                                    char first_char = *seg_start;
                                    if (first_char == '>' || first_char == '+' || first_char == '~') {
                                        const char *css = RSTRING_PTR(ctx->css_string);
                                        long error_pos = seg_start - css;

                                        char error_msg[256];
                                        snprintf(error_msg, sizeof(error_msg),
                                               "Invalid selector: selector cannot start with combinator '%c'",
                                               first_char);

                                        // Build keyword args hash
                                        VALUE kwargs = rb_hash_new();
                                        rb_hash_aset(kwargs, ID2SYM(rb_intern("css")), ctx->css_string);
                                        rb_hash_aset(kwargs, ID2SYM(rb_intern("pos")), LONG2NUM(error_pos));
                                        rb_hash_aset(kwargs, ID2SYM(rb_intern("type")), ID2SYM(rb_intern("invalid_selector")));

                                        VALUE msg_str = rb_str_new_cstr(error_msg);
                                        VALUE argv[2] = {msg_str, kwargs};
                                        VALUE error = rb_funcallv_kw(eParseError, rb_intern("new"), 2, argv, RB_PASS_KEYWORDS);
                                        rb_exc_raise(error);
                                    }
                                }

                                // Check for invalid selector syntax (whitelist validation)
                                if (ctx->check_invalid_selector_syntax && !is_valid_selector(seg_start, seg_end_ptr)) {
                                    raise_parse_error_at(ctx, seg_start, "Invalid selector syntax: selector contains invalid characters", "invalid_selector_syntax");
                                }

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

                                // Deep copy declarations for selector lists to avoid shared state
                                // (principle of least surprise - modifying one rule shouldn't affect others)
                                VALUE rule_declarations;
                                if (list_id >= 0) {
                                    // Deep copy: both array and Declaration structs inside
                                    long decl_count = RARRAY_LEN(declarations);
                                    rule_declarations = rb_ary_new_capa(decl_count);
                                    for (long k = 0; k < decl_count; k++) {
                                        VALUE decl = rb_ary_entry(declarations, k);
                                        VALUE new_decl = rb_struct_new(cDeclaration,
                                            rb_struct_aref(decl, INT2FIX(DECL_PROPERTY)),
                                            rb_struct_aref(decl, INT2FIX(DECL_VALUE)),
                                            rb_struct_aref(decl, INT2FIX(DECL_IMPORTANT))
                                        );
                                        rb_ary_push(rule_declarations, new_decl);
                                    }
                                } else {
                                    rule_declarations = rb_ary_dup(declarations);
                                }

                                // Create Rule
                                VALUE media_query_id_val = (parent_media_query_id >= 0) ? INT2FIX(parent_media_query_id) : Qnil;
                                VALUE rule = rb_struct_new(cRule,
                                    INT2FIX(rule_id),
                                    resolved_selector,
                                    rule_declarations,
                                    Qnil,  // specificity
                                    parent_id_val,
                                    nesting_style_val,
                                    selector_list_id_val,
                                    media_query_id_val  // media_query_id from parent context
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
                            } else if (ctx->check_invalid_selector_syntax && selector_count > 1) {
                                // Empty selector in comma-separated list (e.g., "h1, , h3")
                                raise_parse_error_at(ctx, seg_start, "Invalid selector syntax: empty selector in comma-separated list", "invalid_selector_syntax");
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
                                                                             resolved_current, INT2FIX(current_rule_id), parent_media_sym, parent_media_query_id);
                                ctx->depth--;

                                // Determine selector_list_id value
                                VALUE selector_list_id_val = (list_id >= 0) ? INT2FIX(list_id) : Qnil;

                                // Create parent rule and replace placeholder
                                // Always create the rule (even if empty) to avoid edge cases
                                VALUE media_query_id_val = (parent_media_query_id >= 0) ? INT2FIX(parent_media_query_id) : Qnil;
                                VALUE rule = rb_struct_new(cRule,
                                    INT2FIX(current_rule_id),
                                    resolved_current,
                                    parent_declarations,
                                    Qnil,  // specificity
                                    current_parent_id,
                                    current_nesting_style,
                                    selector_list_id_val,
                                    media_query_id_val  // media_query_id from parent context
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

    // Check for unclosed blocks at end of parsing
    if (ctx->check_unclosed_blocks && brace_depth > 0) {
        rb_raise(eParseError, "Unclosed block: missing closing brace");
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
    BOOLEAN selector_lists_enabled = (NIL_P(selector_lists_opt) || RTEST(selector_lists_opt)) ? 1 : 0;

    // URL conversion options
    VALUE base_uri = rb_hash_aref(parser_options, ID2SYM(rb_intern("base_uri")));
    VALUE absolute_paths_opt = rb_hash_aref(parser_options, ID2SYM(rb_intern("absolute_paths")));
    VALUE uri_resolver = rb_hash_aref(parser_options, ID2SYM(rb_intern("uri_resolver")));
    BOOLEAN absolute_paths = RTEST(absolute_paths_opt) ? 1 : 0;

    // Parse error options
    VALUE raise_parse_errors_opt = rb_hash_aref(parser_options, ID2SYM(rb_intern("raise_parse_errors")));
    BOOLEAN check_empty_values = 0;
    BOOLEAN check_malformed_declarations = 0;
    BOOLEAN check_invalid_selectors = 0;
    BOOLEAN check_invalid_selector_syntax = 0;
    BOOLEAN check_malformed_at_rules = 0;
    BOOLEAN check_unclosed_blocks = 0;

    if (RTEST(raise_parse_errors_opt)) {
        if (TYPE(raise_parse_errors_opt) == T_HASH) {
            // Hash of specific error types
            VALUE empty_values_opt = rb_hash_aref(raise_parse_errors_opt, ID2SYM(rb_intern("empty_values")));
            VALUE malformed_declarations_opt = rb_hash_aref(raise_parse_errors_opt, ID2SYM(rb_intern("malformed_declarations")));
            VALUE invalid_selectors_opt = rb_hash_aref(raise_parse_errors_opt, ID2SYM(rb_intern("invalid_selectors")));
            VALUE invalid_selector_syntax_opt = rb_hash_aref(raise_parse_errors_opt, ID2SYM(rb_intern("invalid_selector_syntax")));
            VALUE malformed_at_rules_opt = rb_hash_aref(raise_parse_errors_opt, ID2SYM(rb_intern("malformed_at_rules")));
            VALUE unclosed_blocks_opt = rb_hash_aref(raise_parse_errors_opt, ID2SYM(rb_intern("unclosed_blocks")));
            check_empty_values = RTEST(empty_values_opt) ? 1 : 0;
            check_malformed_declarations = RTEST(malformed_declarations_opt) ? 1 : 0;
            check_invalid_selectors = RTEST(invalid_selectors_opt) ? 1 : 0;
            check_invalid_selector_syntax = RTEST(invalid_selector_syntax_opt) ? 1 : 0;
            check_malformed_at_rules = RTEST(malformed_at_rules_opt) ? 1 : 0;
            check_unclosed_blocks = RTEST(unclosed_blocks_opt) ? 1 : 0;
        } else {
            // true - enable all checks
            check_empty_values = 1;
            check_malformed_declarations = 1;
            check_invalid_selectors = 1;
            check_invalid_selector_syntax = 1;
            check_malformed_at_rules = 1;
            check_unclosed_blocks = 1;
        }
    }

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
    ctx.media_queries = rb_ary_new();
    ctx.media_query_lists = rb_hash_new();
    ctx.rule_id_counter = rule_id_offset;  // Start from offset
    ctx.next_selector_list_id = 0;  // Start from 0
    ctx.media_query_id_counter = 0;  // Start from 0
    ctx.next_media_query_list_id = 0;  // Start from 0
    ctx.media_query_count = 0;
    ctx.media_cache = NULL;  // Removed - no perf benefit
    ctx.has_nesting = 0;  // Will be set to 1 if any nested rules are created
    ctx.selector_lists_enabled = selector_lists_enabled;
    ctx.depth = 0;  // Start at depth 0
    // URL conversion options
    ctx.base_uri = base_uri;
    ctx.uri_resolver = uri_resolver;
    ctx.absolute_paths = absolute_paths;
    // Parse error options
    ctx.css_string = css_string;
    ctx.check_empty_values = check_empty_values;
    ctx.check_malformed_declarations = check_malformed_declarations;
    ctx.check_invalid_selectors = check_invalid_selectors;
    ctx.check_invalid_selector_syntax = check_invalid_selector_syntax;
    ctx.check_malformed_at_rules = check_malformed_at_rules;
    ctx.check_unclosed_blocks = check_unclosed_blocks;

    // Parse CSS (top-level, no parent context)
    DEBUG_PRINTF("[PARSE] Starting parse_css_recursive from: %.80s\n", p);
    parse_css_recursive(&ctx, p, pe, NO_PARENT_MEDIA, NO_PARENT_SELECTOR, NO_PARENT_RULE_ID, NO_MEDIA_QUERY_ID);

    // Build result hash
    VALUE result = rb_hash_new();
    rb_hash_aset(result, ID2SYM(rb_intern("rules")), ctx.rules_array);
    rb_hash_aset(result, ID2SYM(rb_intern("_media_index")), ctx.media_index);
    rb_hash_aset(result, ID2SYM(rb_intern("media_queries")), ctx.media_queries);
    rb_hash_aset(result, ID2SYM(rb_intern("_selector_lists")), ctx.selector_lists);
    rb_hash_aset(result, ID2SYM(rb_intern("_media_query_lists")), ctx.media_query_lists);
    rb_hash_aset(result, ID2SYM(rb_intern("imports")), ctx.imports_array);
    rb_hash_aset(result, ID2SYM(rb_intern("charset")), charset);
    rb_hash_aset(result, ID2SYM(rb_intern("last_rule_id")), INT2FIX(ctx.rule_id_counter));
    rb_hash_aset(result, ID2SYM(rb_intern("_has_nesting")), ctx.has_nesting ? Qtrue : Qfalse);

    RB_GC_GUARD(charset);
    RB_GC_GUARD(ctx.rules_array);
    RB_GC_GUARD(ctx.media_index);
    RB_GC_GUARD(ctx.media_queries);
    RB_GC_GUARD(ctx.selector_lists);
    RB_GC_GUARD(ctx.media_query_lists);
    RB_GC_GUARD(ctx.imports_array);
    RB_GC_GUARD(ctx.base_uri);
    RB_GC_GUARD(ctx.uri_resolver);
    RB_GC_GUARD(result);

    return result;
}
