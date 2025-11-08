#include "cataract_new.h"

// Cache frequently used symbol IDs (initialized in init_merge_constants)
static ID id_value = 0;
static ID id_specificity = 0;
static ID id_important = 0;
static ID id_all = 0;

// Cached ivar IDs for NewStylesheet
static ID id_ivar_rules = 0;
static ID id_ivar_media_index = 0;

// Cached "merged" selector string
static VALUE str_merged_selector = Qnil;

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
};

// Callback for rb_hash_foreach - process expanded properties and apply cascade
static int merge_expanded_callback(VALUE exp_prop, VALUE exp_value, VALUE ctx_val) {
    struct expand_context *ctx = (struct expand_context *)ctx_val;

    // Expanded properties from shorthand expanders are already lowercase
    // No need to lowercase again
    int is_important = RTEST(ctx->important);

    // Apply cascade rules for expanded property
    VALUE existing = rb_hash_aref(ctx->properties_hash, exp_prop);

    if (NIL_P(existing)) {
        VALUE prop_data = rb_hash_new();
        rb_hash_aset(prop_data, ID2SYM(id_value), exp_value);
        rb_hash_aset(prop_data, ID2SYM(id_specificity), INT2NUM(ctx->specificity));
        rb_hash_aset(prop_data, ID2SYM(id_important), ctx->important);
        // Note: declaration_struct not stored - use global cNewDeclaration instead
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
    // Extract value and important flag from prop_data
    VALUE value = rb_hash_aref(prop_data, ID2SYM(id_value));
    VALUE important = rb_hash_aref(prop_data, ID2SYM(id_important));

    // Create NewDeclaration struct (use global cNewDeclaration)
    VALUE decl_struct = rb_struct_new(cNewDeclaration, property, value, important);
    rb_ary_push(result_ary, decl_struct);

    return ST_CONTINUE;
}

// Initialize cached property strings (called once at module init)
void init_merge_constants(void) {
    // Initialize symbol IDs
    id_value = rb_intern("value");
    id_specificity = rb_intern("specificity");
    id_important = rb_intern("important");
    id_all = rb_intern("all");

    // Initialize ivar IDs for NewStylesheet
    id_ivar_rules = rb_intern("@rules");
    id_ivar_media_index = rb_intern("@media_index");

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

    // Cached "merged" selector string
    str_merged_selector = rb_str_freeze(USASCII_STR("merged"));
    rb_gc_register_mark_object(str_merged_selector);
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
       NIL_P(_pd) ? 1 : (RTEST(rb_hash_aref(_pd, ID2SYM(id_important))) == (ref_important)); })

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
// Input: NewStylesheet object or CSS string
// Output: NewStylesheet with merged declarations
// TODO: Add instance-level merge! that mutates receiver
VALUE cataract_merge_new(VALUE self, VALUE input) {
    VALUE rules_array;

    // Handle different input types
    // Most calls pass NewStylesheet (common case), String is rare
    if (TYPE(input) == T_STRING) {
        // Parse CSS string first
        VALUE parsed = parse_css_new(self, input);
        rules_array = rb_hash_aref(parsed, ID2SYM(rb_intern("rules")));
    } else if (rb_obj_is_kind_of(input, cNewStylesheet)) {
        // Extract @rules from NewStylesheet (common case)
        rules_array = rb_ivar_get(input, id_ivar_rules);
    } else {
        rb_raise(rb_eTypeError, "Expected NewStylesheet or String, got %s",
                rb_obj_classname(input));
    }

    Check_Type(rules_array, T_ARRAY);

    // Initialize cached symbol IDs on first call (thread-safe since GVL is held)
    // This only happens once, so unlikely
    if (id_value == 0) {
        id_value = rb_intern("value");
        id_specificity = rb_intern("specificity");
        id_important = rb_intern("important");
    }

    long num_rules = RARRAY_LEN(rules_array);
    // Empty stylesheets are rare
    if (num_rules == 0) {
        // Return empty stylesheet
        VALUE empty_sheet = rb_class_new_instance(0, NULL, cNewStylesheet);
        return empty_sheet;
    }

    // Get NewDeclaration struct class once (use global cNewDeclaration from cataract_new.h)
    VALUE declaration_struct = cNewDeclaration;

    // Use Ruby hash for temporary storage: property => {value:, specificity:, important:, _struct_class:}
    VALUE properties_hash = rb_hash_new();

    // Iterate through each rule
    for (long i = 0; i < num_rules; i++) {
        VALUE rule = RARRAY_AREF(rules_array, i);
        Check_Type(rule, T_STRUCT);

        // Extract selector, declarations, specificity from NewRule struct
        // NewRule has: id, selector, declarations, specificity
        VALUE selector = rb_struct_aref(rule, INT2FIX(NEW_RULE_SELECTOR));
        VALUE declarations = rb_struct_aref(rule, INT2FIX(NEW_RULE_DECLARATIONS));
        VALUE specificity_val = rb_struct_aref(rule, INT2FIX(NEW_RULE_SPECIFICITY));

        // Calculate specificity if not provided (lazy)
        int specificity = 0;
        if (NIL_P(specificity_val)) {
            specificity_val = calculate_specificity(Qnil, selector);
            // Cache the calculated value back to the struct
            rb_struct_aset(rule, INT2FIX(NEW_RULE_SPECIFICITY), specificity_val);
        }
        specificity = NUM2INT(specificity_val);

        // Process each declaration in this rule
        Check_Type(declarations, T_ARRAY);
        long num_decls = RARRAY_LEN(declarations);

        for (long j = 0; j < num_decls; j++) {
            VALUE decl = RARRAY_AREF(declarations, j);

            // Extract property, value, important from NewDeclaration struct
            VALUE property = rb_struct_aref(decl, INT2FIX(NEW_DECL_PROPERTY));
            VALUE value = rb_struct_aref(decl, INT2FIX(NEW_DECL_VALUE));
            VALUE important = rb_struct_aref(decl, INT2FIX(NEW_DECL_IMPORTANT));

            // Properties are already lowercased during parsing (see cataract_new.c)
            // No need to lowercase again
            int is_important = RTEST(important);

            // Expand shorthand properties if needed
            // Most properties are NOT shorthands, so hint compiler accordingly
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
            // Expansion is rare (most properties are not shorthands)
            if (!NIL_P(expanded)) {
                Check_Type(expanded, T_HASH);

                struct expand_context ctx;
                ctx.properties_hash = properties_hash;
                ctx.specificity = specificity;
                ctx.important = important;

                rb_hash_foreach(expanded, merge_expanded_callback, (VALUE)&ctx);

                RB_GC_GUARD(expanded);
                continue; // Skip processing the original shorthand property
            }

            // Apply CSS cascade rules
            VALUE existing = rb_hash_aref(properties_hash, property);

            // In merge scenarios, properties often collide (same property in multiple rules)
            // so existing property is the common case
            if (NIL_P(existing)) {
                // New property - add it
                VALUE prop_data = rb_hash_new();
                rb_hash_aset(prop_data, ID2SYM(id_value), value);
                rb_hash_aset(prop_data, ID2SYM(id_specificity), INT2NUM(specificity));
                rb_hash_aset(prop_data, ID2SYM(id_important), important);
                // Note: declaration_struct not stored - use global cNewDeclaration instead
                rb_hash_aset(properties_hash, property, prop_data);
            } else {
                // Property exists - check cascade rules
                VALUE existing_spec = rb_hash_aref(existing, ID2SYM(id_specificity));
                VALUE existing_important = rb_hash_aref(existing, ID2SYM(id_important));

                int existing_spec_int = NUM2INT(existing_spec);
                int existing_is_important = RTEST(existing_important);

                int should_replace = 0;

                // Most declarations are NOT !important
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

                // Replacement is common in merge scenarios
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
        str_margin, cataract_create_margin_shorthand, declaration_struct);

    // Try to create padding shorthand
    TRY_CREATE_FOUR_SIDED_SHORTHAND(properties_hash,
        str_padding_top, str_padding_right, str_padding_bottom, str_padding_left,
        str_padding, cataract_create_padding_shorthand, declaration_struct);

    // Create border-width from individual sides
    TRY_CREATE_FOUR_SIDED_SHORTHAND(properties_hash,
        str_border_top_width, str_border_right_width, str_border_bottom_width, str_border_left_width,
        str_border_width, cataract_create_border_width_shorthand, declaration_struct);

    // Create border-style from individual sides
    TRY_CREATE_FOUR_SIDED_SHORTHAND(properties_hash,
        str_border_top_style, str_border_right_style, str_border_bottom_style, str_border_left_style,
        str_border_style, cataract_create_border_style_shorthand, declaration_struct);

    // Create border-color from individual sides
    TRY_CREATE_FOUR_SIDED_SHORTHAND(properties_hash,
        str_border_top_color, str_border_right_color, str_border_bottom_color, str_border_left_color,
        str_border_color, cataract_create_border_color_shorthand, declaration_struct);

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

    // Build merged declarations array
    VALUE merged_declarations = rb_ary_new();
    rb_hash_foreach(properties_hash, merge_build_result_callback, merged_declarations);

    // Create a new NewStylesheet with a single merged rule
    // Use rb_class_new_instance instead of rb_funcall for better performance
    VALUE merged_sheet = rb_class_new_instance(0, NULL, cNewStylesheet);

    // Create merged rule
    VALUE merged_rule = rb_struct_new(cNewRule,
        INT2FIX(0),              // id
        str_merged_selector,     // selector (cached frozen string)
        merged_declarations,      // declarations
        Qnil                      // specificity (not applicable)
    );

    // Set @rules array with single merged rule (use cached ID)
    VALUE rules_ary = rb_ary_new_from_args(1, merged_rule);
    rb_ivar_set(merged_sheet, id_ivar_rules, rules_ary);

    // Set @media_index with :all pointing to rule 0 (use cached ID)
    VALUE media_idx = rb_hash_new();
    VALUE all_ids = rb_ary_new_from_args(1, INT2FIX(0));
    rb_hash_aset(media_idx, ID2SYM(id_all), all_ids);
    rb_ivar_set(merged_sheet, id_ivar_media_index, media_idx);

    RB_GC_GUARD(properties_hash);
    RB_GC_GUARD(merged_declarations);
    RB_GC_GUARD(rules_array);
    RB_GC_GUARD(merged_sheet);

    return merged_sheet;
}
