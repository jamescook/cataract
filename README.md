# Cataract

A performant CSS parser for accurate parsing of complex CSS structures.

[![codecov](https://codecov.io/github/jamescook/cataract/graph/badge.svg?token=1PTVV1QTV5)](https://codecov.io/github/jamescook/cataract)

**[API Documentation](https://jamescook.github.io/cataract/)**

## Features

- **C Extension**: Performance-focused C implementation for parsing and serialization
- **CSS2 Support**: Selectors, combinators, pseudo-classes, pseudo-elements, @media queries
- **CSS3 Support**: Attribute selectors (`^=`, `$=`, `*=`)
- **CSS Color Level 4**: Parses and preserves modern color formats (hex, rgb, hsl, hwb, oklab, oklch, lab, lch, named colors). Optional color conversion utility for transforming between formats.
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

### Advanced Filtering with Enumerable

`Cataracy::Stylesheet` implements `Enumerable`, providing standard Ruby collection methods plus chainable scopes:

```ruby
sheet = Cataract::Stylesheet.parse(css)

# Basic Enumerable methods work
sheet.map(&:selector)                    # => ["body", ".container", "div.header > h1:hover"]
sheet.select(&:selector?).count          # => Count only selector-based rules (excludes @keyframes, etc.)
sheet.find { |r| r.selector == 'body' }  # => First rule matching selector

# Filter to selector-based rules only (excludes at-rules like @keyframes, @font-face)
sheet.select(&:selector?).each do |rule|
  puts "#{rule.selector}: specificity #{rule.specificity}"
end

# Filter by media query (returns chainable scope)
sheet.with_media(:print).each do |rule|
  puts "Print rule: #{rule.selector}"
end

# Filter by selector (returns chainable scope)
sheet.with_selector('body').each do |rule|
  puts "Body rule has #{rule.declarations.length} declarations"
end

# Filter by specificity (returns chainable scope)
sheet.with_specificity(100..).each do |rule|
  puts "High specificity: #{rule.selector} (#{rule.specificity})"
end

# Chain filters together
sheet.with_media(:screen)
     .with_specificity(50..200)
     .select(&:selector?)
     .map(&:selector)
# => ["#header .nav", ".sidebar > ul li"]

# Find all rules with a specific property
sheet.select(&:selector?).select do |rule|
  rule.declarations.any? { |d| d.property == 'color' }
end

# Find high-specificity selectors (potential refactoring targets)
sheet.with_specificity(100..).select(&:selector?).each do |rule|
  puts "Refactor candidate: #{rule.selector} (specificity: #{rule.specificity})"
end

# Find positioned elements in screen media
sheet.with_media(:screen).select do |rule|
  rule.selector? && rule.declarations.any? do |d|
    d.property == 'position' && d.value == 'relative'
  end
end

# Terminal operations force evaluation
sheet.with_media(:print).to_a         # => Array of rules
sheet.with_selector('.header').size   # => 3
sheet.with_specificity(10..50).empty? # => false
```

See [BENCHMARKS.md](BENCHMARKS.md) for detailed performance comparisons.

## CSS Support

Cataract parses and preserves all standard CSS including:
- **Selectors**: All CSS2/CSS3 selectors (type, class, ID, attribute, pseudo-classes, pseudo-elements, combinators)
- **At-rules**:
  - **`@media`**: Special handling with indexing and filtering API (`with_media(:print)`, `with_media(:all)`)
  - **Others** (`@font-face`, `@keyframes`, `@supports`, `@page`, `@layer`, `@container`, `@property`, `@scope`, `@counter-style`): Parsed and preserved as-is (pass-through)
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

# Run fuzzer to test parser robustness
rake fuzz                      # 10,000 iterations (default)
rake fuzz ITERATIONS=100000    # Custom iteration count
```

**Fuzzer**: Generates random CSS input to test parser robustness against malformed or edge-case CSS. Helps catch crashes, memory leaks, and parsing edge cases.

## How It Works

Cataract uses a high-performance C implementation for CSS parsing and serialization.

Each `Rule` is a struct containing:
- `id`: Integer ID (position in rules array)
- `selector`: The CSS selector string
- `declarations`: Array of `Declaration` structs (property, value, important flag)
- `specificity`: Calculated CSS specificity (cached)

Implementation details:
- **C implementation**: Critical paths implemented in C (parsing, merging, serialization)
- **Flat rule array**: All rules stored in a single array, preserving source order
- **Efficient media query handling**: O(1) lookup via internal media index
- **Memory efficient**: Minimal allocations, reuses string buffers where possible
- **Comprehensive parsing**: Preserves complex CSS structures including nested media queries, nested selectors, data URIs, CSS functions (calc(), var(), etc.)

## Development Notes

Significant portions of this codebase were generated with assistance from [Claude Code](https://claude.com/claude-code), including the benchmark infrastructure, test suite, and documentation generation system.

## License

MIT

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/jamescook/cataract.
