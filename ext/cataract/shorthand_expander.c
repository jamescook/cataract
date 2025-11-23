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
 * Helper: Expand dimension shorthand (margin, padding, border-color, etc.)
 * Returns array of 4 Declaration structs (top, right, bottom, left)
 */
static VALUE expand_dimensions(VALUE parts, const char *property, const char *suffix, VALUE important) {
    long len = RARRAY_LEN(parts);
    if (len == 0) return rb_ary_new();

    // Sanity check: property and suffix should be reasonable length
    if (strlen(property) > 32) {
        rb_raise(rb_eArgError, "Property name too long (max 32 chars)");
    }
    if (suffix && strlen(suffix) > 32) {
        rb_raise(rb_eArgError, "Suffix name too long (max 32 chars)");
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
        return rb_ary_new(); // Invalid - return empty array
    }

    // Create array of 4 Declaration structs directly (no intermediate hash!)
    VALUE result = rb_ary_new_capa(4);
    const char *side_names[] = {"top", "right", "bottom", "left"};

    for (int i = 0; i < 4; i++) {
        char prop_name[128];
        if (suffix) {
            snprintf(prop_name, sizeof(prop_name), "%s-%s-%s", property, side_names[i], suffix);
        } else {
            snprintf(prop_name, sizeof(prop_name), "%s-%s", property, side_names[i]);
        }

        // Create Declaration struct directly: Declaration.new(property, value, important)
        VALUE decl = rb_struct_new(cDeclaration,
                                   STR_NEW_CSTR(prop_name),
                                   sides[i],
                                   important);
        rb_ary_push(result, decl);
    }

    return result;
}

/*
 * Expand margin shorthand: "10px 20px 30px 40px"
 * Returns array of Declaration structs
 */
VALUE cataract_expand_margin(VALUE self, VALUE value) {
    VALUE parts = cataract_split_value(self, value);
    return expand_dimensions(parts, "margin", NULL, Qfalse);
}

/*
 * Expand padding shorthand: "10px 20px 30px 40px"
 * Returns array of Declaration structs
 */
VALUE cataract_expand_padding(VALUE self, VALUE value) {
    VALUE parts = cataract_split_value(self, value);
    return expand_dimensions(parts, "padding", NULL, Qfalse);
}

/*
 * Expand border-color shorthand: "red green blue yellow"
 * Returns array of Declaration structs
 */
VALUE cataract_expand_border_color(VALUE self, VALUE value) {
    VALUE parts = cataract_split_value(self, value);
    return expand_dimensions(parts, "border", "color", Qfalse);
}

/*
 * Expand border-style shorthand: "solid dashed dotted double"
 * Returns array of Declaration structs
 */
VALUE cataract_expand_border_style(VALUE self, VALUE value) {
    VALUE parts = cataract_split_value(self, value);
    return expand_dimensions(parts, "border", "style", Qfalse);
}

/*
 * Expand border-width shorthand: "1px 2px 3px 4px"
 * Returns array of Declaration structs
 */
VALUE cataract_expand_border_width(VALUE self, VALUE value) {
    VALUE parts = cataract_split_value(self, value);
    return expand_dimensions(parts, "border", "width", Qfalse);
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
 * Returns array of Declaration structs (up to 12: 4 sides × 3 properties)
 */
VALUE cataract_expand_border(VALUE self, VALUE value) {
    VALUE parts = cataract_split_value(self, value);
    long len = RARRAY_LEN(parts);

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

    // Create array of Declaration structs
    VALUE result = rb_ary_new_capa(12);  // Max 12: 4 sides × 3 properties
    const char *sides[] = {"top", "right", "bottom", "left"};

    for (int i = 0; i < 4; i++) {
        if (width != Qnil) {
            char prop[64];
            snprintf(prop, sizeof(prop), "border-%s-width", sides[i]);
            VALUE decl = rb_struct_new(cDeclaration, STR_NEW_CSTR(prop), width, Qfalse);
            rb_ary_push(result, decl);
        }
        if (style != Qnil) {
            char prop[64];
            snprintf(prop, sizeof(prop), "border-%s-style", sides[i]);
            VALUE decl = rb_struct_new(cDeclaration, STR_NEW_CSTR(prop), style, Qfalse);
            rb_ary_push(result, decl);
        }
        if (color != Qnil) {
            char prop[64];
            snprintf(prop, sizeof(prop), "border-%s-color", sides[i]);
            VALUE decl = rb_struct_new(cDeclaration, STR_NEW_CSTR(prop), color, Qfalse);
            rb_ary_push(result, decl);
        }
    }

    return result;
}

/*
 * Expand border-{side} shorthand: "2px dashed blue"
 * Returns array of Declaration structs (up to 3: width, style, color)
 */
VALUE cataract_expand_border_side(VALUE self, VALUE side, VALUE value) {
    VALUE parts = cataract_split_value(self, value);
    long len = RARRAY_LEN(parts);
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

    // Create array of Declaration structs
    VALUE result = rb_ary_new_capa(3);  // Max 3: width, style, color

    if (width != Qnil) {
        char prop[64];
        snprintf(prop, sizeof(prop), "border-%s-width", side_str);
        VALUE decl = rb_struct_new(cDeclaration, STR_NEW_CSTR(prop), width, Qfalse);
        rb_ary_push(result, decl);
    }
    if (style != Qnil) {
        char prop[64];
        snprintf(prop, sizeof(prop), "border-%s-style", side_str);
        VALUE decl = rb_struct_new(cDeclaration, STR_NEW_CSTR(prop), style, Qfalse);
        rb_ary_push(result, decl);
    }
    if (color != Qnil) {
        char prop[64];
        snprintf(prop, sizeof(prop), "border-%s-color", side_str);
        VALUE decl = rb_struct_new(cDeclaration, STR_NEW_CSTR(prop), color, Qfalse);
        rb_ary_push(result, decl);
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

        // Extract line-height and trim whitespace
        const char *lh_start = after_slash;
        const char *lh_end = family_start;
        trim_leading(&lh_start, lh_end);
        trim_trailing(lh_start, &lh_end);
        line_height = rb_str_new(lh_start, lh_end - lh_start);

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
        size_t plen = strlen(p);

        // Check if it's a size keyword
        if (strcmp(p, "small") == 0 || strcmp(p, "medium") == 0 || strcmp(p, "large") == 0 ||
            strcmp(p, "x-small") == 0 || strcmp(p, "x-large") == 0 || strcmp(p, "xx-small") == 0 ||
            strcmp(p, "xx-large") == 0 || strcmp(p, "smaller") == 0 || strcmp(p, "larger") == 0) {
            size_idx = i;
            size = part;
            break;
        }

        // Check if it ends with a valid CSS unit (not just contains those characters!)
        // Common absolute units: px, pt, pc, cm, mm, in
        // Common relative units: em, ex, rem, ch, vw, vh, vmin, vmax, %
        if (plen >= 2) {
            const char *end = p + plen - 2;
            if (strcmp(end, "px") == 0 || strcmp(end, "pt") == 0 || strcmp(end, "pc") == 0 ||
                strcmp(end, "em") == 0 || strcmp(end, "ex") == 0 || strcmp(end, "cm") == 0 ||
                strcmp(end, "mm") == 0 || strcmp(end, "in") == 0 || strcmp(end, "ch") == 0 ||
                strcmp(end, "vw") == 0 || strcmp(end, "vh") == 0) {
                size_idx = i;
                size = part;
                break;
            }
        }
        if (plen >= 3) {
            const char *end = p + plen - 3;
            if (strcmp(end, "rem") == 0) {
                size_idx = i;
                size = part;
                break;
            }
        }
        if (plen >= 4) {
            const char *end = p + plen - 4;
            if (strcmp(end, "vmin") == 0 || strcmp(end, "vmax") == 0) {
                size_idx = i;
                size = part;
                break;
            }
        }
        // Check for percentage
        if (plen >= 1 && p[plen - 1] == '%') {
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
        family = rb_ary_join(family_parts, STR_NEW_CSTR(" "));
    }

    // Set defaults for optional properties
    if (style == Qnil) style = STR_NEW_CSTR("normal");
    if (variant == Qnil) variant = STR_NEW_CSTR("normal");
    if (weight == Qnil) weight = STR_NEW_CSTR("normal");
    if (line_height == Qnil) line_height = STR_NEW_CSTR("normal");

    // Create array of Declaration structs
    VALUE result = rb_ary_new_capa(6);
    rb_ary_push(result, rb_struct_new(cDeclaration, STR_NEW_CSTR("font-style"), style, Qfalse));
    rb_ary_push(result, rb_struct_new(cDeclaration, STR_NEW_CSTR("font-variant"), variant, Qfalse));
    rb_ary_push(result, rb_struct_new(cDeclaration, STR_NEW_CSTR("font-weight"), weight, Qfalse));
    if (size != Qnil) {
        rb_ary_push(result, rb_struct_new(cDeclaration, STR_NEW_CSTR("font-size"), size, Qfalse));
    }
    rb_ary_push(result, rb_struct_new(cDeclaration, STR_NEW_CSTR("line-height"), line_height, Qfalse));
    if (family != Qnil) {
        rb_ary_push(result, rb_struct_new(cDeclaration, STR_NEW_CSTR("font-family"), family, Qfalse));
    }

    return result;
}

/*
 * Expand list-style shorthand: "square inside"
 */
VALUE cataract_expand_list_style(VALUE self, VALUE value) {
    VALUE parts = cataract_split_value(self, value);
    long len = RARRAY_LEN(parts);

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

    // Create array of Declaration structs
    VALUE result = rb_ary_new_capa(3);
    if (type != Qnil) {
        rb_ary_push(result, rb_struct_new(cDeclaration, STR_NEW_CSTR("list-style-type"), type, Qfalse));
    }
    if (position != Qnil) {
        rb_ary_push(result, rb_struct_new(cDeclaration, STR_NEW_CSTR("list-style-position"), position, Qfalse));
    }
    if (image != Qnil) {
        rb_ary_push(result, rb_struct_new(cDeclaration, STR_NEW_CSTR("list-style-image"), image, Qfalse));
    }

    return result;
}

/*
 * Expand background shorthand: "url(img.png) no-repeat center / cover"
 * This is complex - background has many sub-properties and / separator for size
 */
VALUE cataract_expand_background(VALUE self, VALUE value) {
    DEBUG_PRINTF("[cataract_expand_background] input value: '%s'\n", RSTRING_PTR(value));

    // First, check if there's a / separator for background-size
    const char *str = StringValueCStr(value);
    const char *slash = strchr(str, '/');

    VALUE main_part, size_part;
    if (slash) {
        // Split on /: before is position, after is size
        main_part = rb_str_new(str, slash - str);

        // Trim whitespace from size part
        const char *size_start = slash + 1;
        const char *size_end = str + strlen(str);
        trim_leading(&size_start, size_end);
        trim_trailing(size_start, &size_end);
        size_part = rb_str_new(size_start, size_end - size_start);
    } else {
        main_part = value;
        size_part = Qnil;
    }

    VALUE parts = cataract_split_value(self, main_part);
    long len = RARRAY_LEN(parts);

    // Color keywords (simplified list)
    const char *color_keywords[] = {"red", "blue", "green", "white", "black", "yellow",
                                     "transparent", "inherit", NULL};
    const char *repeat_keywords[] = {"repeat", "repeat-x", "repeat-y", "no-repeat", NULL};
    const char *attachment_keywords[] = {"scroll", "fixed", NULL};
    const char *position_keywords[] = {"left", "right", "top", "bottom", "center", NULL};

    VALUE color = Qnil, repeat = Qnil, attachment = Qnil, size = size_part;
    VALUE position_parts = rb_ary_new(); // Collect all position keywords
    VALUE image_parts = rb_ary_new();    // Collect all image functions (for layered backgrounds)

    for (long i = 0; i < len; i++) {
        VALUE part = rb_ary_entry(parts, i);
        const char *str = StringValueCStr(part);

        // Check for image (url, gradient functions, or none) - collect ALL image tokens
        if (strncmp(str, "url(", 4) == 0 ||
            strncmp(str, "linear-gradient(", 16) == 0 ||
            strncmp(str, "radial-gradient(", 16) == 0 ||
            strncmp(str, "repeating-linear-gradient(", 26) == 0 ||
            strncmp(str, "repeating-radial-gradient(", 26) == 0 ||
            strncmp(str, "conic-gradient(", 15) == 0 ||
            strcmp(str, "none") == 0) {
            DEBUG_PRINTF("  -> Recognized as IMAGE: '%s'\n", str);
            rb_ary_push(image_parts, part);
            goto next_part;
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
        // Check for position - collect ALL position keywords
        {
            for (int j = 0; position_keywords[j]; j++) {
                if (strcmp(str, position_keywords[j]) == 0) {
                    rb_ary_push(position_parts, part);
                    goto next_part;
                }
            }
        }
        // Check for color (hex, rgb, or keyword)
        if (color == Qnil) {
            if (str[0] == '#' || strncmp(str, "rgb", 3) == 0 || strncmp(str, "hsl", 3) == 0) {
                DEBUG_PRINTF("  -> Recognized as COLOR (function/hex): '%s'\n", str);
                color = part;
            } else {
                for (int j = 0; color_keywords[j]; j++) {
                    if (strcmp(str, color_keywords[j]) == 0) {
                        DEBUG_PRINTF("  -> Recognized as COLOR (keyword): '%s'\n", str);
                        color = part;
                        break;
                    }
                }
            }
        }

        next_part:;
    }

    // Join all position parts into a single string if any were found
    VALUE position = Qnil;
    if (RARRAY_LEN(position_parts) > 0) {
        position = rb_ary_join(position_parts, STR_NEW_CSTR(" "));
    }

    // Join all image parts into a single string if any were found (for layered backgrounds)
    VALUE image = Qnil;
    if (RARRAY_LEN(image_parts) > 0) {
        image = rb_ary_join(image_parts, STR_NEW_CSTR(" "));
        DEBUG_PRINTF("  -> Joined %ld image parts into: '%s'\n", RARRAY_LEN(image_parts), RSTRING_PTR(image));
    }

    DEBUG_PRINTF("[cataract_expand_background] Final values:\n");
    DEBUG_PRINTF("  color: %s\n", color != Qnil ? RSTRING_PTR(color) : "(nil -> transparent)");
    DEBUG_PRINTF("  image: %s\n", image != Qnil ? RSTRING_PTR(image) : "(nil -> none)");

    // Background shorthand sets ALL longhand properties
    // Unspecified values get CSS initial values (defaults)
    // Create array of Declaration structs
    VALUE result = rb_ary_new_capa(6);
    rb_ary_push(result, rb_struct_new(cDeclaration, STR_NEW_CSTR("background-color"),
                                      color != Qnil ? color : STR_NEW_CSTR("transparent"), Qfalse));
    rb_ary_push(result, rb_struct_new(cDeclaration, STR_NEW_CSTR("background-image"),
                                      image != Qnil ? image : STR_NEW_CSTR("none"), Qfalse));
    rb_ary_push(result, rb_struct_new(cDeclaration, STR_NEW_CSTR("background-repeat"),
                                      repeat != Qnil ? repeat : STR_NEW_CSTR("repeat"), Qfalse));
    rb_ary_push(result, rb_struct_new(cDeclaration, STR_NEW_CSTR("background-attachment"),
                                      attachment != Qnil ? attachment : STR_NEW_CSTR("scroll"), Qfalse));
    rb_ary_push(result, rb_struct_new(cDeclaration, STR_NEW_CSTR("background-position"),
                                      position != Qnil ? position : STR_NEW_CSTR("0% 0%"), Qfalse));
    if (size != Qnil) {
        rb_ary_push(result, rb_struct_new(cDeclaration, STR_NEW_CSTR("background-size"), size, Qfalse));
    }

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

    // Per W3C spec, border shorthand requires style at minimum
    // Valid: "border: solid", "border: 1px solid", "border: 1px solid red"
    // Invalid: "border: 1px", "border: red"
    if (NIL_P(style)) {
        return Qnil;
    }

    // Can't create border shorthand if any value is multi-value (contains spaces)
    // This handles real-world cases like bootstrap.css: border-width: 1px 0;
    if (!NIL_P(width) && strchr(RSTRING_PTR(width), ' ') != NULL) {
        return Qnil;
    }
    if (strchr(RSTRING_PTR(style), ' ') != NULL) {
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
    // Style is required, always present
    if (!first) rb_str_cat2(result, " ");
    rb_str_append(result, style);
    first = 0;

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
    VALUE attachment = rb_hash_aref(properties, STR_NEW_CSTR("background-attachment"));
    VALUE size = rb_hash_aref(properties, STR_NEW_CSTR("background-size"));

    // Need at least one property
    if (NIL_P(color) && NIL_P(image) && NIL_P(repeat) && NIL_P(position) && NIL_P(attachment) && NIL_P(size)) {
        return Qnil;
    }

    // Check if all 5 core properties are present (from shorthand expansion)
    // If so, omit defaults to optimize output
    int all_present = !NIL_P(color) && !NIL_P(image) && !NIL_P(repeat) &&
                      !NIL_P(position) && !NIL_P(attachment);

    DEBUG_PRINTF("[create_background_shorthand] all_present=%d (color=%d image=%d repeat=%d pos=%d attach=%d)\n",
                 all_present, !NIL_P(color), !NIL_P(image), !NIL_P(repeat),
                 !NIL_P(position), !NIL_P(attachment));
    if (!NIL_P(color)) DEBUG_PRINTF("  color='%s'\n", RSTRING_PTR(color));
    if (!NIL_P(image)) DEBUG_PRINTF("  image='%s'\n", RSTRING_PTR(image));
    if (!NIL_P(repeat)) DEBUG_PRINTF("  repeat='%s'\n", RSTRING_PTR(repeat));
    if (!NIL_P(position)) DEBUG_PRINTF("  position='%s'\n", RSTRING_PTR(position));
    if (!NIL_P(attachment)) DEBUG_PRINTF("  attachment='%s'\n", RSTRING_PTR(attachment));

    VALUE result = STR_NEW_WITH_CAPACITY(128);
    int first = 1;

    if (!NIL_P(color)) {
        // Omit default 'transparent' if all properties present
        if (!all_present || !STR_EQ(color, "transparent")) {
            DEBUG_PRINTF("  -> Adding color: '%s'\n", RSTRING_PTR(color));
            rb_str_append(result, color);
            first = 0;
        } else {
            DEBUG_PRINTF("  -> Omitting default color 'transparent'\n");
        }
    }
    if (!NIL_P(image)) {
        // Omit default 'none' if all properties present
        if (!all_present || !STR_EQ(image, "none")) {
            DEBUG_PRINTF("  -> Adding image: '%s'\n", RSTRING_PTR(image));
            if (!first) rb_str_cat2(result, " ");
            rb_str_append(result, image);
            first = 0;
        } else {
            DEBUG_PRINTF("  -> Omitting default image 'none'\n");
        }
    }
    if (!NIL_P(repeat)) {
        // Omit default 'repeat' if all properties present
        if (!all_present || !STR_EQ(repeat, "repeat")) {
            DEBUG_PRINTF("  -> Adding repeat: '%s'\n", RSTRING_PTR(repeat));
            if (!first) rb_str_cat2(result, " ");
            rb_str_append(result, repeat);
            first = 0;
        } else {
            DEBUG_PRINTF("  -> Omitting default repeat 'repeat'\n");
        }
    }
    if (!NIL_P(position)) {
        // Omit default '0% 0%' if all properties present
        if (!all_present || !STR_EQ(position, "0% 0%")) {
            DEBUG_PRINTF("  -> Adding position: '%s'\n", RSTRING_PTR(position));
            if (!first) rb_str_cat2(result, " ");
            rb_str_append(result, position);
            first = 0;
        } else {
            DEBUG_PRINTF("  -> Omitting default position '0%% 0%%'\n");
        }
    }
    if (!NIL_P(attachment)) {
        // Omit default 'scroll' if all properties present
        if (!all_present || !STR_EQ(attachment, "scroll")) {
            DEBUG_PRINTF("  -> Adding attachment: '%s'\n", RSTRING_PTR(attachment));
            if (!first) rb_str_cat2(result, " ");
            rb_str_append(result, attachment);
            first = 0;
        } else {
            DEBUG_PRINTF("  -> Omitting default attachment 'scroll'\n");
        }
    }
    if (!NIL_P(size)) {
        // size needs to be prefixed with /
        DEBUG_PRINTF("  -> Adding size: '/%s'\n", RSTRING_PTR(size));
        if (!first) rb_str_cat2(result, " ");
        rb_str_cat2(result, "/");
        rb_str_append(result, size);
    }

    // If all properties are defaults, the result would be empty
    // In this case, use "none" which is equivalent to all-default background
    if (RSTRING_LEN(result) == 0) {
        DEBUG_PRINTF("[create_background_shorthand] All defaults omitted, using 'none'\n");
        return USASCII_STR("none");
    }

    DEBUG_PRINTF("[create_background_shorthand] result='%s'\n", RSTRING_PTR(result));
    return result;
}

// Create font shorthand from longhand properties
// Requires: font-size and font-family
// Optional: font-style, font-variant, font-weight, line-height
VALUE cataract_create_font_shorthand(VALUE self, VALUE properties) {
    VALUE size = rb_hash_aref(properties, STR_NEW_CSTR("font-size"));
    VALUE family = rb_hash_aref(properties, STR_NEW_CSTR("font-family"));

    // font-size and font-family are required
    if (NIL_P(size) || NIL_P(family)) {
        return Qnil;
    }

    VALUE style = rb_hash_aref(properties, STR_NEW_CSTR("font-style"));
    VALUE variant = rb_hash_aref(properties, STR_NEW_CSTR("font-variant"));
    VALUE weight = rb_hash_aref(properties, STR_NEW_CSTR("font-weight"));
    VALUE line_height = rb_hash_aref(properties, STR_NEW_CSTR("line-height"));

    // Check if all optional properties are present (from shorthand expansion)
    // If so, omit defaults to optimize output
    int all_present = !NIL_P(style) && !NIL_P(variant) && !NIL_P(weight) && !NIL_P(line_height);

    VALUE result = STR_NEW_WITH_CAPACITY(128);
    int has_content = 0;

    // Order: style variant weight size/line-height family
    if (!NIL_P(style)) {
        // Omit default 'normal' only if all properties present
        if (!all_present || !STR_EQ(style, "normal")) {
            rb_str_append(result, style);
            has_content = 1;
        }
    }
    if (!NIL_P(variant)) {
        // Omit default 'normal' only if all properties present
        if (!all_present || !STR_EQ(variant, "normal")) {
            if (has_content) rb_str_cat2(result, " ");
            rb_str_append(result, variant);
            has_content = 1;
        }
    }
    if (!NIL_P(weight)) {
        // Omit default 'normal' only if all properties present
        if (!all_present || !STR_EQ(weight, "normal")) {
            if (has_content) rb_str_cat2(result, " ");
            rb_str_append(result, weight);
            has_content = 1;
        }
    }

    // size is required
    if (has_content) rb_str_cat2(result, " ");
    if (all_present && !NIL_P(line_height)) {
        // Omit line-height if default 'normal' and all properties present
        if (!STR_EQ(line_height, "normal")) {
            rb_str_append(result, size);
            rb_str_cat2(result, "/");
            rb_str_append(result, line_height);
        } else {
            rb_str_append(result, size);
        }
    } else {
        rb_str_append(result, size);
        // Include line-height if present (partial set)
        if (!NIL_P(line_height)) {
            rb_str_cat2(result, "/");
            rb_str_append(result, line_height);
        }
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

// Expand a single shorthand declaration into longhand declarations.
// Expand a single shorthand declaration into longhand declarations.
// Takes a Declaration struct, returns an array of Declaration structs.
// If the declaration is not a shorthand, returns array with just that declaration.
VALUE cataract_expand_shorthand(VALUE self, VALUE decl) {
    // Extract property, value, important from Declaration struct
    VALUE property = rb_struct_aref(decl, INT2FIX(0));  // property
    VALUE value = rb_struct_aref(decl, INT2FIX(1));      // value
    VALUE important = rb_struct_aref(decl, INT2FIX(2));  // important

    const char *prop = StringValueCStr(property);

    // Early exit: shorthand properties only start with m, p, b, f, or l
    // margin, padding, border*, background, font, list-style
    char first_char = prop[0];
    if (first_char != 'm' && first_char != 'p' && first_char != 'b' &&
        first_char != 'f' && first_char != 'l') {
        // Not a shorthand - return array with original declaration
        VALUE result = rb_ary_new_capa(1);
        rb_ary_push(result, decl);
        return result;
    }

    VALUE expanded_hash = Qnil;

    // Try to expand based on property name - return array of Declarations directly
    VALUE result = Qnil;

    if (strcmp(prop, "margin") == 0) {
        VALUE parts = cataract_split_value(Qnil, value);
        result = expand_dimensions(parts, "margin", NULL, important);
    } else if (strcmp(prop, "padding") == 0) {
        VALUE parts = cataract_split_value(Qnil, value);
        result = expand_dimensions(parts, "padding", NULL, important);
    } else if (strcmp(prop, "border-color") == 0) {
        VALUE parts = cataract_split_value(Qnil, value);
        result = expand_dimensions(parts, "border", "color", important);
    } else if (strcmp(prop, "border-style") == 0) {
        VALUE parts = cataract_split_value(Qnil, value);
        result = expand_dimensions(parts, "border", "style", important);
    } else if (strcmp(prop, "border-width") == 0) {
        VALUE parts = cataract_split_value(Qnil, value);
        result = expand_dimensions(parts, "border", "width", important);
    } else if (strcmp(prop, "border") == 0) {
        result = cataract_expand_border(Qnil, value);
    } else if (strcmp(prop, "border-top") == 0) {
        result = cataract_expand_border_side(Qnil, STR_NEW_CSTR("top"), value);
    } else if (strcmp(prop, "border-right") == 0) {
        result = cataract_expand_border_side(Qnil, STR_NEW_CSTR("right"), value);
    } else if (strcmp(prop, "border-bottom") == 0) {
        result = cataract_expand_border_side(Qnil, STR_NEW_CSTR("bottom"), value);
    } else if (strcmp(prop, "border-left") == 0) {
        result = cataract_expand_border_side(Qnil, STR_NEW_CSTR("left"), value);
    } else if (strcmp(prop, "font") == 0) {
        result = cataract_expand_font(Qnil, value);
    } else if (strcmp(prop, "background") == 0) {
        result = cataract_expand_background(Qnil, value);
    } else if (strcmp(prop, "list-style") == 0) {
        result = cataract_expand_list_style(Qnil, value);
    }

    // If not a shorthand (or expansion failed), return array with original declaration
    if (NIL_P(result)) {
        result = rb_ary_new_capa(1);
        rb_ary_push(result, decl);
    }

    return result;
}
