// color_conversion_named.c - CSS named color support
//
// Implements support for all 147 CSS named colors as defined in:
// https://www.w3.org/TR/css-color-4/#named-colors
//
// Named colors are case-insensitive and map directly to sRGB hex values.
// Examples: "red" -> #ff0000, "rebeccapurple" -> #663399
//
// This file uses a sorted array with binary search for O(log n) lookup.

#include "color_conversion.h"
#include <string.h>
#include <ctype.h>

// Named color entry: color name and its hex RGB value
struct named_color {
    const char *name;
    unsigned int hex;  // RGB as 0xRRGGBB
};

// All 147 CSS named colors, sorted alphabetically for binary search
// Source: https://www.w3.org/TR/css-color-4/#named-colors
static const struct named_color NAMED_COLORS[] = {
    {"aliceblue", 0xf0f8ff},
    {"antiquewhite", 0xfaebd7},
    {"aqua", 0x00ffff},
    {"aquamarine", 0x7fffd4},
    {"azure", 0xf0ffff},
    {"beige", 0xf5f5dc},
    {"bisque", 0xffe4c4},
    {"black", 0x000000},
    {"blanchedalmond", 0xffebcd},
    {"blue", 0x0000ff},
    {"blueviolet", 0x8a2be2},
    {"brown", 0xa52a2a},
    {"burlywood", 0xdeb887},
    {"cadetblue", 0x5f9ea0},
    {"chartreuse", 0x7fff00},
    {"chocolate", 0xd2691e},
    {"coral", 0xff7f50},
    {"cornflowerblue", 0x6495ed},
    {"cornsilk", 0xfff8dc},
    {"crimson", 0xdc143c},
    {"cyan", 0x00ffff},
    {"darkblue", 0x00008b},
    {"darkcyan", 0x008b8b},
    {"darkgoldenrod", 0xb8860b},
    {"darkgray", 0xa9a9a9},
    {"darkgreen", 0x006400},
    {"darkgrey", 0xa9a9a9},
    {"darkkhaki", 0xbdb76b},
    {"darkmagenta", 0x8b008b},
    {"darkolivegreen", 0x556b2f},
    {"darkorange", 0xff8c00},
    {"darkorchid", 0x9932cc},
    {"darkred", 0x8b0000},
    {"darksalmon", 0xe9967a},
    {"darkseagreen", 0x8fbc8f},
    {"darkslateblue", 0x483d8b},
    {"darkslategray", 0x2f4f4f},
    {"darkslategrey", 0x2f4f4f},
    {"darkturquoise", 0x00ced1},
    {"darkviolet", 0x9400d3},
    {"deeppink", 0xff1493},
    {"deepskyblue", 0x00bfff},
    {"dimgray", 0x696969},
    {"dimgrey", 0x696969},
    {"dodgerblue", 0x1e90ff},
    {"firebrick", 0xb22222},
    {"floralwhite", 0xfffaf0},
    {"forestgreen", 0x228b22},
    {"fuchsia", 0xff00ff},
    {"gainsboro", 0xdcdcdc},
    {"ghostwhite", 0xf8f8ff},
    {"gold", 0xffd700},
    {"goldenrod", 0xdaa520},
    {"gray", 0x808080},
    {"green", 0x008000},
    {"greenyellow", 0xadff2f},
    {"grey", 0x808080},
    {"honeydew", 0xf0fff0},
    {"hotpink", 0xff69b4},
    {"indianred", 0xcd5c5c},
    {"indigo", 0x4b0082},
    {"ivory", 0xfffff0},
    {"khaki", 0xf0e68c},
    {"lavender", 0xe6e6fa},
    {"lavenderblush", 0xfff0f5},
    {"lawngreen", 0x7cfc00},
    {"lemonchiffon", 0xfffacd},
    {"lightblue", 0xadd8e6},
    {"lightcoral", 0xf08080},
    {"lightcyan", 0xe0ffff},
    {"lightgoldenrodyellow", 0xfafad2},
    {"lightgray", 0xd3d3d3},
    {"lightgreen", 0x90ee90},
    {"lightgrey", 0xd3d3d3},
    {"lightpink", 0xffb6c1},
    {"lightsalmon", 0xffa07a},
    {"lightseagreen", 0x20b2aa},
    {"lightskyblue", 0x87cefa},
    {"lightslategray", 0x778899},
    {"lightslategrey", 0x778899},
    {"lightsteelblue", 0xb0c4de},
    {"lightyellow", 0xffffe0},
    {"lime", 0x00ff00},
    {"limegreen", 0x32cd32},
    {"linen", 0xfaf0e6},
    {"magenta", 0xff00ff},
    {"maroon", 0x800000},
    {"mediumaquamarine", 0x66cdaa},
    {"mediumblue", 0x0000cd},
    {"mediumorchid", 0xba55d3},
    {"mediumpurple", 0x9370db},
    {"mediumseagreen", 0x3cb371},
    {"mediumslateblue", 0x7b68ee},
    {"mediumspringgreen", 0x00fa9a},
    {"mediumturquoise", 0x48d1cc},
    {"mediumvioletred", 0xc71585},
    {"midnightblue", 0x191970},
    {"mintcream", 0xf5fffa},
    {"mistyrose", 0xffe4e1},
    {"moccasin", 0xffe4b5},
    {"navajowhite", 0xffdead},
    {"navy", 0x000080},
    {"oldlace", 0xfdf5e6},
    {"olive", 0x808000},
    {"olivedrab", 0x6b8e23},
    {"orange", 0xffa500},
    {"orangered", 0xff4500},
    {"orchid", 0xda70d6},
    {"palegoldenrod", 0xeee8aa},
    {"palegreen", 0x98fb98},
    {"paleturquoise", 0xafeeee},
    {"palevioletred", 0xdb7093},
    {"papayawhip", 0xffefd5},
    {"peachpuff", 0xffdab9},
    {"peru", 0xcd853f},
    {"pink", 0xffc0cb},
    {"plum", 0xdda0dd},
    {"powderblue", 0xb0e0e6},
    {"purple", 0x800080},
    {"rebeccapurple", 0x663399},
    {"red", 0xff0000},
    {"rosybrown", 0xbc8f8f},
    {"royalblue", 0x4169e1},
    {"saddlebrown", 0x8b4513},
    {"salmon", 0xfa8072},
    {"sandybrown", 0xf4a460},
    {"seagreen", 0x2e8b57},
    {"seashell", 0xfff5ee},
    {"sienna", 0xa0522d},
    {"silver", 0xc0c0c0},
    {"skyblue", 0x87ceeb},
    {"slateblue", 0x6a5acd},
    {"slategray", 0x708090},
    {"slategrey", 0x708090},
    {"snow", 0xfffafa},
    {"springgreen", 0x00ff7f},
    {"steelblue", 0x4682b4},
    {"tan", 0xd2b48c},
    {"teal", 0x008080},
    {"thistle", 0xd8bfd8},
    {"tomato", 0xff6347},
    {"turquoise", 0x40e0d0},
    {"violet", 0xee82ee},
    {"wheat", 0xf5deb3},
    {"white", 0xffffff},
    {"whitesmoke", 0xf5f5f5},
    {"yellow", 0xffff00},
    {"yellowgreen", 0x9acd32}
};

#define NUM_NAMED_COLORS (sizeof(NAMED_COLORS) / sizeof(NAMED_COLORS[0]))

// Case-insensitive string comparison for binary search
static int strcasecmp_limited(const char *a, const char *b, size_t max_len) {
    for (size_t i = 0; i < max_len; i++) {
        if (a[i] == '\0' && b[i] == '\0') return 0;
        if (a[i] == '\0') return -1;
        if (b[i] == '\0') return 1;

        int diff = tolower((unsigned char)a[i]) - tolower((unsigned char)b[i]);
        if (diff != 0) return diff;
    }
    return 0;
}

// Binary search for named color (case-insensitive)
// Returns hex value or -1 if not found
static int lookup_named_color(const char *name, size_t name_len) {
    int left = 0;
    int right = NUM_NAMED_COLORS - 1;

    DEBUG_PRINTF("lookup: searching for '%.*s' (len=%zu)\n", (int)name_len, name, name_len);

    while (left <= right) {
        int mid = left + (right - left) / 2;
        int cmp = strcasecmp_limited(name, NAMED_COLORS[mid].name, name_len);

        DEBUG_PRINTF("lookup: mid=%d, name='%s', cmp=%d\n", mid, NAMED_COLORS[mid].name, cmp);

        // Also need to check if the matched name is exactly the same length
        if (cmp == 0) {
            // Prefix matches, now check full length
            if (NAMED_COLORS[mid].name[name_len] == '\0') {
                // Exact match!
                DEBUG_PRINTF("lookup: FOUND at mid=%d\n", mid);
                return NAMED_COLORS[mid].hex;
            } else {
                // Prefix matches but array name is longer (e.g., "blue" vs "blueviolet")
                // We want the shorter name, so search left
                right = mid - 1;
            }
        } else if (cmp < 0) {
            right = mid - 1;
        } else {
            left = mid + 1;
        }
    }

    DEBUG_PRINTF("lookup: NOT FOUND\n");
    return -1;  // Not found
}

// Parse named color to IR (sRGB 0-255)
// Syntax: just the color name (e.g., "red", "rebeccapurple")
struct color_ir parse_named(VALUE named_value) {
    struct color_ir color;
    INIT_COLOR_IR(color);

    const char *name = StringValueCStr(named_value);
    size_t name_len = strlen(name);

    // Trim whitespace
    while (name_len > 0 && isspace((unsigned char)name[name_len - 1])) {
        name_len--;
    }
    while (name_len > 0 && isspace((unsigned char)*name)) {
        name++;
        name_len--;
    }

    // Special case: "transparent" is rgba(0,0,0,0) per CSS spec
    if (name_len == 11 && strncasecmp(name, "transparent", 11) == 0) {
        color.red = 0;
        color.green = 0;
        color.blue = 0;
        color.alpha = 0.0;  // Fully transparent
        return color;
    }

    // Look up the color
    int hex = lookup_named_color(name, name_len);

    if (hex < 0) {
        // Unknown color name - return invalid IR (red = -1 signals invalid)
        color.red = -1;
        return color;
    }

    // Extract RGB from hex (0xRRGGBB)
    color.red = (hex >> 16) & 0xFF;
    color.green = (hex >> 8) & 0xFF;
    color.blue = hex & 0xFF;
    // alpha stays at -1.0 (no alpha / opaque)

    return color;
}
