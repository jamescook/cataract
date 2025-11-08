// color_conversion_oklab.c - Oklab color space conversions
//
// Implementation of Oklab color space conversions based on Björn Ottosson's work:
// https://bottosson.github.io/posts/oklab/
//
// ABOUT OKLAB:
// Oklab is a perceptually uniform color space designed for image processing.
// It predicts lightness (L), green-red axis (a), and blue-yellow axis (b) with
// better accuracy than existing alternatives like CIELAB. Key properties:
// - Perceptually uniform: equal distances in Oklab correspond to equal perceived differences
// - Better for color interpolation than HSL or RGB
// - Scale-invariant: changing exposure scales all coordinates proportionally
// - Improved hue prediction versus CIELAB or CIELUV
// - Simpler computation than CAM16-UCS while maintaining uniformity
//
// LICENSE NOTE:
// The reference C++ implementation from Björn Ottosson is provided under public domain
// with optional MIT licensing. This implementation is derived from that reference code.
//
// COLOR CONVERSION PIPELINE:
// Parse:  oklab(L a b) → linear RGB → sRGB (0-255) → struct color_ir
// Format: struct color_ir → sRGB (0-255) → linear RGB → oklab(L a b)
//
// REFERENCES:
// - Main Oklab post: https://bottosson.github.io/posts/oklab/
// - Color processing context: https://bottosson.github.io/posts/colorwrong/
// - CSS Color Module Level 4: https://www.w3.org/TR/css-color-4/#ok-lab

#include "color_conversion.h"
#include <math.h>
#include <stdlib.h>
#include <ctype.h>

// Forward declarations for internal helpers
static void srgb_to_linear_rgb(int r, int g, int b, double *lr, double *lg, double *lb);
static void linear_rgb_to_srgb(double lr, double lg, double lb, int *r, int *g, int *b);
static void linear_rgb_to_oklab(double lr, double lg, double lb, double *L, double *a, double *b);
static void oklab_to_linear_rgb(double L, double a, double b, double *lr, double *lg, double *lb);
static void oklab_to_oklch(double L, double a, double b, double *out_L, double *out_C, double *out_H);
static void oklch_to_oklab(double L, double C, double H, double *out_L, double *out_a, double *out_b);
static double parse_float(const char **p, double percent_max);

// =============================================================================
// CONSTANTS
// =============================================================================

// sRGB gamma correction constants (IEC 61966-2-1:1999)
// These values appear multiple times in gamma correction functions
#define SRGB_GAMMA_THRESHOLD_INV 0.04045    // Inverse transform threshold
#define SRGB_GAMMA_THRESHOLD_FWD 0.0031308  // Forward transform threshold
#define SRGB_GAMMA_LINEAR_SLOPE 12.92       // Linear segment slope
#define SRGB_GAMMA_OFFSET 0.055             // Gamma function offset
#define SRGB_GAMMA_SCALE 1.055              // Gamma function scale (1 + offset)
#define SRGB_GAMMA_EXPONENT 2.4             // Gamma exponent

// OKLCh powerless hue threshold (per W3C CSS Color Module Level 4)
// When chroma is below this value, hue is considered "powerless" (missing)
#define OKLCH_CHROMA_EPSILON 0.000004

// =============================================================================
// GAMMA CORRECTION: sRGB ↔ Linear RGB
// =============================================================================
//
// From https://bottosson.github.io/posts/colorwrong/:
// "The sRGB standard defines a nonlinear transfer function that relates the
// numerical values in the image to the actual light intensity."
//
// The sRGB transfer function applies gamma correction (γ ≈ 2.2) to compress
// the dynamic range for better perceptual distribution in 8-bit storage.
// We must undo this before color space conversions.

// Convert sRGB (0-255) to linear RGB (0.0-1.0)
// Applies inverse gamma: removes the sRGB nonlinearity
static void srgb_to_linear_rgb(int r, int g, int b, double *lr, double *lg, double *lb) {
    double rs = r / 255.0;
    double gs = g / 255.0;
    double bs = b / 255.0;

    // sRGB inverse transfer function (IEC 61966-2-1:1999)
    *lr = (rs <= SRGB_GAMMA_THRESHOLD_INV) ? rs / SRGB_GAMMA_LINEAR_SLOPE
                                           : pow((rs + SRGB_GAMMA_OFFSET) / SRGB_GAMMA_SCALE, SRGB_GAMMA_EXPONENT);
    *lg = (gs <= SRGB_GAMMA_THRESHOLD_INV) ? gs / SRGB_GAMMA_LINEAR_SLOPE
                                           : pow((gs + SRGB_GAMMA_OFFSET) / SRGB_GAMMA_SCALE, SRGB_GAMMA_EXPONENT);
    *lb = (bs <= SRGB_GAMMA_THRESHOLD_INV) ? bs / SRGB_GAMMA_LINEAR_SLOPE
                                           : pow((bs + SRGB_GAMMA_OFFSET) / SRGB_GAMMA_SCALE, SRGB_GAMMA_EXPONENT);
}

// Convert linear RGB (0.0-1.0) to sRGB (0-255)
// Applies gamma: adds the sRGB nonlinearity
static void linear_rgb_to_srgb(double lr, double lg, double lb, int *r, int *g, int *b) {
    // Clamp to valid range [0.0, 1.0]
    if (lr < 0.0) lr = 0.0;
    if (lr > 1.0) lr = 1.0;
    if (lg < 0.0) lg = 0.0;
    if (lg > 1.0) lg = 1.0;
    if (lb < 0.0) lb = 0.0;
    if (lb > 1.0) lb = 1.0;

    // sRGB forward transfer function (IEC 61966-2-1:1999)
    double rs = (lr <= SRGB_GAMMA_THRESHOLD_FWD) ? lr * SRGB_GAMMA_LINEAR_SLOPE
                                                  : SRGB_GAMMA_SCALE * pow(lr, 1.0/SRGB_GAMMA_EXPONENT) - SRGB_GAMMA_OFFSET;
    double gs = (lg <= SRGB_GAMMA_THRESHOLD_FWD) ? lg * SRGB_GAMMA_LINEAR_SLOPE
                                                  : SRGB_GAMMA_SCALE * pow(lg, 1.0/SRGB_GAMMA_EXPONENT) - SRGB_GAMMA_OFFSET;
    double bs = (lb <= SRGB_GAMMA_THRESHOLD_FWD) ? lb * SRGB_GAMMA_LINEAR_SLOPE
                                                  : SRGB_GAMMA_SCALE * pow(lb, 1.0/SRGB_GAMMA_EXPONENT) - SRGB_GAMMA_OFFSET;

    // Convert to 0-255 range and round
    *r = (int)(rs * 255.0 + 0.5);
    *g = (int)(gs * 255.0 + 0.5);
    *b = (int)(bs * 255.0 + 0.5);

    // Clamp to valid byte range
    if (*r < 0) *r = 0;
    if (*r > 255) *r = 255;
    if (*g < 0) *g = 0;
    if (*g > 255) *g = 255;
    if (*b < 0) *b = 0;
    if (*b > 255) *b = 255;
}

// =============================================================================
// OKLAB CONVERSIONS: Linear RGB ↔ Oklab
// =============================================================================
//
// From https://bottosson.github.io/posts/oklab/:
// "Oklab is a perceptual color space that uses a cube root transfer function
// and optimized transformation matrices to achieve perceptual uniformity."
//
// ALGORITHM (Linear RGB → Oklab):
// 1. Convert linear RGB to LMS cone response using matrix M₁
// 2. Apply cube root nonlinearity: l' = ∛l, m' = ∛m, s' = ∛s
// 3. Transform to Lab coordinates using matrix M₂
//
// The matrices below are the optimized versions from the reference implementation
// (public domain / MIT licensed) at https://bottosson.github.io/posts/oklab/

// Convert linear RGB to Oklab
// Inputs: lr, lg, lb in range [0.0, 1.0]
// Outputs: L (lightness), a (green-red), b (blue-yellow)
static void linear_rgb_to_oklab(double lr, double lg, double lb, double *L, double *a, double *b) {
    // Step 1: Linear RGB → LMS cone response (matrix M₁)
    // Matrix coefficients from https://bottosson.github.io/posts/oklab/
    // Transforms sRGB to LMS cone response (approximating human vision)
    double l = lr * 0.4122214708   // M₁[0][0]
             + lg * 0.5363325363   // M₁[0][1]
             + lb * 0.0514459929;  // M₁[0][2]
    double m = lr * 0.2119034982   // M₁[1][0]
             + lg * 0.6806995451   // M₁[1][1]
             + lb * 0.1073969566;  // M₁[1][2]
    double s = lr * 0.0883024619   // M₁[2][0]
             + lg * 0.2817188376   // M₁[2][1]
             + lb * 0.6299787005;  // M₁[2][2]

    // Step 2: Apply cube root nonlinearity
    // From the post: "The cube root is applied to make the space more perceptually uniform"
    // Using cbrt() for better numerical accuracy than pow(x, 1.0/3.0)
    double l_ = cbrt(l);
    double m_ = cbrt(m);
    double s_ = cbrt(s);

    // Step 3: Transform to Lab coordinates (matrix M₂)
    // Matrix coefficients from https://bottosson.github.io/posts/oklab/
    // Final transformation to perceptually uniform Oklab coordinates
    *L = l_ *  0.2104542553   // M₂[0][0]
       + m_ *  0.7936177850   // M₂[0][1]
       + s_ * -0.0040720468;  // M₂[0][2]
    *a = l_ *  1.9779984951   // M₂[1][0]
       + m_ * -2.4285922050   // M₂[1][1]
       + s_ *  0.4505937099;  // M₂[1][2]
    *b = l_ *  0.0259040371   // M₂[2][0]
       + m_ *  0.7827717662   // M₂[2][1]
       + s_ * -0.8086757660;  // M₂[2][2]
}

// Convert Oklab to linear RGB (inverse of above)
// Inputs: L, a, b (Oklab coordinates)
// Outputs: lr, lg, lb in range [0.0, 1.0] (may exceed range, caller should clamp)
static void oklab_to_linear_rgb(double L, double a, double b, double *lr, double *lg, double *lb) {
    // Step 1: Invert M₂ to get l', m', s' from Lab
    // Inverse M₂ matrix coefficients from https://bottosson.github.io/posts/oklab/
    double l_ = L + a *  0.3963377774   // M₂⁻¹[0][1]
                  + b *  0.2158037573;  // M₂⁻¹[0][2]
    double m_ = L + a * -0.1055613458   // M₂⁻¹[1][1]
                  + b * -0.0638541728;  // M₂⁻¹[1][2]
    double s_ = L + a * -0.0894841775   // M₂⁻¹[2][1]
                  + b * -1.2914855480;  // M₂⁻¹[2][2]

    // Step 2: Invert cube root (cube the values)
    double l = l_ * l_ * l_;
    double m = m_ * m_ * m_;
    double s = s_ * s_ * s_;

    // Step 3: Invert M₁ to get linear RGB from LMS
    // Inverse M₁ matrix coefficients from https://bottosson.github.io/posts/oklab/
    *lr = l *  4.0767416621   // M₁⁻¹[0][0]
        + m * -3.3077115913   // M₁⁻¹[0][1]
        + s *  0.2309699292;  // M₁⁻¹[0][2]
    *lg = l * -1.2684380046   // M₁⁻¹[1][0]
        + m *  2.6097574011   // M₁⁻¹[1][1]
        + s * -0.3413193965;  // M₁⁻¹[1][2]
    *lb = l * -0.0041960863   // M₁⁻¹[2][0]
        + m * -0.7034186147   // M₁⁻¹[2][1]
        + s *  1.7076147010;  // M₁⁻¹[2][2]
}

// =============================================================================
// PARSING: oklab() CSS syntax → struct color_ir
// =============================================================================

// Parse a floating-point number from CSS (with optional percentage)
// Supports: integers, decimals, negative values, percentages
// percent_max: value that 100% maps to (1.0 for standard, 0.4 for chroma)
static double parse_float(const char **p, double percent_max) {
    int sign = 1;
    if (**p == '-') {
        sign = -1;
        (*p)++;
    } else if (**p == '+') {
        (*p)++;
    }

    double result = 0.0;

    // Parse integer part
    while (**p >= '0' && **p <= '9') {
        result = result * 10.0 + (**p - '0');
        (*p)++;
    }

    // Parse decimal part
    if (**p == '.') {
        (*p)++;
        double fraction = 0.1;
        while (**p >= '0' && **p <= '9') {
            result += (**p - '0') * fraction;
            fraction *= 0.1;
            (*p)++;
        }
    }

    // Check for percentage sign
    if (**p == '%') {
        (*p)++;
        result = (result / 100.0) * percent_max;
    }

    return sign * result;
}

// =============================================================================
// OKLCH COORDINATE CONVERSION: Oklab (Cartesian) ↔ OKLCh (Cylindrical/Polar)
// =============================================================================
//
// OKLCh is the cylindrical/polar representation of Oklab, similar to how
// HSL relates to RGB. The conversion is straightforward:
//
// Oklab → OKLCh (Cartesian to Polar):
//   L (lightness) stays the same
//   C (chroma) = sqrt(a² + b²)
//   H (hue) = atan2(b, a) converted to degrees
//
// OKLCh → Oklab (Polar to Cartesian):
//   L (lightness) stays the same
//   a = C * cos(H)
//   b = C * sin(H)
//
// W3C Spec: https://www.w3.org/TR/css-color-4/#the-oklch-notation
// - L: 0% = 0.0, 100% = 1.0 (same as Oklab)
// - C: 0% = 0.0, 100% = 0.4 (chroma)
// - H: hue angle in degrees (0-360)
//   - 0° = purplish red (positive a axis)
//   - 90° = mustard yellow (positive b axis)
//   - 180° = greenish cyan (negative a axis)
//   - 270° = sky blue (negative b axis)
// - Powerless hue: when C ≤ 0.000004 (epsilon), hue is powerless

// Convert Oklab (L, a, b) to OKLCh (L, C, H)
static void oklab_to_oklch(double L, double a, double b, double *out_L, double *out_C, double *out_H) {
    *out_L = L;
    *out_C = sqrt(a * a + b * b);

    // Calculate hue angle in degrees
    // atan2 returns radians in range [-π, π]
    double h_rad = atan2(b, a);
    *out_H = h_rad * 180.0 / M_PI;

    // Normalize to [0, 360) range
    if (*out_H < 0.0) {
        *out_H += 360.0;
    }

    // Per W3C spec: if chroma is very small (near zero), hue is powerless
    // and should be treated as missing/0
    if (*out_C <= OKLCH_CHROMA_EPSILON) {
        *out_H = 0.0;  // Powerless hue
    }
}

// Convert OKLCh (L, C, H) to Oklab (L, a, b)
static void oklch_to_oklab(double L, double C, double H, double *out_L, double *out_a, double *out_b) {
    *out_L = L;

    // Clamp negative chroma to 0 (per W3C spec)
    if (C < 0.0) {
        C = 0.0;
    }

    // Convert hue angle from degrees to radians
    double h_rad = H * M_PI / 180.0;

    // Convert polar to Cartesian
    *out_a = C * cos(h_rad);
    *out_b = C * sin(h_rad);
}

// Parse oklab() CSS function into IR (sRGB 0-255)
// Syntax: oklab(L a b) or oklab(L a b / alpha)
// Example: oklab(0.628 0.225 0.126) or oklab(0.5 -0.1 0.2 / 0.8)
struct color_ir parse_oklab(VALUE oklab_value) {
    struct color_ir color;
    INIT_COLOR_IR(color);

    const char *str = StringValueCStr(oklab_value);
    const char *p = str;

    // Skip "oklab("
    while (*p && *p != '(') p++;
    if (*p != '(') {
        rb_raise(rb_eArgError, "Invalid oklab() syntax");
    }
    p++; // Skip '('

    SKIP_WHITESPACE(p);

    // Parse L (lightness): typically 0.0 to 1.0
    double L = parse_float(&p, 1.0);
    SKIP_WHITESPACE(p);

    // Parse a (green-red axis): typically -0.4 to 0.4
    double a = parse_float(&p, 1.0);
    SKIP_WHITESPACE(p);

    // Parse b (blue-yellow axis): typically -0.4 to 0.4
    double b = parse_float(&p, 1.0);
    SKIP_WHITESPACE(p);

    // Check for alpha: oklab(L a b / alpha)
    if (*p == '/') {
        p++;
        SKIP_WHITESPACE(p);
        color.alpha = parse_float(&p, 1.0);
        SKIP_WHITESPACE(p);
    }

    // Verify closing parenthesis
    if (*p != ')') {
        rb_raise(rb_eArgError, "Invalid oklab() syntax: missing closing parenthesis");
    }

    // Convert Oklab → linear RGB
    double lr, lg, lb;
    oklab_to_linear_rgb(L, a, b, &lr, &lg, &lb);

    // Store high-precision linear RGB in IR (avoids quantization loss)
    color.has_linear_rgb = 1;
    color.linear_r = lr;
    color.linear_g = lg;
    color.linear_b = lb;

    // Also populate sRGB (0-255) for compatibility with other formatters
    linear_rgb_to_srgb(lr, lg, lb, &color.red, &color.green, &color.blue);

    return color;
}

// =============================================================================
// FORMATTING: struct color_ir → oklab() CSS syntax
// =============================================================================

// Format IR as oklab() CSS function
// Syntax: oklab(L a b) or oklab(L a b / alpha)
// Prefers high-precision linear RGB if available to avoid quantization errors
VALUE format_oklab(struct color_ir color, int use_modern_syntax) {
    double lr, lg, lb;

    // Prefer linear RGB for precision if available
    // Otherwise fall back to sRGB → linear RGB conversion
    if (color.has_linear_rgb) {
        // Use high-precision linear RGB directly (avoids sRGB quantization)
        lr = color.linear_r;
        lg = color.linear_g;
        lb = color.linear_b;
    } else {
        // Convert sRGB (0-255) → linear RGB
        srgb_to_linear_rgb(color.red, color.green, color.blue, &lr, &lg, &lb);
    }

    // Convert linear RGB → Oklab
    double L, a, b;
    linear_rgb_to_oklab(lr, lg, lb, &L, &a, &b);

    char buf[128];

    if (color.alpha >= 0.0) {
        // With alpha: oklab(L a b / alpha)
        FORMAT_OKLAB_ALPHA(buf, L, a, b, color.alpha);
    } else {
        // No alpha: oklab(L a b)
        FORMAT_OKLAB(buf, L, a, b);
    }

    return rb_str_new_cstr(buf);
}

// =============================================================================
// OKLCH PARSING AND FORMATTING
// =============================================================================

// Parse oklch() CSS function into IR (sRGB 0-255)
// Syntax: oklch(L C H) or oklch(L C H / alpha)
// Example: oklch(51.975% 0.17686 142.495) or oklch(50% 0.2 270 / 0.8)
//
// Per W3C spec:
// - L: 0% = 0.0, 100% = 1.0
// - C: 0% = 0.0, 100% = 0.4 (chroma), negative values clamped to 0
// - H: hue angle in degrees, normalized to [0, 360)
// - Alpha: 0-1.0 or percentage
struct color_ir parse_oklch(VALUE oklch_value) {
    struct color_ir color;
    INIT_COLOR_IR(color);

    const char *str = StringValueCStr(oklch_value);
    const char *p = str;

    // Skip whitespace
    while (*p == ' ' || *p == '\t') p++;

    // Expect "oklch("
    if (!(p[0] == 'o' && p[1] == 'k' && p[2] == 'l' && p[3] == 'c' && p[4] == 'h' && p[5] == '(')) {
        rb_raise(rb_eArgError, "Invalid oklch() syntax: expected 'oklch(', got '%s'", str);
    }
    p += 6;

    // Skip whitespace
    while (*p == ' ' || *p == '\t') p++;

    // Parse L (lightness): 0-1.0 or percentage
    const char *before_L = p;
    double L = parse_float(&p, 1.0);
    if (p == before_L) {
        rb_raise(rb_eArgError, "Invalid oklch() syntax: missing lightness value in '%s'", str);
    }
    while (*p == ' ' || *p == '\t') p++;

    // Parse C (chroma): 0-0.4 or percentage (100% = 0.4)
    const char *before_C = p;
    double C = parse_float(&p, 0.4);
    if (p == before_C) {
        rb_raise(rb_eArgError, "Invalid oklch() syntax: missing chroma value in '%s'", str);
    }
    while (*p == ' ' || *p == '\t' || *p == ',') p++;

    // Parse H (hue): angle in degrees
    const char *before_H = p;
    double H = parse_float(&p, 1.0);
    if (p == before_H) {
        rb_raise(rb_eArgError, "Invalid oklch() syntax: missing hue value in '%s'", str);
    }
    // Normalize hue to [0, 360) range
    H = fmod(H, 360.0);
    if (H < 0.0) {
        H += 360.0;
    }

    // Skip whitespace
    while (*p == ' ' || *p == '\t') p++;

    // Check for alpha channel (slash separator)
    if (*p == '/') {
        p++;
        while (*p == ' ' || *p == '\t') p++;
        color.alpha = parse_float(&p, 1.0);
        while (*p == ' ' || *p == '\t') p++;
    }

    // Expect closing paren
    if (*p != ')') {
        rb_raise(rb_eArgError, "Invalid oklch() syntax: missing closing parenthesis in '%s'", str);
    }

    // Convert OKLCh → Oklab
    double oklab_L, oklab_a, oklab_b;
    oklch_to_oklab(L, C, H, &oklab_L, &oklab_a, &oklab_b);

    // Convert Oklab → linear RGB → sRGB
    double lr, lg, lb;
    oklab_to_linear_rgb(oklab_L, oklab_a, oklab_b, &lr, &lg, &lb);
    linear_rgb_to_srgb(lr, lg, lb, &color.red, &color.green, &color.blue);

    // Store linear RGB for precision (in case we convert back to oklch/oklab later)
    color.has_linear_rgb = 1;
    color.linear_r = lr;
    color.linear_g = lg;
    color.linear_b = lb;

    RB_GC_GUARD(oklch_value);
    return color;
}

// Format IR (sRGB 0-255) as oklch() CSS function
// Returns: oklch(L C H) or oklch(L C H / alpha)
// use_modern_syntax parameter is ignored (oklch always uses modern syntax)
VALUE format_oklch(struct color_ir color, int use_modern_syntax) {
    (void)use_modern_syntax;  // Unused, oklch always uses modern syntax

    double lr, lg, lb;

    // Use high-precision linear RGB if available
    if (color.has_linear_rgb) {
        lr = color.linear_r;
        lg = color.linear_g;
        lb = color.linear_b;
    } else {
        // Convert sRGB (0-255) → linear RGB
        srgb_to_linear_rgb(color.red, color.green, color.blue, &lr, &lg, &lb);
    }

    // Convert linear RGB → Oklab
    double oklab_L, oklab_a, oklab_b;
    linear_rgb_to_oklab(lr, lg, lb, &oklab_L, &oklab_a, &oklab_b);

    // Convert Oklab → OKLCh
    double L, C, H;
    oklab_to_oklch(oklab_L, oklab_a, oklab_b, &L, &C, &H);

    char buf[128];

    if (color.alpha >= 0.0) {
        // With alpha: oklch(L C H / alpha)
        snprintf(buf, sizeof(buf), "oklch(%.4f %.4f %.3f / %.2f)", L, C, H, color.alpha);
    } else {
        // No alpha: oklch(L C H)
        snprintf(buf, sizeof(buf), "oklch(%.4f %.4f %.3f)", L, C, H);
    }

    return rb_str_new_cstr(buf);
}
