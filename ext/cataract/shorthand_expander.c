/*
 * shorthand_expander.c - CSS shorthand property expansion and creation
 *
 * Handles expansion of shorthand properties (margin, padding, border, etc.)
 * and creation of shorthands from longhand properties.
 *
 * NOTE: value_splitter has been migrated to pure C (value_splitter.c)
 */

#include "cataract.h"

/*
 * Helper: Check if string ends with !important and strip it
 * Returns 1 if important, 0 otherwise
 * Updates len to exclude !important if present
 */
static int check_and_strip_important(const char *str, size_t *len) {
    if (*len < 10) return 0; // Need at least "!important"

    const char *p = str + *len - 1;

    // Skip trailing whitespace
    while (p > str && (*p == ' ' || *p == '\t' || *p == '\n' || *p == '\r')) {
        p--;
    }

    // Check if it ends with "!important" (case-insensitive would be: strncasecmp)
    if (p - str >= 9) {
        if (strncmp(p - 9, "!important", 10) == 0) {
            // Found it - update length to exclude !important and trailing whitespace
            p -= 10;
            while (p >= str && (*p == ' ' || *p == '\t')) p--;
            *len = (p - str) + 1;
            return 1;
        }
    }
    return 0;
}

/*
 * Helper: Expand dimension shorthand (margin, padding, border-color, etc.)
 */
static VALUE expand_dimensions(VALUE parts, const char *property, const char *suffix) {
    long len = RARRAY_LEN(parts);
    VALUE result = rb_hash_new();

    if (len == 0) return result;

    // Sanity check: property and suffix should be reasonable length
    if (strlen(property) > 32) {
        rb_raise(rb_eArgError, "Property name too long (max 32 chars)");
    }
    if (suffix && strlen(suffix) > 32) {
        rb_raise(rb_eArgError, "Suffix name too long (max 32 chars)");
    }

    // Check if last part has !important
    int is_important = 0;
    if (len > 0) {
        VALUE last_part = rb_ary_entry(parts, len - 1);
        const char *last_str = RSTRING_PTR(last_part);
        size_t last_len = RSTRING_LEN(last_part);

        if (check_and_strip_important(last_str, &last_len)) {
            is_important = 1;
            // Update the array with stripped value
            if (last_len > 0) {
                rb_ary_store(parts, len - 1, rb_str_new(last_str, last_len));
            } else {
                // The value was just "!important" - reduce array length
                len--;
            }
        }
    }

    VALUE sides[4];
    if (len == 1) {
        VALUE v = rb_ary_entry(parts, 0);
        sides[0] = sides[1] = sides[2] = sides[3] = v;
    } else if (len == 2) {
        sides[0] = sides[2] = rb_ary_entry(parts, 0); // top, bottom
        sides[1] = sides[3] = rb_ary_entry(parts, 1); // right, left
    } else if (len == 3) {
        sides[0] = rb_ary_entry(parts, 0); // top
        sides[1] = sides[3] = rb_ary_entry(parts, 1); // right, left
        sides[2] = rb_ary_entry(parts, 2); // bottom
    } else if (len == 4) {
        sides[0] = rb_ary_entry(parts, 0);
        sides[1] = rb_ary_entry(parts, 1);
        sides[2] = rb_ary_entry(parts, 2);
        sides[3] = rb_ary_entry(parts, 3);
    } else {
        return result; // Invalid
    }

    const char *side_names[] = {"top", "right", "bottom", "left"};
    for (int i = 0; i < 4; i++) {
        char key[128];
        if (suffix) {
            snprintf(key, sizeof(key), "%s-%s-%s", property, side_names[i], suffix);
        } else {
            snprintf(key, sizeof(key), "%s-%s", property, side_names[i]);
        }

        // Append !important if needed
        VALUE final_value;
        if (is_important) {
            const char *val = StringValueCStr(sides[i]);
            char buf[256];
            snprintf(buf, sizeof(buf), "%s !important", val);
            final_value = STR_NEW_CSTR(buf);
        } else {
            final_value = sides[i];
        }

        rb_hash_aset(result, STR_NEW_CSTR(key), final_value);
    }

    return result;
}

/*
 * Expand margin shorthand: "10px 20px 30px 40px"
 */
VALUE cataract_expand_margin(VALUE self, VALUE value) {
    VALUE parts = cataract_split_value(self, value);
    return expand_dimensions(parts, "margin", NULL);
}

/*
 * Expand padding shorthand: "10px 20px 30px 40px"
 */
VALUE cataract_expand_padding(VALUE self, VALUE value) {
    VALUE parts = cataract_split_value(self, value);
    return expand_dimensions(parts, "padding", NULL);
}

/*
 * Expand border-color shorthand: "red green blue yellow"
 */
VALUE cataract_expand_border_color(VALUE self, VALUE value) {
    VALUE parts = cataract_split_value(self, value);
    return expand_dimensions(parts, "border", "color");
}

/*
 * Expand border-style shorthand: "solid dashed dotted double"
 */
VALUE cataract_expand_border_style(VALUE self, VALUE value) {
    VALUE parts = cataract_split_value(self, value);
    return expand_dimensions(parts, "border", "style");
}

/*
 * Expand border-width shorthand: "1px 2px 3px 4px"
 */
VALUE cataract_expand_border_width(VALUE self, VALUE value) {
    VALUE parts = cataract_split_value(self, value);
    return expand_dimensions(parts, "border", "width");
}

/*
 * Check if string matches border width keyword or starts with digit
 */
static int is_border_width(const char *str) {
    const char *keywords[] = {"thin", "medium", "thick", "inherit", NULL};
    for (int i = 0; keywords[i]; i++) {
        if (strcmp(str, keywords[i]) == 0) return 1;
    }
    return (str[0] >= '0' && str[0] <= '9');
}

/*
 * Check if string matches border style keyword
 */
static int is_border_style(const char *str) {
    const char *keywords[] = {"none", "hidden", "dotted", "dashed", "solid",
                              "double", "groove", "ridge", "inset", "outset", "inherit", NULL};
    for (int i = 0; keywords[i]; i++) {
        if (strcmp(str, keywords[i]) == 0) return 1;
    }
    return 0;
}

/*
 * Expand border shorthand: "1px solid red"
 */
VALUE cataract_expand_border(VALUE self, VALUE value) {
    VALUE parts = cataract_split_value(self, value);
    long len = RARRAY_LEN(parts);
    VALUE result = rb_hash_new();

    VALUE width = Qnil;
    VALUE style = Qnil;
    VALUE color = Qnil;

    for (long i = 0; i < len; i++) {
        VALUE part = rb_ary_entry(parts, i);
        const char *str = StringValueCStr(part);

        if (width == Qnil && is_border_width(str)) {
            width = part;
        } else if (style == Qnil && is_border_style(str)) {
            style = part;
        } else if (color == Qnil) {
            color = part;
        }
    }

    const char *sides[] = {"top", "right", "bottom", "left"};
    for (int i = 0; i < 4; i++) {
        if (width != Qnil) {
            char key[64];
            snprintf(key, sizeof(key), "border-%s-width", sides[i]);
            rb_hash_aset(result, STR_NEW_CSTR(key), width);
        }
        if (style != Qnil) {
            char key[64];
            snprintf(key, sizeof(key), "border-%s-style", sides[i]);
            rb_hash_aset(result, STR_NEW_CSTR(key), style);
        }
        if (color != Qnil) {
            char key[64];
            snprintf(key, sizeof(key), "border-%s-color", sides[i]);
            rb_hash_aset(result, STR_NEW_CSTR(key), color);
        }
    }

    return result;
}

/*
 * Expand border-{side} shorthand: "2px dashed blue"
 */
VALUE cataract_expand_border_side(VALUE self, VALUE side, VALUE value) {
    VALUE parts = cataract_split_value(self, value);
    long len = RARRAY_LEN(parts);
    VALUE result = rb_hash_new();
    const char *side_str = StringValueCStr(side);

    // Validate side is one of the valid CSS sides
    const char *valid_sides[] = {"top", "right", "bottom", "left", NULL};
    int valid = 0;
    for (int i = 0; valid_sides[i]; i++) {
        if (strcmp(side_str, valid_sides[i]) == 0) {
            valid = 1;
            break;
        }
    }
    if (!valid) {
        rb_raise(rb_eArgError, "Invalid side '%s'. Must be one of: top, right, bottom, left", side_str);
    }

    VALUE width = Qnil;
    VALUE style = Qnil;
    VALUE color = Qnil;

    for (long i = 0; i < len; i++) {
        VALUE part = rb_ary_entry(parts, i);
        const char *str = StringValueCStr(part);

        if (width == Qnil && is_border_width(str)) {
            width = part;
        } else if (style == Qnil && is_border_style(str)) {
            style = part;
        } else if (color == Qnil) {
            color = part;
        }
    }

    if (width != Qnil) {
        char key[64];
        snprintf(key, sizeof(key), "border-%s-width", side_str);
        rb_hash_aset(result, STR_NEW_CSTR(key), width);
    }
    if (style != Qnil) {
        char key[64];
        snprintf(key, sizeof(key), "border-%s-style", side_str);
        rb_hash_aset(result, STR_NEW_CSTR(key), style);
    }
    if (color != Qnil) {
        char key[64];
        snprintf(key, sizeof(key), "border-%s-color", side_str);
        rb_hash_aset(result, STR_NEW_CSTR(key), color);
    }

    return result;
}

/*
 * Expand font shorthand: "bold 14px/1.5 'Helvetica Neue', sans-serif"
 * Font syntax: [style] [variant] [weight] [size]/[line-height] [family]
 * Only size and family are required
 */
VALUE cataract_expand_font(VALUE self, VALUE value) {
    // Font is complex - need to handle / separator for line-height
    // Split on / first to separate size from line-height
    const char *str = StringValueCStr(value);
    const char *slash = strchr(str, '/');

    VALUE result = rb_hash_new();
    VALUE size_part, family_part;
    VALUE line_height = Qnil;

    if (slash) {
        // Has line-height: "14px/1.5 Arial"
        size_part = rb_str_new(str, slash - str);

        // Find family after line-height (next space after /)
        const char *after_slash = slash + 1;
        while (*after_slash == ' ') after_slash++; // skip spaces
        const char *family_start = after_slash;
        while (*family_start && *family_start != ' ') family_start++;
        while (*family_start == ' ') family_start++; // skip spaces

        // Extract line-height
        line_height = rb_str_new(after_slash, family_start - after_slash);
        line_height = rb_funcall(line_height, rb_intern("strip"), 0);

        // Family is everything after line-height
        if (*family_start) {
            family_part = STR_NEW_CSTR(family_start);
        } else {
            family_part = Qnil;
        }
    } else {
        size_part = value;
        family_part = Qnil;
    }

    // Split size_part to extract style/variant/weight/size
    VALUE parts = cataract_split_value(self, size_part);
    long len = RARRAY_LEN(parts);

    VALUE style = Qnil, variant = Qnil, weight = Qnil, size = Qnil, family = family_part;

    // Font format: [style] [variant] [weight] SIZE [family]
    // SIZE is required and has units or is a keyword
    // Parse to find size first, then work around it
    long size_idx = -1;
    for (long i = 0; i < len; i++) {
        VALUE part = rb_ary_entry(parts, i);
        const char *p = StringValueCStr(part);
        // Size has px, em, %, pt, etc or is a size keyword
        if (strchr(p, 'p') || strchr(p, 'e') || strchr(p, '%') || strchr(p, 't') ||
            strcmp(p, "small") == 0 || strcmp(p, "medium") == 0 || strcmp(p, "large") == 0 ||
            strcmp(p, "x-small") == 0 || strcmp(p, "x-large") == 0 || strcmp(p, "xx-small") == 0 ||
            strcmp(p, "xx-large") == 0 || strcmp(p, "smaller") == 0 || strcmp(p, "larger") == 0) {
            size_idx = i;
            size = part;
            break;
        }
    }

    // Everything before size is style/variant/weight
    if (size_idx > 0) {
        for (long i = 0; i < size_idx; i++) {
            VALUE part = rb_ary_entry(parts, i);
            const char *p = StringValueCStr(part);

            // Check if it's a weight
            if (weight == Qnil && (strcmp(p, "bold") == 0 || strcmp(p, "bolder") == 0 ||
                strcmp(p, "lighter") == 0 || strcmp(p, "normal") == 0 ||
                (p[0] >= '1' && p[0] <= '9' && strlen(p) == 3))) {
                weight = part;
            }
            // Check if it's a style
            else if (style == Qnil && (strcmp(p, "italic") == 0 || strcmp(p, "oblique") == 0)) {
                style = part;
            }
            // Check if it's a variant
            else if (variant == Qnil && strcmp(p, "small-caps") == 0) {
                variant = part;
            }
        }
    }

    // Everything after size is family (if not already extracted from slash parsing)
    if (family == Qnil && size_idx >= 0 && size_idx < len - 1) {
        VALUE family_parts = rb_ary_new();
        for (long i = size_idx + 1; i < len; i++) {
            rb_ary_push(family_parts, rb_ary_entry(parts, i));
        }
        family = rb_funcall(family_parts, rb_intern("join"), 1, STR_NEW_CSTR(" "));
    }

    // Set defaults for optional properties
    if (style == Qnil) style = STR_NEW_CSTR("normal");
    if (variant == Qnil) variant = STR_NEW_CSTR("normal");
    if (weight == Qnil) weight = STR_NEW_CSTR("normal");
    if (line_height == Qnil) line_height = STR_NEW_CSTR("normal");

    rb_hash_aset(result, STR_NEW_CSTR("font-style"), style);
    rb_hash_aset(result, STR_NEW_CSTR("font-variant"), variant);
    rb_hash_aset(result, STR_NEW_CSTR("font-weight"), weight);
    if (size != Qnil) rb_hash_aset(result, STR_NEW_CSTR("font-size"), size);
    rb_hash_aset(result, STR_NEW_CSTR("line-height"), line_height);
    if (family != Qnil) rb_hash_aset(result, STR_NEW_CSTR("font-family"), family);

    return result;
}

/*
 * Expand list-style shorthand: "square inside"
 */
VALUE cataract_expand_list_style(VALUE self, VALUE value) {
    VALUE parts = cataract_split_value(self, value);
    long len = RARRAY_LEN(parts);
    VALUE result = rb_hash_new();

    const char *type_keywords[] = {"disc", "circle", "square", "decimal", "lower-roman", "upper-roman",
                                    "lower-alpha", "upper-alpha", "none", NULL};
    const char *position_keywords[] = {"inside", "outside", NULL};

    VALUE type = Qnil, position = Qnil, image = Qnil;

    for (long i = 0; i < len; i++) {
        VALUE part = rb_ary_entry(parts, i);
        const char *str = StringValueCStr(part);

        // Check if it's an image (url())
        if (image == Qnil && strncmp(str, "url(", 4) == 0) {
            image = part;
        }
        // Check if it's a position
        else if (position == Qnil) {
            int is_pos = 0;
            for (int j = 0; position_keywords[j]; j++) {
                if (strcmp(str, position_keywords[j]) == 0) {
                    position = part;
                    is_pos = 1;
                    break;
                }
            }
            if (is_pos) continue;
        }
        // Check if it's a type
        if (type == Qnil) {
            for (int j = 0; type_keywords[j]; j++) {
                if (strcmp(str, type_keywords[j]) == 0) {
                    type = part;
                    break;
                }
            }
        }
    }

    if (type != Qnil) rb_hash_aset(result, STR_NEW_CSTR("list-style-type"), type);
    if (position != Qnil) rb_hash_aset(result, STR_NEW_CSTR("list-style-position"), position);
    if (image != Qnil) rb_hash_aset(result, STR_NEW_CSTR("list-style-image"), image);

    return result;
}

/*
 * Expand background shorthand: "url(img.png) no-repeat center / cover"
 * This is complex - background has many sub-properties and / separator for size
 */
VALUE cataract_expand_background(VALUE self, VALUE value) {
    // First, check if there's a / separator for background-size
    const char *str = StringValueCStr(value);
    const char *slash = strchr(str, '/');

    VALUE main_part, size_part;
    if (slash) {
        // Split on /: before is position, after is size
        main_part = rb_str_new(str, slash - str);
        size_part = STR_NEW_CSTR(slash + 1);
        size_part = rb_funcall(size_part, rb_intern("strip"), 0);
    } else {
        main_part = value;
        size_part = Qnil;
    }

    VALUE parts = cataract_split_value(self, main_part);
    long len = RARRAY_LEN(parts);
    VALUE result = rb_hash_new();

    // Color keywords (simplified list)
    const char *color_keywords[] = {"red", "blue", "green", "white", "black", "yellow",
                                     "transparent", "inherit", NULL};
    const char *repeat_keywords[] = {"repeat", "repeat-x", "repeat-y", "no-repeat", NULL};
    const char *attachment_keywords[] = {"scroll", "fixed", NULL};
    const char *position_keywords[] = {"left", "right", "top", "bottom", "center", NULL};

    VALUE color = Qnil, image = Qnil, repeat = Qnil, attachment = Qnil, position = Qnil, size = size_part;

    for (long i = 0; i < len; i++) {
        VALUE part = rb_ary_entry(parts, i);
        const char *str = StringValueCStr(part);

        // Check for image
        if (image == Qnil && (strncmp(str, "url(", 4) == 0 || strcmp(str, "none") == 0)) {
            image = part;
        }
        // Check for repeat
        else if (repeat == Qnil) {
            for (int j = 0; repeat_keywords[j]; j++) {
                if (strcmp(str, repeat_keywords[j]) == 0) {
                    repeat = part;
                    goto next_part;
                }
            }
        }
        // Check for attachment
        if (attachment == Qnil) {
            for (int j = 0; attachment_keywords[j]; j++) {
                if (strcmp(str, attachment_keywords[j]) == 0) {
                    attachment = part;
                    goto next_part;
                }
            }
        }
        // Check for position
        if (position == Qnil) {
            for (int j = 0; position_keywords[j]; j++) {
                if (strcmp(str, position_keywords[j]) == 0) {
                    position = part;
                    goto next_part;
                }
            }
        }
        // Check for color (hex, rgb, or keyword)
        if (color == Qnil) {
            if (str[0] == '#' || strncmp(str, "rgb", 3) == 0 || strncmp(str, "hsl", 3) == 0) {
                color = part;
            } else {
                for (int j = 0; color_keywords[j]; j++) {
                    if (strcmp(str, color_keywords[j]) == 0) {
                        color = part;
                        break;
                    }
                }
            }
        }

        next_part:;
    }

    if (color != Qnil) rb_hash_aset(result, STR_NEW_CSTR("background-color"), color);
    if (image != Qnil) rb_hash_aset(result, STR_NEW_CSTR("background-image"), image);
    if (repeat != Qnil) rb_hash_aset(result, STR_NEW_CSTR("background-repeat"), repeat);
    if (attachment != Qnil) rb_hash_aset(result, STR_NEW_CSTR("background-attachment"), attachment);
    if (position != Qnil) rb_hash_aset(result, STR_NEW_CSTR("background-position"), position);
    if (size != Qnil) rb_hash_aset(result, STR_NEW_CSTR("background-size"), size);

    return result;
}

// ============================================================================
// SHORTHAND CREATION (Inverse of expansion)
// ============================================================================

// Helper: Create dimension shorthand (margin or padding)
// Input: hash with "#{base}-top", "#{base}-right", "#{base}-bottom", "#{base}-left"
// Output: optimized shorthand string, or Qnil if not all sides present
static VALUE create_dimension_shorthand(VALUE properties, const char *base) {
    char key_top[32], key_right[32], key_bottom[32], key_left[32];
    snprintf(key_top, sizeof(key_top), "%s-top", base);
    snprintf(key_right, sizeof(key_right), "%s-right", base);
    snprintf(key_bottom, sizeof(key_bottom), "%s-bottom", base);
    snprintf(key_left, sizeof(key_left), "%s-left", base);

    VALUE top = rb_hash_aref(properties, STR_NEW_CSTR(key_top));
    VALUE right = rb_hash_aref(properties, STR_NEW_CSTR(key_right));
    VALUE bottom = rb_hash_aref(properties, STR_NEW_CSTR(key_bottom));
    VALUE left = rb_hash_aref(properties, STR_NEW_CSTR(key_left));

    // All four sides must be present
    if (NIL_P(top) || NIL_P(right) || NIL_P(bottom) || NIL_P(left)) {
        return Qnil;
    }

    const char *top_str = StringValueCStr(top);
    const char *right_str = StringValueCStr(right);
    const char *bottom_str = StringValueCStr(bottom);
    const char *left_str = StringValueCStr(left);

    // Optimize: if all same, use single value
    if (strcmp(top_str, right_str) == 0 &&
        strcmp(top_str, bottom_str) == 0 &&
        strcmp(top_str, left_str) == 0) {
        return rb_str_dup(top);
    }

    // Optimize: if top==bottom and left==right, use two values
    if (strcmp(top_str, bottom_str) == 0 && strcmp(left_str, right_str) == 0) {
        return rb_sprintf("%s %s", top_str, right_str);
    }

    // Optimize: if left==right, use three values
    if (strcmp(left_str, right_str) == 0) {
        return rb_sprintf("%s %s %s", top_str, right_str, bottom_str);
    }

    // All different: use four values
    return rb_sprintf("%s %s %s %s", top_str, right_str, bottom_str, left_str);
}

// Create margin shorthand from longhand properties
// Input: hash with "margin-top", "margin-right", "margin-bottom", "margin-left"
// Output: optimized shorthand string, or Qnil if not all sides present
VALUE cataract_create_margin_shorthand(VALUE self, VALUE properties) {
    return create_dimension_shorthand(properties, "margin");
}

// Create padding shorthand from longhand properties
VALUE cataract_create_padding_shorthand(VALUE self, VALUE properties) {
    return create_dimension_shorthand(properties, "padding");
}

// Helper: Create border-{width,style,color} shorthand from 4 sides
// Uses stack allocation and avoids intermediate Ruby string objects for keys
static VALUE create_border_dimension_shorthand(VALUE properties, const char *suffix) {
    // Build key names on stack: "border-top-{suffix}", etc.
    char key_top[32];     // "border-top-" + suffix + \0
    char key_right[32];
    char key_bottom[32];
    char key_left[32];

    snprintf(key_top, sizeof(key_top), "border-top-%s", suffix);
    snprintf(key_right, sizeof(key_right), "border-right-%s", suffix);
    snprintf(key_bottom, sizeof(key_bottom), "border-bottom-%s", suffix);
    snprintf(key_left, sizeof(key_left), "border-left-%s", suffix);

    // Look up values directly with C strings (no intermediate VALUE objects)
    VALUE top = rb_hash_aref(properties, STR_NEW_CSTR(key_top));
    VALUE right = rb_hash_aref(properties, STR_NEW_CSTR(key_right));
    VALUE bottom = rb_hash_aref(properties, STR_NEW_CSTR(key_bottom));
    VALUE left = rb_hash_aref(properties, STR_NEW_CSTR(key_left));

    // All four sides must be present
    if (NIL_P(top) || NIL_P(right) || NIL_P(bottom) || NIL_P(left)) {
        return Qnil;
    }

    // Extract C strings directly (no intermediate storage)
    const char *top_str = StringValueCStr(top);
    const char *right_str = StringValueCStr(right);
    const char *bottom_str = StringValueCStr(bottom);
    const char *left_str = StringValueCStr(left);

    // Optimize: if all same, return single value
    if (strcmp(top_str, right_str) == 0 &&
        strcmp(top_str, bottom_str) == 0 &&
        strcmp(top_str, left_str) == 0) {
        return rb_str_dup(top);
    }

    // Optimize: if top==bottom and left==right, use two values
    if (strcmp(top_str, bottom_str) == 0 && strcmp(left_str, right_str) == 0) {
        return rb_sprintf("%s %s", top_str, right_str);
    }

    // Optimize: if left==right, use three values
    if (strcmp(left_str, right_str) == 0) {
        return rb_sprintf("%s %s %s", top_str, right_str, bottom_str);
    }

    // All different: use four values
    return rb_sprintf("%s %s %s %s", top_str, right_str, bottom_str, left_str);
}

// Create border-width shorthand from individual sides
VALUE cataract_create_border_width_shorthand(VALUE self, VALUE properties) {
    return create_border_dimension_shorthand(properties, "width");
}

// Create border-style shorthand from individual sides
VALUE cataract_create_border_style_shorthand(VALUE self, VALUE properties) {
    return create_border_dimension_shorthand(properties, "style");
}

// Create border-color shorthand from individual sides
VALUE cataract_create_border_color_shorthand(VALUE self, VALUE properties) {
    return create_border_dimension_shorthand(properties, "color");
}

// Create border shorthand from border-width, border-style, border-color
// Output: combined string, or Qnil if no properties present or if values are multi-value shorthands
// Note: border shorthand can only have ONE value per component (width, style, color)
// Cannot combine "border-width: 1px 0" into "border: 1px 0 solid" (invalid CSS)
VALUE cataract_create_border_shorthand(VALUE self, VALUE properties) {
    VALUE width = rb_hash_aref(properties, STR_NEW_CSTR("border-width"));
    VALUE style = rb_hash_aref(properties, STR_NEW_CSTR("border-style"));
    VALUE color = rb_hash_aref(properties, STR_NEW_CSTR("border-color"));

    // Need at least one property
    if (NIL_P(width) && NIL_P(style) && NIL_P(color)) {
        return Qnil;
    }

    // Can't create border shorthand if any value is multi-value (contains spaces)
    // This handles real-world cases like bootstrap.css: border-width: 1px 0;
    if (!NIL_P(width) && strchr(RSTRING_PTR(width), ' ') != NULL) {
        return Qnil;
    }
    if (!NIL_P(style) && strchr(RSTRING_PTR(style), ' ') != NULL) {
        return Qnil;
    }
    if (!NIL_P(color) && strchr(RSTRING_PTR(color), ' ') != NULL) {
        return Qnil;
    }

    VALUE result = STR_NEW_WITH_CAPACITY(64);
    int first = 1;

    if (!NIL_P(width)) {
        rb_str_append(result, width);
        first = 0;
    }
    if (!NIL_P(style)) {
        if (!first) rb_str_cat2(result, " ");
        rb_str_append(result, style);
        first = 0;
    }
    if (!NIL_P(color)) {
        if (!first) rb_str_cat2(result, " ");
        rb_str_append(result, color);
    }

    return result;
}

// Create background shorthand from longhand properties
VALUE cataract_create_background_shorthand(VALUE self, VALUE properties) {
    VALUE color = rb_hash_aref(properties, STR_NEW_CSTR("background-color"));
    VALUE image = rb_hash_aref(properties, STR_NEW_CSTR("background-image"));
    VALUE repeat = rb_hash_aref(properties, STR_NEW_CSTR("background-repeat"));
    VALUE position = rb_hash_aref(properties, STR_NEW_CSTR("background-position"));
    VALUE size = rb_hash_aref(properties, STR_NEW_CSTR("background-size"));

    // Need at least one property
    if (NIL_P(color) && NIL_P(image) && NIL_P(repeat) && NIL_P(position) && NIL_P(size)) {
        return Qnil;
    }

    VALUE result = STR_NEW_WITH_CAPACITY(128);
    int first = 1;

    if (!NIL_P(color)) {
        rb_str_append(result, color);
        first = 0;
    }
    if (!NIL_P(image)) {
        if (!first) rb_str_cat2(result, " ");
        rb_str_append(result, image);
        first = 0;
    }
    if (!NIL_P(repeat)) {
        if (!first) rb_str_cat2(result, " ");
        rb_str_append(result, repeat);
        first = 0;
    }
    if (!NIL_P(position)) {
        if (!first) rb_str_cat2(result, " ");
        rb_str_append(result, position);
        first = 0;
    }
    if (!NIL_P(size)) {
        // size needs to be prefixed with /
        if (!first) rb_str_cat2(result, " ");
        rb_str_cat2(result, "/ ");
        rb_str_append(result, size);
    }

    return result;
}

// Create font shorthand from longhand properties
// Requires: font-size and font-family
// Optional: font-style, font-weight, line-height
VALUE cataract_create_font_shorthand(VALUE self, VALUE properties) {
    VALUE size = rb_hash_aref(properties, STR_NEW_CSTR("font-size"));
    VALUE family = rb_hash_aref(properties, STR_NEW_CSTR("font-family"));

    // font-size and font-family are required
    if (NIL_P(size) || NIL_P(family)) {
        return Qnil;
    }

    VALUE style = rb_hash_aref(properties, STR_NEW_CSTR("font-style"));
    VALUE weight = rb_hash_aref(properties, STR_NEW_CSTR("font-weight"));
    VALUE line_height = rb_hash_aref(properties, STR_NEW_CSTR("line-height"));

    VALUE result = STR_NEW_WITH_CAPACITY(128);
    int has_content = 0;

    // Order: style weight size/line-height family
    if (!NIL_P(style)) {
        rb_str_append(result, style);
        has_content = 1;
    }
    if (!NIL_P(weight)) {
        if (has_content) rb_str_cat2(result, " ");
        rb_str_append(result, weight);
        has_content = 1;
    }

    // size is required
    if (has_content) rb_str_cat2(result, " ");
    rb_str_append(result, size);

    // line-height goes with size using /
    if (!NIL_P(line_height)) {
        rb_str_cat2(result, "/");
        rb_str_append(result, line_height);
    }

    // family is required
    rb_str_cat2(result, " ");
    rb_str_append(result, family);

    return result;
}

// Create list-style shorthand from longhand properties
VALUE cataract_create_list_style_shorthand(VALUE self, VALUE properties) {
    VALUE type = rb_hash_aref(properties, STR_NEW_CSTR("list-style-type"));
    VALUE position = rb_hash_aref(properties, STR_NEW_CSTR("list-style-position"));
    VALUE image = rb_hash_aref(properties, STR_NEW_CSTR("list-style-image"));

    // Need at least one property
    if (NIL_P(type) && NIL_P(position) && NIL_P(image)) {
        return Qnil;
    }

    VALUE result = STR_NEW_WITH_CAPACITY(64);
    int first = 1;

    if (!NIL_P(type)) {
        rb_str_append(result, type);
        first = 0;
    }
    if (!NIL_P(position)) {
        if (!first) rb_str_cat2(result, " ");
        rb_str_append(result, position);
        first = 0;
    }
    if (!NIL_P(image)) {
        if (!first) rb_str_cat2(result, " ");
        rb_str_append(result, image);
    }

    return result;
}
