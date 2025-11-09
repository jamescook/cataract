# Cataract

A high-performance CSS parser with C extensions for accurate parsing of complex CSS structures.

[![codecov](https://codecov.io/github/jamescook/cataract/graph/badge.svg?token=1PTVV1QTV5)](https://codecov.io/github/jamescook/cataract)

## Features

- **C Extension**: Performance-focused C implementation for parsing and serialization
- **CSS2 Support**: Selectors, combinators, pseudo-classes, pseudo-elements, @media queries
- **CSS3 Support**: Attribute selectors (`^=`, `$=`, `*=`)
- **CSS Color Level 4**: Supports hex, rgb, hsl, hwb, oklab, oklch, and named colors with high precision
- **Specificity Calculation**: Automatic CSS specificity computation
- **Media Query Filtering**: Query rules by media type
- **Zero Runtime Dependencies**: Pure C extension with no runtime gem dependencies

## Installation

Add this line to your Gemfile:

```ruby
gem 'cataract'
```

Or install directly:

```bash
gem install cataract
```

### Requirements

- Ruby >= 3.1.0

## Usage

### Basic Parsing

```ruby
require 'cataract'

# Parse CSS
sheet = Cataract::Stylesheet.parse(<<~CSS)
  body { margin: 0; padding: 0 }

  @media screen and (min-width: 768px) {
    .container { width: 750px }
  }

  div.header > h1:hover { color: blue }
CSS

# Get all selectors
sheet.selectors
# => ["body", ".container", "div.header > h1:hover"]

# Get all rules
sheet.rules.each do |rule|
  puts "#{rule.selector}: #{rule.declarations.length} declarations"
end

# Access specific rule
body_rule = sheet.rules.first
body_rule.selector       # => "body"
body_rule.specificity    # => 1
body_rule.declarations   # => [#<Declaration property="margin" value="0">, ...]

# Count rules
sheet.rules_count
# => 3

# Serialize back to CSS
sheet.to_s
# => "body { margin: 0; padding: 0; } @media screen and (min-width: 768px) { .container { width: 750px; } } ..."
```

### Advanced Filtering with each_selector

The `Stylesheet#each_selector` method provides powerful filtering capabilities for CSS analysis:

```ruby
sheet = Cataract::Stylesheet.parse(css)

# Find high-specificity selectors (potential refactoring targets)
sheet.each_selector(specificity: 100..) do |selector, declarations, specificity, media_types|
  puts "High specificity: #{selector} (#{specificity})"
end

# Find all selectors that define a color property
sheet.each_selector(property: 'color') do |selector, declarations, specificity, media_types|
  puts "#{selector} defines color"
end

# Find all positioned elements
sheet.each_selector(property: 'position', property_value: 'relative') do |selector, declarations, specificity, media_types|
  puts "#{selector} is relatively positioned"
end

# Find any property with a specific value (useful for finding typos or deprecated values)
sheet.each_selector(property_value: 'relative') do |selector, declarations, specificity, media_types|
  puts "#{selector} uses value 'relative'"
end

# Combine filters for complex queries
sheet.each_selector(property: 'z-index', specificity: 100.., media: :screen) do |selector, declarations, specificity, media_types|
  puts "High-specificity z-index usage in screen media: #{selector}"
end

# Filter by specificity ranges
sheet.each_selector(specificity: 10..100) { |sel, decls, spec, media| ... }  # Class to ID range
sheet.each_selector(specificity: ..10) { |sel, decls, spec, media| ... }     # Low specificity (<= 10)
```

See [BENCHMARKS.md](BENCHMARKS.md) for detailed performance comparisons.

## CSS Support

Cataract aims to support all CSS specifications including:
- **Selectors**: All CSS2/CSS3 selectors (type, class, ID, attribute, pseudo-classes, pseudo-elements, combinators)
- **At-rules**: `@media`, `@font-face`, `@keyframes`, `@supports`, `@page`, `@layer`, `@container`, `@property`, `@scope`, `@counter-style`
- **Media Queries**: Full support including nested queries and media features
- **Special syntax**: Data URIs, `calc()`, `url()`, CSS functions with parentheses
- **!important**: Full support with correct cascade behavior

### Color Conversion

Cataract supports converting colors between multiple CSS color formats with high precision.

**Note:** Color conversion is an optional extension. Load it explicitly to reduce memory footprint:

```ruby
require 'cataract'
require 'cataract/color_conversion'

# Convert hex to RGB
sheet = Cataract::Stylesheet.parse('.button { color: #ff0000; background: #00ff00; }')
sheet.convert_colors!(from: :hex, to: :rgb)
sheet.to_s
# => ".button { color: rgb(255 0 0); background: rgb(0 255 0); }"

# Convert RGB to HSL for easier color manipulation
sheet = Cataract::Stylesheet.parse('.card { color: rgb(255, 128, 0); }')
sheet.convert_colors!(from: :rgb, to: :hsl)
sheet.to_s
# => ".card { color: hsl(30, 100%, 50%); }"

# Convert to Oklab for perceptually uniform colors
sheet = Cataract::Stylesheet.parse('.gradient { background: linear-gradient(#ff0000, #0000ff); }')
sheet.convert_colors!(to: :oklab)
sheet.to_s
# => ".gradient { background: linear-gradient(oklab(0.6280 0.2249 0.1258), oklab(0.4520 -0.0325 -0.3115)); }"

# Auto-detect source format and convert all colors
sheet = Cataract::Stylesheet.parse(<<~CSS)
  .mixed {
    color: #ff0000;
    background: rgb(0, 255, 0);
    border-color: hsl(240, 100%, 50%);
  }
CSS
sheet.convert_colors!(to: :hex)  # Converts all formats to hex
```

#### Supported Color Formats

| Format | From | To | Alpha | Example | Notes |
|--------|------|-----|-------|---------|-------|
| **hex** | ✓ | ✓ | ✓ | `#ff0000`, `#f00`, `#ff000080` | 3, 6, or 8 digit hex |
| **rgb** | ✓ | ✓ | ✓ | `rgb(255 0 0)`, `rgb(255, 0, 0)` | Modern & legacy syntax |
| **hsl** | ✓ | ✓ | ✓ | `hsl(0, 100%, 50%)` | Hue, saturation, lightness |
| **hwb** | ✓ | ✓ | ✓ | `hwb(0 0% 0%)` | Hue, whiteness, blackness |
| **oklab** | ✓ | ✓ | ✓ | `oklab(0.628 0.225 0.126)` | Perceptually uniform color space |
| **oklch** | ✓ | ✓ | ✓ | `oklch(0.628 0.258 29.2)` | Cylindrical Oklab (LCh) |
| **lab** | ✓ | ✓ | ✓ | `lab(53.2% 80.1 67.2)` | CIE L\*a\*b\* color space (D50) |
| **lch** | ✓ | ✓ | ✓ | `lch(53.2% 104.5 40)` | Cylindrical Lab (polar coordinates) |
| **named** | ✓ | ✓ | – | `red`, `blue`, `rebeccapurple` | 147 CSS named colors |
| **color()** | – | – | – | `color(display-p3 1 0 0)` | Absolute color spaces (planned) |

**Format aliases:**
- `:rgba` → uses `rgb()` syntax with alpha
- `:hsla` → uses `hsl()` syntax with alpha
- `:hwba` → uses `hwb()` syntax with alpha

**Limitations:**
- Math functions (`calc()`, `min()`, `max()`, `clamp()`) are not evaluated and will be preserved unchanged
- CSS Color Level 5 features (`none`, `infinity`, relative color syntax with `from`) are preserved but not converted
- Unknown or future color functions are passed through unchanged

### `@import` Support

`@import` statements can be resolved with security controls:

```ruby
# Disabled by default
sheet = Cataract::Stylesheet.parse(css)  # @import statements are ignored

# Enable with safe defaults (HTTPS only, .css files only, max depth 5)
sheet = Cataract::Stylesheet.parse(css, import: true)

# Custom options for full control
sheet = Cataract::Stylesheet.parse(css, import: {
  allowed_schemes: ['https', 'file'],   # Default: ['https']
  extensions: ['css'],                   # Default: ['css']
  max_depth: 3,                          # Default: 5
  timeout: 10,                           # Default: 10 seconds
  follow_redirects: true                 # Default: true
})
```

**Security note**: Import resolution includes protections against:
- Unauthorized schemes (file://, data://, etc.)
- Non-CSS file extensions
- Circular references
- Excessive nesting depth

## Development

```bash
# Install dependencies
bundle install

# Compile the C extension
rake compile

# Run tests
rake test

# Run benchmarks
rake benchmark
```

## How It Works

Cataract uses a high-performance C implementation for CSS parsing and serialization. The parser processes CSS into an internal data structure:

```ruby
# Stylesheet structure
{
  rules: [Rule, Rule, ...],          # Flat array of all rules in source order
  media_index: {                      # Hash mapping media queries to rule IDs
    screen: [1, 3, 5],                # Rule IDs that appear in @media screen
    print: [2, 4],                    # Rule IDs that appear in @media print
    # Rules not in any @media block are not indexed
  }
}
```

Each `Rule` is a struct containing:
- `id`: Integer ID (position in rules array)
- `selector`: The CSS selector string
- `declarations`: Array of `Declaration` structs (property, value, important flag)
- `specificity`: Calculated CSS specificity (cached)

Implementation details:
- **C implementation**: Critical paths implemented in C (parsing, merging, serialization)
- **Flat rule array**: All rules in single array, preserving source order
- **Efficient media query handling**: O(1) lookup via media_index hash
- **Memory efficient**: Minimal allocations, reuses string buffers where possible
- **Comprehensive**: Handles complex CSS including nested media queries, nested CSS, data URIs, calc() functions

## Development Notes

Significant portions of this codebase were generated with assistance from [Claude Code](https://claude.com/claude-code), including the benchmark infrastructure, test suite, and documentation generation system.

## License

MIT

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/jamescook/cataract.
