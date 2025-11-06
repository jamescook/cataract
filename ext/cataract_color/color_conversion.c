// color_conversion.c - CSS color format conversion
//
// HOW TO ADD A NEW COLOR FORMAT
// ===============================
//
// This module uses an intermediate representation (IR) to convert between color formats.
// All conversions go through: Source Format → IR → Target Format
//
// STEP 1: Define the Intermediate Representation (IR)
// ---------------------------------------------------
// The IR is defined in color_conversion.h as `struct color_ir`:
//   - red, green, blue (int 0-255): sRGB values (always populated)
//   - alpha (double 0.0-1.0 or -1.0): alpha channel (-1.0 = no alpha)
//   - has_linear_rgb (int): flag indicating if linear RGB is available
//   - linear_r, linear_g, linear_b (double 0.0-1.0): high-precision linear RGB
//
// Use INIT_COLOR_IR(color) to initialize the struct with default values.
//
// High-precision formats (oklab, oklch) should set has_linear_rgb = 1 and populate
// the linear_* fields to preserve precision and avoid quantization loss.
//
// STEP 2: Implement Parser Function
// ----------------------------------
// Signature: static struct color_ir parse_FORMAT(VALUE format_value)
//
// Example:
//   static struct color_ir parse_hsl(VALUE hsl_value) {
//     struct color_ir color;
//     INIT_COLOR_IR(color);
//
//     // Parse the CSS string (e.g., "hsl(120, 100%, 50%)")
//     const char *str = StringValueCStr(hsl_value);
//     // ... parse logic ...
//
//     // Convert to sRGB (0-255) and store in color.red, color.green, color.blue
//     // Optionally store linear RGB for high precision
//
//     RB_GC_GUARD(hsl_value);  // Protect from GC
//     return color;
//   }
//
// Tips:
//   - Use macros from color_conversion.h: SKIP_WHITESPACE, PARSE_INT, etc.
//   - Validate input and raise rb_eArgError for invalid syntax
//   - Always add RB_GC_GUARD before returning
//
// STEP 3: Implement Formatter Function
// -------------------------------------
// Signature: static VALUE format_FORMAT(struct color_ir color, int use_modern_syntax)
//
// Example:
//   static VALUE format_hsl(struct color_ir color, int use_modern_syntax) {
//     // Convert from sRGB (or linear RGB if available) to target format
//     // Use macros from color_conversion.h: FORMAT_HSL, FORMAT_HSLA
//     char buf[64];
//     if (color.alpha >= 0.0) {
//       FORMAT_HSLA(buf, h, s, l, color.alpha);
//     } else {
//       FORMAT_HSL(buf, h, s, l);
//     }
//     return rb_str_new_cstr(buf);
//   }
//
// Tips:
//   - Check color.has_linear_rgb to use high-precision values when available
//   - Define FORMAT_* macros in color_conversion.h for consistent output
//
// STEP 4: Add Detection Macros (color_conversion.h)
// --------------------------------------------------
// Add a STARTS_WITH_FORMAT macro to detect the format in CSS strings:
//
//   #define STARTS_WITH_HSL(p, remaining) \
//       ((remaining) >= 4 && (p)[0] == 'h' && (p)[1] == 's' && (p)[2] == 'l' && \
//        ((p)[3] == '(' || (p)[3] == 'a'))
//
// STEP 5: Register in Dispatchers
// --------------------------------
// Add to get_parser() function:
//   ID format_id = rb_intern("format");
//   if (format_id == format_id) {
//     return parse_format;
//   }
//
// Add to get_formatter() function:
//   ID format_id = rb_intern("format");
//   if (format_id == format_id) {
//     return format_format;
//   }
//
// STEP 6: Integrate into Converter
// ---------------------------------
// Add to convert_value_with_colors() function:
//   if (STARTS_WITH_FORMAT(p, remaining) && (parser == NULL || parser == parse_format)) {
//     const char *end;
//     FIND_CLOSING_PAREN(p, end);
//     color_len = end - p;
//     VALUE format_str = rb_str_new(p, color_len);
//     struct color_ir color = parse_format(format_str);
//     VALUE converted = formatter(color, use_modern_syntax);
//     rb_str_buf_append(result, converted);
//     pos += color_len;
//     found_color = 1;
//     continue;
//   }
//
// Add to detect_color_format() function:
//   if (STARTS_WITH_FORMAT(p, remaining)) {
//     return parse_format;
//   }
//
// Add to matches_color_format() function:
//   ID format_id = rb_intern("format");
//   if (format_id == format_id) {
//     return STARTS_WITH_FORMAT(p, remaining);
//   }
//
// STEP 7: Add Tests
// -----------------
// Create test/test_color_conversion_FORMAT.rb with comprehensive test coverage:
//   - Parsing valid values
//   - Conversions to/from other formats
//   - Edge cases (invalid input, boundary values)
//   - Alpha channel support
//   - Round-trip conversions
//
// EXAMPLE: See oklab/oklch implementations for reference
//
// ============================================================================

#include "cataract.h"
#include "color_conversion.h"
#include <ctype.h>
#include <stdio.h>
#include <math.h>

// Forward declarations
static int is_hex_digit(char c);
static int hex_char_to_int(char c);
static VALUE expand_property_if_needed(VALUE property_name, VALUE value);
VALUE rb_stylesheet_convert_colors(int argc, VALUE *argv, VALUE self);

// Parser function signature: format → IR
typedef struct color_ir (*color_parser_fn)(VALUE color_value);

// Formatter function signature: IR → format
typedef VALUE (*color_formatter_fn)(struct color_ir color, int use_modern_syntax);

// Parser functions
static struct color_ir parse_hex(VALUE hex_value);
static struct color_ir parse_rgb(VALUE rgb_value);
static struct color_ir parse_rgb_percent(VALUE rgb_value);
static struct color_ir parse_hsl(VALUE hsl_value);
static struct color_ir parse_hwb(VALUE hwb_value);

// Formatter functions
static VALUE format_hex(struct color_ir color, int use_modern_syntax);
static VALUE format_rgb(struct color_ir color, int use_modern_syntax);
static VALUE format_hsl(struct color_ir color, int use_modern_syntax);
static VALUE format_hwb(struct color_ir color, int use_modern_syntax);

// Oklab functions (defined in color_conversion_oklab.c)
extern struct color_ir parse_oklab(VALUE oklab_value);
extern VALUE format_oklab(struct color_ir color, int use_modern_syntax);

// OKLCh functions (defined in color_conversion_oklab.c)
extern struct color_ir parse_oklch(VALUE oklch_value);
extern VALUE format_oklch(struct color_ir color, int use_modern_syntax);

// Named color functions (defined in color_conversion_named.c)
extern struct color_ir parse_named(VALUE named_value);

// Lab functions (defined in color_conversion_lab.c)
extern struct color_ir parse_lab(VALUE lab_value);
extern VALUE format_lab(struct color_ir color, int use_modern_syntax);
extern struct color_ir parse_lch(VALUE lch_value);
extern VALUE format_lch(struct color_ir color, int use_modern_syntax);

// Dispatchers
static color_parser_fn get_parser(VALUE format);
static color_formatter_fn get_formatter(VALUE format);

// Exception class
static VALUE rb_eColorConversionError = Qnil;

// Initialize color conversion module
void Init_color_conversion(VALUE mCataract) {
    // Define ColorConversionError exception class
    rb_eColorConversionError = rb_define_class_under(mCataract, "ColorConversionError", rb_eStandardError);

    // Get the Stylesheet class (bootstrapped in C, defined fully in Ruby)
    VALUE cStylesheet = rb_const_get(mCataract, rb_intern("Stylesheet"));

    // Add convert_colors! instance method to Stylesheet
    rb_define_method(cStylesheet, "convert_colors!", rb_stylesheet_convert_colors, -1);
}

// Check if a character is a valid hex digit (0-9, a-f, A-F)
static int is_hex_digit(char c) {
    return (c >= '0' && c <= '9') ||
           (c >= 'a' && c <= 'f') ||
           (c >= 'A' && c <= 'F');
}

// Convert hex character to integer value
static int hex_char_to_int(char c) {
    if (c >= '0' && c <= '9') return c - '0';
    if (c >= 'a' && c <= 'f') return c - 'a' + 10;
    if (c >= 'A' && c <= 'F') return c - 'A' + 10;
    return -1;
}

// Macro to check if a string contains unparseable content and preserve it if found
// Sets has_unparseable to 1 if content should be preserved, 0 otherwise
#define HAS_UNPARSEABLE_CONTENT(str, len, has_unparseable) do { \
    (has_unparseable) = 0; \
    if ((str) != NULL && (len) >= 4) { \
        static const char *unparseable[] = { \
            "calc(", "min(", "max(", "clamp(", "var(", \
            "none", "infinity", "-infinity", "NaN", \
            "from ", \
            NULL \
        }; \
        for (int _i = 0; unparseable[_i] != NULL; _i++) { \
            const char *_kw = unparseable[_i]; \
            size_t _kw_len = strlen(_kw); \
            for (long _j = 0; _j <= (len) - (long)_kw_len; _j++) { \
                if (strncmp((str) + _j, _kw, _kw_len) == 0) { \
                    (has_unparseable) = 1; \
                    break; \
                } \
            } \
            if ((has_unparseable)) break; \
        } \
    } \
} while(0)

// Parse hex color string to intermediate representation
// hex_value: Ruby string like "#fff", "#ffffff", or "#ff000080"
// Returns: color_ir struct with RGB values (0-255) and optional alpha (0.0-1.0)
static struct color_ir parse_hex(VALUE hex_value) {
    Check_Type(hex_value, T_STRING);

    const char *hex_str = RSTRING_PTR(hex_value);
    long hex_len = RSTRING_LEN(hex_value);

    // Must start with '#'
    if (hex_len < 2 || hex_str[0] != '#') {
        rb_raise(rb_eColorConversionError, "Invalid hex color: must start with '#', got '%s'", hex_str);
    }

    // Skip the '#' character
    hex_str++;
    hex_len--;

    // Validate length (3, 6, or 8 digits)
    if (hex_len != 3 && hex_len != 6 && hex_len != 8) {
        // hex_str points past '#', so show original with '#'
        rb_raise(rb_eColorConversionError,
                 "Invalid hex color: expected 3, 6, or 8 digits, got %ld in '%s'",
                 hex_len, RSTRING_PTR(hex_value));
    }

    // Validate all characters are hex digits
    for (long i = 0; i < hex_len; i++) {
        if (!is_hex_digit(hex_str[i])) {
            rb_raise(rb_eColorConversionError,
                     "Invalid hex color: contains non-hex character '%c'",
                     hex_str[i]);
        }
    }

    struct color_ir color;
    INIT_COLOR_IR(color);

    if (hex_len == 3) {
        // 3-digit hex: #RGB -> each digit is duplicated
        color.red = hex_char_to_int(hex_str[0]) * 17;
        color.green = hex_char_to_int(hex_str[1]) * 17;
        color.blue = hex_char_to_int(hex_str[2]) * 17;
    } else {
        // 6 or 8-digit hex: #RRGGBB or #RRGGBBAA
        color.red = (hex_char_to_int(hex_str[0]) << 4) | hex_char_to_int(hex_str[1]);
        color.green = (hex_char_to_int(hex_str[2]) << 4) | hex_char_to_int(hex_str[3]);
        color.blue = (hex_char_to_int(hex_str[4]) << 4) | hex_char_to_int(hex_str[5]);

        if (hex_len == 8) {
            int alpha_int = (hex_char_to_int(hex_str[6]) << 4) | hex_char_to_int(hex_str[7]);
            color.alpha = alpha_int / 255.0;
        }
    }

    return color;
}

// Format intermediate representation to RGB string
// color: color_ir struct with RGB (0-255) and optional alpha (0.0-1.0)
// use_modern_syntax: 1 for "rgb(255 0 0)", 0 for "rgb(255, 0, 0)"
// Returns: Ruby string with RGB/RGBA value
static VALUE format_rgb(struct color_ir color, int use_modern_syntax) {
    char rgb_buf[128];

    // Use high-precision linear RGB if available (preserves precision from oklab/oklch)
    if (color.has_linear_rgb) {
        // Convert linear RGB to sRGB percentages
        double lr = color.linear_r, lg = color.linear_g, lb = color.linear_b;

        // Clamp to [0.0, 1.0]
        if (lr < 0.0) lr = 0.0; if (lr > 1.0) lr = 1.0;
        if (lg < 0.0) lg = 0.0; if (lg > 1.0) lg = 1.0;
        if (lb < 0.0) lb = 0.0; if (lb > 1.0) lb = 1.0;

        // Apply sRGB gamma correction
        double rs = (lr <= 0.0031308) ? lr * 12.92 : 1.055 * pow(lr, 1.0/2.4) - 0.055;
        double gs = (lg <= 0.0031308) ? lg * 12.92 : 1.055 * pow(lg, 1.0/2.4) - 0.055;
        double bs = (lb <= 0.0031308) ? lb * 12.92 : 1.055 * pow(lb, 1.0/2.4) - 0.055;

        // Convert to percentages
        double r_pct = rs * 100.0;
        double g_pct = gs * 100.0;
        double b_pct = bs * 100.0;

        if (color.alpha >= 0.0) {
            FORMAT_RGB_PERCENT_ALPHA(rgb_buf, r_pct, g_pct, b_pct, color.alpha);
        } else {
            FORMAT_RGB_PERCENT(rgb_buf, r_pct, g_pct, b_pct);
        }
    } else {
        // Use integer sRGB values (0-255)
        if (color.alpha >= 0.0) {
            // Has alpha channel
            if (use_modern_syntax) {
                FORMAT_RGBA_MODERN(rgb_buf, color.red, color.green, color.blue, color.alpha);
            } else {
                FORMAT_RGBA_LEGACY(rgb_buf, color.red, color.green, color.blue, color.alpha);
            }
        } else {
            // No alpha channel
            if (use_modern_syntax) {
                FORMAT_RGB_MODERN(rgb_buf, color.red, color.green, color.blue);
            } else {
                FORMAT_RGB_LEGACY(rgb_buf, color.red, color.green, color.blue);
            }
        }
    }

    return rb_str_new_cstr(rgb_buf);
}

// Parse RGB color string to intermediate representation
// rgb_value: Ruby string like "rgb(255, 0, 0)" or "rgb(255 0 0 / 0.5)"
// Returns: color_ir struct with RGB values (0-255) and optional alpha (0.0-1.0)
static struct color_ir parse_rgb(VALUE rgb_value) {
    Check_Type(rgb_value, T_STRING);

    const char *rgb_str = RSTRING_PTR(rgb_value);
    long rgb_len = RSTRING_LEN(rgb_value);

    if (rgb_len < 10 || (strncmp(rgb_str, "rgb(", 4) != 0 && strncmp(rgb_str, "rgba(", 5) != 0)) {
        rb_raise(rb_eColorConversionError, "Invalid RGB color: must start with 'rgb(' or 'rgba(', got '%s'", rgb_str);
    }

    // Skip "rgb(" or "rgba("
    const char *p = rgb_str;                              // "rgb(255, 128, 64, 0.5)"
    if (*p == 'r' && *(p+1) == 'g' && *(p+2) == 'b') {   // "rgb"
        p += 3;                                           // "(255, 128, 64, 0.5)"
        if (*p == 'a') p++;                               // skip 'a' if rgba
        if (*p == '(') p++;                               // "255, 128, 64, 0.5)"
    }

    struct color_ir color;
    INIT_COLOR_IR(color);

    // Check if this is percentage format by looking for '%' before first separator
    const char *check = p;
    int is_percent = 0;
    while (*check && *check != ')' && *check != ',' && *check != '/') {
        if (*check == '%') {
            is_percent = 1;
            break;
        }
        check++;
    }

    if (is_percent) {
        // Delegate to percentage parser
        return parse_rgb_percent(rgb_value);
    }

    SKIP_WHITESPACE(p);                                   // "255, 128, 64, 0.5)"
    PARSE_INT(p, color.red);                              // red=255, p=", 128, 64, 0.5)"

    SKIP_SEPARATOR(p);                                    // "128, 64, 0.5)"
    PARSE_INT(p, color.green);                            // green=128, p=", 64, 0.5)"

    SKIP_SEPARATOR(p);                                    // "64, 0.5)"
    PARSE_INT(p, color.blue);                             // blue=64, p=", 0.5)"

    // Check for alpha (either ",alpha" or "/ alpha")
    SKIP_SEPARATOR(p);                                    // "0.5)" or ", 0.5)" or ", / 0.5)"
    if (*p == '/') {                                      // '/'
        p++;                                              // " 0.5)"
        SKIP_WHITESPACE(p);                               // "0.5)"
    }

    if (*p >= '0' && *p <= '9') {                         // '0'
        color.alpha = 0.0;
        while (*p >= '0' && *p <= '9') {                  // '0' (integer part)
            color.alpha = color.alpha * 10.0 + (*p - '0'); // alpha=0.0
            p++;                                          // ".5)"
        }
        if (*p == '.') {                                  // '.'
            p++;                                          // "5)"
            double decimal = 0.1;
            while (*p >= '0' && *p <= '9') {              // '5'
                color.alpha += (*p - '0') * decimal;      // alpha=0.5
                decimal /= 10.0;
                p++;                                      // ")"
            }
        }
    }

    // Validate ranges
    if (color.red < 0 || color.red > 255 || color.green < 0 || color.green > 255 || color.blue < 0 || color.blue > 255) {
        rb_raise(rb_eColorConversionError,
                 "Invalid RGB values: must be 0-255, got red=%d green=%d blue=%d", color.red, color.green, color.blue);
    }

    if (color.alpha >= 0.0 && (color.alpha < 0.0 || color.alpha > 1.0)) {
        rb_raise(rb_eColorConversionError,
                 "Invalid alpha value: must be 0.0-1.0, got %.10g", color.alpha);
    }

    return color;
}

// Parse RGB percentage color string to intermediate representation
// rgb_value: Ruby string like "rgb(70.492% 2.351% 37.073%)"
// Returns: color_ir struct with high-precision linear RGB
static struct color_ir parse_rgb_percent(VALUE rgb_value) {
    Check_Type(rgb_value, T_STRING);

    const char *rgb_str = RSTRING_PTR(rgb_value);
    long rgb_len = RSTRING_LEN(rgb_value);

    if (rgb_len < 10 || (strncmp(rgb_str, "rgb(", 4) != 0 && strncmp(rgb_str, "rgba(", 5) != 0)) {
        rb_raise(rb_eColorConversionError, "Invalid RGB color: must start with 'rgb(' or 'rgba(', got '%s'", rgb_str);
    }

    // Skip "rgb(" or "rgba("
    const char *p = rgb_str;
    if (*p == 'r' && *(p+1) == 'g' && *(p+2) == 'b') {
        p += 3;
        if (*p == 'a') p++;
        if (*p == '(') p++;
    }

    struct color_ir color;
    INIT_COLOR_IR(color);

    SKIP_WHITESPACE(p);

    // Parse R%
    double r_pct = 0.0;
    while (*p >= '0' && *p <= '9') {
        r_pct = r_pct * 10.0 + (*p - '0');
        p++;
    }
    if (*p == '.') {
        p++;
        double frac = 0.1;
        while (*p >= '0' && *p <= '9') {
            r_pct += (*p - '0') * frac;
            frac *= 0.1;
            p++;
        }
    }
    if (*p == '%') p++;

    SKIP_SEPARATOR(p);

    // Parse G%
    double g_pct = 0.0;
    while (*p >= '0' && *p <= '9') {
        g_pct = g_pct * 10.0 + (*p - '0');
        p++;
    }
    if (*p == '.') {
        p++;
        double frac = 0.1;
        while (*p >= '0' && *p <= '9') {
            g_pct += (*p - '0') * frac;
            frac *= 0.1;
            p++;
        }
    }
    if (*p == '%') p++;

    SKIP_SEPARATOR(p);

    // Parse B%
    double b_pct = 0.0;
    while (*p >= '0' && *p <= '9') {
        b_pct = b_pct * 10.0 + (*p - '0');
        p++;
    }
    if (*p == '.') {
        p++;
        double frac = 0.1;
        while (*p >= '0' && *p <= '9') {
            b_pct += (*p - '0') * frac;
            frac *= 0.1;
            p++;
        }
    }
    if (*p == '%') p++;

    // Check for alpha
    SKIP_SEPARATOR(p);
    if (*p == '/') {
        p++;
        SKIP_WHITESPACE(p);
    }

    if (*p >= '0' && *p <= '9') {
        color.alpha = 0.0;
        while (*p >= '0' && *p <= '9') {
            color.alpha = color.alpha * 10.0 + (*p - '0');
            p++;
        }
        if (*p == '.') {
            p++;
            double decimal = 0.1;
            while (*p >= '0' && *p <= '9') {
                color.alpha += (*p - '0') * decimal;
                decimal /= 10.0;
                p++;
            }
        }
    }

    // Convert percentages to sRGB (0-1.0)
    double rs = r_pct / 100.0;
    double gs = g_pct / 100.0;
    double bs = b_pct / 100.0;

    // Clamp to [0, 1]
    if (rs < 0.0) rs = 0.0; if (rs > 1.0) rs = 1.0;
    if (gs < 0.0) gs = 0.0; if (gs > 1.0) gs = 1.0;
    if (bs < 0.0) bs = 0.0; if (bs > 1.0) bs = 1.0;

    // Apply inverse gamma to get linear RGB for precision
    double lr = (rs <= 0.04045) ? rs / 12.92 : pow((rs + 0.055) / 1.055, 2.4);
    double lg = (gs <= 0.04045) ? gs / 12.92 : pow((gs + 0.055) / 1.055, 2.4);
    double lb = (bs <= 0.04045) ? bs / 12.92 : pow((bs + 0.055) / 1.055, 2.4);

    // Store high-precision linear RGB
    color.has_linear_rgb = 1;
    color.linear_r = lr;
    color.linear_g = lg;
    color.linear_b = lb;

    // Also store integer sRGB for compatibility
    color.red = (int)(rs * 255.0 + 0.5);
    color.green = (int)(gs * 255.0 + 0.5);
    color.blue = (int)(bs * 255.0 + 0.5);

    RB_GC_GUARD(rgb_value);
    return color;
}

// Format intermediate representation to hex string
// color: color_ir struct with RGB (0-255) and optional alpha (0.0-1.0)
// use_modern_syntax: unused for hex format (hex format is always the same)
// Returns: Ruby string with hex value like "#ff0000" or "#ff000080"
static VALUE format_hex(struct color_ir color, int use_modern_syntax) {
    (void)use_modern_syntax;  // Unused - hex format doesn't have variants

    char hex_buf[10];
    if (color.alpha >= 0.0) {
        int alpha_int = (int)(color.alpha * 255.0 + 0.5);
        FORMAT_HEX_ALPHA(hex_buf, color.red, color.green, color.blue, alpha_int);
    } else {
        FORMAT_HEX(hex_buf, color.red, color.green, color.blue);
    }

    return rb_str_new_cstr(hex_buf);
}

// Parse HSL color string to intermediate representation
// hsl_value: Ruby string like "hsl(0, 100%, 50%)" or "hsl(0, 100%, 50%, 0.5)"
// Returns: color_ir struct with RGB values (0-255) and optional alpha (0.0-1.0)
static struct color_ir parse_hsl(VALUE hsl_value) {
    Check_Type(hsl_value, T_STRING);

    const char *hsl_str = RSTRING_PTR(hsl_value);
    long hsl_len = RSTRING_LEN(hsl_value);

    if (hsl_len < 10 || (strncmp(hsl_str, "hsl(", 4) != 0 && strncmp(hsl_str, "hsla(", 5) != 0)) {
        rb_raise(rb_eColorConversionError, "Invalid HSL color: must start with 'hsl(' or 'hsla(', got '%s'", hsl_str);
    }

    // Skip "hsl(" or "hsla("
    const char *p = hsl_str;                              // "hsl(120, 100%, 50%, 0.75)"
    if (*p == 'h' && *(p+1) == 's' && *(p+2) == 'l') {   // "hsl"
        p += 3;                                           // "(120, 100%, 50%, 0.75)"
        if (*p == 'a') p++;                               // skip 'a' if hsla
        if (*p == '(') p++;                               // "120, 100%, 50%, 0.75)"
    }

    int hue, sat_int, light_int;
    double saturation, lightness;
    double alpha = -1.0;

    // Parse hue (0-360)
    SKIP_WHITESPACE(p);                                   // "120, 100%, 50%, 0.75)"
    PARSE_INT(p, hue);                                    // hue=120, p=", 100%, 50%, 0.75)"

    // Parse saturation (0-100%)
    SKIP_SEPARATOR(p);                                    // "100%, 50%, 0.75)"
    PARSE_INT(p, sat_int);                                // sat_int=100, p="%, 50%, 0.75)"
    saturation = sat_int;
    if (*p == '%') p++;                                   // " 50%, 0.75)"

    // Parse lightness (0-100%)
    SKIP_SEPARATOR(p);                                    // "50%, 0.75)"
    PARSE_INT(p, light_int);                              // light_int=50, p="%, 0.75)"
    lightness = light_int;
    if (*p == '%') p++;                                   // " 0.75)"

    // Check for alpha
    SKIP_SEPARATOR(p);                                    // "0.75)" or ", 0.75)" or ", / 0.75)"
    if (*p == '/') {                                      // '/'
        p++;                                              // " 0.75)"
        SKIP_WHITESPACE(p);                               // "0.75)"
    }

    if (*p >= '0' && *p <= '9') {                         // '0'
        alpha = 0.0;
        while (*p >= '0' && *p <= '9') {                  // '0' (integer part)
            alpha = alpha * 10.0 + (*p - '0');            // alpha=0.0
            p++;                                          // ".75)"
        }
        if (*p == '.') {                                  // '.'
            p++;                                          // "75)"
            double decimal = 0.1;
            while (*p >= '0' && *p <= '9') {              // '7', then '5'
                alpha += (*p - '0') * decimal;            // alpha=0.75
                decimal /= 10.0;                          // decimal=0.01
                p++;                                      // "5)" then ")"
            }
        }
    }

    // Convert HSL to RGB
    // Normalize saturation and lightness to 0.0-1.0
    saturation /= 100.0;
    lightness /= 100.0;

    // Normalize hue to 0-360 range
    hue = hue % 360;
    if (hue < 0) hue += 360;

    struct color_ir color;
    INIT_COLOR_IR(color);
    color.alpha = alpha;

    double c = (1.0 - fabs(2.0 * lightness - 1.0)) * saturation; // TODO: Document
    double x = c * (1.0 - fabs(fmod(hue / 60.0, 2.0) - 1.0));
    double m = lightness - c / 2.0;

    double red_prime, green_prime, blue_prime;

    if (hue >= 0 && hue < 60) {
        red_prime = c; green_prime = x; blue_prime = 0;
    } else if (hue >= 60 && hue < 120) {
        red_prime = x; green_prime = c; blue_prime = 0;
    } else if (hue >= 120 && hue < 180) {
        red_prime = 0; green_prime = c; blue_prime = x;
    } else if (hue >= 180 && hue < 240) {
        red_prime = 0; green_prime = x; blue_prime = c;
    } else if (hue >= 240 && hue < 300) {
        red_prime = x; green_prime = 0; blue_prime = c;
    } else {
        red_prime = c; green_prime = 0; blue_prime = x;
    }

    color.red = (int)((red_prime + m) * 255.0 + 0.5);
    color.green = (int)((green_prime + m) * 255.0 + 0.5);
    color.blue = (int)((blue_prime + m) * 255.0 + 0.5);

    return color;
}

// Format intermediate representation to HSL string
// color: color_ir struct with RGB (0-255) and optional alpha (0.0-1.0)
// use_modern_syntax: unused for HSL format (HSL format doesn't have variants like RGB)
// Returns: Ruby string with HSL value like "hsl(0, 100%, 50%)"
static VALUE format_hsl(struct color_ir color, int use_modern_syntax) {
    (void)use_modern_syntax;  // Unused - HSL format doesn't have variants

    // Convert RGB to HSL
    double red = color.red / 255.0;
    double green = color.green / 255.0;
    double blue = color.blue / 255.0;

    double max = red > green ? (red > blue ? red : blue) : (green > blue ? green : blue);
    double min = red < green ? (red < blue ? red : blue) : (green < blue ? green : blue);
    double delta = max - min;

    double hue = 0.0;
    double saturation = 0.0;
    double lightness = (max + min) / 2.0;

    if (delta > 0.0001) {  // Not grayscale
        saturation = lightness > 0.5 ? delta / (2.0 - max - min) : delta / (max + min);

        if (max == red) {
            hue = 60.0 * fmod((green - blue) / delta, 6.0);
        } else if (max == green) {
            hue = 60.0 * ((blue - red) / delta + 2.0);
        } else {
            hue = 60.0 * ((red - green) / delta + 4.0);
        }

        if (hue < 0) hue += 360.0;
    }

    int hue_int = (int)(hue + 0.5);
    int sat_int = (int)(saturation * 100.0 + 0.5);
    int light_int = (int)(lightness * 100.0 + 0.5);

    char hsl_buf[64];
    if (color.alpha >= 0.0) {
        FORMAT_HSLA(hsl_buf, hue_int, sat_int, light_int, color.alpha);
    } else {
        FORMAT_HSL(hsl_buf, hue_int, sat_int, light_int);
    }

    return rb_str_new_cstr(hsl_buf);
}

// Parse HWB color string to intermediate representation
// hwb_value: Ruby string like "hwb(0 0% 0%)" or "hwb(120 30% 20% / 0.5)"
// Returns: color_ir struct with RGB (0-255) and optional alpha (0.0-1.0)
static struct color_ir parse_hwb(VALUE hwb_value) {
    Check_Type(hwb_value, T_STRING);

    const char *hwb_str = RSTRING_PTR(hwb_value);
    long hwb_len = RSTRING_LEN(hwb_value);

    if (hwb_len < 10 || (strncmp(hwb_str, "hwb(", 4) != 0 && strncmp(hwb_str, "hwba(", 5) != 0)) {
        rb_raise(rb_eColorConversionError, "Invalid HWB color: must start with 'hwb(' or 'hwba(', got '%s'", hwb_str);
    }

    // Skip "hwb(" or "hwba("
    const char *p = hwb_str;                              // "hwb(120 30% 20% / 0.5)"
    if (*p == 'h' && *(p+1) == 'w' && *(p+2) == 'b') {   // "hwb"
        p += 3;                                           // "(120 30% 20% / 0.5)"
        if (*p == 'a') p++;                               // skip 'a' if hwba
        if (*p == '(') p++;                               // "120 30% 20% / 0.5)"
    }

    int hue, white_int, black_int;
    double whiteness, blackness;
    double alpha = -1.0;

    // Parse hue (0-360)
    SKIP_WHITESPACE(p);                                   // "120 30% 20% / 0.5)"
    PARSE_INT(p, hue);                                    // hue=120, p=" 30% 20% / 0.5)"

    // Parse whiteness (0-100%)
    SKIP_SEPARATOR(p);                                    // "30% 20% / 0.5)"
    PARSE_INT(p, white_int);                              // white_int=30, p="% 20% / 0.5)"
    whiteness = white_int / 100.0;
    if (*p == '%') p++;                                   // " 20% / 0.5)"

    // Parse blackness (0-100%)
    SKIP_SEPARATOR(p);                                    // "20% / 0.5)"
    PARSE_INT(p, black_int);                              // black_int=20, p="% / 0.5)"
    blackness = black_int / 100.0;
    if (*p == '%') p++;                                   // " / 0.5)"

    // Check for alpha
    SKIP_SEPARATOR(p);                                    // "/ 0.5)" or "0.5)" or ")"
    if (*p == '/') {                                      // '/'
        p++;                                              // " 0.5)"
        SKIP_WHITESPACE(p);                               // "0.5)"
    }

    if (*p >= '0' && *p <= '9') {                         // '0'
        alpha = 0.0;
        while (*p >= '0' && *p <= '9') {                  // '0' (integer part)
            alpha = alpha * 10.0 + (*p - '0');            // alpha=0.0
            p++;                                          // ".5)"
        }
        if (*p == '.') {                                  // '.'
            p++;                                          // "5)"
            double decimal = 0.1;
            while (*p >= '0' && *p <= '9') {              // '5'
                alpha += (*p - '0') * decimal;            // alpha=0.5
                decimal /= 10.0;                          // decimal=0.01
                p++;                                      // ")"
            }
        }
    }

    // Normalize W+B if > 100%
    double wb_sum = whiteness + blackness;
    if (wb_sum > 1.0) {
        whiteness /= wb_sum;
        blackness /= wb_sum;
    }

    // Convert HWB to RGB via HSL intermediate
    // First convert hue to RGB with S=100%, L=50% (fully saturated color)
    hue = hue % 360;
    if (hue < 0) hue += 360;

    // Use HSL→RGB conversion with saturation=1.0, lightness=0.5
    double c = 1.0;  // chroma at full saturation and 50% lightness
    double x = c * (1.0 - fabs(fmod(hue / 60.0, 2.0) - 1.0));
    double m = 0.0;  // no adjustment needed for L=0.5

    double red_prime, green_prime, blue_prime;

    if (hue >= 0 && hue < 60) {
        red_prime = c; green_prime = x; blue_prime = 0;
    } else if (hue >= 60 && hue < 120) {
        red_prime = x; green_prime = c; blue_prime = 0;
    } else if (hue >= 120 && hue < 180) {
        red_prime = 0; green_prime = c; blue_prime = x;
    } else if (hue >= 180 && hue < 240) {
        red_prime = 0; green_prime = x; blue_prime = c;
    } else if (hue >= 240 && hue < 300) {
        red_prime = x; green_prime = 0; blue_prime = c;
    } else {
        red_prime = c; green_prime = 0; blue_prime = x;
    }

    // Apply HWB transformation: rgb = rgb * (1 - W - B) + W
    struct color_ir color;
    INIT_COLOR_IR(color);
    color.red = (int)(((red_prime + m) * (1.0 - whiteness - blackness) + whiteness) * 255.0 + 0.5);
    color.green = (int)(((green_prime + m) * (1.0 - whiteness - blackness) + whiteness) * 255.0 + 0.5);
    color.blue = (int)(((blue_prime + m) * (1.0 - whiteness - blackness) + whiteness) * 255.0 + 0.5);
    color.alpha = alpha;

    return color;
}

// Format intermediate representation to HWB string
// color: color_ir struct with RGB (0-255) and optional alpha (0.0-1.0)
// use_modern_syntax: unused for HWB format
// Returns: Ruby string with HWB value like "hwb(0 0% 0%)"
static VALUE format_hwb(struct color_ir color, int use_modern_syntax) {
    (void)use_modern_syntax;  // Unused - HWB format doesn't have variants

    // Convert RGB to HWB
    double red = color.red / 255.0;
    double green = color.green / 255.0;
    double blue = color.blue / 255.0;

    double max = red > green ? (red > blue ? red : blue) : (green > blue ? green : blue);
    double min = red < green ? (red < blue ? red : blue) : (green < blue ? green : blue);
    double delta = max - min;

    // Calculate hue (same as HSL)
    double hue = 0.0;
    if (delta > 0.0001) {  // Not grayscale
        if (max == red) {
            hue = 60.0 * fmod((green - blue) / delta, 6.0);
        } else if (max == green) {
            hue = 60.0 * ((blue - red) / delta + 2.0);
        } else {
            hue = 60.0 * ((red - green) / delta + 4.0);
        }

        if (hue < 0) hue += 360.0;
    }

    // Whiteness = min component, Blackness = 1 - max component
    double whiteness = min;
    double blackness = 1.0 - max;

    // Per W3C spec: if white + black >= 1, the color is achromatic (hue is undefined)
    // https://www.w3.org/TR/css-color-4/#the-hwb-notation
    // Use epsilon to account for floating-point rounding errors
    double epsilon = 1.0 / 100000.0;
    if (whiteness + blackness >= 1.0 - epsilon) {
        hue = 0.0;  // CSS serializes NaN as 0
    }

    int hue_int = (int)(hue + 0.5);
    int white_int = (int)(whiteness * 100.0 + 0.5);
    int black_int = (int)(blackness * 100.0 + 0.5);

    char hwb_buf[64];
    if (color.alpha >= 0.0) {
        FORMAT_HWBA(hwb_buf, hue_int, white_int, black_int, color.alpha);
    } else {
        FORMAT_HWB(hwb_buf, hue_int, white_int, black_int);
    }

    return rb_str_new_cstr(hwb_buf);
}

// Get parser function for a given format
static color_parser_fn get_parser(VALUE format) {
    ID format_id = SYM2ID(format);
    ID hex_id = rb_intern("hex");
    ID rgb_id = rb_intern("rgb");
    ID hsl_id = rb_intern("hsl");
    ID hwb_id = rb_intern("hwb");
    ID oklab_id = rb_intern("oklab");
    ID oklch_id = rb_intern("oklch");
    ID lab_id = rb_intern("lab");
    ID lch_id = rb_intern("lch");
    ID named_id = rb_intern("named");

    if (format_id == hex_id) {
        return parse_hex;
    }
    if (format_id == rgb_id) {
        return parse_rgb;
    }
    if (format_id == hsl_id) {
        return parse_hsl;
    }
    if (format_id == hwb_id) {
        return parse_hwb;
    }
    if (format_id == oklab_id) {
        return parse_oklab;
    }
    if (format_id == oklch_id) {
        return parse_oklch;
    }
    if (format_id == lab_id) {
        return parse_lab;
    }
    if (format_id == lch_id) {
        return parse_lch;
    }
    if (format_id == named_id) {
        return parse_named;
    }

    return NULL;
}

// Get formatter function for a given format
static color_formatter_fn get_formatter(VALUE format) {
    ID format_id = SYM2ID(format);
    ID hex_id = rb_intern("hex");
    ID rgb_id = rb_intern("rgb");
    ID rgba_id = rb_intern("rgba");
    ID hsl_id = rb_intern("hsl");
    ID hsla_id = rb_intern("hsla");
    ID hwb_id = rb_intern("hwb");
    ID hwba_id = rb_intern("hwba");
    ID oklab_id = rb_intern("oklab");
    ID oklch_id = rb_intern("oklch");
    ID lab_id = rb_intern("lab");
    ID lch_id = rb_intern("lch");

    if (format_id == hex_id) {
        return format_hex;
    }
    if (format_id == rgb_id || format_id == rgba_id) {
        return format_rgb;
    }
    if (format_id == hsl_id || format_id == hsla_id) {
        return format_hsl;
    }
    if (format_id == hwb_id || format_id == hwba_id) {
        return format_hwb;
    }
    if (format_id == oklab_id) {
        return format_oklab;
    }
    if (format_id == oklch_id) {
        return format_oklch;
    }
    if (format_id == lab_id) {
        return format_lab;
    }
    if (format_id == lch_id) {
        return format_lch;
    }

    return NULL;
}

// Convert a value that may contain multiple colors or colors mixed with other values
// (e.g., "border-color: #fff #000 #ccc" or "box-shadow: 0 0 10px #ff0000")
// parser: specific parser to use (e.g., parse_hex), or NULL for auto-detect all formats
// Returns a new Ruby string with all colors converted, or Qnil if no colors found
static VALUE convert_value_with_colors(VALUE value, color_parser_fn parser, color_formatter_fn formatter, int use_modern_syntax) {
    if (NIL_P(value) || TYPE(value) != T_STRING) {
        return Qnil;
    }

    const char *input = RSTRING_PTR(value);
    long input_len = RSTRING_LEN(value);

    DEBUG_PRINTF("convert_value_with_colors: input='%.*s' parser=%p formatter=%p\n", (int)input_len, input, (void*)parser, (void*)formatter);

    // Build output string with converted colors
    VALUE result = rb_str_buf_new(input_len * 2);  // Allocate generous space
    long pos = 0;
    int found_color = 0;
    int in_url = 0;  // Track if we're inside url()
    int url_paren_depth = 0;  // Track paren depth inside url()

    while (pos < input_len) {
        const char *p = input + pos;
        long remaining = input_len - pos;
        long color_len = 0;

        // Check for url( to skip content inside URLs
        if (!in_url && remaining >= 4 && p[0] == 'u' && p[1] == 'r' && p[2] == 'l' && p[3] == '(') {
            in_url = 1;
            url_paren_depth = 1;  // Start counting from the url's opening paren
            // Copy "url("
            rb_str_buf_cat(result, p, 4);
            pos += 4;
            continue;
        }

        // If we're inside url(), track parens and copy as-is
        if (in_url) {
            if (*p == '(') {
                url_paren_depth++;
            } else if (*p == ')') {
                url_paren_depth--;
                if (url_paren_depth == 0) {
                    in_url = 0;  // Exiting url()
                }
            }
            rb_str_buf_cat(result, &input[pos], 1);
            pos++;
            continue;
        }

        // Skip whitespace and preserve it
        while (pos < input_len && (input[pos] == ' ' || input[pos] == '\t')) {
            rb_str_buf_cat(result, &input[pos], 1);
            pos++;
            p = input + pos;
            remaining = input_len - pos;
        }

        if (pos >= input_len) break;

        // Check for hex color
        if (*p == '#' && (parser == NULL || parser == parse_hex)) {
            // Find the end of the hex color (next space, comma, or delimiter)
            const char *end = p + 1;
            while (*end && *end != ' ' && *end != ',' && *end != ';' && *end != ')' && *end != '\n') {
                end++;
            }
            color_len = end - p;

            // Parse and convert hex color
            VALUE hex_str = rb_str_new(p, color_len);
            struct color_ir color = parse_hex(hex_str);
            VALUE converted = formatter(color, use_modern_syntax);
            rb_str_buf_append(result, converted);
            pos += color_len;
            found_color = 1;
            continue;
        }

        // Check for rgb/rgba
        if (STARTS_WITH_RGB(p, remaining) && (parser == NULL || parser == parse_rgb)) {
            const char *end;
            FIND_CLOSING_PAREN(p, end);
            color_len = end - p;

            // Skip if contains unparseable content (calc, none, etc.)
            int skip;
            HAS_UNPARSEABLE_CONTENT(p, color_len, skip);
            if (skip) {
                rb_str_buf_append(result, rb_str_new(p, color_len));
                pos += color_len;
                found_color = 1;
                continue;
            }

            VALUE rgb_str = rb_str_new(p, color_len);
            struct color_ir color = parse_rgb(rgb_str);
            VALUE converted = formatter(color, use_modern_syntax);
            rb_str_buf_append(result, converted);
            pos += color_len;
            found_color = 1;
            continue;
        }

        // Check for hsl/hsla
        if (STARTS_WITH_HSL(p, remaining) && (parser == NULL || parser == parse_hsl)) {
            const char *end;
            FIND_CLOSING_PAREN(p, end);
            color_len = end - p;

            // Skip if contains unparseable content (calc, none, etc.)
            int skip;
            HAS_UNPARSEABLE_CONTENT(p, color_len, skip);
            if (skip) {
                rb_str_buf_append(result, rb_str_new(p, color_len));
                pos += color_len;
                found_color = 1;
                continue;
            }

            VALUE hsl_str = rb_str_new(p, color_len);
            struct color_ir color = parse_hsl(hsl_str);
            VALUE converted = formatter(color, use_modern_syntax);
            rb_str_buf_append(result, converted);
            pos += color_len;
            found_color = 1;
            continue;
        }

        // Check for hwb/hwba
        if (STARTS_WITH_HWB(p, remaining) && (parser == NULL || parser == parse_hwb)) {
            const char *end;
            FIND_CLOSING_PAREN(p, end);
            color_len = end - p;

            // Skip if contains unparseable content (calc, none, etc.)
            int skip;
            HAS_UNPARSEABLE_CONTENT(p, color_len, skip);
            if (skip) {
                rb_str_buf_append(result, rb_str_new(p, color_len));
                pos += color_len;
                found_color = 1;
                continue;
            }

            VALUE hwb_str = rb_str_new(p, color_len);
            struct color_ir color = parse_hwb(hwb_str);
            VALUE converted = formatter(color, use_modern_syntax);
            rb_str_buf_append(result, converted);
            pos += color_len;
            found_color = 1;
            continue;
        }

        // Check for oklab
        if (STARTS_WITH_OKLAB(p, remaining) && (parser == NULL || parser == parse_oklab)) {
            const char *end;
            FIND_CLOSING_PAREN(p, end);
            color_len = end - p;

            // Skip if contains unparseable content (calc, none, etc.)
            int skip;
            HAS_UNPARSEABLE_CONTENT(p, color_len, skip);
            if (skip) {
                rb_str_buf_append(result, rb_str_new(p, color_len));
                pos += color_len;
                found_color = 1;
                continue;
            }

            VALUE oklab_str = rb_str_new(p, color_len);
            struct color_ir color = parse_oklab(oklab_str);
            VALUE converted = formatter(color, use_modern_syntax);
            rb_str_buf_append(result, converted);
            pos += color_len;
            found_color = 1;
            continue;
        }

        // Check for oklch
        if (STARTS_WITH_OKLCH(p, remaining) && (parser == NULL || parser == parse_oklch)) {
            const char *end;
            FIND_CLOSING_PAREN(p, end);
            color_len = end - p;

            // Skip if contains unparseable content (calc, none, etc.)
            int skip;
            HAS_UNPARSEABLE_CONTENT(p, color_len, skip);
            if (skip) {
                rb_str_buf_append(result, rb_str_new(p, color_len));
                pos += color_len;
                found_color = 1;
                continue;
            }

            VALUE oklch_str = rb_str_new(p, color_len);
            struct color_ir color = parse_oklch(oklch_str);
            VALUE converted = formatter(color, use_modern_syntax);
            rb_str_buf_append(result, converted);
            pos += color_len;
            found_color = 1;
            continue;
        }

        // Check for lch (must check before lab since both start with 'l')
        if (STARTS_WITH_LCH(p, remaining) && (parser == NULL || parser == parse_lch)) {
            const char *end;
            FIND_CLOSING_PAREN(p, end);
            color_len = end - p;

            // Skip if contains unparseable content (calc, none, etc.)
            int skip;
            HAS_UNPARSEABLE_CONTENT(p, color_len, skip);
            if (skip) {
                rb_str_buf_append(result, rb_str_new(p, color_len));
                pos += color_len;
                found_color = 1;
                continue;
            }

            VALUE lch_str = rb_str_new(p, color_len);
            struct color_ir color = parse_lch(lch_str);
            VALUE converted = formatter(color, use_modern_syntax);
            rb_str_buf_append(result, converted);
            pos += color_len;
            found_color = 1;
            continue;
        }

        // Check for lab
        if (STARTS_WITH_LAB(p, remaining) && (parser == NULL || parser == parse_lab)) {
            const char *end;
            FIND_CLOSING_PAREN(p, end);
            color_len = end - p;

            // Skip if contains unparseable content (calc, none, etc.)
            int skip;
            HAS_UNPARSEABLE_CONTENT(p, color_len, skip);
            if (skip) {
                rb_str_buf_append(result, rb_str_new(p, color_len));
                pos += color_len;
                found_color = 1;
                continue;
            }

            VALUE lab_str = rb_str_new(p, color_len);
            struct color_ir color = parse_lab(lab_str);
            VALUE converted = formatter(color, use_modern_syntax);
            rb_str_buf_append(result, converted);
            pos += color_len;
            found_color = 1;
            continue;
        }

        // Check for named colors (alphabetic, length 3-20)
        // Try early to catch valid color names, skip word if not found
        if (((*p >= 'a' && *p <= 'z') || (*p >= 'A' && *p <= 'Z')) && (parser == NULL || parser == parse_named)) {
            DEBUG_PRINTF("Checking alphabetic word at pos %ld, parser=%p, parse_named=%p\n", pos, (void*)parser, (void*)parse_named);
            // Find the end of the alphabetic word
            const char *end = p + 1;
            while (*end && ((*end >= 'a' && *end <= 'z') || (*end >= 'A' && *end <= 'Z'))) {
                end++;
            }
            color_len = end - p;
            DEBUG_PRINTF("Word length = %ld\n", color_len);

            // Named colors are 3-20 characters (red to lightgoldenrodyellow)
            if (color_len >= 3 && color_len <= 20) {
                VALUE named_str = rb_str_new(p, color_len);
                DEBUG_PRINTF("Trying to parse: '%s'\n", StringValueCStr(named_str));
                struct color_ir color = parse_named(named_str);
                DEBUG_PRINTF("parse_named returned red=%d\n", color.red);

                // Check if valid (red >= 0 means found)
                if (color.red >= 0) {
                    DEBUG_PRINTF("Valid color! Converting...\n");
                    VALUE converted = formatter(color, use_modern_syntax);
                    rb_str_buf_append(result, converted);
                    pos += color_len;
                    found_color = 1;
                    continue;
                }

                DEBUG_PRINTF("Not a valid color, copying word\n");
                // Not a valid color - copy the whole word as-is and continue
                rb_str_buf_cat(result, p, color_len);
                pos += color_len;
                continue;
            }
        }

        // Not a color - copy character as-is
        rb_str_buf_cat(result, &input[pos], 1);
        pos++;
    }

    RB_GC_GUARD(value);  // Prevent GC of value while we hold input pointer

    DEBUG_PRINTF("Returning %s\n", found_color ? "result" : "Qnil (no colors found)");

    return found_color ? result : Qnil;
}

// Auto-detect the color format of a value string
// Returns the appropriate parser function, or NULL if not recognized
static color_parser_fn detect_color_format(VALUE value) {
    if (NIL_P(value) || TYPE(value) != T_STRING) {
        return NULL;
    }

    const char *val_str = RSTRING_PTR(value);
    long val_len = RSTRING_LEN(value);

    if (val_len == 0) {
        return NULL;
    }

    // Skip leading whitespace
    const char *p = val_str;
    while (*p == ' ' || *p == '\t') {
        p++;
    }

    long remaining = val_len - (p - val_str);

    // Check for hex (starts with #)
    if (*p == '#') {
        return parse_hex;
    }

    // Check for rgb (starts with 'rgb')
    if (STARTS_WITH_RGB(p, remaining)) {
        return parse_rgb;
    }

    // Check for hwb (starts with 'hwb')
    if (STARTS_WITH_HWB(p, remaining)) {
        return parse_hwb;
    }

    // Check for hsl (starts with 'hsl')
    if (STARTS_WITH_HSL(p, remaining)) {
        return parse_hsl;
    }

    // Check for oklab (starts with 'oklab')
    if (STARTS_WITH_OKLAB(p, remaining)) {
        return parse_oklab;
    }

    // Check for oklch (starts with 'oklch')
    if (STARTS_WITH_OKLCH(p, remaining)) {
        return parse_oklch;
    }

    // Check for lch (starts with 'lch(') - must check before lab
    if (STARTS_WITH_LCH(p, remaining)) {
        return parse_lch;
    }

    // Check for lab (starts with 'lab(')
    if (STARTS_WITH_LAB(p, remaining)) {
        return parse_lab;
    }

    // Check for named colors (fallback - alphabetic characters)
    // Named colors must start with a letter
    if ((*p >= 'a' && *p <= 'z') || (*p >= 'A' && *p <= 'Z')) {
        return parse_named;
    }

    return NULL;
}

// Check if a value matches a given color format
// Returns 1 if it matches, 0 otherwise
static int matches_color_format(VALUE value, VALUE format) {
    if (NIL_P(value) || TYPE(value) != T_STRING) {
        return 0;
    }

    const char *val_str = RSTRING_PTR(value);
    long val_len = RSTRING_LEN(value);

    if (val_len == 0) {
        return 0;
    }

    // Skip leading whitespace
    const char *p = val_str;
    while (*p == ' ' || *p == '\t') {
        p++;
    }

    long remaining = val_len - (p - val_str);

    ID format_id = SYM2ID(format);
    ID hex_id = rb_intern("hex");
    ID rgb_id = rb_intern("rgb");
    ID hsl_id = rb_intern("hsl");
    ID hwb_id = rb_intern("hwb");
    ID oklab_id = rb_intern("oklab");
    ID oklch_id = rb_intern("oklch");
    ID lab_id = rb_intern("lab");
    ID lch_id = rb_intern("lch");
    ID named_id = rb_intern("named");

    if (format_id == hex_id) {
        return *p == '#';
    }
    if (format_id == rgb_id) {
        return STARTS_WITH_RGB(p, remaining);
    }
    if (format_id == hwb_id) {
        return STARTS_WITH_HWB(p, remaining);
    }
    if (format_id == hsl_id) {
        return STARTS_WITH_HSL(p, remaining);
    }
    if (format_id == oklab_id) {
        return STARTS_WITH_OKLAB(p, remaining);
    }
    if (format_id == oklch_id) {
        return STARTS_WITH_OKLCH(p, remaining);
    }
    if (format_id == lab_id) {
        return STARTS_WITH_LAB(p, remaining);
    }
    if (format_id == lch_id) {
        return STARTS_WITH_LCH(p, remaining);
    }
    if (format_id == named_id) {
        // Named colors are alphabetic (possibly with whitespace)
        // Just check that it starts with a letter
        return (*p >= 'a' && *p <= 'z') || (*p >= 'A' && *p <= 'Z');
    }

    return 0;
}

// Expand shorthand properties if needed (e.g., background → background-color, background-image, etc.)
// Returns hash of expanded properties, or nil if no expansion needed
static VALUE expand_property_if_needed(VALUE property_name, VALUE value) {
    Check_Type(property_name, T_STRING);
    Check_Type(value, T_STRING);

    const char *prop = RSTRING_PTR(property_name);

    // Check if this is a shorthand property that needs expansion
    if (strcmp(prop, "background") == 0) {
        return cataract_expand_background(Qnil, value);
    }
    // Add other shorthands if needed (margin, padding, border, font, list-style)

    return Qnil;  // No expansion needed
}

// Context struct for hash iteration
struct convert_colors_context {
    color_parser_fn parser;          // NULL if auto-detect mode
    color_formatter_fn formatter;
    int use_modern_syntax;
    VALUE from_format;                // :any for auto-detect
};

// Context for expanding and converting shorthand properties
struct expand_convert_context {
    color_parser_fn parser;          // NULL if auto-detect mode
    color_formatter_fn formatter;
    int use_modern_syntax;
    VALUE from_format;                // :any for auto-detect
    VALUE new_declarations;
    VALUE important;
};

// Callback for iterating expanded properties, converting colors, and creating declaration structs
static int convert_expanded_property_callback(VALUE prop_name, VALUE prop_value, VALUE arg) {
    struct expand_convert_context *ctx = (struct expand_convert_context *)arg;

    if (!NIL_P(prop_value) && TYPE(prop_value) == T_STRING) {
        color_parser_fn parser;

        // Auto-detect or use specified format
        if (ctx->parser == NULL) {
            parser = detect_color_format(prop_value);
        } else if (matches_color_format(prop_value, ctx->from_format)) {
            parser = ctx->parser;
        } else {
            parser = NULL;
        }

        if (parser != NULL) {
            // Parse → IR → Format
            struct color_ir color = parser(prop_value);
            prop_value = ctx->formatter(color, ctx->use_modern_syntax);
        }

        VALUE new_decl = rb_struct_new(cDeclaration, prop_name, prop_value, ctx->important, NULL);
        rb_ary_push(ctx->new_declarations, new_decl);
    }

    return ST_CONTINUE;
}

// Hash iterator callback for processing each rule group
static int process_rule_group_callback(VALUE media_key, VALUE group, VALUE arg) {
    struct convert_colors_context *ctx = (struct convert_colors_context *)arg;

    if (NIL_P(group) || TYPE(group) != T_HASH) {
        return ST_CONTINUE;
    }

    // Get the rules array from the group
    VALUE rules = rb_hash_aref(group, ID2SYM(rb_intern("rules")));

    if (NIL_P(rules) || TYPE(rules) != T_ARRAY) {
        return ST_CONTINUE;
    }

    // Process each rule in the array
    long rules_count = RARRAY_LEN(rules);

    for (long i = 0; i < rules_count; i++) {
        VALUE rule = rb_ary_entry(rules, i);

        // Get declarations array from the rule struct
        // Rule = Struct.new(:selector, :declarations, :specificity)
        // where declarations is an Array of Declaration structs
        VALUE declarations = rb_struct_aref(rule, INT2FIX(RULE_DECLARATIONS));

        if (NIL_P(declarations) || TYPE(declarations) != T_ARRAY) {
            continue;
        }

        // Iterate through each Declaration struct in the array
        long decl_count = RARRAY_LEN(declarations);

        // Build new declarations array with expanded and converted values
        VALUE new_declarations = rb_ary_new();

        for (long j = 0; j < decl_count; j++) {
            VALUE decl_struct = rb_ary_entry(declarations, j);

            // Declaration = Struct.new(:property, :value, :important)
            VALUE property = rb_struct_aref(decl_struct, INT2FIX(DECL_PROPERTY));
            VALUE value = rb_struct_aref(decl_struct, INT2FIX(DECL_VALUE));
            VALUE important = rb_struct_aref(decl_struct, INT2FIX(DECL_IMPORTANT));

            if (NIL_P(value) || TYPE(value) != T_STRING) {
                rb_ary_push(new_declarations, decl_struct);
                continue;
            }

            // Check if this property needs expansion (e.g., background shorthand)
            VALUE expanded = expand_property_if_needed(property, value);

            if (!NIL_P(expanded) && TYPE(expanded) == T_HASH && RHASH_SIZE(expanded) > 0) {
                // Expand and convert each sub-property
                struct expand_convert_context exp_ctx = {
                    .parser = ctx->parser,
                    .formatter = ctx->formatter,
                    .use_modern_syntax = ctx->use_modern_syntax,
                    .from_format = ctx->from_format,
                    .new_declarations = new_declarations,
                    .important = important
                };
                rb_hash_foreach(expanded, convert_expanded_property_callback, (VALUE)&exp_ctx);
                continue;
            }
            // If expansion returned empty hash, keep original declaration (e.g., gradients)

            // Try to convert as a value with potentially multiple colors
            // (e.g., "border-color: #fff #000 #ccc" or "box-shadow: 0 0 10px #ff0000")
            VALUE converted_multi = convert_value_with_colors(value, ctx->parser, ctx->formatter, ctx->use_modern_syntax);

            if (!NIL_P(converted_multi)) {
                DEBUG_PRINTF("Creating new decl with property='%s' value='%s'\n",
                        StringValueCStr(property), StringValueCStr(converted_multi));
                // Successfully converted multi-value property
                VALUE new_decl = rb_struct_new(cDeclaration, property, converted_multi, important, NULL);
                rb_ary_push(new_declarations, new_decl);
                DEBUG_PRINTF("Pushed new_decl to new_declarations\n");
                continue;
            }

            // Try single-value color conversion
            color_parser_fn parser;

            // Auto-detect or use specified format
            if (ctx->parser == NULL) {
                parser = detect_color_format(value);
            } else if (matches_color_format(value, ctx->from_format)) {
                parser = ctx->parser;
            } else {
                parser = NULL;
            }

            if (parser != NULL) {
                // Parse → IR → Format
                struct color_ir color = parser(value);

                // Check if parse was successful (named colors can fail lookup)
                if (color.red < 0) {
                    // Invalid color - keep original declaration
                    rb_ary_push(new_declarations, decl_struct);
                } else {
                    VALUE new_value = ctx->formatter(color, ctx->use_modern_syntax);
                    VALUE new_decl = rb_struct_new(cDeclaration, property, new_value, important, NULL);
                    rb_ary_push(new_declarations, new_decl);
                }
            } else {
                rb_ary_push(new_declarations, decl_struct);
            }
        }

        // Replace rule's declarations array
        rb_struct_aset(rule, INT2FIX(RULE_DECLARATIONS), new_declarations);
    }

    return ST_CONTINUE;
}

// Ruby method: stylesheet.convert_colors!(from: :hex, to: :rgb, variant: :modern)
// Returns self for method chaining
VALUE rb_stylesheet_convert_colors(int argc, VALUE *argv, VALUE self) {
    VALUE kwargs;
    rb_scan_args(argc, argv, ":", &kwargs);

    // Handle case where no kwargs provided
    if (NIL_P(kwargs)) {
        kwargs = rb_hash_new();
    }

    // Extract keyword arguments
    VALUE from_format = rb_hash_aref(kwargs, ID2SYM(rb_intern("from")));
    VALUE to_format = rb_hash_aref(kwargs, ID2SYM(rb_intern("to")));
    VALUE variant = rb_hash_aref(kwargs, ID2SYM(rb_intern("variant")));

    // Default from_format to :any (auto-detect)
    if (NIL_P(from_format)) {
        from_format = ID2SYM(rb_intern("any"));
    }

    // Validate required arguments
    if (NIL_P(to_format)) {
        rb_raise(rb_eArgError, "missing keyword: :to");
    }

    // Auto-detect variant based on to_format if not explicitly set
    // :rgba, :hsla, :hwba imply legacy syntax (rgba(), hsla(), hwba())
    // :rgb, :hsl, :hwb, :hex default to modern syntax
    if (NIL_P(variant)) {
        ID to_id = SYM2ID(to_format);
        ID rgba_id = rb_intern("rgba");
        ID hsla_id = rb_intern("hsla");
        ID hwba_id = rb_intern("hwba");

        if (to_id == rgba_id || to_id == hsla_id || to_id == hwba_id) {
            variant = ID2SYM(rb_intern("legacy"));
        } else {
            variant = ID2SYM(rb_intern("modern"));
        }
    }

    // Get the appropriate parser and formatter functions
    color_parser_fn parser = NULL;
    ID from_id = SYM2ID(from_format);
    ID any_id = rb_intern("any");

    // If from is :any, we'll auto-detect per value (parser = NULL)
    if (from_id != any_id) {
        parser = get_parser(from_format);
        if (parser == NULL) {
            const char *from_str = rb_id2name(from_id);
            rb_raise(rb_eArgError, "Unsupported source format: %s", from_str);
        }
    }

    color_formatter_fn formatter = get_formatter(to_format);
    if (formatter == NULL) {
        const char *to_str = rb_id2name(SYM2ID(to_format));
        rb_raise(rb_eArgError, "Unsupported target format: %s", to_str);
    }

    // Determine syntax variant
    ID variant_id = SYM2ID(variant);
    ID modern_id = rb_intern("modern");
    int use_modern_syntax = (variant_id == modern_id) ? 1 : 0;

    // Get the rule_groups hash from the stylesheet
    // @rule_groups is {media_query_string => {media_types: [...], rules: [...]}}
    VALUE rule_groups = rb_ivar_get(self, rb_intern("@rule_groups"));

    if (NIL_P(rule_groups)) {
        return self;  // No rules, nothing to convert
    }

    if (TYPE(rule_groups) != T_HASH) {
        rb_raise(rb_eTypeError, "Stylesheet @rule_groups must be a Hash, got %s",
                 rb_obj_classname(rule_groups));
    }

    // Iterate through each media query group using rb_hash_foreach
    struct convert_colors_context ctx = {
        .parser = parser,
        .formatter = formatter,
        .use_modern_syntax = use_modern_syntax,
        .from_format = from_format
    };

    rb_hash_foreach(rule_groups, process_rule_group_callback, (VALUE)&ctx);

    // Clear the @declarations cache so it gets regenerated on next access
    rb_ivar_set(self, rb_intern("@declarations"), Qnil);

    return self;  // Return self for chaining
}
