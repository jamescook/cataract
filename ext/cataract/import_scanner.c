#include <ruby.h>
#include <ctype.h>
#include <string.h>
#include "cataract.h"

/*
 * Scan CSS for @import statements
 *
 * Matches patterns:
 *   @import url("path");
 *   @import url('path');
 *   @import "path";
 *   @import 'path';
 *   @import url("path") print;  (with media query)
 *
 * Returns array of hashes: [{url: "...", media: "...", full_match: "..."}]
 */
VALUE extract_imports(VALUE self, VALUE css_string) {
    Check_Type(css_string, T_STRING);

    const char *css = RSTRING_PTR(css_string);
    long css_len = RSTRING_LEN(css_string);

    VALUE imports = rb_ary_new();

    const char *p = css;
    const char *end = css + css_len;

    while (p < end) {
        // Skip whitespace and comments
        while (p < end && IS_WHITESPACE(*p)) p++;

        // Check for @import
        if (p + 7 <= end && strncasecmp(p, "@import", 7) == 0) {
            const char *import_start = p;
            p += 7;

            // Skip whitespace after @import
            while (p < end && IS_WHITESPACE(*p)) p++;

            // Check for optional url(
            int has_url_function = 0;
            if (p + 4 <= end && strncasecmp(p, "url(", 4) == 0) {
                has_url_function = 1;
                p += 4;
                while (p < end && IS_WHITESPACE(*p)) p++;
            }

            // Find opening quote
            if (p >= end || (*p != '"' && *p != '\'')) {
                // Invalid @import, skip to next semicolon
                while (p < end && *p != ';') p++;
                if (p < end) p++; // Skip semicolon
                continue;
            }

            char quote_char = *p;
            p++; // Skip opening quote

            const char *url_start = p;

            // Find closing quote (handle escaped quotes)
            while (p < end && *p != quote_char) {
                if (*p == '\\' && p + 1 < end) {
                    p += 2; // Skip escaped character
                } else {
                    p++;
                }
            }

            if (p >= end) {
                // Unterminated string
                break;
            }

            const char *url_end = p;
            p++; // Skip closing quote

            // Skip closing paren if we had url(
            if (has_url_function) {
                while (p < end && IS_WHITESPACE(*p)) p++;
                if (p < end && *p == ')') {
                    p++;
                }
            }

            // Skip whitespace before optional media query or semicolon
            while (p < end && IS_WHITESPACE(*p)) p++;

            // Check for optional media query (everything until semicolon)
            const char *media_start = NULL;
            const char *media_end = NULL;

            if (p < end && *p != ';') {
                media_start = p;

                // Find semicolon
                while (p < end && *p != ';') p++;

                media_end = p;

                // Trim trailing whitespace from media query
                while (media_end > media_start && IS_WHITESPACE(*(media_end - 1))) {
                    media_end--;
                }
            }

            // Skip semicolon
            if (p < end && *p == ';') p++;

            const char *import_end = p;

            // Build result hash
            VALUE import_hash = rb_hash_new();

            // Extract URL
            VALUE url = rb_str_new(url_start, url_end - url_start);
            rb_hash_aset(import_hash, ID2SYM(rb_intern("url")), url);

            // Extract media query (or nil)
            VALUE media = Qnil;
            if (media_start && media_end > media_start) {
                media = rb_str_new(media_start, media_end - media_start);
            }
            rb_hash_aset(import_hash, ID2SYM(rb_intern("media")), media);

            // Extract full match
            VALUE full_match = rb_str_new(import_start, import_end - import_start);
            rb_hash_aset(import_hash, ID2SYM(rb_intern("full_match")), full_match);

            rb_ary_push(imports, import_hash);

            RB_GC_GUARD(url);
            RB_GC_GUARD(media);
            RB_GC_GUARD(full_match);
            RB_GC_GUARD(import_hash);
        } else {
            // Not an @import, skip to next line or rule
            // Once we hit a non-@import rule (except @charset), stop looking
            // Per CSS spec, @import must be at the top

            // Skip @charset if present
            if (p + 8 <= end && strncasecmp(p, "@charset", 8) == 0) {
                // Skip to semicolon
                while (p < end && *p != ';') p++;
                if (p < end) p++; // Skip semicolon
                continue;
            }

            // If we hit any other content, stop scanning for imports
            if (p < end && !IS_WHITESPACE(*p)) {
                break;
            }

            p++;
        }
    }

    RB_GC_GUARD(imports);
    return imports;
}
