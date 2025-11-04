#include "cataract.h"

// Cache frequently used symbol IDs (initialized in init_merge_constants)
static ID id_value = 0;
static ID id_specificity = 0;
static ID id_important = 0;
static ID id_struct_class = 0;

// Cached property name strings (frozen, never GC'd)
// Initialized in init_merge_constants() at module load time
static VALUE str_margin = Qnil;
static VALUE str_margin_top = Qnil;
static VALUE str_margin_right = Qnil;
static VALUE str_margin_bottom = Qnil;
static VALUE str_margin_left = Qnil;
static VALUE str_padding = Qnil;
static VALUE str_padding_top = Qnil;
static VALUE str_padding_right = Qnil;
static VALUE str_padding_bottom = Qnil;
static VALUE str_padding_left = Qnil;
static VALUE str_border_width = Qnil;
static VALUE str_border_top_width = Qnil;
static VALUE str_border_right_width = Qnil;
static VALUE str_border_bottom_width = Qnil;
static VALUE str_border_left_width = Qnil;
static VALUE str_border_style = Qnil;
static VALUE str_border_top_style = Qnil;
static VALUE str_border_right_style = Qnil;
static VALUE str_border_bottom_style = Qnil;
static VALUE str_border_left_style = Qnil;
static VALUE str_border_color = Qnil;
static VALUE str_border_top_color = Qnil;
static VALUE str_border_right_color = Qnil;
static VALUE str_border_bottom_color = Qnil;
static VALUE str_border_left_color = Qnil;
static VALUE str_border = Qnil;
static VALUE str_font = Qnil;
static VALUE str_font_style = Qnil;
static VALUE str_font_variant = Qnil;
static VALUE str_font_weight = Qnil;
static VALUE str_font_size = Qnil;
static VALUE str_line_height = Qnil;
static VALUE str_font_family = Qnil;
static VALUE str_list_style = Qnil;
static VALUE str_list_style_type = Qnil;
static VALUE str_list_style_position = Qnil;
static VALUE str_list_style_image = Qnil;
static VALUE str_background = Qnil;
static VALUE str_background_color = Qnil;
static VALUE str_background_image = Qnil;
static VALUE str_background_repeat = Qnil;
static VALUE str_background_attachment = Qnil;
static VALUE str_background_position = Qnil;

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
        rb_hash_aset(prop_data, ID2SYM(id_value), exp_value);
        rb_hash_aset(prop_data, ID2SYM(id_specificity), INT2NUM(ctx->specificity));
        rb_hash_aset(prop_data, ID2SYM(id_important), ctx->important);
        rb_hash_aset(prop_data, ID2SYM(id_struct_class), ctx->value_struct);
        rb_hash_aset(ctx->properties_hash, exp_prop, prop_data);
    } else {
        VALUE existing_spec = rb_hash_aref(existing, ID2SYM(id_specificity));
        VALUE existing_important = rb_hash_aref(existing, ID2SYM(id_important));

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
            rb_hash_aset(existing, ID2SYM(id_value), exp_value);
            rb_hash_aset(existing, ID2SYM(id_specificity), INT2NUM(ctx->specificity));
            rb_hash_aset(existing, ID2SYM(id_important), ctx->important);
        }
    }

    RB_GC_GUARD(exp_prop);
    RB_GC_GUARD(exp_value);
    return ST_CONTINUE;
}

// Callback for rb_hash_foreach - builds result array from properties hash
static int merge_build_result_callback(VALUE property, VALUE prop_data, VALUE result_ary) {
    // Get Declarations::Value struct class (cached in prop_data for efficiency)
    VALUE value_struct = rb_hash_aref(prop_data, ID2SYM(id_struct_class));
    VALUE value = rb_hash_aref(prop_data, ID2SYM(id_value));
    VALUE important = rb_hash_aref(prop_data, ID2SYM(id_important));

    // Create Declarations::Value struct
    VALUE decl_struct = rb_struct_new(value_struct, property, value, important);
    rb_ary_push(result_ary, decl_struct);

    return ST_CONTINUE;
}

// Initialize cached property strings (called once at module init)
void init_merge_constants(void) {
    // Initialize symbol IDs
    id_value = rb_intern("value");
    id_specificity = rb_intern("specificity");
    id_important = rb_intern("important");
    id_struct_class = rb_intern("_struct_class");

    // Margin properties
    str_margin = rb_str_freeze(USASCII_STR("margin"));
    str_margin_top = rb_str_freeze(USASCII_STR("margin-top"));
    str_margin_right = rb_str_freeze(USASCII_STR("margin-right"));
    str_margin_bottom = rb_str_freeze(USASCII_STR("margin-bottom"));
    str_margin_left = rb_str_freeze(USASCII_STR("margin-left"));

    // Padding properties
    str_padding = rb_str_freeze(USASCII_STR("padding"));
    str_padding_top = rb_str_freeze(USASCII_STR("padding-top"));
    str_padding_right = rb_str_freeze(USASCII_STR("padding-right"));
    str_padding_bottom = rb_str_freeze(USASCII_STR("padding-bottom"));
    str_padding_left = rb_str_freeze(USASCII_STR("padding-left"));

    // Border-width properties
    str_border_width = rb_str_freeze(USASCII_STR("border-width"));
    str_border_top_width = rb_str_freeze(USASCII_STR("border-top-width"));
    str_border_right_width = rb_str_freeze(USASCII_STR("border-right-width"));
    str_border_bottom_width = rb_str_freeze(USASCII_STR("border-bottom-width"));
    str_border_left_width = rb_str_freeze(USASCII_STR("border-left-width"));

    // Border-style properties
    str_border_style = rb_str_freeze(USASCII_STR("border-style"));
    str_border_top_style = rb_str_freeze(USASCII_STR("border-top-style"));
    str_border_right_style = rb_str_freeze(USASCII_STR("border-right-style"));
    str_border_bottom_style = rb_str_freeze(USASCII_STR("border-bottom-style"));
    str_border_left_style = rb_str_freeze(USASCII_STR("border-left-style"));

    // Border-color properties
    str_border_color = rb_str_freeze(USASCII_STR("border-color"));
    str_border_top_color = rb_str_freeze(USASCII_STR("border-top-color"));
    str_border_right_color = rb_str_freeze(USASCII_STR("border-right-color"));
    str_border_bottom_color = rb_str_freeze(USASCII_STR("border-bottom-color"));
    str_border_left_color = rb_str_freeze(USASCII_STR("border-left-color"));

    // Border shorthand
    str_border = rb_str_freeze(USASCII_STR("border"));

    // Font properties
    str_font = rb_str_freeze(USASCII_STR("font"));
    str_font_style = rb_str_freeze(USASCII_STR("font-style"));
    str_font_variant = rb_str_freeze(USASCII_STR("font-variant"));
    str_font_weight = rb_str_freeze(USASCII_STR("font-weight"));
    str_font_size = rb_str_freeze(USASCII_STR("font-size"));
    str_line_height = rb_str_freeze(USASCII_STR("line-height"));
    str_font_family = rb_str_freeze(USASCII_STR("font-family"));

    // List-style properties
    str_list_style = rb_str_freeze(USASCII_STR("list-style"));
    str_list_style_type = rb_str_freeze(USASCII_STR("list-style-type"));
    str_list_style_position = rb_str_freeze(USASCII_STR("list-style-position"));
    str_list_style_image = rb_str_freeze(USASCII_STR("list-style-image"));

    // Background properties
    str_background = rb_str_freeze(USASCII_STR("background"));
    str_background_color = rb_str_freeze(USASCII_STR("background-color"));
    str_background_image = rb_str_freeze(USASCII_STR("background-image"));
    str_background_repeat = rb_str_freeze(USASCII_STR("background-repeat"));
    str_background_attachment = rb_str_freeze(USASCII_STR("background-attachment"));
    str_background_position = rb_str_freeze(USASCII_STR("background-position"));

    // Register all strings with GC so they're never collected
    rb_gc_register_mark_object(str_margin);
    rb_gc_register_mark_object(str_margin_top);
    rb_gc_register_mark_object(str_margin_right);
    rb_gc_register_mark_object(str_margin_bottom);
    rb_gc_register_mark_object(str_margin_left);
    rb_gc_register_mark_object(str_padding);
    rb_gc_register_mark_object(str_padding_top);
    rb_gc_register_mark_object(str_padding_right);
    rb_gc_register_mark_object(str_padding_bottom);
    rb_gc_register_mark_object(str_padding_left);
    rb_gc_register_mark_object(str_border_width);
    rb_gc_register_mark_object(str_border_top_width);
    rb_gc_register_mark_object(str_border_right_width);
    rb_gc_register_mark_object(str_border_bottom_width);
    rb_gc_register_mark_object(str_border_left_width);
    rb_gc_register_mark_object(str_border_style);
    rb_gc_register_mark_object(str_border_top_style);
    rb_gc_register_mark_object(str_border_right_style);
    rb_gc_register_mark_object(str_border_bottom_style);
    rb_gc_register_mark_object(str_border_left_style);
    rb_gc_register_mark_object(str_border_color);
    rb_gc_register_mark_object(str_border_top_color);
    rb_gc_register_mark_object(str_border_right_color);
    rb_gc_register_mark_object(str_border_bottom_color);
    rb_gc_register_mark_object(str_border_left_color);
    rb_gc_register_mark_object(str_border);
    rb_gc_register_mark_object(str_font);
    rb_gc_register_mark_object(str_font_style);
    rb_gc_register_mark_object(str_font_variant);
    rb_gc_register_mark_object(str_font_weight);
    rb_gc_register_mark_object(str_font_size);
    rb_gc_register_mark_object(str_line_height);
    rb_gc_register_mark_object(str_font_family);
    rb_gc_register_mark_object(str_list_style);
    rb_gc_register_mark_object(str_list_style_type);
    rb_gc_register_mark_object(str_list_style_position);
    rb_gc_register_mark_object(str_list_style_image);
    rb_gc_register_mark_object(str_background);
    rb_gc_register_mark_object(str_background_color);
    rb_gc_register_mark_object(str_background_image);
    rb_gc_register_mark_object(str_background_repeat);
    rb_gc_register_mark_object(str_background_attachment);
    rb_gc_register_mark_object(str_background_position);
}

// Helper macros to extract property data from properties_hash
// Note: These use id_value, id_specificity, id_important which are initialized in cataract_merge
#define GET_PROP_VALUE(hash, prop_name) \
    ({ VALUE pd = rb_hash_aref(hash, USASCII_STR(prop_name)); \
       NIL_P(pd) ? Qnil : rb_hash_aref(pd, ID2SYM(id_value)); })

#define GET_PROP_DATA(hash, prop_name) \
    rb_hash_aref(hash, USASCII_STR(prop_name))

// Versions that accept cached VALUE strings instead of string literals
#define GET_PROP_VALUE_STR(hash, str_prop) \
    ({ VALUE pd = rb_hash_aref(hash, str_prop); \
       NIL_P(pd) ? Qnil : rb_hash_aref(pd, ID2SYM(id_value)); })

#define GET_PROP_DATA_STR(hash, str_prop) \
    rb_hash_aref(hash, str_prop)

// Helper macro to check if a property's !important flag matches a reference
#define CHECK_IMPORTANT_MATCH(hash, str_prop, ref_important) \
    ({ VALUE _pd = GET_PROP_DATA_STR(hash, str_prop); \
       NIL_P(_pd) ? 1 : (RTEST(rb_hash_aref(_pd, ID2SYM(id_important))) == ref_important); })

// Macro to create shorthand from 4-sided properties (margin, padding, border-width/style/color)
// Reduces repetitive code by encapsulating the common pattern:
// 1. Get 4 longhand values (top, right, bottom, left)
// 2. Check if all 4 exist
// 3. Call shorthand creator function
// 4. Add shorthand to properties_hash and remove longhands
// Note: Uses cached static strings (VALUE) for property names - no runtime allocation
#define TRY_CREATE_FOUR_SIDED_SHORTHAND(hash, str_top, str_right, str_bottom, str_left, str_shorthand, creator_func, vstruct) \
    do { \
        VALUE _top = GET_PROP_VALUE_STR(hash, str_top); \
        VALUE _right = GET_PROP_VALUE_STR(hash, str_right); \
        VALUE _bottom = GET_PROP_VALUE_STR(hash, str_bottom); \
        VALUE _left = GET_PROP_VALUE_STR(hash, str_left); \
        \
        if (!NIL_P(_top) && !NIL_P(_right) && !NIL_P(_bottom) && !NIL_P(_left)) { \
            /* Check that all properties have the same !important flag */ \
            VALUE _top_data = GET_PROP_DATA_STR(hash, str_top); \
            VALUE _right_data = GET_PROP_DATA_STR(hash, str_right); \
            VALUE _bottom_data = GET_PROP_DATA_STR(hash, str_bottom); \
            VALUE _left_data = GET_PROP_DATA_STR(hash, str_left); \
            \
            VALUE _top_imp = rb_hash_aref(_top_data, ID2SYM(id_important)); \
            VALUE _right_imp = rb_hash_aref(_right_data, ID2SYM(id_important)); \
            VALUE _bottom_imp = rb_hash_aref(_bottom_data, ID2SYM(id_important)); \
            VALUE _left_imp = rb_hash_aref(_left_data, ID2SYM(id_important)); \
            \
            int _top_is_imp = RTEST(_top_imp); \
            int _right_is_imp = RTEST(_right_imp); \
            int _bottom_is_imp = RTEST(_bottom_imp); \
            int _left_is_imp = RTEST(_left_imp); \
            \
            /* Only create shorthand if all have same !important flag */ \
            if (_top_is_imp == _right_is_imp && _top_is_imp == _bottom_is_imp && _top_is_imp == _left_is_imp) { \
                VALUE _props = rb_hash_new(); \
                rb_hash_aset(_props, str_top, _top); \
                rb_hash_aset(_props, str_right, _right); \
                rb_hash_aset(_props, str_bottom, _bottom); \
                rb_hash_aset(_props, str_left, _left); \
                \
                VALUE _shorthand_value = creator_func(Qnil, _props); \
                if (!NIL_P(_shorthand_value)) { \
                    int _specificity = NUM2INT(rb_hash_aref(_top_data, ID2SYM(id_specificity))); \
                    \
                    VALUE _shorthand_data = rb_hash_new(); \
                    rb_hash_aset(_shorthand_data, ID2SYM(id_value), _shorthand_value); \
                    rb_hash_aset(_shorthand_data, ID2SYM(id_specificity), INT2NUM(_specificity)); \
                    rb_hash_aset(_shorthand_data, ID2SYM(id_important), _top_imp); \
                    rb_hash_aset(_shorthand_data, ID2SYM(id_struct_class), vstruct); \
                    rb_hash_aset(hash, str_shorthand, _shorthand_data); \
                    \
                    rb_hash_delete(hash, str_top); \
                    rb_hash_delete(hash, str_right); \
                    rb_hash_delete(hash, str_bottom); \
                    rb_hash_delete(hash, str_left); \
                    \
                    RB_GC_GUARD(_shorthand_value); \
                } \
                RB_GC_GUARD(_props); \
            } \
        } \
    } while(0)

// Merge CSS rules according to cascade rules
// Input: array of parsed rules from parse_css
// Output: array of Declarations::Value structs (merged and with shorthand recreated)
VALUE cataract_merge(VALUE self, VALUE rules_array) {
    Check_Type(rules_array, T_ARRAY);

    // Initialize cached symbol IDs on first call (thread-safe since GVL is held)
    if (id_value == 0) {
        id_value = rb_intern("value");
        id_specificity = rb_intern("specificity");
        id_important = rb_intern("important");
        id_struct_class = rb_intern("_struct_class");
    }

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
        Check_Type(rule, T_STRUCT);

        // Extract selector, declarations, specificity from Rule struct
        VALUE selector = rb_struct_aref(rule, INT2FIX(RULE_SELECTOR));
        VALUE declarations = rb_struct_aref(rule, INT2FIX(RULE_DECLARATIONS));
        VALUE specificity_val = rb_struct_aref(rule, INT2FIX(RULE_SPECIFICITY));

        // Calculate specificity if not provided (lazy)
        int specificity = 0;
        if (NIL_P(specificity_val)) {
            specificity_val = calculate_specificity(Qnil, selector);
            // Cache the calculated value back to the struct
            rb_struct_aset(rule, INT2FIX(RULE_SPECIFICITY), specificity_val);
        }
        specificity = NUM2INT(specificity_val);

        // Process each declaration in this rule
        Check_Type(declarations, T_ARRAY);
        long num_decls = RARRAY_LEN(declarations);

        for (long j = 0; j < num_decls; j++) {
            VALUE decl = RARRAY_AREF(declarations, j);

            // Extract property, value, important from Declarations::Value struct
            VALUE property = rb_struct_aref(decl, INT2FIX(DECL_PROPERTY));
            VALUE value = rb_struct_aref(decl, INT2FIX(DECL_VALUE));
            VALUE important = rb_struct_aref(decl, INT2FIX(DECL_IMPORTANT));

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
                expanded = cataract_expand_border_side(Qnil, USASCII_STR("top"), value);
            } else if (strcmp(prop_str, "border-right") == 0) {
                expanded = cataract_expand_border_side(Qnil, USASCII_STR("right"), value);
            } else if (strcmp(prop_str, "border-bottom") == 0) {
                expanded = cataract_expand_border_side(Qnil, USASCII_STR("bottom"), value);
            } else if (strcmp(prop_str, "border-left") == 0) {
                expanded = cataract_expand_border_side(Qnil, USASCII_STR("left"), value);
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
                rb_hash_aset(prop_data, ID2SYM(id_value), value);
                rb_hash_aset(prop_data, ID2SYM(id_specificity), INT2NUM(specificity));
                rb_hash_aset(prop_data, ID2SYM(id_important), important);
                rb_hash_aset(prop_data, ID2SYM(id_struct_class), value_struct);
                rb_hash_aset(properties_hash, property, prop_data);
            } else {
                // Property exists - check cascade rules
                VALUE existing_spec = rb_hash_aref(existing, ID2SYM(id_specificity));
                VALUE existing_important = rb_hash_aref(existing, ID2SYM(id_important));

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
                    rb_hash_aset(existing, ID2SYM(id_value), value);
                    rb_hash_aset(existing, ID2SYM(id_specificity), INT2NUM(specificity));
                    rb_hash_aset(existing, ID2SYM(id_important), important);
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
    // Uses cached static strings to avoid runtime allocation

    // Try to create margin shorthand
    TRY_CREATE_FOUR_SIDED_SHORTHAND(properties_hash,
        str_margin_top, str_margin_right, str_margin_bottom, str_margin_left,
        str_margin, cataract_create_margin_shorthand, value_struct);

    // Try to create padding shorthand
    TRY_CREATE_FOUR_SIDED_SHORTHAND(properties_hash,
        str_padding_top, str_padding_right, str_padding_bottom, str_padding_left,
        str_padding, cataract_create_padding_shorthand, value_struct);

    // Create border-width from individual sides
    TRY_CREATE_FOUR_SIDED_SHORTHAND(properties_hash,
        str_border_top_width, str_border_right_width, str_border_bottom_width, str_border_left_width,
        str_border_width, cataract_create_border_width_shorthand, value_struct);

    // Create border-style from individual sides
    TRY_CREATE_FOUR_SIDED_SHORTHAND(properties_hash,
        str_border_top_style, str_border_right_style, str_border_bottom_style, str_border_left_style,
        str_border_style, cataract_create_border_style_shorthand, value_struct);

    // Create border-color from individual sides
    TRY_CREATE_FOUR_SIDED_SHORTHAND(properties_hash,
        str_border_top_color, str_border_right_color, str_border_bottom_color, str_border_left_color,
        str_border_color, cataract_create_border_color_shorthand, value_struct);

    // Now create border shorthand from border-{width,style,color}
    VALUE border_width = GET_PROP_VALUE_STR(properties_hash, str_border_width);
    VALUE border_style = GET_PROP_VALUE_STR(properties_hash, str_border_style);
    VALUE border_color = GET_PROP_VALUE_STR(properties_hash, str_border_color);

    if (!NIL_P(border_width) || !NIL_P(border_style) || !NIL_P(border_color)) {
        // Use first available property's metadata as reference
        VALUE border_data_src = !NIL_P(border_width) ? GET_PROP_DATA_STR(properties_hash, str_border_width) :
                                !NIL_P(border_style) ? GET_PROP_DATA_STR(properties_hash, str_border_style) :
                                GET_PROP_DATA_STR(properties_hash, str_border_color);
        VALUE border_important = rb_hash_aref(border_data_src, ID2SYM(id_important));
        int border_is_important = RTEST(border_important);

        // Check that all present properties have the same !important flag
        int important_match = CHECK_IMPORTANT_MATCH(properties_hash, str_border_width, border_is_important) &&
                             CHECK_IMPORTANT_MATCH(properties_hash, str_border_style, border_is_important) &&
                             CHECK_IMPORTANT_MATCH(properties_hash, str_border_color, border_is_important);

        if (important_match) {
            VALUE border_props = rb_hash_new();
            if (!NIL_P(border_width)) rb_hash_aset(border_props, str_border_width, border_width);
            if (!NIL_P(border_style)) rb_hash_aset(border_props, str_border_style, border_style);
            if (!NIL_P(border_color)) rb_hash_aset(border_props, str_border_color, border_color);

            VALUE border_shorthand = cataract_create_border_shorthand(Qnil, border_props);
            if (!NIL_P(border_shorthand)) {
                int border_spec = NUM2INT(rb_hash_aref(border_data_src, ID2SYM(id_specificity)));

                VALUE border_data = rb_hash_new();
                rb_hash_aset(border_data, ID2SYM(id_value), border_shorthand);
                rb_hash_aset(border_data, ID2SYM(id_specificity), INT2NUM(border_spec));
                rb_hash_aset(border_data, ID2SYM(id_important), border_important);
                rb_hash_aset(border_data, ID2SYM(id_struct_class), value_struct);
                rb_hash_aset(properties_hash, str_border, border_data);

                if (!NIL_P(border_width)) rb_hash_delete(properties_hash, str_border_width);
                if (!NIL_P(border_style)) rb_hash_delete(properties_hash, str_border_style);
                if (!NIL_P(border_color)) rb_hash_delete(properties_hash, str_border_color);
            }
            RB_GC_GUARD(border_props);
            RB_GC_GUARD(border_shorthand);
        }
    }

    // Try to create font shorthand
    VALUE font_size = GET_PROP_VALUE_STR(properties_hash, str_font_size);
    VALUE font_family = GET_PROP_VALUE_STR(properties_hash, str_font_family);

    // Font shorthand requires at least font-size and font-family
    if (!NIL_P(font_size) && !NIL_P(font_family)) {
        VALUE font_style = GET_PROP_VALUE_STR(properties_hash, str_font_style);
        VALUE font_variant = GET_PROP_VALUE_STR(properties_hash, str_font_variant);
        VALUE font_weight = GET_PROP_VALUE_STR(properties_hash, str_font_weight);
        VALUE line_height = GET_PROP_VALUE_STR(properties_hash, str_line_height);

        // Get metadata from font-size as reference
        VALUE size_data = GET_PROP_DATA_STR(properties_hash, str_font_size);
        VALUE font_important = rb_hash_aref(size_data, ID2SYM(id_important));
        int font_is_important = RTEST(font_important);

        // Check that all present properties have the same !important flag
        int important_match = CHECK_IMPORTANT_MATCH(properties_hash, str_font_style, font_is_important) &&
                             CHECK_IMPORTANT_MATCH(properties_hash, str_font_variant, font_is_important) &&
                             CHECK_IMPORTANT_MATCH(properties_hash, str_font_weight, font_is_important) &&
                             CHECK_IMPORTANT_MATCH(properties_hash, str_line_height, font_is_important) &&
                             CHECK_IMPORTANT_MATCH(properties_hash, str_font_family, font_is_important);

        if (important_match) {
            VALUE font_props = rb_hash_new();
            if (!NIL_P(font_style)) rb_hash_aset(font_props, str_font_style, font_style);
            if (!NIL_P(font_variant)) rb_hash_aset(font_props, str_font_variant, font_variant);
            if (!NIL_P(font_weight)) rb_hash_aset(font_props, str_font_weight, font_weight);
            rb_hash_aset(font_props, str_font_size, font_size);
            if (!NIL_P(line_height)) rb_hash_aset(font_props, str_line_height, line_height);
            rb_hash_aset(font_props, str_font_family, font_family);

            VALUE font_shorthand = cataract_create_font_shorthand(Qnil, font_props);
            if (!NIL_P(font_shorthand)) {
                int font_spec = NUM2INT(rb_hash_aref(size_data, ID2SYM(id_specificity)));

                VALUE font_data = rb_hash_new();
                rb_hash_aset(font_data, ID2SYM(id_value), font_shorthand);
                rb_hash_aset(font_data, ID2SYM(id_specificity), INT2NUM(font_spec));
                rb_hash_aset(font_data, ID2SYM(id_important), font_important);
                rb_hash_aset(font_data, ID2SYM(id_struct_class), value_struct);
                rb_hash_aset(properties_hash, str_font, font_data);

                // Remove longhand properties
                if (!NIL_P(font_style)) rb_hash_delete(properties_hash, str_font_style);
                if (!NIL_P(font_variant)) rb_hash_delete(properties_hash, str_font_variant);
                if (!NIL_P(font_weight)) rb_hash_delete(properties_hash, str_font_weight);
                rb_hash_delete(properties_hash, str_font_size);
                if (!NIL_P(line_height)) rb_hash_delete(properties_hash, str_line_height);
                rb_hash_delete(properties_hash, str_font_family);
            }
            RB_GC_GUARD(font_props);
            RB_GC_GUARD(font_shorthand);
        }
    }

    // Try to create list-style shorthand
    VALUE list_style_type = GET_PROP_VALUE_STR(properties_hash, str_list_style_type);
    VALUE list_style_position = GET_PROP_VALUE_STR(properties_hash, str_list_style_position);
    VALUE list_style_image = GET_PROP_VALUE_STR(properties_hash, str_list_style_image);

    // List-style shorthand requires at least 2 properties
    int list_style_count = (!NIL_P(list_style_type) ? 1 : 0) +
                           (!NIL_P(list_style_position) ? 1 : 0) +
                           (!NIL_P(list_style_image) ? 1 : 0);

    if (list_style_count >= 2) {
        // Use first available property's metadata as reference
        VALUE list_style_data_src = !NIL_P(list_style_type) ? GET_PROP_DATA_STR(properties_hash, str_list_style_type) :
                                    !NIL_P(list_style_position) ? GET_PROP_DATA_STR(properties_hash, str_list_style_position) :
                                    GET_PROP_DATA_STR(properties_hash, str_list_style_image);
        VALUE list_style_important = rb_hash_aref(list_style_data_src, ID2SYM(id_important));
        int list_style_is_important = RTEST(list_style_important);

        // Check that all present properties have the same !important flag
        int important_match = CHECK_IMPORTANT_MATCH(properties_hash, str_list_style_type, list_style_is_important) &&
                             CHECK_IMPORTANT_MATCH(properties_hash, str_list_style_position, list_style_is_important) &&
                             CHECK_IMPORTANT_MATCH(properties_hash, str_list_style_image, list_style_is_important);

        if (important_match) {
            VALUE list_style_props = rb_hash_new();
            if (!NIL_P(list_style_type)) rb_hash_aset(list_style_props, str_list_style_type, list_style_type);
            if (!NIL_P(list_style_position)) rb_hash_aset(list_style_props, str_list_style_position, list_style_position);
            if (!NIL_P(list_style_image)) rb_hash_aset(list_style_props, str_list_style_image, list_style_image);

            VALUE list_style_shorthand = cataract_create_list_style_shorthand(Qnil, list_style_props);
            if (!NIL_P(list_style_shorthand)) {
                int list_style_spec = NUM2INT(rb_hash_aref(list_style_data_src, ID2SYM(id_specificity)));

                VALUE list_style_data = rb_hash_new();
                rb_hash_aset(list_style_data, ID2SYM(id_value), list_style_shorthand);
                rb_hash_aset(list_style_data, ID2SYM(id_specificity), INT2NUM(list_style_spec));
                rb_hash_aset(list_style_data, ID2SYM(id_important), list_style_important);
                rb_hash_aset(list_style_data, ID2SYM(id_struct_class), value_struct);
                rb_hash_aset(properties_hash, str_list_style, list_style_data);

                // Remove longhand properties
                if (!NIL_P(list_style_type)) rb_hash_delete(properties_hash, str_list_style_type);
                if (!NIL_P(list_style_position)) rb_hash_delete(properties_hash, str_list_style_position);
                if (!NIL_P(list_style_image)) rb_hash_delete(properties_hash, str_list_style_image);
            }
            RB_GC_GUARD(list_style_props);
            RB_GC_GUARD(list_style_shorthand);
        }
    }

    // Try to create background shorthand
    VALUE background_color = GET_PROP_VALUE_STR(properties_hash, str_background_color);
    VALUE background_image = GET_PROP_VALUE_STR(properties_hash, str_background_image);
    VALUE background_repeat = GET_PROP_VALUE_STR(properties_hash, str_background_repeat);
    VALUE background_attachment = GET_PROP_VALUE_STR(properties_hash, str_background_attachment);
    VALUE background_position = GET_PROP_VALUE_STR(properties_hash, str_background_position);

    // Background shorthand requires at least 2 properties
    int background_count = (!NIL_P(background_color) ? 1 : 0) +
                          (!NIL_P(background_image) ? 1 : 0) +
                          (!NIL_P(background_repeat) ? 1 : 0) +
                          (!NIL_P(background_attachment) ? 1 : 0) +
                          (!NIL_P(background_position) ? 1 : 0);

    if (background_count >= 2) {
        // Use first available property's metadata as reference
        VALUE background_data_src = !NIL_P(background_color) ? GET_PROP_DATA_STR(properties_hash, str_background_color) :
                                   !NIL_P(background_image) ? GET_PROP_DATA_STR(properties_hash, str_background_image) :
                                   !NIL_P(background_repeat) ? GET_PROP_DATA_STR(properties_hash, str_background_repeat) :
                                   !NIL_P(background_attachment) ? GET_PROP_DATA_STR(properties_hash, str_background_attachment) :
                                   GET_PROP_DATA_STR(properties_hash, str_background_position);
        VALUE background_important = rb_hash_aref(background_data_src, ID2SYM(id_important));
        int background_is_important = RTEST(background_important);

        // Check that all present properties have the same !important flag
        int important_match = CHECK_IMPORTANT_MATCH(properties_hash, str_background_color, background_is_important) &&
                             CHECK_IMPORTANT_MATCH(properties_hash, str_background_image, background_is_important) &&
                             CHECK_IMPORTANT_MATCH(properties_hash, str_background_repeat, background_is_important) &&
                             CHECK_IMPORTANT_MATCH(properties_hash, str_background_attachment, background_is_important) &&
                             CHECK_IMPORTANT_MATCH(properties_hash, str_background_position, background_is_important);

        if (important_match) {
            VALUE background_props = rb_hash_new();
            if (!NIL_P(background_color)) rb_hash_aset(background_props, str_background_color, background_color);
            if (!NIL_P(background_image)) rb_hash_aset(background_props, str_background_image, background_image);
            if (!NIL_P(background_repeat)) rb_hash_aset(background_props, str_background_repeat, background_repeat);
            if (!NIL_P(background_attachment)) rb_hash_aset(background_props, str_background_attachment, background_attachment);
            if (!NIL_P(background_position)) rb_hash_aset(background_props, str_background_position, background_position);

            VALUE background_shorthand = cataract_create_background_shorthand(Qnil, background_props);
            if (!NIL_P(background_shorthand)) {
                int background_spec = NUM2INT(rb_hash_aref(background_data_src, ID2SYM(id_specificity)));

                VALUE background_data = rb_hash_new();
                rb_hash_aset(background_data, ID2SYM(id_value), background_shorthand);
                rb_hash_aset(background_data, ID2SYM(id_specificity), INT2NUM(background_spec));
                rb_hash_aset(background_data, ID2SYM(id_important), background_important);
                rb_hash_aset(background_data, ID2SYM(id_struct_class), value_struct);
                rb_hash_aset(properties_hash, str_background, background_data);

                // Remove longhand properties
                if (!NIL_P(background_color)) rb_hash_delete(properties_hash, str_background_color);
                if (!NIL_P(background_image)) rb_hash_delete(properties_hash, str_background_image);
                if (!NIL_P(background_repeat)) rb_hash_delete(properties_hash, str_background_repeat);
                if (!NIL_P(background_attachment)) rb_hash_delete(properties_hash, str_background_attachment);
                if (!NIL_P(background_position)) rb_hash_delete(properties_hash, str_background_position);
            }
            RB_GC_GUARD(background_props);
            RB_GC_GUARD(background_shorthand);
        }
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

// Context for flattening hash structure callback
struct flatten_hash_ctx {
    VALUE rules_array;
};

// Callback to flatten {query_string => {media_types: [...], rules: [...]}} to array
static int flatten_hash_callback(VALUE query_string, VALUE group_hash, VALUE arg) {
    struct flatten_hash_ctx *ctx = (struct flatten_hash_ctx *)arg;

    VALUE rules = rb_hash_aref(group_hash, ID2SYM(rb_intern("rules")));
    if (!NIL_P(rules) && TYPE(rules) == T_ARRAY) {
        long rules_len = RARRAY_LEN(rules);
        for (long i = 0; i < rules_len; i++) {
            rb_ary_push(ctx->rules_array, RARRAY_AREF(rules, i));
        }
    }

    return ST_CONTINUE;
}

// Wrapper function that accepts either array or hash structure
// This is called from Ruby as Cataract.merge_rules
VALUE cataract_merge_wrapper(VALUE self, VALUE input) {
    // Check if input is a hash (new structure from Stylesheet)
    if (TYPE(input) == T_HASH) {
        // Flatten hash structure to array
        VALUE rules_array = rb_ary_new();
        struct flatten_hash_ctx ctx = { rules_array };
        rb_hash_foreach(input, flatten_hash_callback, (VALUE)&ctx);

        // Call the original merge function
        VALUE result = cataract_merge(self, rules_array);

        RB_GC_GUARD(rules_array);
        return result;
    }

    // Input is already an array - call original function directly
    return cataract_merge(self, input);
}
