#include "cataract.h"

// NOTE: This file was previously called merge.c and the functions were named cataract_merge_*
// The terminology was changed to "flatten" to better represent CSS cascade behavior.

// Array indices for property metadata: [source_order, specificity, important, value]
#define PROP_SOURCE_ORDER 0
#define PROP_SPECIFICITY 1
#define PROP_IMPORTANT 2
#define PROP_VALUE 3

// Cache frequently used symbol IDs (initialized in init_flatten_constants)
static ID id_all = 0;

// Cached ivar IDs for Stylesheet
static ID id_ivar_rules = 0;
static ID id_ivar_media_index = 0;

// Cached "merged" selector string
static VALUE str_merged_selector = Qnil;

/*
 * Shorthand recreation mapping: defines how to recreate shorthands from longhand properties
 *
 * We cache VALUE objects for property names to avoid repeated string allocations during
 * hash lookups. These are initialized once in init_flatten_constants().
 */
struct shorthand_mapping {
    const char *shorthand_name;          // e.g., "border-width"
    size_t shorthand_name_len;           // Pre-computed strlen(shorthand_name)
    VALUE shorthand_name_val;            // Cached Ruby string (initialized at load time)
    const char *prop_top;                // e.g., "border-top-width"
    VALUE prop_top_val;                  // Cached Ruby string
    const char *prop_right;              // e.g., "border-right-width"
    VALUE prop_right_val;                // Cached Ruby string
    const char *prop_bottom;             // e.g., "border-bottom-width"
    VALUE prop_bottom_val;               // Cached Ruby string
    const char *prop_left;               // e.g., "border-left-width"
    VALUE prop_left_val;                 // Cached Ruby string
    VALUE (*creator_func)(VALUE, VALUE); // Function pointer to shorthand creator
};

// Static mapping table for all 4-sided shorthand properties
// The _val fields are initialized to Qnil here and populated in init_flatten_constants()
static struct shorthand_mapping SHORTHAND_MAPPINGS[] = {
    {"margin", 6, Qnil, "margin-top", Qnil, "margin-right", Qnil, "margin-bottom", Qnil, "margin-left", Qnil, cataract_create_margin_shorthand},
    {"padding", 7, Qnil, "padding-top", Qnil, "padding-right", Qnil, "padding-bottom", Qnil, "padding-left", Qnil, cataract_create_padding_shorthand},
    {"border-width", 12, Qnil, "border-top-width", Qnil, "border-right-width", Qnil, "border-bottom-width", Qnil, "border-left-width", Qnil, cataract_create_border_width_shorthand},
    {"border-style", 12, Qnil, "border-top-style", Qnil, "border-right-style", Qnil, "border-bottom-style", Qnil, "border-left-style", Qnil, cataract_create_border_style_shorthand},
    {"border-color", 12, Qnil, "border-top-color", Qnil, "border-right-color", Qnil, "border-bottom-color", Qnil, "border-left-color", Qnil, cataract_create_border_color_shorthand},
    {NULL, 0, Qnil, NULL, Qnil, NULL, Qnil, NULL, Qnil, NULL, Qnil, NULL} // Sentinel to mark end of array
};

// Cached property name strings (frozen, never GC'd)
// Initialized in init_flatten_constants() at module load time
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
    long source_order;
    int specificity;
    VALUE important;
};

// Callback for rb_hash_foreach - process expanded properties and apply cascade
static int flatten_expanded_callback(VALUE exp_prop, VALUE exp_value, VALUE ctx_val) {
    struct expand_context *ctx = (struct expand_context *)ctx_val;

    // Expanded properties from shorthand expanders are already lowercase
    // No need to lowercase again
    int is_important = RTEST(ctx->important);

    // Apply cascade rules for expanded property
    VALUE existing = rb_hash_aref(ctx->properties_hash, exp_prop);

    if (NIL_P(existing)) {
        // Create array: [source_order, specificity, important, value]
        VALUE prop_data = rb_ary_new_capa(4);
        rb_ary_push(prop_data, LONG2NUM(ctx->source_order));
        rb_ary_push(prop_data, INT2NUM(ctx->specificity));
        rb_ary_push(prop_data, ctx->important);
        rb_ary_push(prop_data, exp_value);
        rb_hash_aset(ctx->properties_hash, exp_prop, prop_data);
    } else {
        // Access array elements directly
        long existing_order = NUM2LONG(RARRAY_AREF(existing, PROP_SOURCE_ORDER));
        int existing_spec_int = NUM2INT(RARRAY_AREF(existing, PROP_SPECIFICITY));
        VALUE existing_important = RARRAY_AREF(existing, PROP_IMPORTANT);
        int existing_is_important = RTEST(existing_important);

        int should_replace = 0;
        if (is_important) {
            if (!existing_is_important || existing_spec_int < ctx->specificity ||
                (existing_spec_int == ctx->specificity && existing_order <= ctx->source_order)) {
                should_replace = 1;
            }
        } else {
            if (!existing_is_important &&
                (existing_spec_int < ctx->specificity ||
                 (existing_spec_int == ctx->specificity && existing_order <= ctx->source_order))) {
                should_replace = 1;
            }
        }

        if (should_replace) {
            // Update array elements
            RARRAY_ASET(existing, PROP_SOURCE_ORDER, LONG2NUM(ctx->source_order));
            RARRAY_ASET(existing, PROP_SPECIFICITY, INT2NUM(ctx->specificity));
            RARRAY_ASET(existing, PROP_IMPORTANT, ctx->important);
            RARRAY_ASET(existing, PROP_VALUE, exp_value);
        }
    }

    RB_GC_GUARD(exp_prop);
    RB_GC_GUARD(exp_value);
    return ST_CONTINUE;
}

// Callback for rb_hash_foreach - builds result array from properties hash
static int flatten_build_result_callback(VALUE property, VALUE prop_data, VALUE result_ary) {
    // Extract value and important flag from array: [source_order, specificity, important, value]
    VALUE value = RARRAY_AREF(prop_data, PROP_VALUE);
    VALUE important = RARRAY_AREF(prop_data, PROP_IMPORTANT);

    // Create Declaration struct (use global cDeclaration)
    VALUE decl_struct = rb_struct_new(cDeclaration, property, value, important);
    rb_ary_push(result_ary, decl_struct);

    return ST_CONTINUE;
}

// Initialize cached property strings (called once at module init)
void init_flatten_constants(void) {
    // Initialize symbol IDs
    id_all = rb_intern("all");

    // Initialize ivar IDs for Stylesheet
    id_ivar_rules = rb_intern("@rules");
    id_ivar_media_index = rb_intern("@_media_index");

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

    // Populate the shorthand mapping table with cached string VALUEs
    // This avoids allocating new strings on every hash lookup
    SHORTHAND_MAPPINGS[0].shorthand_name_val = str_margin;
    SHORTHAND_MAPPINGS[0].prop_top_val = str_margin_top;
    SHORTHAND_MAPPINGS[0].prop_right_val = str_margin_right;
    SHORTHAND_MAPPINGS[0].prop_bottom_val = str_margin_bottom;
    SHORTHAND_MAPPINGS[0].prop_left_val = str_margin_left;

    SHORTHAND_MAPPINGS[1].shorthand_name_val = str_padding;
    SHORTHAND_MAPPINGS[1].prop_top_val = str_padding_top;
    SHORTHAND_MAPPINGS[1].prop_right_val = str_padding_right;
    SHORTHAND_MAPPINGS[1].prop_bottom_val = str_padding_bottom;
    SHORTHAND_MAPPINGS[1].prop_left_val = str_padding_left;

    SHORTHAND_MAPPINGS[2].shorthand_name_val = str_border_width;
    SHORTHAND_MAPPINGS[2].prop_top_val = str_border_top_width;
    SHORTHAND_MAPPINGS[2].prop_right_val = str_border_right_width;
    SHORTHAND_MAPPINGS[2].prop_bottom_val = str_border_bottom_width;
    SHORTHAND_MAPPINGS[2].prop_left_val = str_border_left_width;

    SHORTHAND_MAPPINGS[3].shorthand_name_val = str_border_style;
    SHORTHAND_MAPPINGS[3].prop_top_val = str_border_top_style;
    SHORTHAND_MAPPINGS[3].prop_right_val = str_border_right_style;
    SHORTHAND_MAPPINGS[3].prop_bottom_val = str_border_bottom_style;
    SHORTHAND_MAPPINGS[3].prop_left_val = str_border_left_style;

    SHORTHAND_MAPPINGS[4].shorthand_name_val = str_border_color;
    SHORTHAND_MAPPINGS[4].prop_top_val = str_border_top_color;
    SHORTHAND_MAPPINGS[4].prop_right_val = str_border_right_color;
    SHORTHAND_MAPPINGS[4].prop_bottom_val = str_border_bottom_color;
    SHORTHAND_MAPPINGS[4].prop_left_val = str_border_left_color;
}

// Helper macros to extract property data from properties_hash
// Properties are stored as arrays: [source_order, specificity, important, value]
#define GET_PROP_VALUE(hash, prop_name) \
    ({ VALUE pd = rb_hash_aref(hash, USASCII_STR(prop_name)); \
       NIL_P(pd) ? Qnil : RARRAY_AREF(pd, PROP_VALUE); })

#define GET_PROP_DATA(hash, prop_name) \
    rb_hash_aref(hash, USASCII_STR(prop_name))

// Versions that accept cached VALUE strings instead of string literals
#define GET_PROP_VALUE_STR(hash, str_prop) \
    ({ VALUE pd = rb_hash_aref(hash, str_prop); \
       NIL_P(pd) ? Qnil : RARRAY_AREF(pd, PROP_VALUE); })

#define GET_PROP_DATA_STR(hash, str_prop) \
    rb_hash_aref(hash, str_prop)

// Helper macro to check if a property's !important flag matches a reference
#define CHECK_IMPORTANT_MATCH(hash, str_prop, ref_important) \
    ({ VALUE _pd = GET_PROP_DATA_STR(hash, str_prop); \
       NIL_P(_pd) ? 1 : (RTEST(RARRAY_AREF(_pd, PROP_IMPORTANT)) == (ref_important)); })

// Macro to create shorthand from 4-sided properties (margin, padding, border-width/style/color)
// Reduces repetitive code by encapsulating the common pattern:
// 1. Get 4 longhand values (top, right, bottom, left)
// 2. Check if all 4 exist
// 3. Call shorthand creator function
// 4. Add shorthand to properties_hash and remove longhands
// Note: Uses cached static strings (VALUE) for property names - no runtime allocation
#define TRY_CREATE_FOUR_SIDED_SHORTHAND(hash, str_top, str_right, str_bottom, str_left, str_shorthand, creator_func) \
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
            VALUE _top_imp = RARRAY_AREF(_top_data, PROP_IMPORTANT); \
            VALUE _right_imp = RARRAY_AREF(_right_data, PROP_IMPORTANT); \
            VALUE _bottom_imp = RARRAY_AREF(_bottom_data, PROP_IMPORTANT); \
            VALUE _left_imp = RARRAY_AREF(_left_data, PROP_IMPORTANT); \
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
                    long _source_order = NUM2LONG(RARRAY_AREF(_top_data, PROP_SOURCE_ORDER)); \
                    int _specificity = NUM2INT(RARRAY_AREF(_top_data, PROP_SPECIFICITY)); \
                    \
                    VALUE _shorthand_data = rb_ary_new_capa(4); \
                    rb_ary_push(_shorthand_data, LONG2NUM(_source_order)); \
                    rb_ary_push(_shorthand_data, INT2NUM(_specificity)); \
                    rb_ary_push(_shorthand_data, _top_imp); \
                    rb_ary_push(_shorthand_data, _shorthand_value); \
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

// Helper macro: Recreate dimension shorthand (margin, padding, border-width)
// Takes a property prefix like "margin" and creates "margin" from margin-top/right/bottom/left
#define RECREATE_DIMENSION_SHORTHAND(hash, prefix, creator_func) \
    do { \
        char _top_name[64], _right_name[64], _bottom_name[64], _left_name[64]; \
        snprintf(_top_name, sizeof(_top_name), "%s-top", prefix); \
        snprintf(_right_name, sizeof(_right_name), "%s-right", prefix); \
        snprintf(_bottom_name, sizeof(_bottom_name), "%s-bottom", prefix); \
        snprintf(_left_name, sizeof(_left_name), "%s-left", prefix); \
        \
        VALUE _top_data = rb_hash_aref(hash, STR_NEW_CSTR(_top_name)); \
        VALUE _right_data = rb_hash_aref(hash, STR_NEW_CSTR(_right_name)); \
        VALUE _bottom_data = rb_hash_aref(hash, STR_NEW_CSTR(_bottom_name)); \
        VALUE _left_data = rb_hash_aref(hash, STR_NEW_CSTR(_left_name)); \
        \
        if (!NIL_P(_top_data) && !NIL_P(_right_data) && !NIL_P(_bottom_data) && !NIL_P(_left_data)) { \
            VALUE _top_imp = RARRAY_AREF(_top_data, PROP_IMPORTANT); \
            VALUE _right_imp = RARRAY_AREF(_right_data, PROP_IMPORTANT); \
            VALUE _bottom_imp = RARRAY_AREF(_bottom_data, PROP_IMPORTANT); \
            VALUE _left_imp = RARRAY_AREF(_left_data, PROP_IMPORTANT); \
            \
            if (RTEST(_top_imp) == RTEST(_right_imp) && RTEST(_top_imp) == RTEST(_bottom_imp) && RTEST(_top_imp) == RTEST(_left_imp)) { \
                VALUE _props = rb_hash_new(); \
                rb_hash_aset(_props, STR_NEW_CSTR(_top_name), RARRAY_AREF(_top_data, PROP_VALUE)); \
                rb_hash_aset(_props, STR_NEW_CSTR(_right_name), RARRAY_AREF(_right_data, PROP_VALUE)); \
                rb_hash_aset(_props, STR_NEW_CSTR(_bottom_name), RARRAY_AREF(_bottom_data, PROP_VALUE)); \
                rb_hash_aset(_props, STR_NEW_CSTR(_left_name), RARRAY_AREF(_left_data, PROP_VALUE)); \
                \
                VALUE _shorthand_value = creator_func(Qnil, _props); \
                if (!NIL_P(_shorthand_value)) { \
                    VALUE _shorthand_data = rb_ary_new_capa(4); \
                    rb_ary_push(_shorthand_data, RARRAY_AREF(_top_data, PROP_SOURCE_ORDER)); \
                    rb_ary_push(_shorthand_data, RARRAY_AREF(_top_data, PROP_SPECIFICITY)); \
                    rb_ary_push(_shorthand_data, _top_imp); \
                    rb_ary_push(_shorthand_data, _shorthand_value); \
                    rb_hash_aset(hash, rb_usascii_str_new(prefix, strlen(prefix)), _shorthand_data); \
                    \
                    rb_hash_delete(hash, STR_NEW_CSTR(_top_name)); \
                    rb_hash_delete(hash, STR_NEW_CSTR(_right_name)); \
                    rb_hash_delete(hash, STR_NEW_CSTR(_bottom_name)); \
                    rb_hash_delete(hash, STR_NEW_CSTR(_left_name)); \
                    DEBUG_PRINTF("      -> Recreated %s shorthand\n", prefix); \
                } \
            } \
        } \
    } while(0)

// Helper function: Try to recreate a shorthand property from its longhand components
// Uses cached VALUE objects for property names to avoid repeated string allocations
static inline void try_recreate_shorthand(VALUE properties_hash, const struct shorthand_mapping *mapping) {
    VALUE top_data = rb_hash_aref(properties_hash, mapping->prop_top_val);
    VALUE right_data = rb_hash_aref(properties_hash, mapping->prop_right_val);
    VALUE bottom_data = rb_hash_aref(properties_hash, mapping->prop_bottom_val);
    VALUE left_data = rb_hash_aref(properties_hash, mapping->prop_left_val);

    // All four sides must be present
    if (NIL_P(top_data) || NIL_P(right_data) || NIL_P(bottom_data) || NIL_P(left_data)) {
        return;
    }

    // All four sides must have the same !important flag
    VALUE top_imp = RARRAY_AREF(top_data, PROP_IMPORTANT);
    VALUE right_imp = RARRAY_AREF(right_data, PROP_IMPORTANT);
    VALUE bottom_imp = RARRAY_AREF(bottom_data, PROP_IMPORTANT);
    VALUE left_imp = RARRAY_AREF(left_data, PROP_IMPORTANT);

    if (RTEST(top_imp) != RTEST(right_imp) ||
        RTEST(top_imp) != RTEST(bottom_imp) ||
        RTEST(top_imp) != RTEST(left_imp)) {
        return;
    }

    // Build a hash of property values for the creator function
    VALUE props = rb_hash_new();
    rb_hash_aset(props, mapping->prop_top_val, RARRAY_AREF(top_data, PROP_VALUE));
    rb_hash_aset(props, mapping->prop_right_val, RARRAY_AREF(right_data, PROP_VALUE));
    rb_hash_aset(props, mapping->prop_bottom_val, RARRAY_AREF(bottom_data, PROP_VALUE));
    rb_hash_aset(props, mapping->prop_left_val, RARRAY_AREF(left_data, PROP_VALUE));

    // Call the creator function
    VALUE shorthand_value = mapping->creator_func(Qnil, props);
    if (NIL_P(shorthand_value)) {
        return; // Creator decided not to create shorthand
    }

    // Create the shorthand property data array
    VALUE shorthand_data = rb_ary_new_capa(4);
    rb_ary_push(shorthand_data, RARRAY_AREF(top_data, PROP_SOURCE_ORDER));
    rb_ary_push(shorthand_data, RARRAY_AREF(top_data, PROP_SPECIFICITY));
    rb_ary_push(shorthand_data, top_imp);
    rb_ary_push(shorthand_data, shorthand_value);

    // Add shorthand and remove longhand properties
    rb_hash_aset(properties_hash, mapping->shorthand_name_val, shorthand_data);
    rb_hash_delete(properties_hash, mapping->prop_top_val);
    rb_hash_delete(properties_hash, mapping->prop_right_val);
    rb_hash_delete(properties_hash, mapping->prop_bottom_val);
    rb_hash_delete(properties_hash, mapping->prop_left_val);

    DEBUG_PRINTF("      -> Recreated %s shorthand\n", mapping->shorthand_name);
}

/*
 * Helper struct: For processing expanded properties during merge
 */
struct expand_property_data {
    VALUE properties_hash;      // Target hash to store properties
    VALUE selector;             // Selector string (for lazy specificity calculation)
    int specificity;            // Cached specificity (-1 if not yet calculated)
    int is_important;           // Whether the original declaration was !important
    long source_order;          // Source order of the original declaration
};

/*
 * Callback: Process each expanded property and apply cascade rules
 *
 * Optimization: Specificity is calculated lazily only when needed for cascade comparison.
 * This avoids expensive specificity calculation when:
 * - Property doesn't exist yet (no comparison needed)
 * - Importance levels differ (!important always wins, regardless of specificity)
 */
static int process_expanded_property(VALUE prop_name, VALUE prop_value, VALUE arg) {
    struct expand_property_data *data = (struct expand_property_data *)arg;
    VALUE properties_hash = data->properties_hash;
    int is_important = data->is_important;
    long source_order = data->source_order;

    DEBUG_PRINTF("          -> Processing expanded: %s: %s%s\n",
                 RSTRING_PTR(prop_name), RSTRING_PTR(prop_value),
                 is_important ? " !important" : "");

    // Apply CSS cascade rules
    VALUE existing = rb_hash_aref(properties_hash, prop_name);
    if (NIL_P(existing)) {
        DEBUG_PRINTF("             -> NEW property\n");
        // Calculate specificity on first use (lazy initialization)
        if (data->specificity == -1) {
            data->specificity = NUM2INT(calculate_specificity(Qnil, data->selector));
        }
        // Create array: [source_order, specificity, important, value]
        VALUE prop_data = rb_ary_new_capa(4);
        rb_ary_push(prop_data, LONG2NUM(source_order));
        rb_ary_push(prop_data, INT2NUM(data->specificity));
        rb_ary_push(prop_data, is_important ? Qtrue : Qfalse);
        rb_ary_push(prop_data, prop_value);
        rb_hash_aset(properties_hash, prop_name, prop_data);
    } else {
        // Property exists - apply CSS cascade rules
        long existing_source_order = NUM2LONG(RARRAY_AREF(existing, PROP_SOURCE_ORDER));
        int existing_spec = NUM2INT(RARRAY_AREF(existing, PROP_SPECIFICITY));
        VALUE existing_important = RARRAY_AREF(existing, PROP_IMPORTANT);
        int existing_is_important = RTEST(existing_important);

        int should_replace = 0;

        // Apply CSS cascade rules:
        // 1. !important always wins over non-!important (no specificity check needed)
        // 2. Higher specificity wins (only check when importance is same)
        // 3. Later source order wins
        if (is_important && !existing_is_important) {
            // New declaration is !important, existing is not - replace (no specificity needed)
            should_replace = 1;
            DEBUG_PRINTF("             -> REPLACE (new is !important, existing is not)\n");
        } else if (!is_important && existing_is_important) {
            // Existing declaration is !important, new is not - keep existing (no specificity needed)
            should_replace = 0;
            DEBUG_PRINTF("             -> KEEP (existing is !important, new is not)\n");
        } else {
            // Same importance level - NOW we need specificity
            // Calculate specificity on first use (lazy initialization)
            if (data->specificity == -1) {
                data->specificity = NUM2INT(calculate_specificity(Qnil, data->selector));
            }

            DEBUG_PRINTF("             -> COLLISION: existing spec=%d important=%d source_order=%ld, new spec=%d important=%d source_order=%ld\n",
                         existing_spec, existing_is_important, existing_source_order,
                         data->specificity, is_important, source_order);

            // Same importance level - check specificity then source order
            if (data->specificity > existing_spec) {
                should_replace = 1;
            } else if (data->specificity == existing_spec) {
                should_replace = source_order > existing_source_order;
            }
            DEBUG_PRINTF("             -> %s (same importance, spec=%d vs %d, order=%ld vs %ld)\n",
                         should_replace ? "REPLACE" : "KEEP",
                         data->specificity, existing_spec, source_order, existing_source_order);
        }

        if (should_replace) {
            // Calculate specificity if we haven't yet (edge case: importance differs but we're replacing)
            if (data->specificity == -1) {
                data->specificity = NUM2INT(calculate_specificity(Qnil, data->selector));
            }
            RARRAY_ASET(existing, PROP_SOURCE_ORDER, LONG2NUM(source_order));
            RARRAY_ASET(existing, PROP_SPECIFICITY, INT2NUM(data->specificity));
            RARRAY_ASET(existing, PROP_IMPORTANT, is_important ? Qtrue : Qfalse);
            RARRAY_ASET(existing, PROP_VALUE, prop_value);
        }
    }

    return ST_CONTINUE;
}

// Context for flatten_selector_group_callback
struct flatten_selectors_context {
    VALUE merged_rules;
    VALUE rules_array;
    int *rule_id_counter;
    long selector_index;
    long total_selectors;
};

// Forward declaration
static VALUE flatten_rules_for_selector(VALUE rules_array, VALUE rule_indices, VALUE selector, VALUE *out_selector_list_id);

// Callback for rb_hash_foreach when merging selector groups
static int flatten_selector_group_callback(VALUE selector, VALUE group_indices, VALUE arg) {
    struct flatten_selectors_context *ctx = (struct flatten_selectors_context *)arg;
    ctx->selector_index++;

    DEBUG_PRINTF("\n[Selector %ld/%ld] '%s' - %ld rules in group\n",
                 ctx->selector_index, ctx->total_selectors,
                 RSTRING_PTR(selector), RARRAY_LEN(group_indices));

    // Merge all rules in this selector group and preserve selector_list_id if all rules share same ID
    VALUE selector_list_id = Qnil;
    VALUE merged_decls = flatten_rules_for_selector(ctx->rules_array, group_indices, selector, &selector_list_id);

    // Create new rule with this selector and merged declarations
    VALUE new_rule = rb_struct_new(cRule,
        INT2FIX((*ctx->rule_id_counter)++),
        selector,
        merged_decls,
        Qnil,  // specificity
        Qnil,  // parent_rule_id
        Qnil,  // nesting_style
        selector_list_id  // Preserve selector_list_id if all rules in group share same ID
    );
    rb_ary_push(ctx->merged_rules, new_rule);

    return ST_CONTINUE;
}

/*
 * Helper function: Merge multiple rules with the same selector
 *
 * Takes an array of rule indices that all share the same selector,
 * expands shorthands, applies cascade rules, and recreates shorthands.
 *
 * @param out_selector_list_id Output parameter: set to selector_list_id if all rules share same ID, else Qnil
 * Returns: Array of merged Declaration structs
 */
static VALUE flatten_rules_for_selector(VALUE rules_array, VALUE rule_indices, VALUE selector, VALUE *out_selector_list_id) {
    long num_rules_in_group = RARRAY_LEN(rule_indices);
    VALUE properties_hash = rb_hash_new();

    DEBUG_PRINTF("    [flatten_rules_for_selector] Merging %ld rules for selector '%s'\n",
                 num_rules_in_group, RSTRING_PTR(selector));

    // Extract selector_list_id from rules - preserve if all rules share same ID
    VALUE first_selector_list_id = Qnil;
    int all_same_selector_list_id = 1;

    DEBUG_PRINTF("    Checking if rules share same selector_list_id...\n");

    for (long g = 0; g < num_rules_in_group; g++) {
        long rule_idx = FIX2LONG(rb_ary_entry(rule_indices, g));
        VALUE rule = RARRAY_AREF(rules_array, rule_idx);

        // Skip AtRule objects - they don't have selector_list_id
        if (rb_obj_is_kind_of(rule, cAtRule)) {
            continue;
        }

        VALUE selector_list_id = rb_struct_aref(rule, INT2FIX(RULE_SELECTOR_LIST_ID));

        if (NIL_P(selector_list_id)) {
            DEBUG_PRINTF("      Rule %ld: has nil selector_list_id, can't preserve\n", g);
            // If any rule has nil selector_list_id, can't preserve
            all_same_selector_list_id = 0;
            break;
        }

        if (g == 0 || NIL_P(first_selector_list_id)) {
            first_selector_list_id = selector_list_id;
            DEBUG_PRINTF("      Rule %ld: first selector_list_id=%ld\n", g, NUM2LONG(first_selector_list_id));
        } else if (!rb_equal(first_selector_list_id, selector_list_id)) {
            DEBUG_PRINTF("      Rule %ld: different selector_list_id=%ld (vs %ld), can't preserve\n",
                         g, NUM2LONG(selector_list_id), NUM2LONG(first_selector_list_id));
            // Different selector_list_ids - can't preserve
            all_same_selector_list_id = 0;
            break;
        } else {
            DEBUG_PRINTF("      Rule %ld: same selector_list_id=%ld\n", g, NUM2LONG(selector_list_id));
        }
    }

    // Set output parameter: preserve selector_list_id only if all rules share same ID
    if (out_selector_list_id) {
        *out_selector_list_id = (all_same_selector_list_id && !NIL_P(first_selector_list_id)) ? first_selector_list_id : Qnil;
        if (!NIL_P(*out_selector_list_id)) {
            DEBUG_PRINTF("    -> Preserving selector_list_id=%ld for merged rule\n", NUM2LONG(*out_selector_list_id));
        } else {
            DEBUG_PRINTF("    -> NOT preserving selector_list_id (not all same)\n");
        }
    }

    // Process each rule in this selector group
    for (long g = 0; g < num_rules_in_group; g++) {
        long rule_idx = FIX2LONG(rb_ary_entry(rule_indices, g));
        VALUE rule = RARRAY_AREF(rules_array, rule_idx);

        // Skip AtRule objects (@keyframes, @font-face, etc.) - they don't have declarations to merge
        // AtRule has 'content' (string) instead of 'declarations' (array) at field index 2
        if (rb_obj_is_kind_of(rule, cAtRule)) {
            DEBUG_PRINTF("      [Rule %ld/%ld] Skipping AtRule (no declarations to merge)\n",
                         g + 1, num_rules_in_group);
            continue;
        }

        VALUE rule_id_val = rb_struct_aref(rule, INT2FIX(RULE_ID));
        long rule_id = NUM2LONG(rule_id_val);
        VALUE declarations = rb_struct_aref(rule, INT2FIX(RULE_DECLARATIONS));
        long num_decls = RARRAY_LEN(declarations);

        DEBUG_PRINTF("      [Rule %ld/%ld] rule_id=%ld, %ld declarations\n",
                     g + 1, num_rules_in_group, rule_id, num_decls);

        // Process each declaration
        for (long j = 0; j < num_decls; j++) {
            VALUE decl = RARRAY_AREF(declarations, j);
            VALUE property = rb_struct_aref(decl, INT2FIX(DECL_PROPERTY));
            VALUE value = rb_struct_aref(decl, INT2FIX(DECL_VALUE));
            VALUE important = rb_struct_aref(decl, INT2FIX(DECL_IMPORTANT));
            int is_important = RTEST(important);

            // Calculate source order
            long source_order = rule_id * 1000 + j;

            DEBUG_PRINTF("        [Decl %ld] %s: %s%s (source_order=%ld)\n",
                         j, RSTRING_PTR(property), RSTRING_PTR(value),
                         is_important ? " !important" : "", source_order);

            // Expand shorthands (margin, padding, background, font, etc.)
            // The expand functions return an array of Declaration structs
            const char *prop_cstr = RSTRING_PTR(property);
            VALUE expanded = Qnil;

            // Early exit: shorthand properties only start with m, p, b, f, or l
            char first_char = prop_cstr[0];
            if (first_char == 'm' || first_char == 'p' || first_char == 'b' ||
                first_char == 'f' || first_char == 'l') {
                // Potentially a shorthand - check specific property names
                if (strcmp(prop_cstr, "margin") == 0) {
                    expanded = cataract_expand_margin(Qnil, value);
                    DEBUG_PRINTF("          -> Expanding margin shorthand (%ld longhands)\n", RARRAY_LEN(expanded));
                } else if (strcmp(prop_cstr, "padding") == 0) {
                    expanded = cataract_expand_padding(Qnil, value);
                    DEBUG_PRINTF("          -> Expanding padding shorthand (%ld longhands)\n", RARRAY_LEN(expanded));
                } else if (strcmp(prop_cstr, "background") == 0) {
                    expanded = cataract_expand_background(Qnil, value);
                    DEBUG_PRINTF("          -> Expanding background shorthand (%ld longhands)\n", RARRAY_LEN(expanded));
                } else if (strcmp(prop_cstr, "font") == 0) {
                    expanded = cataract_expand_font(Qnil, value);
                    DEBUG_PRINTF("          -> Expanding font shorthand (%ld longhands)\n", RARRAY_LEN(expanded));
                } else if (strcmp(prop_cstr, "border") == 0) {
                    expanded = cataract_expand_border(Qnil, value);
                    DEBUG_PRINTF("          -> Expanding border shorthand (%ld longhands)\n", RARRAY_LEN(expanded));
                } else if (strcmp(prop_cstr, "border-color") == 0) {
                    expanded = cataract_expand_border_color(Qnil, value);
                    DEBUG_PRINTF("          -> Expanding border-color shorthand (%ld longhands)\n", RARRAY_LEN(expanded));
                } else if (strcmp(prop_cstr, "border-style") == 0) {
                    expanded = cataract_expand_border_style(Qnil, value);
                    DEBUG_PRINTF("          -> Expanding border-style shorthand (%ld longhands)\n", RARRAY_LEN(expanded));
                } else if (strcmp(prop_cstr, "border-width") == 0) {
                    expanded = cataract_expand_border_width(Qnil, value);
                    DEBUG_PRINTF("          -> Expanding border-width shorthand (%ld longhands)\n", RARRAY_LEN(expanded));
                } else if (strcmp(prop_cstr, "list-style") == 0) {
                    expanded = cataract_expand_list_style(Qnil, value);
                    DEBUG_PRINTF("          -> Expanding list-style shorthand (%ld longhands)\n", RARRAY_LEN(expanded));
                } else if (strcmp(prop_cstr, "border-top") == 0) {
                    expanded = cataract_expand_border_side(Qnil, STR_NEW_CSTR("top"), value);
                    DEBUG_PRINTF("          -> Expanding border-top shorthand (%ld longhands)\n", RARRAY_LEN(expanded));
                } else if (strcmp(prop_cstr, "border-right") == 0) {
                    expanded = cataract_expand_border_side(Qnil, STR_NEW_CSTR("right"), value);
                    DEBUG_PRINTF("          -> Expanding border-right shorthand (%ld longhands)\n", RARRAY_LEN(expanded));
                } else if (strcmp(prop_cstr, "border-bottom") == 0) {
                    expanded = cataract_expand_border_side(Qnil, STR_NEW_CSTR("bottom"), value);
                    DEBUG_PRINTF("          -> Expanding border-bottom shorthand (%ld longhands)\n", RARRAY_LEN(expanded));
                } else if (strcmp(prop_cstr, "border-left") == 0) {
                    expanded = cataract_expand_border_side(Qnil, STR_NEW_CSTR("left"), value);
                    DEBUG_PRINTF("          -> Expanding border-left shorthand (%ld longhands)\n", RARRAY_LEN(expanded));
                }
            }
            // If first_char doesn't match, expanded stays Qnil and we skip to processing original property

            // Process expanded properties or the original property
            if (!NIL_P(expanded) && RARRAY_LEN(expanded) > 0) {
                // Iterate over expanded Declaration array
                struct expand_property_data expand_data = {
                    .properties_hash = properties_hash,
                    .selector = selector,
                    .specificity = -1,  // Lazy: calculated only when needed
                    .is_important = is_important,
                    .source_order = source_order
                };
                long expanded_len = RARRAY_LEN(expanded);
                for (long i = 0; i < expanded_len; i++) {
                    VALUE decl = rb_ary_entry(expanded, i);
                    VALUE prop = rb_struct_aref(decl, INT2FIX(DECL_PROPERTY));
                    VALUE val = rb_struct_aref(decl, INT2FIX(DECL_VALUE));
                    process_expanded_property(prop, val, (VALUE)&expand_data);
                }
            } else {
                // No expansion - process the original property directly
                struct expand_property_data expand_data = {
                    .properties_hash = properties_hash,
                    .selector = selector,
                    .specificity = -1,  // Lazy: calculated only when needed
                    .is_important = is_important,
                    .source_order = source_order
                };
                process_expanded_property(property, value, (VALUE)&expand_data);
            }

            // GC guard: protect property and value from being collected while their
            // C string pointers (from RSTRING_PTR) are in use above
            RB_GC_GUARD(property);
            RB_GC_GUARD(value);
        }
    }

    // Recreate shorthands where possible (reduces output size)
    DEBUG_PRINTF("    [flatten_rules_for_selector] Recreating shorthands...\n");

    // Try to recreate all 4-sided shorthands using the mapping table
    for (const struct shorthand_mapping *mapping = SHORTHAND_MAPPINGS; mapping->shorthand_name != NULL; mapping++) {
        try_recreate_shorthand(properties_hash, mapping);
    }

    // Try to recreate full border shorthand (if border-width, border-style, border-color present)
    {
        VALUE width = rb_hash_aref(properties_hash, STR_NEW_CSTR("border-width"));
        VALUE style = rb_hash_aref(properties_hash, STR_NEW_CSTR("border-style"));
        VALUE color = rb_hash_aref(properties_hash, STR_NEW_CSTR("border-color"));

        // Need at least style (border shorthand requires style)
        if (!NIL_P(style)) {
            // Check all have same !important flag
            VALUE style_imp = RARRAY_AREF(style, PROP_IMPORTANT);
            int same_importance = 1;
            if (!NIL_P(width)) same_importance = same_importance && (RTEST(style_imp) == RTEST(RARRAY_AREF(width, PROP_IMPORTANT)));
            if (!NIL_P(color)) same_importance = same_importance && (RTEST(style_imp) == RTEST(RARRAY_AREF(color, PROP_IMPORTANT)));

            if (same_importance) {
                VALUE props = rb_hash_new();
                if (!NIL_P(width)) rb_hash_aset(props, STR_NEW_CSTR("border-width"), RARRAY_AREF(width, PROP_VALUE));
                rb_hash_aset(props, STR_NEW_CSTR("border-style"), RARRAY_AREF(style, PROP_VALUE));
                if (!NIL_P(color)) rb_hash_aset(props, STR_NEW_CSTR("border-color"), RARRAY_AREF(color, PROP_VALUE));

                VALUE shorthand_value = cataract_create_border_shorthand(Qnil, props);
                if (!NIL_P(shorthand_value)) {
                    VALUE shorthand_data = rb_ary_new_capa(4);
                    rb_ary_push(shorthand_data, RARRAY_AREF(style, PROP_SOURCE_ORDER));
                    rb_ary_push(shorthand_data, RARRAY_AREF(style, PROP_SPECIFICITY));
                    rb_ary_push(shorthand_data, style_imp);
                    rb_ary_push(shorthand_data, shorthand_value);
                    rb_hash_aset(properties_hash, USASCII_STR("border"), shorthand_data);

                    rb_hash_delete(properties_hash, STR_NEW_CSTR("border-width"));
                    rb_hash_delete(properties_hash, STR_NEW_CSTR("border-style"));
                    rb_hash_delete(properties_hash, STR_NEW_CSTR("border-color"));
                    DEBUG_PRINTF("      -> Recreated border shorthand\n");
                }
            }
        }
    }

    // Try to recreate list-style shorthand
    {
        VALUE type = rb_hash_aref(properties_hash, STR_NEW_CSTR("list-style-type"));
        VALUE position = rb_hash_aref(properties_hash, STR_NEW_CSTR("list-style-position"));
        VALUE image = rb_hash_aref(properties_hash, STR_NEW_CSTR("list-style-image"));

        // Need at least 2 properties to create shorthand
        // Single property should stay as longhand (semantic difference)
        int list_count = 0;
        if (!NIL_P(type)) list_count++;
        if (!NIL_P(position)) list_count++;
        if (!NIL_P(image)) list_count++;

        if (list_count >= 2) {
            // Check all have same !important flag
            VALUE first_imp = Qnil;
            if (!NIL_P(type)) first_imp = RARRAY_AREF(type, PROP_IMPORTANT);
            else if (!NIL_P(position)) first_imp = RARRAY_AREF(position, PROP_IMPORTANT);
            else if (!NIL_P(image)) first_imp = RARRAY_AREF(image, PROP_IMPORTANT);

            int same_importance = 1;
            if (!NIL_P(type)) same_importance = same_importance && (RTEST(first_imp) == RTEST(RARRAY_AREF(type, PROP_IMPORTANT)));
            if (!NIL_P(position)) same_importance = same_importance && (RTEST(first_imp) == RTEST(RARRAY_AREF(position, PROP_IMPORTANT)));
            if (!NIL_P(image)) same_importance = same_importance && (RTEST(first_imp) == RTEST(RARRAY_AREF(image, PROP_IMPORTANT)));

            if (same_importance) {
                VALUE props = rb_hash_new();
                if (!NIL_P(type)) rb_hash_aset(props, STR_NEW_CSTR("list-style-type"), RARRAY_AREF(type, PROP_VALUE));
                if (!NIL_P(position)) rb_hash_aset(props, STR_NEW_CSTR("list-style-position"), RARRAY_AREF(position, PROP_VALUE));
                if (!NIL_P(image)) rb_hash_aset(props, STR_NEW_CSTR("list-style-image"), RARRAY_AREF(image, PROP_VALUE));

                VALUE shorthand_value = cataract_create_list_style_shorthand(Qnil, props);
                if (!NIL_P(shorthand_value)) {
                    VALUE first_prop = !NIL_P(type) ? type : (!NIL_P(position) ? position : image);
                    VALUE shorthand_data = rb_ary_new_capa(4);
                    rb_ary_push(shorthand_data, RARRAY_AREF(first_prop, PROP_SOURCE_ORDER));
                    rb_ary_push(shorthand_data, RARRAY_AREF(first_prop, PROP_SPECIFICITY));
                    rb_ary_push(shorthand_data, first_imp);
                    rb_ary_push(shorthand_data, shorthand_value);
                    rb_hash_aset(properties_hash, USASCII_STR("list-style"), shorthand_data);

                    rb_hash_delete(properties_hash, STR_NEW_CSTR("list-style-type"));
                    rb_hash_delete(properties_hash, STR_NEW_CSTR("list-style-position"));
                    rb_hash_delete(properties_hash, STR_NEW_CSTR("list-style-image"));
                    DEBUG_PRINTF("      -> Recreated list-style shorthand\n");
                }
            }
        }
    }

    // Try to recreate font shorthand (requires at least font-size and font-family)
    {
        VALUE size = rb_hash_aref(properties_hash, STR_NEW_CSTR("font-size"));
        VALUE family = rb_hash_aref(properties_hash, STR_NEW_CSTR("font-family"));

        if (!NIL_P(size) && !NIL_P(family)) {
            VALUE style = rb_hash_aref(properties_hash, STR_NEW_CSTR("font-style"));
            VALUE variant = rb_hash_aref(properties_hash, STR_NEW_CSTR("font-variant"));
            VALUE weight = rb_hash_aref(properties_hash, STR_NEW_CSTR("font-weight"));
            VALUE line_height = rb_hash_aref(properties_hash, STR_NEW_CSTR("line-height"));

            // Check all font properties have same !important flag
            VALUE size_imp = RARRAY_AREF(size, PROP_IMPORTANT);
            VALUE family_imp = RARRAY_AREF(family, PROP_IMPORTANT);

            int same_importance = (RTEST(size_imp) == RTEST(family_imp));
            if (!NIL_P(style)) same_importance = same_importance && (RTEST(size_imp) == RTEST(RARRAY_AREF(style, PROP_IMPORTANT)));
            if (!NIL_P(variant)) same_importance = same_importance && (RTEST(size_imp) == RTEST(RARRAY_AREF(variant, PROP_IMPORTANT)));
            if (!NIL_P(weight)) same_importance = same_importance && (RTEST(size_imp) == RTEST(RARRAY_AREF(weight, PROP_IMPORTANT)));
            if (!NIL_P(line_height)) same_importance = same_importance && (RTEST(size_imp) == RTEST(RARRAY_AREF(line_height, PROP_IMPORTANT)));

            if (same_importance) {
                VALUE props = rb_hash_new();
                rb_hash_aset(props, STR_NEW_CSTR("font-size"), RARRAY_AREF(size, PROP_VALUE));
                rb_hash_aset(props, STR_NEW_CSTR("font-family"), RARRAY_AREF(family, PROP_VALUE));
                if (!NIL_P(style)) rb_hash_aset(props, STR_NEW_CSTR("font-style"), RARRAY_AREF(style, PROP_VALUE));
                if (!NIL_P(variant)) rb_hash_aset(props, STR_NEW_CSTR("font-variant"), RARRAY_AREF(variant, PROP_VALUE));
                if (!NIL_P(weight)) rb_hash_aset(props, STR_NEW_CSTR("font-weight"), RARRAY_AREF(weight, PROP_VALUE));
                if (!NIL_P(line_height)) rb_hash_aset(props, STR_NEW_CSTR("line-height"), RARRAY_AREF(line_height, PROP_VALUE));

                VALUE shorthand_value = cataract_create_font_shorthand(Qnil, props);
                if (!NIL_P(shorthand_value)) {
                    VALUE shorthand_data = rb_ary_new_capa(4);
                    rb_ary_push(shorthand_data, RARRAY_AREF(size, PROP_SOURCE_ORDER));
                    rb_ary_push(shorthand_data, RARRAY_AREF(size, PROP_SPECIFICITY));
                    rb_ary_push(shorthand_data, size_imp);
                    rb_ary_push(shorthand_data, shorthand_value);
                    rb_hash_aset(properties_hash, USASCII_STR("font"), shorthand_data);

                    rb_hash_delete(properties_hash, STR_NEW_CSTR("font-size"));
                    rb_hash_delete(properties_hash, STR_NEW_CSTR("font-family"));
                    rb_hash_delete(properties_hash, STR_NEW_CSTR("font-style"));
                    rb_hash_delete(properties_hash, STR_NEW_CSTR("font-variant"));
                    rb_hash_delete(properties_hash, STR_NEW_CSTR("font-weight"));
                    rb_hash_delete(properties_hash, STR_NEW_CSTR("line-height"));
                    DEBUG_PRINTF("      -> Recreated font shorthand\n");
                }
            }
        }
    }

    // Try to recreate background shorthand (if 2+ properties present)
    {
        VALUE color = rb_hash_aref(properties_hash, STR_NEW_CSTR("background-color"));
        VALUE image = rb_hash_aref(properties_hash, STR_NEW_CSTR("background-image"));
        VALUE repeat = rb_hash_aref(properties_hash, STR_NEW_CSTR("background-repeat"));
        VALUE position = rb_hash_aref(properties_hash, STR_NEW_CSTR("background-position"));
        VALUE attachment = rb_hash_aref(properties_hash, STR_NEW_CSTR("background-attachment"));

        int bg_count = 0;
        if (!NIL_P(color)) bg_count++;
        if (!NIL_P(image)) bg_count++;
        if (!NIL_P(repeat)) bg_count++;
        if (!NIL_P(position)) bg_count++;
        if (!NIL_P(attachment)) bg_count++;

        // Need at least 2 properties to create shorthand
        if (bg_count >= 2) {
            // Check all have same !important flag
            VALUE first_imp = Qnil;
            if (!NIL_P(color)) first_imp = RARRAY_AREF(color, PROP_IMPORTANT);
            else if (!NIL_P(image)) first_imp = RARRAY_AREF(image, PROP_IMPORTANT);
            else if (!NIL_P(repeat)) first_imp = RARRAY_AREF(repeat, PROP_IMPORTANT);
            else if (!NIL_P(position)) first_imp = RARRAY_AREF(position, PROP_IMPORTANT);
            else if (!NIL_P(attachment)) first_imp = RARRAY_AREF(attachment, PROP_IMPORTANT);

            int same_importance = 1;
            if (!NIL_P(color)) same_importance = same_importance && (RTEST(first_imp) == RTEST(RARRAY_AREF(color, PROP_IMPORTANT)));
            if (!NIL_P(image)) same_importance = same_importance && (RTEST(first_imp) == RTEST(RARRAY_AREF(image, PROP_IMPORTANT)));
            if (!NIL_P(repeat)) same_importance = same_importance && (RTEST(first_imp) == RTEST(RARRAY_AREF(repeat, PROP_IMPORTANT)));
            if (!NIL_P(position)) same_importance = same_importance && (RTEST(first_imp) == RTEST(RARRAY_AREF(position, PROP_IMPORTANT)));
            if (!NIL_P(attachment)) same_importance = same_importance && (RTEST(first_imp) == RTEST(RARRAY_AREF(attachment, PROP_IMPORTANT)));

            if (same_importance) {
                VALUE props = rb_hash_new();
                if (!NIL_P(color)) rb_hash_aset(props, STR_NEW_CSTR("background-color"), RARRAY_AREF(color, PROP_VALUE));
                if (!NIL_P(image)) rb_hash_aset(props, STR_NEW_CSTR("background-image"), RARRAY_AREF(image, PROP_VALUE));
                if (!NIL_P(repeat)) rb_hash_aset(props, STR_NEW_CSTR("background-repeat"), RARRAY_AREF(repeat, PROP_VALUE));
                if (!NIL_P(position)) rb_hash_aset(props, STR_NEW_CSTR("background-position"), RARRAY_AREF(position, PROP_VALUE));
                if (!NIL_P(attachment)) rb_hash_aset(props, STR_NEW_CSTR("background-attachment"), RARRAY_AREF(attachment, PROP_VALUE));

                VALUE shorthand_value = cataract_create_background_shorthand(Qnil, props);
                if (!NIL_P(shorthand_value)) {
                    VALUE first_prop = !NIL_P(color) ? color : (!NIL_P(image) ? image : (!NIL_P(repeat) ? repeat : (!NIL_P(position) ? position : attachment)));
                    VALUE shorthand_data = rb_ary_new_capa(4);
                    rb_ary_push(shorthand_data, RARRAY_AREF(first_prop, PROP_SOURCE_ORDER));
                    rb_ary_push(shorthand_data, RARRAY_AREF(first_prop, PROP_SPECIFICITY));
                    rb_ary_push(shorthand_data, first_imp);
                    rb_ary_push(shorthand_data, shorthand_value);
                    rb_hash_aset(properties_hash, USASCII_STR("background"), shorthand_data);

                    rb_hash_delete(properties_hash, STR_NEW_CSTR("background-color"));
                    rb_hash_delete(properties_hash, STR_NEW_CSTR("background-image"));
                    rb_hash_delete(properties_hash, STR_NEW_CSTR("background-repeat"));
                    rb_hash_delete(properties_hash, STR_NEW_CSTR("background-position"));
                    rb_hash_delete(properties_hash, STR_NEW_CSTR("background-attachment"));
                    DEBUG_PRINTF("      -> Recreated background shorthand\n");
                }
            }
        }
    }

    // Build declarations array from properties_hash
    // NOTE: We don't sort by source_order here because:
    // 1. Hash iteration order reflects insertion order
    // 2. Declaration order doesn't affect CSS behavior (cascade is already resolved)
    // 3. Sorting would add overhead for purely aesthetic output
    // The output order is roughly source order but may vary when properties are
    // overridden by later rules with higher specificity or importance.
    VALUE merged_decls = rb_ary_new();
    rb_hash_foreach(properties_hash, flatten_build_result_callback, merged_decls);

    DEBUG_PRINTF("    [flatten_rules_for_selector] Result: %ld merged declarations\n",
                 RARRAY_LEN(merged_decls));

    return merged_decls;
}

/*
 * Helper function: Check if two declaration arrays are equal
 *
 * Returns: true if declarations have same properties, values, and importance
 */
static int declarations_equal(VALUE decls1, VALUE decls2) {
    long len1 = RARRAY_LEN(decls1);
    long len2 = RARRAY_LEN(decls2);

    DEBUG_PRINTF("      [declarations_equal] Comparing %ld vs %ld declarations\n", len1, len2);

    if (len1 != len2) {
        DEBUG_PRINTF("      -> Different lengths, NOT equal\n");
        return 0;
    }

    // Compare each declaration (property, value, important must all match)
    for (long i = 0; i < len1; i++) {
        VALUE d1 = RARRAY_AREF(decls1, i);
        VALUE d2 = RARRAY_AREF(decls2, i);

        VALUE prop1 = rb_struct_aref(d1, INT2FIX(DECL_PROPERTY));
        VALUE prop2 = rb_struct_aref(d2, INT2FIX(DECL_PROPERTY));
        VALUE val1 = rb_struct_aref(d1, INT2FIX(DECL_VALUE));
        VALUE val2 = rb_struct_aref(d2, INT2FIX(DECL_VALUE));
        VALUE imp1 = rb_struct_aref(d1, INT2FIX(DECL_IMPORTANT));
        VALUE imp2 = rb_struct_aref(d2, INT2FIX(DECL_IMPORTANT));

        if (!rb_equal(prop1, prop2) || !rb_equal(val1, val2) || (RTEST(imp1) != RTEST(imp2))) {
            DEBUG_PRINTF("      -> Decl %ld differs: %s:%s%s vs %s:%s%s\n",
                         i,
                         RSTRING_PTR(prop1), RSTRING_PTR(val1), RTEST(imp1) ? "!" : "",
                         RSTRING_PTR(prop2), RSTRING_PTR(val2), RTEST(imp2) ? "!" : "");
            // Protect VALUEs from GC after rb_equal() calls and before RSTRING_PTR usage above
            RB_GC_GUARD(prop1);
            RB_GC_GUARD(val1);
            RB_GC_GUARD(prop2);
            RB_GC_GUARD(val2);
            return 0;
        }
    }

    DEBUG_PRINTF("      -> All declarations match, equal\n");
    return 1;
}

/*
 * Update selector lists to remove diverged rules
 *
 * After flattening/cascade, rules that were in the same selector list may have
 * different declarations. This function builds the selector_lists hash with only
 * rules that still match, and clears selector_list_id for diverged rules.
 *
 * @param merged_rules Array of flattened rules (with new IDs assigned)
 * @param selector_lists Empty hash to populate with list_id => Array of rule IDs
 */
static void update_selector_lists_for_divergence(VALUE merged_rules, VALUE selector_lists) {
    DEBUG_PRINTF("\n=== update_selector_lists_for_divergence ===\n");

    // Group merged rules by selector_list_id (skip rules with no list)
    // NOTE: Using manual iteration instead of group_by to avoid Ruby method calls
    VALUE rules_by_list = rb_hash_new();

    long num_rules = RARRAY_LEN(merged_rules);
    DEBUG_PRINTF("  Total merged rules: %ld\n", num_rules);

    for (long i = 0; i < num_rules; i++) {
        VALUE rule = RARRAY_AREF(merged_rules, i);

        // Skip AtRule objects
        if (rb_obj_is_kind_of(rule, cAtRule)) {
            continue;
        }

        VALUE selector_list_id = rb_struct_aref(rule, INT2FIX(RULE_SELECTOR_LIST_ID));
        VALUE selector = rb_struct_aref(rule, INT2FIX(RULE_SELECTOR));

        if (NIL_P(selector_list_id)) {
            DEBUG_PRINTF("  Rule %ld (%s): no selector_list_id\n", i, RSTRING_PTR(selector));
            continue;
        }

        DEBUG_PRINTF("  Rule %ld (%s): selector_list_id=%ld\n",
                     i, RSTRING_PTR(selector), NUM2LONG(selector_list_id));

        VALUE group = rb_hash_aref(rules_by_list, selector_list_id);
        if (NIL_P(group)) {
            group = rb_ary_new();
            rb_hash_aset(rules_by_list, selector_list_id, group);
            DEBUG_PRINTF("    -> Created new group for list_id=%ld\n", NUM2LONG(selector_list_id));
        }
        rb_ary_push(group, rule);
    }

    // For each selector list, check if declarations still match
    VALUE list_ids = rb_funcall(rules_by_list, rb_intern("keys"), 0);
    long num_lists = RARRAY_LEN(list_ids);
    DEBUG_PRINTF("  Found %ld selector list groups to check\n", num_lists);

    for (long i = 0; i < num_lists; i++) {
        VALUE list_id = RARRAY_AREF(list_ids, i);
        VALUE rules_in_list = rb_hash_aref(rules_by_list, list_id);
        long num_in_list = RARRAY_LEN(rules_in_list);

        DEBUG_PRINTF("\n  Checking list_id=%ld: %ld rules\n", NUM2LONG(list_id), num_in_list);

        // Skip if only one rule in list (nothing to compare)
        if (num_in_list <= 1) {
            DEBUG_PRINTF("    -> Only 1 rule, skipping\n");
            continue;
        }

        // Get first rule as reference
        VALUE reference_rule = RARRAY_AREF(rules_in_list, 0);
        VALUE reference_selector = rb_struct_aref(reference_rule, INT2FIX(RULE_SELECTOR));
        VALUE reference_decls = rb_struct_aref(reference_rule, INT2FIX(RULE_DECLARATIONS));

        DEBUG_PRINTF("    Reference rule: selector=%s, %ld declarations\n",
                     RSTRING_PTR(reference_selector), RARRAY_LEN(reference_decls));

        // Find rules that still match (have identical declarations)
        VALUE matching_rules = rb_ary_new();
        rb_ary_push(matching_rules, reference_rule);

        for (long j = 1; j < num_in_list; j++) {
            VALUE rule = RARRAY_AREF(rules_in_list, j);
            VALUE selector = rb_struct_aref(rule, INT2FIX(RULE_SELECTOR));
            VALUE decls = rb_struct_aref(rule, INT2FIX(RULE_DECLARATIONS));

            DEBUG_PRINTF("    Comparing rule %ld (selector=%s):\n", j, RSTRING_PTR(selector));

            if (declarations_equal(reference_decls, decls)) {
                DEBUG_PRINTF("      -> MATCHES reference, keeping in list\n");
                rb_ary_push(matching_rules, rule);
            } else {
                DEBUG_PRINTF("      -> DIVERGED from reference, clearing selector_list_id\n");
                // Clear selector_list_id for diverged rule
                rb_struct_aset(rule, INT2FIX(RULE_SELECTOR_LIST_ID), Qnil);
            }
        }

        // Only keep the selector list if at least 2 rules still match
        long num_matching = RARRAY_LEN(matching_rules);
        DEBUG_PRINTF("    Result: %ld/%ld rules still match\n", num_matching, num_in_list);

        if (num_matching >= 2) {
            // Build selector_lists hash with NEW rule IDs
            VALUE rule_ids = rb_ary_new_capa(num_matching);
            for (long j = 0; j < num_matching; j++) {
                VALUE rule = RARRAY_AREF(matching_rules, j);
                VALUE rule_id = rb_struct_aref(rule, INT2FIX(RULE_ID));
                rb_ary_push(rule_ids, rule_id);
            }
            rb_hash_aset(selector_lists, list_id, rule_ids);
            DEBUG_PRINTF("    -> Keeping selector list with %ld rules\n", num_matching);
        } else {
            DEBUG_PRINTF("    -> Only 1 rule left, clearing selector_list_id for it too\n");
            // Clear selector_list_id for the last remaining rule too
            for (long j = 0; j < num_matching; j++) {
                VALUE rule = RARRAY_AREF(matching_rules, j);
                rb_struct_aset(rule, INT2FIX(RULE_SELECTOR_LIST_ID), Qnil);
            }
        }
    }

    DEBUG_PRINTF("\n=== End divergence tracking: %ld selector lists preserved ===\n\n", RHASH_SIZE(selector_lists));
}

// Flatten CSS rules by applying cascade rules
// Input: Stylesheet object or CSS string
// Output: Stylesheet with flattened declarations (cascade applied)
VALUE cataract_flatten(VALUE self, VALUE input) {
    VALUE rules_array;

    // Handle different input types
    // Most calls pass Stylesheet (common case), String is rare
    if (TYPE(input) == T_STRING) {
        // Parse CSS string first
        VALUE argv[1] = { input };
        VALUE parsed = parse_css_new(1, argv, self);
        rules_array = rb_hash_aref(parsed, ID2SYM(rb_intern("rules")));
    } else if (rb_obj_is_kind_of(input, cStylesheet)) {
        // Extract @rules from Stylesheet (common case)
        rules_array = rb_ivar_get(input, id_ivar_rules);
    } else {
        rb_raise(rb_eTypeError, "Expected Stylesheet or String, got %s",
                rb_obj_classname(input));
    }

    Check_Type(rules_array, T_ARRAY);

    // Check if stylesheet has nesting (affects selector rollup)
    int has_nesting = 0;
    if (rb_obj_is_kind_of(input, cStylesheet)) {
        VALUE has_nesting_ivar = rb_ivar_get(input, rb_intern("@_has_nesting"));
        has_nesting = RTEST(has_nesting_ivar);
    }

    long num_rules = RARRAY_LEN(rules_array);
    // Empty stylesheets are rare
    if (num_rules == 0) {
        // Return empty stylesheet
        VALUE empty_sheet = rb_class_new_instance(0, NULL, cStylesheet);
        return empty_sheet;
    }

    /*
     * ============================================================================
     * FLATTEN ALGORITHM - Rules and Implementation Notes
     * ============================================================================
     *
     * CORE PRINCIPLE: Group rules by selector, flatten declarations within each group
     *
     * Different selectors (.test vs #test) target different elements and must stay separate.
     * Same selectors should flatten into one rule to reduce output size.
     *
     * ALGORITHM STEPS:
     * 1. Group rules by selector (.test, #test, etc.)
     * 2. For each selector group:
     *    a. Expand shorthand properties (margin, background, font, etc.)
     *    b. Apply CSS cascade rules to resolve conflicts
     *    c. Recreate shorthand properties where beneficial
     * 3. Output one rule per unique selector
     *
     * CSS CASCADE RULES (in order of precedence):
     * 1. !important declarations always win over non-!important
     * 2. Higher specificity wins (#id > .class > element)
     * 3. Later source order wins (for same importance + specificity)
     *
     * SOURCE ORDER CALCULATION:
     *   source_order = rule_id * 1000 + declaration_index
     * This ensures declarations within the same rule maintain relative order.
     *
     * SHORTHAND EXPANSION:
     * When flattening, all shorthands must be expanded to longhands first.
     * Example: "background: blue" expands to:
     *   - background-color: blue
     *   - background-image: none
     *   - background-repeat: repeat
     *   - background-position: 0% 0%
     *   - background-attachment: scroll
     *
     * This is REQUIRED because partial overrides must work correctly:
     *   .test { background: blue; }
     *   .test { background-image: url(x.png); }
     * Should result in: blue background with image (not image reset to none)
     *
     * SHORTHAND RECREATION:
     * After cascade resolution, recreate shorthands for smaller output:
     *   - margin-top: 10px, margin-right: 10px, ... → margin: 10px
     *   - background-color: blue, background-image: none, ... → background: blue
     *
     * Optimization: Omit default values ONLY when all properties are present
     * (indicating they came from shorthand expansion, not explicit longhands)
     *
     * If only some properties present (explicit longhands), include all values:
     *   background-color: black, background-image: none → "black none"
     * Not: "black" (user explicitly set image to none)
     *
     * If all properties present (from expansion), omit defaults:
     *   background-color: blue, background-image: none, repeat: repeat, ... → "blue"
     * (The "none", "repeat", etc. are just defaults from expansion)
     *
     * EDGE CASES:
     * - Empty rules (no declarations): Skip during flatten
     * - Nested CSS: Parent rules with children are containers only, skip their declarations
     * - Mixed !important: Properties with different importance cannot flatten into shorthand
     * - Single property: Don't create shorthand (e.g., background-color alone stays as-is)
     *   Reason: "background: blue" resets all other background properties to defaults,
     *   which is semantically different from just setting background-color.
     *
     * PERFORMANCE NOTES:
     * - Use cached static strings (VALUE) for property names (no allocation)
     * - Group by selector in single pass (O(n) hash building)
     * - Flatten within groups (O(n*m) where m is avg declarations per rule)
     * ============================================================================
     */

    // For nested CSS: identify parent rules (rules that have children)
    // These should be skipped during flatten, even if they have declarations
    // Use Ruby hash as a set: parent_id => true
    VALUE parent_ids = Qnil;
    if (has_nesting) {
        DEBUG_PRINTF("\n=== FLATTEN: has_nesting=true, num_rules=%ld ===\n", num_rules);
        parent_ids = rb_hash_new();
        for (long i = 0; i < num_rules; i++) {
            VALUE rule = RARRAY_AREF(rules_array, i);
            VALUE parent_rule_id = rb_struct_aref(rule, INT2FIX(RULE_PARENT_RULE_ID));
            DEBUG_PRINTF("  Rule %ld: selector='%s', rule_id=%d, parent_rule_id=%s\n",
                         i,
                         RSTRING_PTR(rb_struct_aref(rule, INT2FIX(RULE_SELECTOR))),
                         FIX2INT(rb_struct_aref(rule, INT2FIX(RULE_ID))),
                         NIL_P(parent_rule_id) ? "nil" : RSTRING_PTR(rb_inspect(parent_rule_id)));
            if (!NIL_P(parent_rule_id)) {
                // This rule has a parent, so mark that parent ID
                rb_hash_aset(parent_ids, parent_rule_id, Qtrue);
            }
        }
    }

    // ALWAYS build selector groups - this is the core of flatten logic
    // Group rules by selector: different selectors stay separate
    // selector => [rule indices]
    DEBUG_PRINTF("\n=== Building selector groups (has_nesting=%d) ===\n", has_nesting);
    VALUE selector_groups = rb_hash_new();
    VALUE passthrough_rules = rb_ary_new(); // AtRules to pass through unchanged

    for (long i = 0; i < num_rules; i++) {
        VALUE rule = RARRAY_AREF(rules_array, i);

        // Handle AtRule objects (@keyframes, @font-face, etc.) - pass through unchanged
        // AtRule has 'content' (string) instead of 'declarations' (array)
        if (rb_obj_is_kind_of(rule, cAtRule)) {
            DEBUG_PRINTF("  [Rule %ld] PASSTHROUGH: AtRule (e.g., @keyframes, @font-face)\n", i);
            rb_ary_push(passthrough_rules, rule);
            continue;
        }

        VALUE declarations = rb_struct_aref(rule, INT2FIX(RULE_DECLARATIONS));
        VALUE selector = rb_struct_aref(rule, INT2FIX(RULE_SELECTOR));

        // Skip empty rules (no declarations)
        // This handles both empty containers and rules with no properties
        if (RARRAY_LEN(declarations) == 0) {
            DEBUG_PRINTF("  [Rule %ld] SKIP: selector='%s' (empty declarations)\n",
                         i, RSTRING_PTR(selector));
            continue;
        }

        // Note: We do NOT skip parent rules that have children!
        // Per CSS spec, parent can have its own declarations AND nested rules.
        // Example: .parent { color: red; .child { color: blue; } }
        // Should output both .parent (color: red) and .parent .child (color: blue)
        // The nesting is already flattened during parsing, so they have different selectors.

        DEBUG_PRINTF("  [Rule %ld] ADD: selector='%s', %ld declarations\n",
                     i, RSTRING_PTR(selector), RARRAY_LEN(declarations));

        VALUE group = rb_hash_aref(selector_groups, selector);
        if (NIL_P(group)) {
            group = rb_ary_new();
            rb_hash_aset(selector_groups, selector, group);
            DEBUG_PRINTF("    -> Created new selector group for '%s'\n", RSTRING_PTR(selector));
        }
        rb_ary_push(group, LONG2FIX(i));
    }
    DEBUG_PRINTF("=== Total selector groups: %ld ===\n\n", RHASH_SIZE(selector_groups));

    // ALWAYS group by selector and keep them separate
    // Different selectors target different elements and must remain distinct
    // Example: .test { color: red; } #test { color: blue; }
    // Should return 2 rules (not merged into one)
    DEBUG_PRINTF("=== DECISION POINT ===\n");
    DEBUG_PRINTF("  selector_groups size: %ld\n", RHASH_SIZE(selector_groups));

    if (RHASH_SIZE(selector_groups) == 0 && RARRAY_LEN(passthrough_rules) == 0) {
        DEBUG_PRINTF("  -> No rules to merge (all were empty or skipped)\n");
        // Return empty stylesheet
        VALUE empty_sheet = rb_class_new_instance(0, NULL, cStylesheet);
        return empty_sheet;
    }

    // Handle case where we only have passthrough rules (no regular rules to merge)
    if (RHASH_SIZE(selector_groups) == 0 && RARRAY_LEN(passthrough_rules) > 0) {
        DEBUG_PRINTF("  -> Only passthrough rules (no regular rules to merge)\n");
        VALUE passthrough_sheet = rb_class_new_instance(0, NULL, cStylesheet);
        rb_ivar_set(passthrough_sheet, id_ivar_rules, passthrough_rules);

        // Set empty @media_index (no media rules after flatten)
        VALUE media_idx = rb_hash_new();
        rb_ivar_set(passthrough_sheet, id_ivar_media_index, media_idx);

        return passthrough_sheet;
    }

    if (RHASH_SIZE(selector_groups) > 0) {
        DEBUG_PRINTF("  -> Taking SELECTOR-GROUPED path (%ld unique selectors)\n",
                     RHASH_SIZE(selector_groups));
        VALUE merged_sheet = rb_class_new_instance(0, NULL, cStylesheet);
        VALUE merged_rules = rb_ary_new();
        int rule_id_counter = 0;

        // Iterate through each selector group using rb_hash_foreach
        // to avoid rb_funcall in hot path
        struct flatten_selectors_context merge_ctx;
        merge_ctx.merged_rules = merged_rules;
        merge_ctx.rules_array = rules_array;
        merge_ctx.rule_id_counter = &rule_id_counter;
        merge_ctx.selector_index = 0;
        merge_ctx.total_selectors = RHASH_SIZE(selector_groups);

        DEBUG_PRINTF("\n=== Processing %ld selector groups ===\n", merge_ctx.total_selectors);

        rb_hash_foreach(selector_groups, flatten_selector_group_callback, (VALUE)&merge_ctx);

        // Add passthrough AtRules to output (preserve @keyframes, @font-face, etc.)
        long num_passthrough = RARRAY_LEN(passthrough_rules);
        for (long i = 0; i < num_passthrough; i++) {
            VALUE at_rule = RARRAY_AREF(passthrough_rules, i);
            // Update AtRule's id to maintain sequential IDs
            rb_struct_aset(at_rule, INT2FIX(AT_RULE_ID), INT2FIX(rule_id_counter++));
            rb_ary_push(merged_rules, at_rule);
            DEBUG_PRINTF("  -> Added passthrough AtRule (new id=%d)\n", rule_id_counter - 1);
        }

        DEBUG_PRINTF("\n=== Created %d output rules (%ld passthrough) ===\n",
                     rule_id_counter, num_passthrough);

        rb_ivar_set(merged_sheet, id_ivar_rules, merged_rules);

        // Handle selector list divergence: remove rules from selector lists if declarations no longer match
        // This makes selector_list_id authoritative - if set, declarations MUST be identical
        // Only process if selector_lists is enabled in the stylesheet's parser options
        VALUE selector_lists = rb_hash_new();
        int selector_lists_enabled = 0;

        if (rb_obj_is_kind_of(input, cStylesheet)) {
            VALUE parser_options = rb_ivar_get(input, rb_intern("@parser_options"));

            if (!NIL_P(parser_options)) {
                VALUE enabled_val = rb_hash_aref(parser_options, ID2SYM(rb_intern("selector_lists")));
                selector_lists_enabled = RTEST(enabled_val);

                if (selector_lists_enabled) {
                    update_selector_lists_for_divergence(merged_rules, selector_lists);
                } else {
                    // Clear all selector_list_ids when feature is disabled
                    for (long i = 0; i < rule_id_counter; i++) {
                        VALUE rule = RARRAY_AREF(merged_rules, i);
                        if (!rb_obj_is_kind_of(rule, cAtRule)) {
                            rb_struct_aset(rule, INT2FIX(RULE_SELECTOR_LIST_ID), Qnil);
                        }
                    }
                }
            } else {
                // Default behavior when parser_options is nil: assume enabled
                selector_lists_enabled = 1;
                update_selector_lists_for_divergence(merged_rules, selector_lists);
            }
        }

        // Set @media_index to empty hash (no media rules after flatten)
        // NOTE: Setting to empty hash instead of { all: [ids] } to match pure Ruby behavior
        // and avoid wrapping output in @media all during serialization
        VALUE media_idx = rb_hash_new();
        rb_ivar_set(merged_sheet, id_ivar_media_index, media_idx);

        // Set @_selector_lists with divergence tracking
        rb_ivar_set(merged_sheet, rb_intern("@_selector_lists"), selector_lists);

        return merged_sheet;
    }

    // Single-merge path: merge all rules into one
    VALUE properties_hash = rb_hash_new();

    // Track selector for rollup (minimize allocations)
    // Store pointer + length to first non-parent selector
    // Also keep the VALUE alive since we extract C pointer before allocations
    const char *first_selector_ptr = NULL;
    long first_selector_len = 0;
    VALUE first_selector_value = Qnil;
    int all_same_selector = 1;

    // Track source order for cascade rules
    long source_order = 0;

    // Iterate through each rule
    for (long i = 0; i < num_rules; i++) {
        VALUE rule = RARRAY_AREF(rules_array, i);
        Check_Type(rule, T_STRUCT);

        // Extract rule fields
        VALUE rule_id = rb_struct_aref(rule, INT2FIX(RULE_ID));
        VALUE selector = rb_struct_aref(rule, INT2FIX(RULE_SELECTOR));
        VALUE declarations = rb_struct_aref(rule, INT2FIX(RULE_DECLARATIONS));

        // Skip parent rules when handling nested CSS
        // Example: .button { color: black; &:hover { color: red; } }
        //   - Rule id=0, selector=".button", declarations=[color: black] (SKIP - has children)
        //   - Rule id=1, selector=".button:hover", declarations=[color: red] (PROCESS)
        if (has_nesting && !NIL_P(parent_ids)) {
            VALUE is_parent = rb_hash_aref(parent_ids, rule_id);
            if (RTEST(is_parent)) {
                continue;
            }
        }

        long num_decls = RARRAY_LEN(declarations);
        // Skip rules with no declarations (empty parent containers)
        if (num_decls == 0) {
            continue;
        }

        // Track selectors for rollup (delay allocation)
        const char *sel_ptr = RSTRING_PTR(selector);
        long sel_len = RSTRING_LEN(selector);
        if (first_selector_ptr == NULL) {
            first_selector_ptr = sel_ptr;
            first_selector_len = sel_len;
            first_selector_value = selector;  // Keep VALUE alive for RB_GC_GUARD
        } else if (all_same_selector) {
            if (sel_len != first_selector_len || memcmp(sel_ptr, first_selector_ptr, sel_len) != 0) {
                all_same_selector = 0;
            }
        }

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

        for (long j = 0; j < num_decls; j++) {
            VALUE decl = RARRAY_AREF(declarations, j);

            // Extract property, value, important from Declaration struct
            VALUE property = rb_struct_aref(decl, INT2FIX(DECL_PROPERTY));
            VALUE value = rb_struct_aref(decl, INT2FIX(DECL_VALUE));
            VALUE important = rb_struct_aref(decl, INT2FIX(DECL_IMPORTANT));

            // Properties are already lowercased during parsing (see cataract_new.c)
            // No need to lowercase again
            int is_important = RTEST(important);

            // Expand shorthand properties if needed
            // Most properties are NOT shorthands, so hint compiler accordingly
            const char *prop_str = StringValueCStr(property);
            VALUE expanded = Qnil;

            // Early exit: shorthand properties only start with m, p, b, f, or l
            char first_char = prop_str[0];
            if (first_char == 'm' || first_char == 'p' || first_char == 'b' ||
                first_char == 'f' || first_char == 'l') {
                // Potentially a shorthand - check specific property names
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
            }
            // If first_char doesn't match, expanded stays Qnil

            // If property was expanded, iterate array and apply cascade
            // Expansion is rare (most properties are not shorthands)
            if (!NIL_P(expanded)) {
                Check_Type(expanded, T_ARRAY);

                struct expand_context ctx;
                ctx.properties_hash = properties_hash;
                ctx.source_order = source_order;
                ctx.specificity = specificity;
                ctx.important = important;

                long expanded_len = RARRAY_LEN(expanded);
                for (long i = 0; i < expanded_len; i++) {
                    VALUE decl = rb_ary_entry(expanded, i);
                    VALUE prop = rb_struct_aref(decl, INT2FIX(DECL_PROPERTY));
                    VALUE val = rb_struct_aref(decl, INT2FIX(DECL_VALUE));
                    flatten_expanded_callback(prop, val, (VALUE)&ctx);
                }

                RB_GC_GUARD(expanded);
                continue; // Skip processing the original shorthand property
            }

            // Apply CSS cascade rules
            VALUE existing = rb_hash_aref(properties_hash, property);

            // In merge scenarios, properties often collide (same property in multiple rules)
            // so existing property is the common case
            if (NIL_P(existing)) {
                // New property - add it as array: [source_order, specificity, important, value]
                VALUE prop_data = rb_ary_new_capa(4);
                rb_ary_push(prop_data, LONG2NUM(source_order));
                rb_ary_push(prop_data, INT2NUM(specificity));
                rb_ary_push(prop_data, important);
                rb_ary_push(prop_data, value);
                rb_hash_aset(properties_hash, property, prop_data);
            } else {
                // Property exists - check cascade rules
                long existing_order = NUM2LONG(RARRAY_AREF(existing, PROP_SOURCE_ORDER));
                int existing_spec_int = NUM2INT(RARRAY_AREF(existing, PROP_SPECIFICITY));
                VALUE existing_important = RARRAY_AREF(existing, PROP_IMPORTANT);
                int existing_is_important = RTEST(existing_important);

                int should_replace = 0;

                // Most declarations are NOT !important
                if (is_important) {
                    // New is !important - wins if existing is NOT important OR higher specificity OR (equal specificity AND later order)
                    if (!existing_is_important || existing_spec_int < specificity ||
                        (existing_spec_int == specificity && existing_order <= source_order)) {
                        should_replace = 1;
                    }
                } else {
                    // New is NOT important - only wins if existing is also NOT important AND (higher specificity OR equal specificity with later order)
                    if (!existing_is_important &&
                        (existing_spec_int < specificity ||
                         (existing_spec_int == specificity && existing_order <= source_order))) {
                        should_replace = 1;
                    }
                }

                // Replacement is common in merge scenarios
                if (should_replace) {
                    RARRAY_ASET(existing, PROP_SOURCE_ORDER, LONG2NUM(source_order));
                    RARRAY_ASET(existing, PROP_SPECIFICITY, INT2NUM(specificity));
                    RARRAY_ASET(existing, PROP_IMPORTANT, important);
                    RARRAY_ASET(existing, PROP_VALUE, value);
                }
            }

            RB_GC_GUARD(property);
            RB_GC_GUARD(value);
            RB_GC_GUARD(decl);
            source_order++;
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
        str_margin, cataract_create_margin_shorthand);

    // Try to create padding shorthand
    TRY_CREATE_FOUR_SIDED_SHORTHAND(properties_hash,
        str_padding_top, str_padding_right, str_padding_bottom, str_padding_left,
        str_padding, cataract_create_padding_shorthand);

    // Create border-width from individual sides
    TRY_CREATE_FOUR_SIDED_SHORTHAND(properties_hash,
        str_border_top_width, str_border_right_width, str_border_bottom_width, str_border_left_width,
        str_border_width, cataract_create_border_width_shorthand);

    // Create border-style from individual sides
    TRY_CREATE_FOUR_SIDED_SHORTHAND(properties_hash,
        str_border_top_style, str_border_right_style, str_border_bottom_style, str_border_left_style,
        str_border_style, cataract_create_border_style_shorthand);

    // Create border-color from individual sides
    TRY_CREATE_FOUR_SIDED_SHORTHAND(properties_hash,
        str_border_top_color, str_border_right_color, str_border_bottom_color, str_border_left_color,
        str_border_color, cataract_create_border_color_shorthand);

    // Now create border shorthand from border-{width,style,color}
    VALUE border_width = GET_PROP_VALUE_STR(properties_hash, str_border_width);
    VALUE border_style = GET_PROP_VALUE_STR(properties_hash, str_border_style);
    VALUE border_color = GET_PROP_VALUE_STR(properties_hash, str_border_color);

    if (!NIL_P(border_width) || !NIL_P(border_style) || !NIL_P(border_color)) {
        // Use first available property's metadata as reference
        VALUE border_data_src = !NIL_P(border_width) ? GET_PROP_DATA_STR(properties_hash, str_border_width) :
                                !NIL_P(border_style) ? GET_PROP_DATA_STR(properties_hash, str_border_style) :
                                GET_PROP_DATA_STR(properties_hash, str_border_color);
        VALUE border_important = RARRAY_AREF(border_data_src, PROP_IMPORTANT);
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
                VALUE border_data = rb_ary_new_capa(4);
                rb_ary_push(border_data, RARRAY_AREF(border_data_src, PROP_SOURCE_ORDER));
                rb_ary_push(border_data, RARRAY_AREF(border_data_src, PROP_SPECIFICITY));
                rb_ary_push(border_data, border_important);
                rb_ary_push(border_data, border_shorthand);
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
        VALUE font_important = RARRAY_AREF(size_data, PROP_IMPORTANT);
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
                VALUE font_data = rb_ary_new_capa(4);
                rb_ary_push(font_data, RARRAY_AREF(size_data, PROP_SOURCE_ORDER));
                rb_ary_push(font_data, RARRAY_AREF(size_data, PROP_SPECIFICITY));
                rb_ary_push(font_data, font_important);
                rb_ary_push(font_data, font_shorthand);
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
        VALUE list_style_important = RARRAY_AREF(list_style_data_src, PROP_IMPORTANT);
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
                VALUE list_style_data = rb_ary_new_capa(4);
                rb_ary_push(list_style_data, RARRAY_AREF(list_style_data_src, PROP_SOURCE_ORDER));
                rb_ary_push(list_style_data, RARRAY_AREF(list_style_data_src, PROP_SPECIFICITY));
                rb_ary_push(list_style_data, list_style_important);
                rb_ary_push(list_style_data, list_style_shorthand);
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
        VALUE background_important = RARRAY_AREF(background_data_src, PROP_IMPORTANT);
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
                VALUE background_data = rb_ary_new_capa(4);
                rb_ary_push(background_data, RARRAY_AREF(background_data_src, PROP_SOURCE_ORDER));
                rb_ary_push(background_data, RARRAY_AREF(background_data_src, PROP_SPECIFICITY));
                rb_ary_push(background_data, background_important);
                rb_ary_push(background_data, background_shorthand);
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
    rb_hash_foreach(properties_hash, flatten_build_result_callback, merged_declarations);

    // Determine final selector (allocate only once at the end)
    VALUE final_selector;
    if (has_nesting && all_same_selector && first_selector_ptr != NULL) {
        // All rules have same selector - use it for rollup
        final_selector = rb_usascii_str_new(first_selector_ptr, first_selector_len);
    } else {
        // Mixed selectors or no nesting - use "merged"
        final_selector = str_merged_selector;
    }

    // Create a new Stylesheet with a single merged rule
    // Use rb_class_new_instance instead of rb_funcall for better performance
    VALUE merged_sheet = rb_class_new_instance(0, NULL, cStylesheet);

    // Create merged rule
    VALUE merged_rule = rb_struct_new(cRule,
        INT2FIX(0),              // id
        final_selector,          // selector (rolled-up or "merged")
        merged_declarations,      // declarations
        Qnil,                     // specificity (not applicable)
        Qnil,                     // parent_rule_id (not nested)
        Qnil,                     // nesting_style (not nested)
        Qnil                      // selector_list_id
    );

    // Set @rules array with single merged rule (use cached ID)
    VALUE rules_ary = rb_ary_new_from_args(1, merged_rule);
    rb_ivar_set(merged_sheet, id_ivar_rules, rules_ary);

    // Set @media_index with :all pointing to rule 0 (use cached ID)
    VALUE media_idx = rb_hash_new();
    VALUE all_ids = rb_ary_new_from_args(1, INT2FIX(0));
    rb_hash_aset(media_idx, ID2SYM(id_all), all_ids);
    rb_ivar_set(merged_sheet, id_ivar_media_index, media_idx);

    // Guard first_selector_value: C pointer extracted via RSTRING_PTR during iteration,
    // then used after many allocations (hash operations, shorthand expansions) when
    // creating final_selector with rb_usascii_str_new
    RB_GC_GUARD(first_selector_value);

    return merged_sheet;
}
