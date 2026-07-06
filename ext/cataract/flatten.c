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

/*
 * Family shorthand mapping: for shorthands whose longhand components aren't
 * "all N required" like the 4-sided shorthands above, but a mix of required
 * and optional candidates - border only requires border-style (width/color
 * optional); font requires font-size and font-family (4 others optional);
 * list-style and background don't require any specific candidate, just a
 * minimum count of any 2 present.
 *
 * Candidates must be listed with any REQUIRED ones first: the recreation
 * logic uses "first present candidate in this order" as the source of
 * source_order/specificity/importance for the resulting shorthand, which is
 * always the first required candidate when there is one (border-style for
 * border, font-size for font) or the first present optional candidate
 * otherwise (matching what list-style/background use) - see
 * try_recreate_shorthand_family.
 */
#define MAX_SHORTHAND_FAMILY_CANDIDATES 6

struct shorthand_family_mapping {
    VALUE shorthand_name_val;                              // Cached Ruby string for the shorthand property name
    VALUE candidate_vals[MAX_SHORTHAND_FAMILY_CANDIDATES]; // Cached candidate longhand property names, populated in init_flatten_constants()
    int num_candidates;
    int num_required;  // First `num_required` candidates are mandatory; 0 means "optional-only" (see min_present)
    int min_present;    // Only checked when num_required == 0: minimum count of ANY candidates that must be present
    VALUE (*creator_func)(VALUE, VALUE);
};

// Order matches the original inline recreation blocks (border, list-style,
// font, background) - properties_hash is a Ruby Hash, whose iteration order
// (and therefore the final declaration output order) follows insertion
// order, so this table's order is observable behavior, not just style.
static struct shorthand_family_mapping SHORTHAND_FAMILY_MAPPINGS[] = {
    // border: only border-style is required; border-width/border-color are optional
    { Qnil, { Qnil, Qnil, Qnil, Qnil, Qnil, Qnil }, 3, 1, 0, cataract_create_border_shorthand },
    // list-style: none individually required, but at least 2 of the 3 must be present
    { Qnil, { Qnil, Qnil, Qnil, Qnil, Qnil, Qnil }, 3, 0, 2, cataract_create_list_style_shorthand },
    // font: font-size and font-family are both required; the rest are optional
    { Qnil, { Qnil, Qnil, Qnil, Qnil, Qnil, Qnil }, 6, 2, 0, cataract_create_font_shorthand },
    // background: none individually required, but at least 2 of the 5 must be present
    { Qnil, { Qnil, Qnil, Qnil, Qnil, Qnil, Qnil }, 5, 0, 2, cataract_create_background_shorthand },
};
#define NUM_SHORTHAND_FAMILIES (sizeof(SHORTHAND_FAMILY_MAPPINGS) / sizeof(SHORTHAND_FAMILY_MAPPINGS[0]))

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

    // Populate the family shorthand mapping table. Candidate order matches
    // what each original inline block checked (required candidates first).
    SHORTHAND_FAMILY_MAPPINGS[0].shorthand_name_val = str_border;
    SHORTHAND_FAMILY_MAPPINGS[0].candidate_vals[0] = str_border_style;
    SHORTHAND_FAMILY_MAPPINGS[0].candidate_vals[1] = str_border_width;
    SHORTHAND_FAMILY_MAPPINGS[0].candidate_vals[2] = str_border_color;

    SHORTHAND_FAMILY_MAPPINGS[1].shorthand_name_val = str_list_style;
    SHORTHAND_FAMILY_MAPPINGS[1].candidate_vals[0] = str_list_style_type;
    SHORTHAND_FAMILY_MAPPINGS[1].candidate_vals[1] = str_list_style_position;
    SHORTHAND_FAMILY_MAPPINGS[1].candidate_vals[2] = str_list_style_image;

    SHORTHAND_FAMILY_MAPPINGS[2].shorthand_name_val = str_font;
    SHORTHAND_FAMILY_MAPPINGS[2].candidate_vals[0] = str_font_size;
    SHORTHAND_FAMILY_MAPPINGS[2].candidate_vals[1] = str_font_family;
    SHORTHAND_FAMILY_MAPPINGS[2].candidate_vals[2] = str_font_style;
    SHORTHAND_FAMILY_MAPPINGS[2].candidate_vals[3] = str_font_variant;
    SHORTHAND_FAMILY_MAPPINGS[2].candidate_vals[4] = str_font_weight;
    SHORTHAND_FAMILY_MAPPINGS[2].candidate_vals[5] = str_line_height;

    SHORTHAND_FAMILY_MAPPINGS[3].shorthand_name_val = str_background;
    SHORTHAND_FAMILY_MAPPINGS[3].candidate_vals[0] = str_background_color;
    SHORTHAND_FAMILY_MAPPINGS[3].candidate_vals[1] = str_background_image;
    SHORTHAND_FAMILY_MAPPINGS[3].candidate_vals[2] = str_background_repeat;
    SHORTHAND_FAMILY_MAPPINGS[3].candidate_vals[3] = str_background_position;
    SHORTHAND_FAMILY_MAPPINGS[3].candidate_vals[4] = str_background_attachment;
}

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

// Helper function: Try to recreate a "family" shorthand (border, font,
// list-style, background) from its longhand components. Unlike
// try_recreate_shorthand above (always exactly 4 required sides), these
// allow a mix of required and optional candidates - see
// shorthand_family_mapping for the exact rules.
static inline void try_recreate_shorthand_family(VALUE properties_hash, const struct shorthand_family_mapping *family) {
    // Zero-initialize all slots (not just the first num_candidates) so every
    // read below is well-defined regardless of a given family's arity.
    VALUE datas[MAX_SHORTHAND_FAMILY_CANDIDATES] = { Qnil, Qnil, Qnil, Qnil, Qnil, Qnil };
    int present_count = 0;

    for (int i = 0; i < family->num_candidates; i++) {
        datas[i] = rb_hash_aref(properties_hash, family->candidate_vals[i]);
        if (!NIL_P(datas[i])) present_count++;
    }

    // Required candidates (if any) must all be present
    for (int i = 0; i < family->num_required; i++) {
        if (NIL_P(datas[i])) return;
    }

    // If nothing is individually required, need a minimum count of ANY present
    if (family->num_required == 0 && present_count < family->min_present) {
        return;
    }

    // All present candidates must share the same !important flag
    VALUE reference_imp = Qnil;
    int have_reference = 0;
    for (int i = 0; i < family->num_candidates; i++) {
        if (NIL_P(datas[i])) continue;
        VALUE imp = RARRAY_AREF(datas[i], PROP_IMPORTANT);
        if (!have_reference) {
            reference_imp = imp;
            have_reference = 1;
        } else if (RTEST(reference_imp) != RTEST(imp)) {
            return;
        }
    }

    // Build a hash of present property values for the creator function
    VALUE props = rb_hash_new();
    for (int i = 0; i < family->num_candidates; i++) {
        if (!NIL_P(datas[i])) {
            rb_hash_aset(props, family->candidate_vals[i], RARRAY_AREF(datas[i], PROP_VALUE));
        }
    }

    VALUE shorthand_value = family->creator_func(Qnil, props);
    if (NIL_P(shorthand_value)) {
        return; // Creator decided not to create shorthand
    }

    // First present candidate (in declared order) supplies source_order/
    // specificity/importance for the shorthand - always the first required
    // candidate when there is one (border-style for border, font-size for
    // font), otherwise the first present optional candidate, matching what
    // each original inline block hardcoded.
    int primary_idx = -1;
    for (int i = 0; i < family->num_candidates; i++) {
        if (!NIL_P(datas[i])) {
            primary_idx = i;
            break;
        }
    }
    if (primary_idx < 0) {
        return; // Nothing present to build a shorthand from
    }

    VALUE shorthand_data = rb_ary_new_capa(4);
    rb_ary_push(shorthand_data, RARRAY_AREF(datas[primary_idx], PROP_SOURCE_ORDER));
    rb_ary_push(shorthand_data, RARRAY_AREF(datas[primary_idx], PROP_SPECIFICITY));
    rb_ary_push(shorthand_data, reference_imp);
    rb_ary_push(shorthand_data, shorthand_value);

    // Add shorthand and remove longhand properties
    rb_hash_aset(properties_hash, family->shorthand_name_val, shorthand_data);
    for (int i = 0; i < family->num_candidates; i++) {
        if (!NIL_P(datas[i])) {
            rb_hash_delete(properties_hash, family->candidate_vals[i]);
        }
    }

    DEBUG_PRINTF("      -> Recreated family shorthand\n");
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
    VALUE old_to_new_id;  // Hash mapping old rule IDs to new merged rule IDs (for media index)
};

// Context for remapping media_index
struct remap_media_context {
    VALUE old_to_new_id;
    VALUE new_media_index;
};

// Callback for remapping media_index entries
static int remap_media_index_callback(VALUE media_sym, VALUE old_rule_ids, VALUE arg) {
    struct remap_media_context *ctx = (struct remap_media_context *)arg;

    if (NIL_P(old_rule_ids) || TYPE(old_rule_ids) != T_ARRAY) {
        return ST_CONTINUE;
    }

    VALUE new_rule_ids = rb_ary_new();
    long num_old_ids = RARRAY_LEN(old_rule_ids);

    for (long i = 0; i < num_old_ids; i++) {
        VALUE old_id = RARRAY_AREF(old_rule_ids, i);
        VALUE new_id = rb_hash_aref(ctx->old_to_new_id, old_id);

        // Only include if the rule still exists after merging and isn't already in the list
        if (!NIL_P(new_id) && rb_ary_includes(new_rule_ids, new_id) == Qfalse) {
            rb_ary_push(new_rule_ids, new_id);
        }
    }

    // Only preserve media entry if there are still rules for it
    if (RARRAY_LEN(new_rule_ids) > 0) {
        rb_hash_aset(ctx->new_media_index, media_sym, new_rule_ids);
    }

    return ST_CONTINUE;
}

// Forward declaration
static VALUE flatten_rules_for_selector(VALUE rules_array, VALUE rule_indices, VALUE selector, VALUE *out_selector_list_id);

// Callback for rb_hash_foreach when merging selector groups
static int flatten_selector_group_callback(VALUE group_key, VALUE group_indices, VALUE arg) {
    struct flatten_selectors_context *ctx = (struct flatten_selectors_context *)arg;
    ctx->selector_index++;

    // Extract selector and media_context from group_key array [selector, media_context]
    VALUE selector = RARRAY_AREF(group_key, 0);
    VALUE media_context = RARRAY_AREF(group_key, 1);

    DEBUG_PRINTF("\n[Selector %ld/%ld] '%s' (media=%s) - %ld rules in group\n",
                 ctx->selector_index, ctx->total_selectors,
                 RSTRING_PTR(selector),
                 NIL_P(media_context) ? "nil" : RSTRING_PTR(rb_inspect(media_context)),
                 RARRAY_LEN(group_indices));

    // Merge all rules in this selector group and preserve selector_list_id if all rules share same ID
    VALUE selector_list_id = Qnil;
    VALUE merged_decls = flatten_rules_for_selector(ctx->rules_array, group_indices, selector, &selector_list_id);

    int new_rule_id = *ctx->rule_id_counter;

    // Extract media_query_id from first rule in group (all should have same media_query_id)
    VALUE media_query_id = Qnil;
    if (RARRAY_LEN(group_indices) > 0) {
        long first_rule_idx = FIX2LONG(RARRAY_AREF(group_indices, 0));
        VALUE first_rule = RARRAY_AREF(ctx->rules_array, first_rule_idx);
        media_query_id = rb_struct_aref(first_rule, INT2FIX(RULE_MEDIA_QUERY_ID));
    }

    // Track old rule IDs to new rule ID mapping (only for rules in media queries)
    if (!NIL_P(media_context)) {
        long num_rules_in_group = RARRAY_LEN(group_indices);
        for (long i = 0; i < num_rules_in_group; i++) {
            long old_rule_idx = FIX2LONG(RARRAY_AREF(group_indices, i));
            VALUE old_rule = RARRAY_AREF(ctx->rules_array, old_rule_idx);
            VALUE old_rule_id = rb_struct_aref(old_rule, INT2FIX(RULE_ID));
            rb_hash_aset(ctx->old_to_new_id, old_rule_id, INT2FIX(new_rule_id));
        }
    }

    // Create new rule with this selector and merged declarations
    VALUE new_rule = rb_struct_new(cRule,
        INT2FIX((*ctx->rule_id_counter)++),
        selector,
        merged_decls,
        Qnil,  // specificity
        Qnil,  // parent_rule_id
        Qnil,  // nesting_style
        selector_list_id,  // Preserve selector_list_id if all rules in group share same ID
        media_query_id  // Preserve media_query_id from source rules
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
#ifdef CATARACT_DEBUG
        if (!NIL_P(*out_selector_list_id)) {
            DEBUG_PRINTF("    -> Preserving selector_list_id=%ld for merged rule\n", NUM2LONG(*out_selector_list_id));
        } else {
            DEBUG_PRINTF("    -> NOT preserving selector_list_id (not all same)\n");
        }
#endif
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

    // Try to recreate family shorthands (border, font, list-style, background) using the mapping table
    for (size_t i = 0; i < NUM_SHORTHAND_FAMILIES; i++) {
        try_recreate_shorthand_family(properties_hash, &SHORTHAND_FAMILY_MAPPINGS[i]);
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

// Context for iterating through rules_by_list hash
struct check_selector_lists_ctx {
    VALUE selector_lists;  // Output hash to populate
};

// Callback for iterating through rules_by_list hash: list_id => [rule1, rule2, ...]
static int check_selector_list_callback(VALUE list_id, VALUE rules_in_list, VALUE arg) {
    struct check_selector_lists_ctx *ctx = (struct check_selector_lists_ctx *)arg;
    long num_in_list = RARRAY_LEN(rules_in_list);

    DEBUG_PRINTF("\n  Checking list_id=%ld: %ld rules\n", NUM2LONG(list_id), num_in_list);

    // Skip if only one rule in list (nothing to compare)
    if (num_in_list <= 1) {
        DEBUG_PRINTF("    -> Only 1 rule, skipping\n");
        return ST_CONTINUE;
    }

    // Get first rule as reference
    VALUE reference_rule = RARRAY_AREF(rules_in_list, 0);
    VALUE reference_decls = rb_struct_aref(reference_rule, INT2FIX(RULE_DECLARATIONS));
#ifdef CATARACT_DEBUG
    VALUE reference_selector = rb_struct_aref(reference_rule, INT2FIX(RULE_SELECTOR));
    DEBUG_PRINTF("    Reference rule: selector=%s, %ld declarations\n",
                 RSTRING_PTR(reference_selector), RARRAY_LEN(reference_decls));
#endif

    // Find rules that still match (have identical declarations)
    VALUE matching_rules = rb_ary_new();
    rb_ary_push(matching_rules, reference_rule);

    for (long j = 1; j < num_in_list; j++) {
        VALUE rule = RARRAY_AREF(rules_in_list, j);
        VALUE decls = rb_struct_aref(rule, INT2FIX(RULE_DECLARATIONS));
#ifdef CATARACT_DEBUG
        VALUE selector = rb_struct_aref(rule, INT2FIX(RULE_SELECTOR));
        DEBUG_PRINTF("    Comparing rule %ld (selector=%s):\n", j, RSTRING_PTR(selector));
#endif

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
        rb_hash_aset(ctx->selector_lists, list_id, rule_ids);
        DEBUG_PRINTF("    -> Keeping selector list with %ld rules\n", num_matching);
    } else {
        DEBUG_PRINTF("    -> Only 1 rule left, clearing selector_list_id for it too\n");
        // Clear selector_list_id for the last remaining rule too
        for (long j = 0; j < num_matching; j++) {
            VALUE rule = RARRAY_AREF(matching_rules, j);
            rb_struct_aset(rule, INT2FIX(RULE_SELECTOR_LIST_ID), Qnil);
        }
    }

    return ST_CONTINUE;
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
#ifdef CATARACT_DEBUG
        VALUE selector = rb_struct_aref(rule, INT2FIX(RULE_SELECTOR));
#endif

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
    DEBUG_PRINTF("  Found %ld selector list groups to check\n", RHASH_SIZE(rules_by_list));
    struct check_selector_lists_ctx ctx = { selector_lists };
    rb_hash_foreach(rules_by_list, check_selector_list_callback, (VALUE)&ctx);

    DEBUG_PRINTF("\n=== End divergence tracking: %ld selector lists preserved ===\n\n", RHASH_SIZE(selector_lists));
}

// Build a map from rule_id -> media_query_id for all Rule (non-AtRule)
// entries that have one set. Used to group rules by (selector, media)
// instead of just selector, and later to remap the stylesheet's media_index
// after flattening.
//
// @param out_input_media_index Output: the input Stylesheet's @media_index
//   ivar (Qnil if input isn't a Stylesheet), needed by the caller for
//   remap_media_index_callback
static VALUE build_rule_media_map(VALUE input, VALUE rules_array, long num_rules, VALUE *out_input_media_index) {
    VALUE rule_media_map = rb_hash_new();
    *out_input_media_index = Qnil;

    if (!rb_obj_is_kind_of(input, cStylesheet)) {
        return rule_media_map;
    }

    *out_input_media_index = rb_ivar_get(input, id_ivar_media_index);

    // Only process Rule objects, not AtRules (AtRules don't have media_query_id field at same offset)
    for (long i = 0; i < num_rules; i++) {
        VALUE rule = rb_ary_entry(rules_array, i);
        if (!rb_obj_is_kind_of(rule, cAtRule)) {
            VALUE media_query_id = rb_struct_aref(rule, INT2FIX(RULE_MEDIA_QUERY_ID));
            if (!NIL_P(media_query_id)) {
                VALUE rule_id = rb_struct_aref(rule, INT2FIX(RULE_ID));
                rb_hash_aset(rule_media_map, rule_id, media_query_id);
            }
        }
    }

    return rule_media_map;
}

// Group rules by (selector, media) - not just selector - since rules with
// the same selector but different media contexts must NOT be merged
// together. AtRule entries (e.g. @keyframes, @font-face) have no
// declarations to merge and can't be grouped this way at all, so they're
// collected separately into passthrough_rules and passed through unchanged.
//
// @param passthrough_rules Output: empty array to populate with AtRule entries
// @return Hash of [selector, media_context] => Array of rule indices
static VALUE group_rules_by_selector_and_media(VALUE rules_array, long num_rules, VALUE rule_media_map, VALUE passthrough_rules) {
    VALUE selector_groups = rb_hash_new();

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
        VALUE rule_id_val = rb_struct_aref(rule, INT2FIX(RULE_ID));

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

        // Get media context for this rule (nil if not in media query)
        VALUE media_context = rb_hash_aref(rule_media_map, rule_id_val);

        // Build grouping key as [selector, media_context]
        VALUE group_key = rb_ary_new3(2, selector, media_context);

        DEBUG_PRINTF("  [Rule %ld] ADD: selector='%s', media=%s, %ld declarations\n",
                     i, RSTRING_PTR(selector),
                     NIL_P(media_context) ? "nil" : RSTRING_PTR(rb_inspect(media_context)),
                     RARRAY_LEN(declarations));

        VALUE group = rb_hash_aref(selector_groups, group_key);
        if (NIL_P(group)) {
            group = rb_ary_new();
            rb_hash_aset(selector_groups, group_key, group);
            DEBUG_PRINTF("    -> Created new selector+media group for '%s' + %s\n",
                        RSTRING_PTR(selector),
                        NIL_P(media_context) ? "nil" : RSTRING_PTR(rb_inspect(media_context)));
        }
        rb_ary_push(group, LONG2FIX(i));
    }

    return selector_groups;
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

    // Build rule_media_map: rule_id => media_query_id
    // This is used to group rules by (selector, media) instead of just selector
    VALUE input_media_index = Qnil;
    VALUE rule_media_map = build_rule_media_map(input, rules_array, num_rules, &input_media_index);

    // Group rules by (selector, media) instead of just selector
    // Rules with same selector but different media contexts should NOT be merged
    DEBUG_PRINTF("\n=== Building selector+media groups ===\n");
    VALUE passthrough_rules = rb_ary_new(); // AtRules to pass through unchanged
    VALUE selector_groups = group_rules_by_selector_and_media(rules_array, num_rules, rule_media_map, passthrough_rules);
    DEBUG_PRINTF("=== Total selector+media groups: %ld ===\n\n", RHASH_SIZE(selector_groups));

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

        // Copy @media_queries and @_media_query_lists from input
        if (rb_obj_is_kind_of(input, cStylesheet)) {
            VALUE media_queries = rb_ivar_get(input, rb_intern("@media_queries"));
            VALUE media_query_lists = rb_ivar_get(input, rb_intern("@_media_query_lists"));
            Check_Type(media_queries, T_ARRAY);
            if (!NIL_P(media_query_lists)) Check_Type(media_query_lists, T_HASH);
            rb_ivar_set(passthrough_sheet, rb_intern("@media_queries"), media_queries);
            rb_ivar_set(passthrough_sheet, rb_intern("@_media_query_lists"), media_query_lists);
        }

        return passthrough_sheet;
    } else {
        DEBUG_PRINTF("  -> Taking SELECTOR-GROUPED path (%ld unique selectors)\n",
                     RHASH_SIZE(selector_groups));
        VALUE merged_sheet = rb_class_new_instance(0, NULL, cStylesheet);
        VALUE merged_rules = rb_ary_new();
        int rule_id_counter = 0;

        // Iterate through each selector group using rb_hash_foreach
        // to avoid rb_funcall in hot path
        VALUE old_to_new_id = rb_hash_new();  // Hash to track old rule IDs -> new merged rule IDs
        struct flatten_selectors_context merge_ctx;
        merge_ctx.merged_rules = merged_rules;
        merge_ctx.rules_array = rules_array;
        merge_ctx.rule_id_counter = &rule_id_counter;
        merge_ctx.selector_index = 0;
        merge_ctx.total_selectors = RHASH_SIZE(selector_groups);
        merge_ctx.old_to_new_id = old_to_new_id;

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
                update_selector_lists_for_divergence(merged_rules, selector_lists);
            }
        }

        // Preserve media_index by remapping old rule IDs to new rule IDs
        // This is important for @media rules and @import statements with media constraints
        VALUE new_media_index = rb_hash_new();

        if (!NIL_P(input_media_index) && TYPE(input_media_index) == T_HASH) {
            struct remap_media_context remap_ctx;
            remap_ctx.old_to_new_id = old_to_new_id;
            remap_ctx.new_media_index = new_media_index;
            rb_hash_foreach(input_media_index, remap_media_index_callback, (VALUE)&remap_ctx);
        }

        rb_ivar_set(merged_sheet, id_ivar_media_index, new_media_index);

        // Copy @media_queries and @_media_query_lists from input (these don't change during flatten)
        if (rb_obj_is_kind_of(input, cStylesheet)) {
            VALUE media_queries = rb_ivar_get(input, rb_intern("@media_queries"));
            VALUE media_query_lists = rb_ivar_get(input, rb_intern("@_media_query_lists"));
            Check_Type(media_queries, T_ARRAY);
            if (!NIL_P(media_query_lists)) Check_Type(media_query_lists, T_HASH);
            rb_ivar_set(merged_sheet, rb_intern("@media_queries"), media_queries);
            rb_ivar_set(merged_sheet, rb_intern("@_media_query_lists"), media_query_lists);
        }

        // Set @_selector_lists with divergence tracking
        rb_ivar_set(merged_sheet, rb_intern("@_selector_lists"), selector_lists);

        // Protect intermediate VALUEs from being collected
        RB_GC_GUARD(input_media_index);
        RB_GC_GUARD(rule_media_map);
        RB_GC_GUARD(selector_groups);
        RB_GC_GUARD(passthrough_rules);
        RB_GC_GUARD(old_to_new_id);
        RB_GC_GUARD(new_media_index);

        return merged_sheet;
    }

}
