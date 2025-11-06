// color_conversion_lab.c - CIE L*a*b* and LCH color space conversions
//
// Implementation of CIE 1976 (L*, a*, b*) and LCH color space conversions.
//
// ABOUT LAB:
// CIE L*a*b* (CIELAB) is a color space designed to be perceptually uniform,
// meaning that a change of the same amount in a color value should produce
// a change of about the same visual importance. Key properties:
// - Device-independent (unlike RGB which depends on display characteristics)
// - L* represents lightness (0 = black, 100 = white)
// - a* represents green-red axis (negative = green, positive = red)
// - b* represents blue-yellow axis (negative = blue, positive = yellow)
// - Covers entire range of human color perception
//
// ABOUT LCH:
// CIE LCH (cylindrical Lab) uses polar coordinates for the same color space:
// - L (lightness) is identical to Lab
// - C (chroma) = sqrt(a² + b²), represents "amount of color"
// - H (hue) = atan2(b, a), hue angle in degrees
// LCH is often more intuitive than Lab for color manipulation.
//
// COLOR CONVERSION PIPELINE:
// Parse:  lab(L a b) → XYZ → linear RGB → sRGB (0-255) → struct color_ir
//         lch(L C H) → Lab → XYZ → linear RGB → sRGB (0-255) → struct color_ir
// Format: struct color_ir → sRGB (0-255) → linear RGB → XYZ → lab(L a b)
//         struct color_ir → sRGB (0-255) → linear RGB → XYZ → Lab → lch(L C H)
//
// REFERENCES:
// - CSS Color Module Level 4: https://www.w3.org/TR/css-color-4/#lab-colors
// - CIE 1976 L*a*b*: https://en.wikipedia.org/wiki/CIELAB_color_space
// - Bruce Lindbloom: http://www.brucelindbloom.com/

#include "color_conversion.h"
#include <math.h>
#include <stdlib.h>
#include <ctype.h>

// Forward declarations for internal helpers
static void srgb_to_linear_rgb(int r, int g, int b, double *lr, double *lg, double *lb);
static void linear_rgb_to_srgb(double lr, double lg, double lb, int *r, int *g, int *b);
static void linear_rgb_to_xyz_d65(double lr, double lg, double lb, double *x, double *y, double *z);
static void xyz_d65_to_linear_rgb(double x, double y, double z, double *lr, double *lg, double *lb);
static void xyz_d50_to_d65(double x50, double y50, double z50, double *x65, double *y65, double *z65);
static void xyz_d65_to_d50(double x65, double y65, double z65, double *x50, double *y50, double *z50);
static void xyz_to_lab(double x, double y, double z, double *L, double *a, double *b);
static void lab_to_xyz(double L, double a, double b, double *x, double *y, double *z);
static void lab_to_lch(double L, double a, double b, double *out_L, double *out_C, double *out_H);
static void lch_to_lab(double L, double C, double H, double *out_L, double *out_a, double *out_b);
static double parse_float(const char **p, double percent_max);

// =============================================================================
// GAMMA CORRECTION: sRGB ↔ Linear RGB
// =============================================================================

// sRGB gamma correction constants (IEC 61966-2-1:1999)
#define SRGB_GAMMA_THRESHOLD_INV 0.04045    // Inverse transform threshold
#define SRGB_GAMMA_THRESHOLD_FWD 0.0031308  // Forward transform threshold
#define SRGB_GAMMA_LINEAR_SLOPE 12.92       // Linear segment slope
#define SRGB_GAMMA_OFFSET 0.055             // Gamma function offset
#define SRGB_GAMMA_SCALE 1.055              // Gamma function scale (1 + offset)
#define SRGB_GAMMA_EXPONENT 2.4             // Gamma exponent

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
    if (lr < 0.0) lr = 0.0; if (lr > 1.0) lr = 1.0;
    if (lg < 0.0) lg = 0.0; if (lg > 1.0) lg = 1.0;
    if (lb < 0.0) lb = 0.0; if (lb > 1.0) lb = 1.0;

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
    if (*r < 0) *r = 0; if (*r > 255) *r = 255;
    if (*g < 0) *g = 0; if (*g > 255) *g = 255;
    if (*b < 0) *b = 0; if (*b > 255) *b = 255;
}

// =============================================================================
// LINEAR RGB ↔ XYZ CONVERSIONS
// =============================================================================

// Convert linear RGB to CIE XYZ (D65 illuminant, sRGB primaries)
// Matrix from http://www.brucelindbloom.com/index.html?Eqn_RGB_XYZ_Matrix.html
static void linear_rgb_to_xyz_d65(double lr, double lg, double lb, double *x, double *y, double *z) {
    // sRGB to XYZ-D65 transformation matrix (M = sRGB primaries × D65 white point)
    *x = lr * 0.4124564 + lg * 0.3575761 + lb * 0.1804375;  // X from R,G,B
    *y = lr * 0.2126729 + lg * 0.7151522 + lb * 0.0721750;  // Y from R,G,B (luminance)
    *z = lr * 0.0193339 + lg * 0.1191920 + lb * 0.9503041;  // Z from R,G,B
}

// Convert CIE XYZ to linear RGB (D65 illuminant, sRGB primaries)
// Matrix from http://www.brucelindbloom.com/index.html?Eqn_RGB_XYZ_Matrix.html
static void xyz_d65_to_linear_rgb(double x, double y, double z, double *lr, double *lg, double *lb) {
    // XYZ-D65 to sRGB transformation matrix (M^-1)
    *lr =  x *  3.2404542 + y * -1.5371385 + z * -0.4985314;  // R from X,Y,Z
    *lg =  x * -0.9692660 + y *  1.8760108 + z *  0.0415560;  // G from X,Y,Z
    *lb =  x *  0.0556434 + y * -0.2040259 + z *  1.0572252;  // B from X,Y,Z
}

// =============================================================================
// CHROMATIC ADAPTATION: D50 ↔ D65
// =============================================================================
// Lab uses D50, sRGB uses D65, so we need chromatic adaptation
// Bradford matrices from CSS Color Module Level 4 spec

// Convert XYZ D50 to XYZ D65
static void xyz_d50_to_d65(double x50, double y50, double z50, double *x65, double *y65, double *z65) {
    // Bradford chromatic adaptation matrix D50→D65
    *x65 = x50 *  0.9554734527042182    // M[0][0]
         + y50 * -0.023098536874261423  // M[0][1]
         + z50 *  0.0632593086610217;   // M[0][2]
    *y65 = x50 * -0.028369706963208136  // M[1][0]
         + y50 *  1.0099954580058226    // M[1][1]
         + z50 *  0.021041398966943008; // M[1][2]
    *z65 = x50 *  0.012314001688319899  // M[2][0]
         + y50 * -0.020507696433477912  // M[2][1]
         + z50 *  1.3303659366080753;   // M[2][2]
}

// Convert XYZ D65 to XYZ D50
static void xyz_d65_to_d50(double x65, double y65, double z65, double *x50, double *y50, double *z50) {
    // Bradford chromatic adaptation matrix D65→D50 (inverse of above)
    *x50 = x65 *  1.0479298208405488    // M^-1[0][0]
         + y65 *  0.022946793341019088  // M^-1[0][1]
         + z65 * -0.05019222954313557;  // M^-1[0][2]
    *y50 = x65 *  0.029627815688159344  // M^-1[1][0]
         + y65 *  0.990434484573249     // M^-1[1][1]
         + z65 * -0.01707382502938514;  // M^-1[1][2]
    *z50 = x65 * -0.009243058152591178  // M^-1[2][0]
         + y65 *  0.015055144896577895  // M^-1[2][1]
         + z65 *  0.7518742899580008;   // M^-1[2][2]
}

// =============================================================================
// XYZ ↔ LAB CONVERSIONS
// =============================================================================

// CIE Standard Illuminant D50 white point (used for Lab in CSS)
// From CSS Color Module Level 4 spec
#define XYZ_WHITE_X 0.96422
#define XYZ_WHITE_Y 1.00000
#define XYZ_WHITE_Z 0.82521

// CIE Lab constants from CSS Color Module Level 4
#define LAB_EPSILON (216.0 / 24389.0)  // 6^3 / 29^3
#define LAB_KAPPA (24389.0 / 27.0)     // 29^3 / 3^3

// LCH powerless hue threshold (per W3C CSS Color Module Level 4)
// When chroma is below this value, hue is considered "powerless" (missing)
#define LCH_CHROMA_EPSILON 0.0015

// Convert XYZ to CIE L*a*b* (CSS Color Module Level 4 algorithm)
static void xyz_to_lab(double x, double y, double z, double *L, double *a, double *b) {
    // Normalize by D65 white point
    double xn = x / XYZ_WHITE_X;
    double yn = y / XYZ_WHITE_Y;
    double zn = z / XYZ_WHITE_Z;

    // Apply f function to each component
    double fx = (xn > LAB_EPSILON) ? pow(xn, 1.0/3.0) : (LAB_KAPPA * xn + 16.0) / 116.0;
    double fy = (yn > LAB_EPSILON) ? pow(yn, 1.0/3.0) : (LAB_KAPPA * yn + 16.0) / 116.0;
    double fz = (zn > LAB_EPSILON) ? pow(zn, 1.0/3.0) : (LAB_KAPPA * zn + 16.0) / 116.0;

    *L = 116.0 * fy - 16.0;
    *a = 500.0 * (fx - fy);
    *b = 200.0 * (fy - fz);
}

// Convert CIE L*a*b* to XYZ (CSS Color Module Level 4 algorithm)
static void lab_to_xyz(double L, double a, double b, double *x, double *y, double *z) {
    double fy = (L + 16.0) / 116.0;
    double fx = a / 500.0 + fy;
    double fz = fy - b / 200.0;

    // Apply inverse f function
    double xn = (pow(fx, 3) > LAB_EPSILON) ? pow(fx, 3) : (116.0 * fx - 16.0) / LAB_KAPPA;
    double yn = (L > LAB_KAPPA * LAB_EPSILON) ? pow((L + 16.0) / 116.0, 3) : L / LAB_KAPPA;
    double zn = (pow(fz, 3) > LAB_EPSILON) ? pow(fz, 3) : (116.0 * fz - 16.0) / LAB_KAPPA;

    *x = xn * XYZ_WHITE_X;
    *y = yn * XYZ_WHITE_Y;
    *z = zn * XYZ_WHITE_Z;
}

// =============================================================================
// LAB ↔ LCH COORDINATE CONVERSION (Cartesian ↔ Polar)
// =============================================================================
//
// LCH is the cylindrical/polar representation of Lab, similar to how
// HSL relates to RGB. The conversion is straightforward:
//
// Lab → LCH (Cartesian to Polar):
//   L (lightness) stays the same
//   C (chroma) = sqrt(a² + b²)
//   H (hue) = atan2(b, a) converted to degrees
//
// LCH → Lab (Polar to Cartesian):
//   L (lightness) stays the same
//   a = C * cos(H)
//   b = C * sin(H)
//
// W3C Spec: https://www.w3.org/TR/css-color-4/#lch-to-lab
// - L: 0% = 0.0, 100% = 100.0 (same as Lab)
// - C: 0% = 0, 100% = 150 (chroma), negative values clamped to 0
// - H: hue angle in degrees (0-360)
//   - 0° = purplish red (positive a axis)
//   - 90° = mustard yellow (positive b axis)
//   - 180° = greenish cyan (negative a axis)
//   - 270° = sky blue (negative b axis)
// - Powerless hue: when C <= 0.0015, hue is powerless

// Convert Lab (L, a, b) to LCH (L, C, H)
static void lab_to_lch(double L, double a, double b, double *out_L, double *out_C, double *out_H) {
    *out_L = L;
    *out_C = sqrt(a * a + b * b);

    // Calculate hue angle in degrees
    // atan2 returns radians in range [-π, π]
    double h_rad = atan2(b, a);
    *out_H = h_rad * 180.0 / M_PI;  // Convert to degrees

    // Normalize to [0, 360) range
    if (*out_H < 0.0) {
        *out_H += 360.0;
    }

    // Per W3C spec: if chroma is very small (near zero), hue is powerless
    // and should be treated as missing/0
    if (*out_C <= LCH_CHROMA_EPSILON) {
        *out_H = 0.0;  // Powerless hue
    }
}

// Convert LCH (L, C, H) to Lab (L, a, b)
static void lch_to_lab(double L, double C, double H, double *out_L, double *out_a, double *out_b) {
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

// =============================================================================
// PARSING HELPERS
// =============================================================================

// Parse a floating point number with optional percentage
// Returns the value, or raises error on invalid syntax
// If percentage is found, value is scaled by percent_max
// e.g., "50%" with percent_max=100.0 returns 50.0
static double parse_float(const char **p, double percent_max) {
    char *end;
    double value = strtod(*p, &end);

    if (end == *p) {
        rb_raise(rb_eArgError, "Expected number in color value");
    }

    *p = end;
    SKIP_WHITESPACE(*p);

    // Check for percentage
    if (**p == '%') {
        value = (value / 100.0) * percent_max;
        (*p)++;
        SKIP_WHITESPACE(*p);
    }

    return value;
}

// =============================================================================
// PUBLIC API: Parse and Format Lab
// =============================================================================

// Parse lab() CSS function to intermediate representation
// Format: lab(L a b) or lab(L a b / alpha)
// L: 0-100 or 0%-100% (lightness)
// a, b: typically -125 to 125 (but unbounded)
// alpha: 0-1 or 0%-100%
struct color_ir parse_lab(VALUE lab_value) {
    struct color_ir color;
    INIT_COLOR_IR(color);

    const char *str = StringValueCStr(lab_value);
    const char *p = str;

    // Skip "lab("
    if (strncmp(p, "lab(", 4) != 0) {
        rb_raise(rb_eArgError, "Invalid lab() syntax: must start with 'lab('");
    }
    p += 4;
    SKIP_WHITESPACE(p);

    // Parse L (lightness): 0-100 or 0%-100%
    double L = parse_float(&p, 100.0);

    // Clamp L to [0, 100] per spec
    if (L < 0.0) L = 0.0;
    if (L > 100.0) L = 100.0;

    SKIP_SEPARATOR(p);

    // Parse a (green-red axis)
    // a is typically -125 to 125, but can be percentage relative to -125/125
    double a = parse_float(&p, 125.0);

    SKIP_SEPARATOR(p);

    // Parse b (blue-yellow axis)
    // b is typically -125 to 125, but can be percentage relative to -125/125
    double b = parse_float(&p, 125.0);

    SKIP_WHITESPACE(p);

    // Check for optional alpha
    if (*p == '/') {
        p++;
        SKIP_WHITESPACE(p);
        color.alpha = parse_float(&p, 1.0);

        // Clamp alpha to [0, 1]
        if (color.alpha < 0.0) color.alpha = 0.0;
        if (color.alpha > 1.0) color.alpha = 1.0;

        SKIP_WHITESPACE(p);
    }

    // Expect closing paren
    if (*p != ')') {
        rb_raise(rb_eArgError, "Invalid lab() syntax: expected closing ')'");
    }

    // Convert Lab → XYZ D50 → XYZ D65 → linear RGB → sRGB
    double x_d50, y_d50, z_d50;
    lab_to_xyz(L, a, b, &x_d50, &y_d50, &z_d50);

    // Chromatic adaptation D50 → D65
    double x_d65, y_d65, z_d65;
    xyz_d50_to_d65(x_d50, y_d50, z_d50, &x_d65, &y_d65, &z_d65);

    double lr, lg, lb;
    xyz_d65_to_linear_rgb(x_d65, y_d65, z_d65, &lr, &lg, &lb);

    linear_rgb_to_srgb(lr, lg, lb, &color.red, &color.green, &color.blue);

    // Store linear RGB for high precision
    color.has_linear_rgb = 1;
    color.linear_r = lr;
    color.linear_g = lg;
    color.linear_b = lb;

    RB_GC_GUARD(lab_value);
    return color;
}

// Format intermediate representation to lab() CSS function
// Returns Ruby string like "lab(L a b)" or "lab(L a b / alpha)"
VALUE format_lab(struct color_ir color, int use_modern_syntax) {
    (void)use_modern_syntax;  // Lab only has one syntax

    double lr, lg, lb;

    // Use high-precision linear RGB if available, otherwise convert from sRGB
    if (color.has_linear_rgb) {
        lr = color.linear_r;
        lg = color.linear_g;
        lb = color.linear_b;
    } else {
        srgb_to_linear_rgb(color.red, color.green, color.blue, &lr, &lg, &lb);
    }

    // Convert linear RGB → XYZ D65 → XYZ D50 → Lab
    double x_d65, y_d65, z_d65;
    linear_rgb_to_xyz_d65(lr, lg, lb, &x_d65, &y_d65, &z_d65);

    // Chromatic adaptation D65 → D50
    double x_d50, y_d50, z_d50;
    xyz_d65_to_d50(x_d65, y_d65, z_d65, &x_d50, &y_d50, &z_d50);

    double L, a, b;
    xyz_to_lab(x_d50, y_d50, z_d50, &L, &a, &b);

    char buf[128];
    if (color.alpha >= 0.0) {
        FORMAT_LAB_ALPHA(buf, L, a, b, color.alpha);
    } else {
        FORMAT_LAB(buf, L, a, b);
    }

    return rb_str_new_cstr(buf);
}

// =============================================================================
// PUBLIC API: Parse and Format LCH
// =============================================================================

// Parse lch() CSS function to intermediate representation
// Format: lch(L C H) or lch(L C H / alpha)
// L: 0-100 or 0%-100% (lightness)
// C: 0-150 or 0%-100% (chroma, where 100% = 150)
// H: hue angle in degrees (0-360, wraps)
// alpha: 0-1 or 0%-100%
struct color_ir parse_lch(VALUE lch_value) {
    struct color_ir color;
    INIT_COLOR_IR(color);

    const char *str = StringValueCStr(lch_value);
    const char *p = str;

    // Skip "lch("
    if (strncmp(p, "lch(", 4) != 0) {
        rb_raise(rb_eArgError, "Invalid lch() syntax: must start with 'lch('");
    }
    p += 4;
    SKIP_WHITESPACE(p);

    // Parse L (lightness): 0-100 or 0%-100%
    double L = parse_float(&p, 100.0);

    // Clamp L to [0, 100] per spec
    if (L < 0.0) L = 0.0;
    if (L > 100.0) L = 100.0;

    SKIP_SEPARATOR(p);

    // Parse C (chroma): 0-150 or 0%-100% (where 100% = 150)
    double C = parse_float(&p, 150.0);

    // Clamp negative chroma to 0 per spec
    if (C < 0.0) C = 0.0;

    SKIP_SEPARATOR(p);

    // Parse H (hue): degrees, can be any value (wraps around)
    double H = parse_float(&p, 1.0);  // Hue is not a percentage typically

    // Normalize hue to [0, 360) range
    H = fmod(H, 360.0);
    if (H < 0.0) {
        H += 360.0;
    }

    SKIP_WHITESPACE(p);

    // Check for optional alpha
    if (*p == '/') {
        p++;
        SKIP_WHITESPACE(p);
        color.alpha = parse_float(&p, 1.0);

        // Clamp alpha to [0, 1]
        if (color.alpha < 0.0) color.alpha = 0.0;
        if (color.alpha > 1.0) color.alpha = 1.0;

        SKIP_WHITESPACE(p);
    }

    // Expect closing paren
    if (*p != ')') {
        rb_raise(rb_eArgError, "Invalid lch() syntax: expected closing ')'");
    }

    // Convert LCH → Lab → XYZ D50 → XYZ D65 → linear RGB → sRGB
    double lab_L, lab_a, lab_b;
    lch_to_lab(L, C, H, &lab_L, &lab_a, &lab_b);

    double x_d50, y_d50, z_d50;
    lab_to_xyz(lab_L, lab_a, lab_b, &x_d50, &y_d50, &z_d50);

    // Chromatic adaptation D50 → D65
    double x_d65, y_d65, z_d65;
    xyz_d50_to_d65(x_d50, y_d50, z_d50, &x_d65, &y_d65, &z_d65);

    double lr, lg, lb;
    xyz_d65_to_linear_rgb(x_d65, y_d65, z_d65, &lr, &lg, &lb);

    linear_rgb_to_srgb(lr, lg, lb, &color.red, &color.green, &color.blue);

    // Store linear RGB for high precision
    color.has_linear_rgb = 1;
    color.linear_r = lr;
    color.linear_g = lg;
    color.linear_b = lb;

    RB_GC_GUARD(lch_value);
    return color;
}

// Format intermediate representation to lch() CSS function
// Returns Ruby string like "lch(L C H)" or "lch(L C H / alpha)"
VALUE format_lch(struct color_ir color, int use_modern_syntax) {
    (void)use_modern_syntax;  // LCH only has one syntax

    double lr, lg, lb;

    // Use high-precision linear RGB if available, otherwise convert from sRGB
    if (color.has_linear_rgb) {
        lr = color.linear_r;
        lg = color.linear_g;
        lb = color.linear_b;
    } else {
        srgb_to_linear_rgb(color.red, color.green, color.blue, &lr, &lg, &lb);
    }

    // Convert linear RGB → XYZ D65 → XYZ D50 → Lab → LCH
    double x_d65, y_d65, z_d65;
    linear_rgb_to_xyz_d65(lr, lg, lb, &x_d65, &y_d65, &z_d65);

    // Chromatic adaptation D65 → D50
    double x_d50, y_d50, z_d50;
    xyz_d65_to_d50(x_d65, y_d65, z_d65, &x_d50, &y_d50, &z_d50);

    double lab_L, lab_a, lab_b;
    xyz_to_lab(x_d50, y_d50, z_d50, &lab_L, &lab_a, &lab_b);

    // Convert Lab to LCH
    double L, C, H;
    lab_to_lch(lab_L, lab_a, lab_b, &L, &C, &H);

    char buf[128];
    if (color.alpha >= 0.0) {
        FORMAT_LCH_ALPHA(buf, L, C, H, color.alpha);
    } else {
        FORMAT_LCH(buf, L, C, H);
    }

    return rb_str_new_cstr(buf);
}
