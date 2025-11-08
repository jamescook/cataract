/*
 * specificity.c - CSS selector specificity calculator
 *
 * Calculates CSS selector specificity according to W3C spec:
 * https://www.w3.org/TR/selectors/#specificity
 *
 * Specificity = a*100 + b*10 + c*1 where:
 *   a = count of ID selectors (#id)
 *   b = count of class selectors (.class), attributes ([attr]), and pseudo-classes (:hover)
 *   c = count of type selectors (div) and pseudo-elements (::before)
 *
 * Special handling:
 *   - :not() doesn't count itself, but its content does
 *   - Legacy pseudo-elements with single colon (:before) count as pseudo-elements
 *   - Universal selector (*) has zero specificity
 */

#include "cataract_new.h"
#include <string.h>

// Calculate specificity for a CSS selector string
VALUE calculate_specificity(VALUE self, VALUE selector_string) {
    Check_Type(selector_string, T_STRING);

    const char *p = RSTRING_PTR(selector_string);
    const char *pe = p + RSTRING_LEN(selector_string);

    // Counters for specificity components
    int id_count = 0;
    int class_count = 0;
    int attr_count = 0;
    int pseudo_class_count = 0;
    int pseudo_element_count = 0;
    int element_count = 0;

    while (p < pe) {
        char c = *p;

        // Skip whitespace and combinators
        if (IS_WHITESPACE(c) || c == '>' || c == '+' || c == '~' || c == ',') {
            p++;
            continue;
        }

        // ID selector: #id
        if (c == '#') {
            id_count++;
            p++;
            // Skip the identifier
            while (p < pe && ((*p >= 'a' && *p <= 'z') || (*p >= 'A' && *p <= 'Z') ||
                              (*p >= '0' && *p <= '9') || *p == '-' || *p == '_')) {
                p++;
            }
            continue;
        }

        // Class selector: .class
        if (c == '.') {
            class_count++;
            p++;
            // Skip the identifier
            while (p < pe && ((*p >= 'a' && *p <= 'z') || (*p >= 'A' && *p <= 'Z') ||
                              (*p >= '0' && *p <= '9') || *p == '-' || *p == '_')) {
                p++;
            }
            continue;
        }

        // Attribute selector: [attr] or [attr=value]
        if (c == '[') {
            attr_count++;
            p++;
            // Skip to closing bracket
            int bracket_depth = 1;
            while (p < pe && bracket_depth > 0) {
                if (*p == '[') bracket_depth++;
                else if (*p == ']') bracket_depth--;
                p++;
            }
            continue;
        }

        // Pseudo-element (::) or pseudo-class (:)
        if (c == ':') {
            p++;
            int is_pseudo_element = 0;

            // Check for double colon (::)
            if (p < pe && *p == ':') {
                is_pseudo_element = 1;
                p++;
            }

            // Extract pseudo name
            const char *pseudo_start = p;
            while (p < pe && ((*p >= 'a' && *p <= 'z') || (*p >= 'A' && *p <= 'Z') ||
                              (*p >= '0' && *p <= '9') || *p == '-')) {
                p++;
            }
            long pseudo_len = p - pseudo_start;

            // Check for legacy pseudo-elements (single colon but should be double)
            // :before, :after, :first-line, :first-letter, :selection
            int is_legacy_pseudo_element = 0;
            if (!is_pseudo_element && pseudo_len > 0) {
                is_legacy_pseudo_element =
                    (pseudo_len == 6 && strncmp(pseudo_start, "before", 6) == 0) ||
                    (pseudo_len == 5 && strncmp(pseudo_start, "after", 5) == 0) ||
                    (pseudo_len == 10 && strncmp(pseudo_start, "first-line", 10) == 0) ||
                    (pseudo_len == 12 && strncmp(pseudo_start, "first-letter", 12) == 0) ||
                    (pseudo_len == 9 && strncmp(pseudo_start, "selection", 9) == 0);
            }

            // Check for :not() - it doesn't count itself, but its content does
            int is_not = (pseudo_len == 3 && strncmp(pseudo_start, "not", 3) == 0);

            // Skip function arguments if present
            if (p < pe && *p == '(') {
                p++;
                int paren_depth = 1;

                // If it's :not(), we need to calculate specificity of the content
                if (is_not) {
                    const char *not_content_start = p;

                    // Find closing paren
                    while (p < pe && paren_depth > 0) {
                        if (*p == '(') paren_depth++;
                        else if (*p == ')') paren_depth--;
                        if (paren_depth > 0) p++;
                    }

                    const char *not_content_end = p;
                    long not_content_len = not_content_end - not_content_start;

                    // Recursively calculate specificity of :not() content
                    if (not_content_len > 0) {
                        VALUE not_content = rb_str_new(not_content_start, not_content_len);
                        VALUE not_spec = calculate_specificity(self, not_content);
                        int not_specificity = NUM2INT(not_spec);

                        // Add :not() content's specificity to our counts
                        int additional_a = not_specificity / 100;
                        int additional_b = (not_specificity % 100) / 10;
                        int additional_c = not_specificity % 10;

                        id_count += additional_a;
                        class_count += additional_b;
                        element_count += additional_c;

                        RB_GC_GUARD(not_content);
                        RB_GC_GUARD(not_spec);
                    }

                    p++;  // Skip closing paren
                } else {
                    // Skip other function arguments
                    while (p < pe && paren_depth > 0) {
                        if (*p == '(') paren_depth++;
                        else if (*p == ')') paren_depth--;
                        p++;
                    }

                    // Count the pseudo-class/element
                    if (is_pseudo_element || is_legacy_pseudo_element) {
                        pseudo_element_count++;
                    } else {
                        pseudo_class_count++;
                    }
                }
            } else {
                // No function arguments - count the pseudo-class/element
                if (is_not) {
                    // :not without parens is invalid, but don't count it
                } else if (is_pseudo_element || is_legacy_pseudo_element) {
                    pseudo_element_count++;
                } else {
                    pseudo_class_count++;
                }
            }
            continue;
        }

        // Universal selector: *
        if (c == '*') {
            // Universal selector has specificity 0, don't count
            p++;
            continue;
        }

        // Type selector (element name): div, span, etc.
        if ((*p >= 'a' && *p <= 'z') || (*p >= 'A' && *p <= 'Z')) {
            element_count++;
            // Skip the identifier
            while (p < pe && ((*p >= 'a' && *p <= 'z') || (*p >= 'A' && *p <= 'Z') ||
                              (*p >= '0' && *p <= '9') || *p == '-' || *p == '_')) {
                p++;
            }
            continue;
        }

        // Unknown character, skip it
        p++;
    }

    // Calculate specificity using W3C formula:
    // IDs * 100 + (classes + attributes + pseudo-classes) * 10 + (elements + pseudo-elements) * 1
    int specificity = (id_count * 100) +
                      ((class_count + attr_count + pseudo_class_count) * 10) +
                      ((element_count + pseudo_element_count) * 1);

    return INT2NUM(specificity);
}
