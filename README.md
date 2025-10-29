# Cataract

A high-performance CSS parser with C extensions for accurate parsing of complex CSS structures.

[![codecov](https://codecov.io/github/jamescook/cataract/graph/badge.svg?token=1PTVV1QTV5)](https://codecov.io/github/jamescook/cataract)

## Features

- **Fast**: High-performance C implementation for parsing and serialization
- **CSS2 Support**: Selectors, combinators, pseudo-classes, pseudo-elements, @media queries
- **CSS3 Support**: Attribute selectors (`^=`, `$=`, `*=`)
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
parser = Cataract::Parser.new
parser.parse(<<~CSS)
  body { margin: 0; padding: 0 }

  @media screen and (min-width: 768px) {
    .container { width: 750px }
  }

  div.header > h1:hover { color: blue }
CSS

# Query selectors
parser.selectors
# => ["body", ".container", "div.header > h1:hover"]

# Find declarations by selector
parser.find_by_selector("body")
# => ["margin: 0;", "padding: 0;"]

# Filter by media type
parser.find_by_selector(".container", :screen)
# => ["width: 750px;"]

# Get specificity
parser.each_selector do |selector, declarations, specificity|
  puts "#{selector}: specificity=#{specificity}"
end
# body: specificity=1
# .container: specificity=10
# div.header > h1:hover: specificity=23

# Count rules
parser.rules_count
# => 3
```

### css_parser Compatibility

Cataract provides a compatible API with the popular [css_parser](https://github.com/premailer/css_parser) gem, making it easy to switch between implementations:

```ruby
parser = Cataract::Parser.new

# Load CSS from various sources
parser.add_block!('body { color: red }')
parser.load_string!('p { margin: 0 }')
parser.load_file!('/path/to/styles.css')
parser.load_uri!('https://example.com/styles.css')

# Lenient parsing with automatic brace closing
parser.add_block!('p { color: red', fix_braces: true)
# Automatically closes the missing brace

# Add rules with media types
parser.add_block!('body { font-size: 12px }', media_types: [:screen])
parser.add_rule!(selector: '.mobile', declarations: 'width: 100%', media_types: :handheld)

# Access rules
parser.each_selector do |selector, declarations, specificity, media_types|
  # Process each selector
end

parser.find_rule_sets(['.header', '.footer'])
# => [array of matching RuleSet objects]
```

**Note on `fix_braces`:** This option is `false` by default for performance. Enable it only when parsing untrusted or malformed CSS that may have missing closing braces.

## Supported CSS Features

### CSS2
- Type selectors: `div`, `p`, `span`
- Class selectors: `.classname`
- ID selectors: `#idname`
- Attribute selectors: `[attr]`, `[attr="value"]`, `[attr~="value"]`, `[attr|="value"]`
- Pseudo-classes: `:hover`, `:focus`, `:first-child`, `:link`, `:visited`, `:active`
- Pseudo-elements: `::before`, `::after`, `::first-line`, `::first-letter`
- Combinators: descendant (`div p`), child (`div > p`), adjacent sibling (`h1 + p`)
- Universal selector: `*`
- @media queries with features: `@media screen and (min-width: 768px)`
- `!important` declarations

### CSS3
- Attribute substring selectors: `[attr^="value"]`, `[attr$="value"]`, `[attr*="value"]`

### Special Features
- **Data URI support**: Correctly handles semicolons in data URIs (e.g., `url(data:image/png;base64,...)`)
- **URL functions**: Parses `url()`, `calc()`, and other CSS functions with parentheses
- **Lenient parsing**: Optional `fix_braces` mode for auto-closing missing braces

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

# Clean build artifacts
rake clean
```

## How It Works

Cataract uses a high-performance C implementation for CSS parsing and serialization. The parser processes CSS into an internal data structure organized by media queries:

```ruby
{
  # Media query string => group info
  "(min-width: 768px)" => {
    media_types: [:screen],  # Array of applicable media types
    rules: [...]             # Array of Rule structs for this media query
  },
  nil => {
    media_types: [:all],     # Rules with no media query
    rules: [...]
  }
}
```

Each `Rule` is a struct containing:
- `selector`: The CSS selector string
- `declarations`: Array of `Declarations::Value` structs (property, value, important flag)
- `specificity`: Calculated CSS specificity (cached)

Key advantages:
- **Fast**: Critical paths implemented in C (parsing, merging, serialization)
- **Efficient media query handling**: Rules grouped by media query for O(1) lookups
- **Memory efficient**: Minimal allocations, reuses string buffers where possible
- **Accurate**: Handles complex CSS including nested media queries, data URIs, calc() functions

## License

MIT

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/jamescook/cataract.
