// Helper: Lowercase a CSS property name (ASCII only, safe for CSS)
//
// SAFE FOR: Property names (color, margin-top), media types (screen, print)
// NOT SAFE FOR: Property values (content: "Unicode 你好"), selectors with attributes
//
// CSS property names are guaranteed ASCII per W3C spec, so simple A-Z → a-z is correct.
// Returns a new Ruby string with lowercased content.
static VALUE lowercase_property(VALUE property_str) {
    const char *str = StringValueCStr(property_str);
    long len = RSTRING_LEN(property_str);

    char lower[len];  // VLA - C99
    for (long i = 0; i < len; i++) {
        char c = str[i];
        lower[i] = (c >= 'A' && c <= 'Z') ? (c + 32) : c;
    }

    return rb_str_new(lower, len);
}

// Context for expanded property iteration
struct expand_context {
    VALUE properties_hash;
    int specificity;
    VALUE important;
    VALUE value_struct;
};

// Callback for rb_hash_foreach - process expanded properties and apply cascade
static int merge_expanded_callback(VALUE exp_prop, VALUE exp_value, VALUE ctx_val) {
    struct expand_context *ctx = (struct expand_context *)ctx_val;

    // Lowercase expanded property
    exp_prop = lowercase_property(exp_prop);

    int is_important = RTEST(ctx->important);

    // Apply cascade rules for expanded property
    VALUE existing = rb_hash_aref(ctx->properties_hash, exp_prop);

    if (NIL_P(existing)) {
        VALUE prop_data = rb_hash_new();
        rb_hash_aset(prop_data, ID2SYM(rb_intern("value")), exp_value);
        rb_hash_aset(prop_data, ID2SYM(rb_intern("specificity")), INT2NUM(ctx->specificity));
        rb_hash_aset(prop_data, ID2SYM(rb_intern("important")), ctx->important);
        rb_hash_aset(prop_data, ID2SYM(rb_intern("_struct_class")), ctx->value_struct);
        rb_hash_aset(ctx->properties_hash, exp_prop, prop_data);
    } else {
        VALUE existing_spec = rb_hash_aref(existing, ID2SYM(rb_intern("specificity")));
        VALUE existing_important = rb_hash_aref(existing, ID2SYM(rb_intern("important")));

        int existing_spec_int = NUM2INT(existing_spec);
        int existing_is_important = RTEST(existing_important);

        int should_replace = 0;
        if (is_important) {
            if (!existing_is_important || existing_spec_int <= ctx->specificity) {
                should_replace = 1;
            }
        } else {
            if (!existing_is_important && existing_spec_int <= ctx->specificity) {
                should_replace = 1;
            }
        }

        if (should_replace) {
            rb_hash_aset(existing, ID2SYM(rb_intern("value")), exp_value);
            rb_hash_aset(existing, ID2SYM(rb_intern("specificity")), INT2NUM(ctx->specificity));
            rb_hash_aset(existing, ID2SYM(rb_intern("important")), ctx->important);
        }
    }

    RB_GC_GUARD(exp_prop);
    RB_GC_GUARD(exp_value);
    return ST_CONTINUE;
}

// Callback for rb_hash_foreach - builds result array from properties hash
static int merge_build_result_callback(VALUE property, VALUE prop_data, VALUE result_ary) {
    // Get Declarations::Value struct class (cached in prop_data for efficiency)
    VALUE value_struct = rb_hash_aref(prop_data, ID2SYM(rb_intern("_struct_class")));
    VALUE value = rb_hash_aref(prop_data, ID2SYM(rb_intern("value")));
    VALUE important = rb_hash_aref(prop_data, ID2SYM(rb_intern("important")));

    // Create Declarations::Value struct
    VALUE decl_struct = rb_struct_new(value_struct, property, value, important);
    rb_ary_push(result_ary, decl_struct);

    return ST_CONTINUE;
}

// Merge CSS rules according to cascade rules
// Input: array of parsed rules from parse_css
// Output: array of Declarations::Value structs (merged and with shorthand recreated)
static VALUE cataract_merge(VALUE self, VALUE rules_array) {
    Check_Type(rules_array, T_ARRAY);

    long num_rules = RARRAY_LEN(rules_array);
    if (num_rules == 0) {
        return rb_ary_new();
    }

    // Get Declarations::Value struct class once
    VALUE cataract_module = rb_const_get(rb_cObject, rb_intern("Cataract"));
    VALUE declarations_class = rb_const_get(cataract_module, rb_intern("Declarations"));
    VALUE value_struct = rb_const_get(declarations_class, rb_intern("Value"));

    // Use Ruby hash for temporary storage: property => {value:, specificity:, important:, _struct_class:}
    VALUE properties_hash = rb_hash_new();

    // Iterate through each rule
    for (long i = 0; i < num_rules; i++) {
        VALUE rule = RARRAY_AREF(rules_array, i);
        Check_Type(rule, T_HASH);

        // Extract selector, declarations, specificity
        VALUE selector = rb_hash_aref(rule, ID2SYM(rb_intern("selector")));
        VALUE declarations = rb_hash_aref(rule, ID2SYM(rb_intern("declarations")));
        VALUE specificity_val = rb_hash_aref(rule, ID2SYM(rb_intern("specificity")));

        // Calculate specificity if not provided (lazy)
        int specificity = 0;
        if (NIL_P(specificity_val)) {
            specificity_val = calculate_specificity(Qnil, selector);
        }
        specificity = NUM2INT(specificity_val);

        // Process each declaration in this rule
        Check_Type(declarations, T_ARRAY);
        long num_decls = RARRAY_LEN(declarations);

        for (long j = 0; j < num_decls; j++) {
            VALUE decl = RARRAY_AREF(declarations, j);

            // Extract property, value, important from Declarations::Value struct
            VALUE property = rb_struct_aref(decl, INT2FIX(0)); // property
            VALUE value = rb_struct_aref(decl, INT2FIX(1));    // value
            VALUE important = rb_struct_aref(decl, INT2FIX(2)); // important

            // Lowercase property name (safe - CSS properties are ASCII)
            property = lowercase_property(property);
            int is_important = RTEST(important);

            // Expand shorthand properties if needed
            const char *prop_str = StringValueCStr(property);
            VALUE expanded = Qnil;

            if (strcmp(prop_str, "margin") == 0) {
                expanded = cataract_expand_margin(Qnil, value);
            } else if (strcmp(prop_str, "padding") == 0) {
                expanded = cataract_expand_padding(Qnil, value);
            } else if (strcmp(prop_str, "border") == 0) {
                expanded = cataract_expand_border(Qnil, value);
            } else if (strcmp(prop_str, "border-color") == 0) {
                expanded = cataract_expand_border_color(Qnil, value);
            } else if (strcmp(prop_str, "border-style") == 0) {
                expanded = cataract_expand_border_style(Qnil, value);
            } else if (strcmp(prop_str, "border-width") == 0) {
                expanded = cataract_expand_border_width(Qnil, value);
            } else if (strcmp(prop_str, "border-top") == 0) {
                expanded = cataract_expand_border_side(Qnil, value, rb_str_new_cstr("top"));
            } else if (strcmp(prop_str, "border-right") == 0) {
                expanded = cataract_expand_border_side(Qnil, value, rb_str_new_cstr("right"));
            } else if (strcmp(prop_str, "border-bottom") == 0) {
                expanded = cataract_expand_border_side(Qnil, value, rb_str_new_cstr("bottom"));
            } else if (strcmp(prop_str, "border-left") == 0) {
                expanded = cataract_expand_border_side(Qnil, value, rb_str_new_cstr("left"));
            } else if (strcmp(prop_str, "font") == 0) {
                expanded = cataract_expand_font(Qnil, value);
            } else if (strcmp(prop_str, "list-style") == 0) {
                expanded = cataract_expand_list_style(Qnil, value);
            } else if (strcmp(prop_str, "background") == 0) {
                expanded = cataract_expand_background(Qnil, value);
            }

            // If property was expanded, iterate and apply cascade using rb_hash_foreach
            if (!NIL_P(expanded)) {
                Check_Type(expanded, T_HASH);

                struct expand_context ctx;
                ctx.properties_hash = properties_hash;
                ctx.specificity = specificity;
                ctx.important = important;
                ctx.value_struct = value_struct;

                rb_hash_foreach(expanded, merge_expanded_callback, (VALUE)&ctx);

                RB_GC_GUARD(expanded);
                continue; // Skip processing the original shorthand property
            }

            // Apply CSS cascade rules
            VALUE existing = rb_hash_aref(properties_hash, property);

            if (NIL_P(existing)) {
                // New property - add it
                VALUE prop_data = rb_hash_new();
                rb_hash_aset(prop_data, ID2SYM(rb_intern("value")), value);
                rb_hash_aset(prop_data, ID2SYM(rb_intern("specificity")), INT2NUM(specificity));
                rb_hash_aset(prop_data, ID2SYM(rb_intern("important")), important);
                rb_hash_aset(prop_data, ID2SYM(rb_intern("_struct_class")), value_struct);
                rb_hash_aset(properties_hash, property, prop_data);
            } else {
                // Property exists - check cascade rules
                VALUE existing_spec = rb_hash_aref(existing, ID2SYM(rb_intern("specificity")));
                VALUE existing_important = rb_hash_aref(existing, ID2SYM(rb_intern("important")));

                int existing_spec_int = NUM2INT(existing_spec);
                int existing_is_important = RTEST(existing_important);

                int should_replace = 0;

                if (is_important) {
                    // New is !important - wins if existing is NOT important OR equal/higher specificity
                    if (!existing_is_important || existing_spec_int <= specificity) {
                        should_replace = 1;
                    }
                } else {
                    // New is NOT important - only wins if existing is also NOT important AND equal/higher specificity
                    if (!existing_is_important && existing_spec_int <= specificity) {
                        should_replace = 1;
                    }
                }

                if (should_replace) {
                    rb_hash_aset(existing, ID2SYM(rb_intern("value")), value);
                    rb_hash_aset(existing, ID2SYM(rb_intern("specificity")), INT2NUM(specificity));
                    rb_hash_aset(existing, ID2SYM(rb_intern("important")), important);
                }
            }

            RB_GC_GUARD(property);
            RB_GC_GUARD(value);
            RB_GC_GUARD(decl);
        }

        RB_GC_GUARD(selector);
        RB_GC_GUARD(declarations);
        RB_GC_GUARD(rule);
    }

    // Create shorthand from longhand properties
    // For each shorthand type, check if all required properties exist and create shorthand

    // Helper macro to extract property data
    #define GET_PROP_VALUE(hash, prop_name) \
        ({ VALUE pd = rb_hash_aref(hash, rb_str_new_cstr(prop_name)); \
           NIL_P(pd) ? Qnil : rb_hash_aref(pd, ID2SYM(rb_intern("value"))); })

    #define GET_PROP_DATA(hash, prop_name) \
        rb_hash_aref(hash, rb_str_new_cstr(prop_name))

    // Try to create margin shorthand
    VALUE margin_top = GET_PROP_VALUE(properties_hash, "margin-top");
    VALUE margin_right = GET_PROP_VALUE(properties_hash, "margin-right");
    VALUE margin_bottom = GET_PROP_VALUE(properties_hash, "margin-bottom");
    VALUE margin_left = GET_PROP_VALUE(properties_hash, "margin-left");

    if (!NIL_P(margin_top) && !NIL_P(margin_right) && !NIL_P(margin_bottom) && !NIL_P(margin_left)) {
        VALUE margin_props = rb_hash_new();
        rb_hash_aset(margin_props, rb_str_new_cstr("margin-top"), margin_top);
        rb_hash_aset(margin_props, rb_str_new_cstr("margin-right"), margin_right);
        rb_hash_aset(margin_props, rb_str_new_cstr("margin-bottom"), margin_bottom);
        rb_hash_aset(margin_props, rb_str_new_cstr("margin-left"), margin_left);

        VALUE margin_shorthand = cataract_create_margin_shorthand(Qnil, margin_props);
        if (!NIL_P(margin_shorthand)) {
            // Find max specificity and check if any are important
            VALUE top_data = GET_PROP_DATA(properties_hash, "margin-top");
            VALUE margin_important = rb_hash_aref(top_data, ID2SYM(rb_intern("important")));
            int margin_spec = NUM2INT(rb_hash_aref(top_data, ID2SYM(rb_intern("specificity"))));

            // Add shorthand
            VALUE margin_data = rb_hash_new();
            rb_hash_aset(margin_data, ID2SYM(rb_intern("value")), margin_shorthand);
            rb_hash_aset(margin_data, ID2SYM(rb_intern("specificity")), INT2NUM(margin_spec));
            rb_hash_aset(margin_data, ID2SYM(rb_intern("important")), margin_important);
            rb_hash_aset(margin_data, ID2SYM(rb_intern("_struct_class")), value_struct);
            rb_hash_aset(properties_hash, rb_str_new_cstr("margin"), margin_data);

            // Remove longhand properties
            rb_hash_delete(properties_hash, rb_str_new_cstr("margin-top"));
            rb_hash_delete(properties_hash, rb_str_new_cstr("margin-right"));
            rb_hash_delete(properties_hash, rb_str_new_cstr("margin-bottom"));
            rb_hash_delete(properties_hash, rb_str_new_cstr("margin-left"));
        }
        RB_GC_GUARD(margin_props);
        RB_GC_GUARD(margin_shorthand);
    }

    // Try to create padding shorthand
    VALUE padding_top = GET_PROP_VALUE(properties_hash, "padding-top");
    VALUE padding_right = GET_PROP_VALUE(properties_hash, "padding-right");
    VALUE padding_bottom = GET_PROP_VALUE(properties_hash, "padding-bottom");
    VALUE padding_left = GET_PROP_VALUE(properties_hash, "padding-left");

    if (!NIL_P(padding_top) && !NIL_P(padding_right) && !NIL_P(padding_bottom) && !NIL_P(padding_left)) {
        VALUE padding_props = rb_hash_new();
        rb_hash_aset(padding_props, rb_str_new_cstr("padding-top"), padding_top);
        rb_hash_aset(padding_props, rb_str_new_cstr("padding-right"), padding_right);
        rb_hash_aset(padding_props, rb_str_new_cstr("padding-bottom"), padding_bottom);
        rb_hash_aset(padding_props, rb_str_new_cstr("padding-left"), padding_left);

        VALUE padding_shorthand = cataract_create_padding_shorthand(Qnil, padding_props);
        if (!NIL_P(padding_shorthand)) {
            VALUE top_data = GET_PROP_DATA(properties_hash, "padding-top");
            VALUE padding_important = rb_hash_aref(top_data, ID2SYM(rb_intern("important")));
            int padding_spec = NUM2INT(rb_hash_aref(top_data, ID2SYM(rb_intern("specificity"))));

            VALUE padding_data = rb_hash_new();
            rb_hash_aset(padding_data, ID2SYM(rb_intern("value")), padding_shorthand);
            rb_hash_aset(padding_data, ID2SYM(rb_intern("specificity")), INT2NUM(padding_spec));
            rb_hash_aset(padding_data, ID2SYM(rb_intern("important")), padding_important);
            rb_hash_aset(padding_data, ID2SYM(rb_intern("_struct_class")), value_struct);
            rb_hash_aset(properties_hash, rb_str_new_cstr("padding"), padding_data);

            rb_hash_delete(properties_hash, rb_str_new_cstr("padding-top"));
            rb_hash_delete(properties_hash, rb_str_new_cstr("padding-right"));
            rb_hash_delete(properties_hash, rb_str_new_cstr("padding-bottom"));
            rb_hash_delete(properties_hash, rb_str_new_cstr("padding-left"));
        }
        RB_GC_GUARD(padding_props);
        RB_GC_GUARD(padding_shorthand);
    }

    // Create border-width from individual sides (border-{top,right,bottom,left}-width)
    VALUE border_top_width = GET_PROP_VALUE(properties_hash, "border-top-width");
    VALUE border_right_width = GET_PROP_VALUE(properties_hash, "border-right-width");
    VALUE border_bottom_width = GET_PROP_VALUE(properties_hash, "border-bottom-width");
    VALUE border_left_width = GET_PROP_VALUE(properties_hash, "border-left-width");

    if (!NIL_P(border_top_width) && !NIL_P(border_right_width) &&
        !NIL_P(border_bottom_width) && !NIL_P(border_left_width)) {
        VALUE width_props = rb_hash_new();
        rb_hash_aset(width_props, rb_str_new_cstr("border-top-width"), border_top_width);
        rb_hash_aset(width_props, rb_str_new_cstr("border-right-width"), border_right_width);
        rb_hash_aset(width_props, rb_str_new_cstr("border-bottom-width"), border_bottom_width);
        rb_hash_aset(width_props, rb_str_new_cstr("border-left-width"), border_left_width);

        VALUE border_width_short = cataract_create_border_width_shorthand(Qnil, width_props);
        if (!NIL_P(border_width_short)) {
            VALUE data = GET_PROP_DATA(properties_hash, "border-top-width");
            VALUE prop_data = rb_hash_new();
            rb_hash_aset(prop_data, ID2SYM(rb_intern("value")), border_width_short);
            rb_hash_aset(prop_data, ID2SYM(rb_intern("specificity")), rb_hash_aref(data, ID2SYM(rb_intern("specificity"))));
            rb_hash_aset(prop_data, ID2SYM(rb_intern("important")), rb_hash_aref(data, ID2SYM(rb_intern("important"))));
            rb_hash_aset(prop_data, ID2SYM(rb_intern("_struct_class")), value_struct);
            rb_hash_aset(properties_hash, rb_str_new_cstr("border-width"), prop_data);

            rb_hash_delete(properties_hash, rb_str_new_cstr("border-top-width"));
            rb_hash_delete(properties_hash, rb_str_new_cstr("border-right-width"));
            rb_hash_delete(properties_hash, rb_str_new_cstr("border-bottom-width"));
            rb_hash_delete(properties_hash, rb_str_new_cstr("border-left-width"));
        }
        RB_GC_GUARD(width_props);
        RB_GC_GUARD(border_width_short);
    }

    // Create border-style from individual sides
    VALUE border_top_style = GET_PROP_VALUE(properties_hash, "border-top-style");
    VALUE border_right_style = GET_PROP_VALUE(properties_hash, "border-right-style");
    VALUE border_bottom_style = GET_PROP_VALUE(properties_hash, "border-bottom-style");
    VALUE border_left_style = GET_PROP_VALUE(properties_hash, "border-left-style");

    if (!NIL_P(border_top_style) && !NIL_P(border_right_style) &&
        !NIL_P(border_bottom_style) && !NIL_P(border_left_style)) {
        VALUE style_props = rb_hash_new();
        rb_hash_aset(style_props, rb_str_new_cstr("border-top-style"), border_top_style);
        rb_hash_aset(style_props, rb_str_new_cstr("border-right-style"), border_right_style);
        rb_hash_aset(style_props, rb_str_new_cstr("border-bottom-style"), border_bottom_style);
        rb_hash_aset(style_props, rb_str_new_cstr("border-left-style"), border_left_style);

        VALUE border_style_short = cataract_create_border_style_shorthand(Qnil, style_props);
        if (!NIL_P(border_style_short)) {
            VALUE data = GET_PROP_DATA(properties_hash, "border-top-style");
            VALUE prop_data = rb_hash_new();
            rb_hash_aset(prop_data, ID2SYM(rb_intern("value")), border_style_short);
            rb_hash_aset(prop_data, ID2SYM(rb_intern("specificity")), rb_hash_aref(data, ID2SYM(rb_intern("specificity"))));
            rb_hash_aset(prop_data, ID2SYM(rb_intern("important")), rb_hash_aref(data, ID2SYM(rb_intern("important"))));
            rb_hash_aset(prop_data, ID2SYM(rb_intern("_struct_class")), value_struct);
            rb_hash_aset(properties_hash, rb_str_new_cstr("border-style"), prop_data);

            rb_hash_delete(properties_hash, rb_str_new_cstr("border-top-style"));
            rb_hash_delete(properties_hash, rb_str_new_cstr("border-right-style"));
            rb_hash_delete(properties_hash, rb_str_new_cstr("border-bottom-style"));
            rb_hash_delete(properties_hash, rb_str_new_cstr("border-left-style"));
        }
        RB_GC_GUARD(style_props);
        RB_GC_GUARD(border_style_short);
    }

    // Create border-color from individual sides
    VALUE border_top_color = GET_PROP_VALUE(properties_hash, "border-top-color");
    VALUE border_right_color = GET_PROP_VALUE(properties_hash, "border-right-color");
    VALUE border_bottom_color = GET_PROP_VALUE(properties_hash, "border-bottom-color");
    VALUE border_left_color = GET_PROP_VALUE(properties_hash, "border-left-color");

    if (!NIL_P(border_top_color) && !NIL_P(border_right_color) &&
        !NIL_P(border_bottom_color) && !NIL_P(border_left_color)) {
        VALUE color_props = rb_hash_new();
        rb_hash_aset(color_props, rb_str_new_cstr("border-top-color"), border_top_color);
        rb_hash_aset(color_props, rb_str_new_cstr("border-right-color"), border_right_color);
        rb_hash_aset(color_props, rb_str_new_cstr("border-bottom-color"), border_bottom_color);
        rb_hash_aset(color_props, rb_str_new_cstr("border-left-color"), border_left_color);

        VALUE border_color_short = cataract_create_border_color_shorthand(Qnil, color_props);
        if (!NIL_P(border_color_short)) {
            VALUE data = GET_PROP_DATA(properties_hash, "border-top-color");
            VALUE prop_data = rb_hash_new();
            rb_hash_aset(prop_data, ID2SYM(rb_intern("value")), border_color_short);
            rb_hash_aset(prop_data, ID2SYM(rb_intern("specificity")), rb_hash_aref(data, ID2SYM(rb_intern("specificity"))));
            rb_hash_aset(prop_data, ID2SYM(rb_intern("important")), rb_hash_aref(data, ID2SYM(rb_intern("important"))));
            rb_hash_aset(prop_data, ID2SYM(rb_intern("_struct_class")), value_struct);
            rb_hash_aset(properties_hash, rb_str_new_cstr("border-color"), prop_data);

            rb_hash_delete(properties_hash, rb_str_new_cstr("border-top-color"));
            rb_hash_delete(properties_hash, rb_str_new_cstr("border-right-color"));
            rb_hash_delete(properties_hash, rb_str_new_cstr("border-bottom-color"));
            rb_hash_delete(properties_hash, rb_str_new_cstr("border-left-color"));
        }
        RB_GC_GUARD(color_props);
        RB_GC_GUARD(border_color_short);
    }

    // Now create border shorthand from border-{width,style,color}
    VALUE border_width = GET_PROP_VALUE(properties_hash, "border-width");
    VALUE border_style = GET_PROP_VALUE(properties_hash, "border-style");
    VALUE border_color = GET_PROP_VALUE(properties_hash, "border-color");

    if (!NIL_P(border_width) || !NIL_P(border_style) || !NIL_P(border_color)) {
        VALUE border_props = rb_hash_new();
        if (!NIL_P(border_width)) rb_hash_aset(border_props, rb_str_new_cstr("border-width"), border_width);
        if (!NIL_P(border_style)) rb_hash_aset(border_props, rb_str_new_cstr("border-style"), border_style);
        if (!NIL_P(border_color)) rb_hash_aset(border_props, rb_str_new_cstr("border-color"), border_color);

        VALUE border_shorthand = cataract_create_border_shorthand(Qnil, border_props);
        if (!NIL_P(border_shorthand)) {
            // Use first available property's metadata
            VALUE border_data_src = !NIL_P(border_width) ? GET_PROP_DATA(properties_hash, "border-width") :
                                    !NIL_P(border_style) ? GET_PROP_DATA(properties_hash, "border-style") :
                                    GET_PROP_DATA(properties_hash, "border-color");
            VALUE border_important = rb_hash_aref(border_data_src, ID2SYM(rb_intern("important")));
            int border_spec = NUM2INT(rb_hash_aref(border_data_src, ID2SYM(rb_intern("specificity"))));

            VALUE border_data = rb_hash_new();
            rb_hash_aset(border_data, ID2SYM(rb_intern("value")), border_shorthand);
            rb_hash_aset(border_data, ID2SYM(rb_intern("specificity")), INT2NUM(border_spec));
            rb_hash_aset(border_data, ID2SYM(rb_intern("important")), border_important);
            rb_hash_aset(border_data, ID2SYM(rb_intern("_struct_class")), value_struct);
            rb_hash_aset(properties_hash, rb_str_new_cstr("border"), border_data);

            if (!NIL_P(border_width)) rb_hash_delete(properties_hash, rb_str_new_cstr("border-width"));
            if (!NIL_P(border_style)) rb_hash_delete(properties_hash, rb_str_new_cstr("border-style"));
            if (!NIL_P(border_color)) rb_hash_delete(properties_hash, rb_str_new_cstr("border-color"));
        }
        RB_GC_GUARD(border_props);
        RB_GC_GUARD(border_shorthand);
    }

    #undef GET_PROP_VALUE
    #undef GET_PROP_DATA

    // Build result array by iterating properties_hash using rb_hash_foreach
    VALUE result = rb_ary_new();
    rb_hash_foreach(properties_hash, merge_build_result_callback, result);

    RB_GC_GUARD(properties_hash);
    RB_GC_GUARD(result);
    RB_GC_GUARD(rules_array);

    return result;
}
