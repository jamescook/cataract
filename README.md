# Cataract

A high-performance CSS parser built with Ragel state machines for accurate parsing of complex CSS structures.

## Features

- **Fast**: Built with Ragel finite state machines compiled to C
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

- Ruby >= 2.7.0
- Ragel (for development/building from source)
  - macOS: `brew install ragel`
  - Ubuntu: `sudo apt-get install ragel`

## Usage

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
# => ["margin: 0", "padding: 0"]

# Filter by media type
parser.find_by_selector(".container", :screen)
# => ["width: 750px"]

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

Cataract uses [Ragel](http://www.colm.net/open-source/ragel/) to generate a high-performance C parser from a state machine grammar. The Ragel grammar (`ext/cataract/cataract.rl`) defines the complete CSS syntax, including multiple specialized state machines for different parsing contexts (main CSS parser, specificity counter, media query parser).

Key advantages:
- **Deterministic**: No backtracking or regex complexity issues
- **Fast**: Compiled C code with minimal overhead
- **Maintainable**: Grammar is readable and maps directly to CSS specs

## License

MIT

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/jamescook/cataract.
