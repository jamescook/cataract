// color_conversion.h - Shared types and macros for CSS color conversion
#ifndef COLOR_CONVERSION_H
#define COLOR_CONVERSION_H

#include "cataract.h"

// Intermediate representation for colors
// All colors are stored as sRGB (0-255) for compatibility.
// Optionally, high-precision linear RGB can be preserved to avoid quantization loss.
struct color_ir {
    // sRGB representation (0-255) - always populated
    int red;      // 0-255
    int green;    // 0-255
    int blue;     // 0-255
    double alpha; // 0.0-1.0, or -1.0 for "no alpha"

    // Optional high-precision linear RGB (0.0-1.0)
    // Set has_linear_rgb = 1 if linear_* fields contain valid data
    // Formatters that support high precision (e.g., oklab) should check this flag
    // and prefer linear RGB over sRGB to avoid quantization errors
    int has_linear_rgb;
    double linear_r;  // 0.0-1.0 (linear RGB, not gamma-corrected)
    double linear_g;  // 0.0-1.0
    double linear_b;  // 0.0-1.0
};

// Initialize color_ir struct with default values
#define INIT_COLOR_IR(color) do { \
    (color).red = 0; \
    (color).green = 0; \
    (color).blue = 0; \
    (color).alpha = -1.0; \
    (color).has_linear_rgb = 0; \
    (color).linear_r = 0.0; \
    (color).linear_g = 0.0; \
    (color).linear_b = 0.0; \
} while(0)

// Macros for parsing color values
#define SKIP_WHITESPACE(p) while (*(p) == ' ') (p)++
#define SKIP_SEPARATOR(p) while (*(p) == ',' || *(p) == ' ') (p)++
#define PARSE_INT(p, var) do { \
    int is_negative = 0; \
    if (*(p) == '-') { \
        is_negative = 1; \
        (p)++; \
    } \
    (var) = 0; \
    while (*(p) >= '0' && *(p) <= '9') { \
        (var) = (var) * 10 + (*(p) - '0'); \
        (p)++; \
    } \
    if (is_negative) (var) = -(var); \
} while(0)

// Find matching closing parenthesis
// Sets 'end' pointer to character after closing paren
#define FIND_CLOSING_PAREN(start, end) do { \
    int paren_count = 0; \
    (end) = (start); \
    while (*(end)) { \
        if (*(end) == '(') paren_count++; \
        if (*(end) == ')') { \
            paren_count--; \
            if (paren_count == 0) { \
                (end)++; \
                break; \
            } \
        } \
        (end)++; \
    } \
} while(0)

// Detect color format at current position
#define STARTS_WITH_RGB(p, remaining) \
    ((remaining) >= 4 && (p)[0] == 'r' && (p)[1] == 'g' && (p)[2] == 'b' && ((p)[3] == '(' || (p)[3] == 'a'))

#define STARTS_WITH_HSL(p, remaining) \
    ((remaining) >= 4 && (p)[0] == 'h' && (p)[1] == 's' && (p)[2] == 'l' && ((p)[3] == '(' || (p)[3] == 'a'))

#define STARTS_WITH_HWB(p, remaining) \
    ((remaining) >= 4 && (p)[0] == 'h' && (p)[1] == 'w' && (p)[2] == 'b' && ((p)[3] == '(' || (p)[3] == 'a'))

#define STARTS_WITH_OKLAB(p, remaining) \
    ((remaining) >= 6 && (p)[0] == 'o' && (p)[1] == 'k' && (p)[2] == 'l' && \
     (p)[3] == 'a' && (p)[4] == 'b' && (p)[5] == '(')

#define STARTS_WITH_OKLCH(p, remaining) \
    ((remaining) >= 6 && (p)[0] == 'o' && (p)[1] == 'k' && (p)[2] == 'l' && \
     (p)[3] == 'c' && (p)[4] == 'h' && (p)[5] == '(')

#define STARTS_WITH_LAB(p, remaining) \
    ((remaining) >= 4 && (p)[0] == 'l' && (p)[1] == 'a' && (p)[2] == 'b' && (p)[3] == '(')

#define STARTS_WITH_LCH(p, remaining) \
    ((remaining) >= 4 && (p)[0] == 'l' && (p)[1] == 'c' && (p)[2] == 'h' && (p)[3] == '(')

// Macros for formatting color values
#define FORMAT_RGB_MODERN(buf, red, green, blue) \
    snprintf(buf, sizeof(buf), "rgb(%d %d %d)", red, green, blue)
#define FORMAT_RGB_LEGACY(buf, red, green, blue) \
    snprintf(buf, sizeof(buf), "rgb(%d, %d, %d)", red, green, blue)
#define FORMAT_RGBA_MODERN(buf, red, green, blue, alpha) \
    snprintf(buf, sizeof(buf), "rgb(%d %d %d / %.10g)", red, green, blue, alpha)
#define FORMAT_RGBA_LEGACY(buf, red, green, blue, alpha) \
    snprintf(buf, sizeof(buf), "rgba(%d, %d, %d, %.10g)", red, green, blue, alpha)
#define FORMAT_HEX(buf, red, green, blue) \
    snprintf(buf, sizeof(buf), "#%02x%02x%02x", red, green, blue)
#define FORMAT_HEX_ALPHA(buf, red, green, blue, alpha_int) \
    snprintf(buf, sizeof(buf), "#%02x%02x%02x%02x", red, green, blue, alpha_int)
#define FORMAT_HSL(buf, hue, sat, light) \
    snprintf(buf, sizeof(buf), "hsl(%d, %d%%, %d%%)", hue, sat, light)
#define FORMAT_HSLA(buf, hue, sat, light, alpha) \
    snprintf(buf, sizeof(buf), "hsl(%d, %d%%, %d%%, %.10g)", hue, sat, light, alpha)
#define FORMAT_HWB(buf, hue, white, black) \
    snprintf(buf, sizeof(buf), "hwb(%d %d%% %d%%)", hue, white, black)
#define FORMAT_HWBA(buf, hue, white, black, alpha) \
    snprintf(buf, sizeof(buf), "hwb(%d %d%% %d%% / %.10g)", hue, white, black, alpha)
#define FORMAT_OKLAB(buf, l, a, b) \
    snprintf(buf, sizeof(buf), "oklab(%.4f %.4f %.4f)", l, a, b)
#define FORMAT_OKLAB_ALPHA(buf, l, a, b, alpha) \
    snprintf(buf, sizeof(buf), "oklab(%.4f %.4f %.4f / %.10g)", l, a, b, alpha)
#define FORMAT_RGB_PERCENT(buf, r_pct, g_pct, b_pct) \
    snprintf(buf, sizeof(buf), "rgb(%.3f%% %.3f%% %.3f%%)", r_pct, g_pct, b_pct)
#define FORMAT_RGB_PERCENT_ALPHA(buf, r_pct, g_pct, b_pct, alpha) \
    snprintf(buf, sizeof(buf), "rgb(%.3f%% %.3f%% %.3f%% / %.10g)", r_pct, g_pct, b_pct, alpha)
#define FORMAT_LAB(buf, l, a, b) \
    snprintf(buf, sizeof(buf), "lab(%.4f%% %.4f %.4f)", l, a, b)
#define FORMAT_LAB_ALPHA(buf, l, a, b, alpha) \
    snprintf(buf, sizeof(buf), "lab(%.4f%% %.4f %.4f / %.10g)", l, a, b, alpha)
#define FORMAT_LCH(buf, l, c, h) \
    snprintf(buf, sizeof(buf), "lch(%.4f%% %.4f %.3f)", l, c, h)
#define FORMAT_LCH_ALPHA(buf, l, c, h, alpha) \
    snprintf(buf, sizeof(buf), "lch(%.4f%% %.4f %.3f / %.10g)", l, c, h, alpha)

#endif // COLOR_CONVERSION_H
