#!/usr/bin/env ruby
# frozen_string_literal: true

# Simple CSS parser fuzzer
# Usage: ruby scripts/fuzz_css_parser.rb [iterations] [rng_seed]
#   iterations: number of fuzzing iterations (default: 10,000)
#   rng_seed:   random number generator seed for reproducibility (default: random)

require 'timeout'
require 'open3'
require 'rbconfig'

# Load pure Ruby or C extension based on ENV var
PURE_RUBY = ENV['CATARACT_PURE'] == '1'
if PURE_RUBY
  require_relative '../../lib/cataract/pure'
  COLOR_AVAILABLE = false
else
  require_relative '../../lib/cataract'
  require_relative '../../lib/cataract/color_conversion'
  COLOR_AVAILABLE = true
end

# Check if Cataract is compiled in debug mode (would overwhelm pipe buffer)
if Cataract::COMPILE_FLAGS[:debug]
  abort <<~ERROR
    #{'=' * 80}
    ERROR: Cataract compiled with DEBUG mode enabled
    #{'=' * 80}
    Debug output will overwhelm the pipe buffer and freeze the fuzzer.

    To disable debug mode:
      1. Edit ext/cataract/cataract.h
      2. Comment out the line: #define CATARACT_DEBUG 1
      3. Recompile: rake compile
    #{'=' * 80}
  ERROR
end

# Check if Ruby is compiled with AddressSanitizer (ASAN)
# ASAN provides detailed heap-buffer-overflow and use-after-free reports
def check_asan_enabled
  ruby_bin = RbConfig.ruby

  # Check for ASAN library linkage (cross-platform)
  case RbConfig::CONFIG['host_os']
  when /darwin|mac os/
    # macOS: use otool to check dynamic libraries
    output = `otool -L "#{ruby_bin}" 2>&1`
    output.include?('asan')
  when /linux/
    # Linux: use ldd to check dynamic libraries
    output = `ldd "#{ruby_bin}" 2>&1`
    output.include?('asan')
  else
    # Unknown platform - assume not enabled
    false
  end
rescue StandardError
  # If check fails, assume not enabled
  false
end

unless check_asan_enabled
  warn '=' * 80
  warn 'WARNING: Ruby not compiled with AddressSanitizer (ASAN)'
  warn '=' * 80
  warn 'Crash reports will have limited utility for debugging memory errors.'
  warn ''
  warn 'To enable ASAN, recompile Ruby with these flags:'
  warn '  CFLAGS="-fsanitize=address -g -O1" LDFLAGS="-fsanitize=address"'
  warn ''
  warn 'Example with mise:'
  warn "  CFLAGS=\"-fsanitize=address -g -O1\" LDFLAGS=\"-fsanitize=address\" mise install ruby@#{RUBY_VERSION} --force"
  warn ''
  warn 'Example with rbenv/ruby-build:'
  warn "  CFLAGS=\"-fsanitize=address -g -O1\" LDFLAGS=\"-fsanitize=address\" rbenv install #{RUBY_VERSION}"
  warn ''
  warn 'ASAN provides detailed reports for:'
  warn '  - Heap buffer overflows'
  warn '  - Use-after-free bugs'
  warn '  - Stack buffer overflows'
  warn '  - Memory leaks'
  warn '=' * 80
  warn ''
end

ITERATIONS = (ARGV[0] || 10_000).to_i
RNG_SEED = (ARGV[1] || Random.new_seed).to_i

# Set the random seed for reproducibility
srand(RNG_SEED)

# Load bootstrap.css as main seed
BOOTSTRAP_CSS = File.read(File.join(__dir__, '../../test/fixtures/bootstrap.css'))

# Clean CSS samples for regex-based mutations (guaranteed valid UTF-8)
CLEAN_CORPUS = [
  'body { margin: 0; padding: 0; }',
  'div { color: red; background: blue; }',
  '.class { font-size: 14px; }',
  '#id { display: flex; }',
  'a:hover { text-decoration: underline; }',
  '@media screen { body { font-size: 16px; } }',
  '.button { color: blue; &:hover { color: red; } }',
  '.parent { margin: 0; .child { padding: 10px; } }',
  '@supports (display: flex) { div { display: flex; } }',
  "@font-face { font-family: 'Custom'; src: url('font.woff'); }",
  '@keyframes fade { from { opacity: 0; } to { opacity: 1; } }',
  'h1 + *[rel=up] { border: 1px solid red; }',
  # Parse error triggering patterns (will be mutated but base is valid to parse)
  'h1 { color: red; }', # Will mutate to empty values
  'div { property: value; }', # Will mutate to malformed declarations
  '.selector { color: blue; }', # Will mutate to invalid selectors
  '@media screen { .test { color: red; } }', # Will mutate to malformed @media
  'body { color: red; }', # Will mutate to unclosed blocks
  BOOTSTRAP_CSS[0..1000] # Clean bootstrap snippet
].freeze

# CSS corpus - real CSS snippets to mutate (includes garbage samples with binary data)
CORPUS = [
  BOOTSTRAP_CSS, # Full bootstrap.css
  # Interesting subsections of bootstrap
  BOOTSTRAP_CSS[0..5000],
  BOOTSTRAP_CSS[10_000..20_000],
  BOOTSTRAP_CSS[-5000..],
  # Small focused examples
  'body { margin: 0; }',
  "div.class { color: red; background: url('data:image/png;base64,ABC'); }",
  "#id > p:hover::before { content: 'test'; }",
  "a[href^='https'] { color: blue !important; }",
  '@keyframes fade { from { opacity: 0; } to { opacity: 1; } }',
  "@font-face { font-family: 'Custom'; src: url('font.woff'); }",
  'h1 + *[rel=up] { margin: 10px 20px; }',
  'li.red.level { border: 1px solid red; }',
  '/* comment */ .test { padding: 0; }',

  # Media query parsing - test parse_media_query() function
  '@media screen { .nav { display: flex; } }',
  '@media print { body { margin: 1in; } }',
  '@media screen, print { .dual { color: black; } }',
  '@media screen and (min-width: 768px) { .responsive { width: 100%; } }',
  '@media (prefers-color-scheme: dark) { body { background: black; } }',
  '@media only screen and (max-width: 600px) { .mobile { font-size: 12px; } }',
  '@media not print { .no-print { display: none; } }',
  '@media screen and (min-width: 768px) and (max-width: 1024px) { .tablet { padding: 20px; } }',
  '@media (orientation: landscape) { .landscape { width: 100vw; } }',
  '@media screen and (color) { .color { background: red; } }',
  "@media (min-resolution: 2dppx) { .retina { background-image: url('hi-res.png'); } }",
  "@media (-webkit-min-device-pixel-ratio: 2) { .webkit { content: 'vendor'; } }",

  # Multiple media queries with same selector - tests flatten grouping by (selector, media)
  '@media screen { div { margin: 10px; } } @media print { div { margin: 0; } }',
  '@media screen { body { color: blue; } body { background: white; } } @media print { body { color: black; } }',

  # Color conversion test cases - try to trigger segfaults
  '.test { color: #ff0000; }',
  '.test { color: rgb(255, 0, 0); }',
  '.test { color: rgb(255 0 0); }',
  '.test { color: rgba(255, 0, 0, 0.5); }',
  '.test { color: hsl(0, 100%, 50%); }',
  '.test { color: hsla(0, 100%, 50%, 0.5); }',
  '.test { color: hwb(0 0% 0%); }',
  '.test { color: oklab(0.628 0.225 0.126); }',
  '.test { color: oklch(0.628 0.258 29.2); }',
  '.test { color: lab(53.2% 80.1 67.2); }',
  '.test { color: lch(53.2% 104.5 40); }',
  '.test { color: red; }',
  # Invalid/malformed color values for fuzzing
  '.test { color: #gg0000; }',
  '.test { color: rgb(999, -100, 300); }',
  '.test { color: hsl(999deg, 200%, -50%); }',
  '.test { color: oklab(99 99 99); }',
  '.test { color: lab(200% 999 999); }',

  # URL conversion test cases - exercise convert_urls_in_value code path
  "body { background: url('image.png') }",
  'body { background: url(image.png) }',
  'body { background: url("image.png") }',
  "body { background: url('../images/bg.png') }",
  "body { background: url('http://example.com/image.png') }",
  "body { background: url('https://example.com/image.png') }",
  "body { background: url('//example.com/image.png') }",
  "body { background: url('data:image/png;base64,ABC123') }",
  "body { background: url('#fragment') }",
  "body { background-image: url('a.png'), url('b.png'), url('c.png') }",
  ".icon { list-style-image: url('bullet.gif') }",
  "@font-face { src: url('font.woff2') format('woff2'), url('font.woff') format('woff') }",
  "body { background: url('path/with spaces/image.png') }",
  "body { background: url('path?query=1&other=2#frag') }",
  "body { background: url('') }",  # Empty URL
  'body { background: url() }',    # No quotes, empty
  "body { background: url('   ') }", # Only whitespace
  'body { background: url(   image.png   ) }', # Whitespace around URL
  # Malformed URLs for fuzzing
  "body { background: url('unclosed }",
  'body { background: url(unclosed }',
  "body { background: url('data:image/png;base64,#{'A' * 10_000}') }", # Large data URI
  "body { background: url('http://user:pass@example.com/image.png') }", # URL with userinfo
  "body { background: url('http://localhost:3000/image.png') }", # URL with port
  "body { background: url('file:///etc/passwd') }", # File URL
  "body { background: url('\x00malicious\x00') }", # Null bytes in URL
  "body { background: url('#{'../' * 50}image.png') }", # Directory traversal
  "body { background: url('image.png'); color: url('notacolor') }", # URL in wrong property

  # Deep nesting - close to MAX_PARSE_DEPTH (10)
  # Depth 8 - mutations can push it over the limit
  '@supports (a) { @media (b) { @supports (c) { @layer d { @container (e) { @scope (f) { @media (g) { @supports (h) { body { margin: 0; } } } } } } } }',

  # Long property names - close to MAX_PROPERTY_NAME_LENGTH (256)
  "body { #{'a' * 200}-property: value; }",

  # Long property values - close to MAX_PROPERTY_VALUE_LENGTH (32KB)
  "body { background: url('data:image/svg+xml,#{'A' * 30_000}'); }",
  "div { content: '#{'x' * 31_000}'; }",

  # Multiple nested @supports to stress recursion
  '@supports (display: flex) { @supports (gap: 1rem) { div { display: flex; } } }',

  # CSS Nesting - Valid cases
  '.button { color: blue; &:hover { color: red; } }',
  '.parent { margin: 0; .child { padding: 10px; } }',
  '.card { & .title { font-size: 20px; } & .body { margin: 10px; } }',
  '.a, .b { color: black; & .child { color: white; } }',
  '.foo { color: red; @media (min-width: 768px) { color: blue; } }',
  '.parent { color: red; & > .child { color: blue; } }',
  '.nav { display: flex; &.active { background: red; } }',
  '.outer { .middle { .inner { color: red; } } }',
  '.button { &:hover, &:focus { outline: 2px solid blue; } }',
  '.list { & > li { & > a { text-decoration: none; } } }',

  # CSS Nesting - Garbage/malformed cases to stress parser
  '.parent { & { } }', # Empty nested rule
  '.a { & }', # Incomplete nested rule
  '.b { &', # Missing closing brace
  '.c { & .child { }', # Missing outer closing brace
  '.d { & .child { color: red; }', # Missing outer closing brace
  '.e { & & & & & { color: red; } }', # Multiple ampersands
  '.f { &&&&& { } }', # Continuous ampersands
  '.g { &..child { } }', # Invalid selector after &
  '.h { &#invalid { } }', # Invalid combinator
  '.i { &::: { } }', # Too many colons
  '.j { & .a { & .b { & .c { & .d { & .e { & .f { & .g { & .h { & .i { & .j { } } } } } } } } } } }', # Deep nesting
  '.k { & .child { color: red; & }', # Incomplete nested block
  '.l { .child & { } }', # & in wrong position
  '.m { .a { .b { .c }', # Missing closing braces in chain
  '.n { & { & { & { } } }', # Nested empty blocks
  '.o { color: red &:hover { } }', # Missing semicolon before nesting
  '.p { &, { } }', # Comma with nothing after
  '.q { &, , , .child { } }', # Multiple commas
  '.r { & .child { @media { } } }', # Incomplete @media in nested
  '.s { @media { .child { } }', # Missing @media query
  '.t { @media screen & .child { } }', # Invalid @media syntax with nesting
  '.u { & .a, & .b, & .c, }', # Trailing comma in nested selector
  '.v { & { color: &; } }', # & as value
  '.w { & .child { & .grandchild { & .great { color: red } } }', # Missing braces
  '.x { &&&.child { } }', # Multiple & before class
  '.y { & + & + & { } }', # Adjacent sibling combinators
  '.z { & ~ & ~ & { } }', # General sibling combinators

  # CSS Nesting with @media - garbage
  '.a { @media }', # Incomplete @media
  '.b { @media screen }', # @media without block
  '.c { @media screen { }', # Missing outer closing brace
  '.d { @media (garbage) { color: red; } }', # Invalid media query in nested
  '.e { @media screen { @media print { } }', # Missing closing braces
  '.f { @media { @media { @media { } } } }', # Nested @media without queries

  # Invalid selector syntax - tests whitelist validation
  '..invalid { color: red; }', # Double dot at start
  'h2..foo { color: blue; }', # Double dot in middle
  '##invalid { margin: 0; }', # Double hash
  '??? { padding: 10px; }', # Question marks (invalid chars)
  '$$$selector { color: red; }', # Dollar signs (invalid start char)
  '@@@test { margin: 0; }', # Multiple @ (invalid in selector)
  'h1, , h3 { color: red; }', # Empty selector in list
  'h1,, h3 { color: red; }', # Consecutive commas
  ', h2 { color: blue; }', # Leading comma
  'h3, { color: green; }', # Trailing comma
  '..class1, ..class2 { margin: 0; }', # Multiple invalid selectors
  'div...triple { padding: 0; }', # Triple dots
  'span###triple { color: red; }', # Triple hashes
  'p....quad { margin: 0; }', # Quadruple dots
  '!!!invalid { color: red; }', # Exclamation marks
  '```code { color: red; }', # Backticks
  '~~~test { margin: 0; }', # Tildes at start (~ is valid but not at start alone)
  '+++plus { padding: 0; }', # Plus signs at start
  '>>>arrows { color: red; }', # Multiple child combinators
  '.valid, ???, .also-valid { color: red; }', # Invalid in middle of list
  '..bad, h1, h2 { color: red; }', # Invalid at start of list
  'h1, h2, ##bad { color: red; }', # Invalid at end of list

  # @import statements - valid cases (will use InMemoryImportFetcher)
  "@import 'base.css';",
  "@import url('base.css');",
  "@import 'responsive.css' screen;",
  "@import url('parent.css');\nbody { margin: 0; }", # With rules after
  "@import 'child.css';\n@import 'base.css';", # Multiple imports
  "@import 'charset.css';", # Import with charset
  "@import 'nested.css';", # Import with nesting
  "@charset 'UTF-8';\n@import 'multi.css';", # Charset before import

  # @import statements - malformed/garbage
  '@import', # Incomplete
  "@import 'missing.css", # Missing quote and semicolon
  '@import url(', # Incomplete url()
  "@import url('test.css'", # Missing closing paren
  "@import 'test.css' {}", # Invalid syntax (block instead of semicolon)
  "@import url url url('test.css');", # Multiple url()
  '@import "test.css" "another.css";', # Multiple URLs
  "@import 'test.css' garbage media query;", # Invalid media query
  "@import \x00.css;", # Null byte in URL
  "@import '#{'x' * 1000}.css';", # Very long URL
  "body { margin: 0; }\n@import 'late.css';", # Import after rules (invalid)
  "@import 'first.css';\nbody {}\n@import 'second.css';", # Import in middle

  # Extreme nesting garbage
  '.a { & .b { & .c { & .d { & .e { & .f { & .g { & .h { & .i { & .j { & .k { } } } } } } } } } } }', # 11 levels
  ".deep { #{'& .x { ' * 50}color: red;#{' }' * 50} }", # Very deep nesting
  ".unclosed { #{'& .x { ' * 20}", # Many unclosed nested blocks
  '.chaos { & { & { & { & { & { & { & { & { & { & { } } } } } } } } } } }', # Deep self-nesting

  # Brace chaos in nested context
  '.parent { &:hover { color: red; }}}}}', # Extra closing braces
  '.parent { &:hover {{{{{{ color: red; } }', # Extra opening braces
  '.parent { &:hover { color: red; }; &:focus { color: blue; }', # Missing outer close
  '.parent { & .child { } } } }', # Too many closing braces
  '.parent { { & .child { } }', # Opening brace before nested
  '.parent { & .child { { color: red; } }', # Double opening in nested

  # Null bytes and binary in nested CSS
  ".parent { &\x00.child { color: red; } }", # Null in selector
  ".parent { & .child { color: \x00\xFF\xFE; } }", # Null/binary in value
  ".parent {\x00 & .child { } }", # Null after opening brace
  ".parent { & .child {\x00} }", # Null before closing brace

  # Comment chaos in nested CSS
  '.parent { /* & .child { */ color: red; }', # Commented nesting
  '.parent { & .child { /* color: red; } */ }', # Unclosed comment in nested
  '.parent { & /* .child */ { color: red; } }', # Comment in middle of selector
  '.parent { & .child /* { color: red; } }', # Comment breaking structure

  # Escaped characters in nested selectors
  '.parent { &\\.child { } }', # Escaped dot
  '.parent { &\\:hover { } }', # Escaped colon
  '.parent { &\\&child { } }', # Escaped ampersand
  '.parent { \\& .child { } }', # Escaped ampersand at start

  # Property/value chaos in nested blocks
  '.parent { color: red; & .child { : value; } }', # Missing property
  '.parent { & .child { property; } }', # Missing colon and value
  '.parent { & .child { : ; } }', # Just colon and semicolon
  '.parent { & .child { :::; } }', # Multiple colons
  '.parent { & .child { color red } }', # Missing colon
  '.parent { & .child { color: } }' # Missing value
].freeze

# Color formats to test conversion between
COLOR_FORMATS = %i[hex rgb hsl hwb oklab oklch lab lch named].freeze

# In-memory import fetcher for testing @import resolution without I/O
# This allows fuzzing the import resolution code path without creating files
IMPORT_CSS_FILES = {
  # Base imported file - simple CSS
  'base.css' => '.imported { color: blue; margin: 10px; }',

  # File with media query - tests media combining
  'responsive.css' => '@media screen and (min-width: 768px) { .responsive { display: flex; } }',

  # File that imports another file - tests recursive imports
  'parent.css' => "@import 'child.css';\n.parent { padding: 5px; }",

  # Nested import target
  'child.css' => '.child { font-size: 14px; }',

  # File with @charset - tests charset propagation
  'charset.css' => '@charset "UTF-8"; .unicode { content: "★"; }',

  # Complex file with nesting
  'nested.css' => '.outer { color: red; .inner { color: blue; } }',

  # File with multiple rules
  'multi.css' => '.one { color: red; } .two { color: blue; } .three { color: green; }'
}.freeze

# In-memory fetcher - returns CSS from constant hash instead of reading files
# Accepts any URL and maps it to a hardcoded CSS file
InMemoryImportFetcher = lambda do |url, _opts|
  # Extract filename from URL (supports file://, http://, https://, or bare names)
  filename = url.split('/').last || 'base.css'

  # Return CSS from our hash, default to base.css if not found
  IMPORT_CSS_FILES[filename] || IMPORT_CSS_FILES['base.css']
end

# Mutation strategies (binary-safe)
def mutate(css)
  # Work with dup to avoid mutating original (unfreeze if needed)
  css = css.dup.force_encoding('UTF-8')
  css = +css # Unfreeze if frozen

  mutations = [
    # Basic mutations
    -> { css[0..rand(css.length)] }, # Truncate
    lambda {
      pos = rand(css.length)
      css.insert(pos, css[0..rand(css.length)])
    }, # Duplicate section
    -> { css.bytes.select { rand > 0.1 }.pack('C*').force_encoding('UTF-8') }, # Delete random bytes
    lambda {
      bytes = css.bytes
      10.times do
        a = rand(bytes.size)
        b = rand(bytes.size)
        bytes[a], bytes[b] = bytes[b], bytes[a]
      end
      bytes.pack('C*').force_encoding('UTF-8')
    }, # Swap bytes

    # Brace/bracket corruption
    -> { css.gsub(/{/, '').gsub(/}/, '') }, # Remove braces
    -> { css.gsub(/{/, '{{').gsub(/}/, '}}') }, # Duplicate braces
    -> { css + ('{' * rand(5)) }, # Unmatched braces
    -> { css.tr('{', '[').tr('}', ']') }, # Wrong bracket type

    # Quote corruption
    -> { css.gsub(/["']/, '') }, # Remove quotes
    -> { css.tr('"', "'").tr('\'', '"') }, # Swap quote types
    -> { css.gsub(/(['"])/, '\1\1') }, # Double quotes

    # @rule mutations
    -> { "@media print { #{css} @media screen { #{css} } }" }, # Deep nesting
    -> { css.gsub(/@media/, '@MEDIA').gsub(/@keyframes/, '@KEYFRAMES') }, # Wrong case
    -> { css.gsub(/@(media|keyframes|font-face)/) { "@#{rand(99_999)}" } }, # Invalid @rules
    -> { "@supports (garbage) { #{css} }" }, # Invalid @supports

    # Selector mutations
    -> { css.gsub(/\.[\w-]+/, "..#{'x' * rand(100)}") }, # Corrupt class names
    -> { css.gsub(/#[\w-]+/, "###{'x' * rand(100)}") }, # Corrupt IDs
    -> { css.gsub(/::?[\w-]+/, ":::#{'x' * rand(50)}") }, # Corrupt pseudo-elements
    -> { css.gsub(/\[[\w-]+/, "[#{'X' * rand(10)}") }, # Corrupt attributes

    # Value mutations
    -> { css.gsub(';', ' !important;') }, # Add !important everywhere
    -> { css.gsub(/:[^;]+;/, ": #{'x' * rand(10_000)};") }, # Very long values

    # Parse error triggering mutations
    -> { css.gsub(/:\s*[^;]+;/, ': ;') }, # Empty values (triggers empty_values check)
    -> { css.gsub(/:\s*[^;]+;/, ' ;') }, # Remove colon (triggers malformed_declarations check)
    -> { css.gsub(/[.#][\w-]+\s*{/, ' { ') }, # Remove selector (triggers invalid_selectors check)
    -> { css.gsub(/@media\s+[^{]+{/, '@media { ') }, # Remove @media query (triggers malformed_at_rules check)
    -> { css.gsub(/}\s*$/, '') }, # Remove closing braces (triggers unclosed_blocks check)
    -> { css.gsub(/calc\([^)]+\)/, "calc(#{'(' * rand(10)}1+2#{')' * rand(10)}") }, # Unbalanced calc()
    -> { css.gsub(/url\([^)]+\)/, "url(CORRUPT#{'X' * rand(100)})") }, # Corrupt URLs
    -> { css.gsub('url(', 'url(url(url(') }, # Nested url() calls
    -> { css.gsub(/url\([^)]*\)/, "url('#{'../' * rand(100)}image.png')") }, # Deep path traversal
    -> { css.gsub(/url\([^)]*\)/, "url('\x00\xFF\xFE')") }, # Binary in URL
    -> { css.gsub(/url\((['"])?/, 'url(') }, # Remove quotes from URLs
    -> { css.gsub('url(', "url('") }, # Add unclosed quote to URLs
    -> { css.gsub(/rgba?\([^)]+\)/, "rgb(#{[rand(999), rand(999), rand(999)].join(',')})") }, # Invalid rgb values

    # Color mutation - corrupt color values to trigger parser/conversion crashes
    -> { css.gsub(/#[0-9a-f]{3,8}/i, "###{'X' * rand(10)}") }, # Corrupt hex colors
    -> { css.gsub(/rgb\([^)]+\)/, "rgb(#{rand(9999)},#{rand(9999)},#{rand(9999)})") }, # Invalid RGB
    -> { css.gsub(/hsl\([^)]+\)/, "hsl(#{rand(9999)},#{rand(9999)}%,#{rand(9999)}%)") }, # Invalid HSL
    -> { css.gsub(/oklab\([^)]+\)/, "oklab(#{rand(99)} #{rand(99)} #{rand(99)})") }, # Invalid Oklab
    -> { css.gsub(/lab\([^)]+\)/, "lab(#{rand(999)}% #{rand(999)} #{rand(999)})") }, # Invalid Lab

    # Hex color chaos
    -> { ".test { color: #{'#' * rand(20)}ff0000; }" }, # Multiple hash symbols
    -> { ".test { color: #\x00\x00\x00; }" }, # Null bytes in hex
    -> { ".test { color: ##{'f' * rand(100)}; }" }, # Extremely long hex
    -> { '.test { color: #-ff0000; }' }, # Negative hex
    -> { '.test { color: #ff00; }' }, # Wrong length (5 chars)

    # RGB/RGBA chaos
    -> { ".test { color: rgb(#{-rand(999)}, #{-rand(999)}, #{-rand(999)}); }" }, # Negative RGB
    -> { '.test { color: rgb(NaN, Infinity, -Infinity); }' }, # Special float values
    -> { '.test { color: rgb(1e999, 1e999, 1e999); }' }, # Scientific notation overflow
    -> { ".test { color: rgba(255, 0, 0, #{rand(999)}); }" }, # Alpha > 1
    -> { ".test { color: rgb(255 0 0 / #{-rand(10)}); }" }, # Negative alpha
    -> { ".test { color: rgb(#{'(' * rand(10)}255, 0, 0#{')' * rand(10)}); }" }, # Paren chaos
    -> { ".test { color: rgb(\x00, \x00, \x00); }" }, # Null bytes in RGB
    -> { '.test { color: rgb(255,,,,,0,,,0); }' }, # Multiple commas
    -> { '.test { color: rgb(255 255 255 255 255); }' }, # Too many values

    # HSL/HSLA chaos
    -> { ".test { color: hsl(#{rand(99_999)}deg, 100%, 50%); }" }, # Huge hue
    -> { ".test { color: hsl(-#{rand(999)}deg, #{-rand(999)}%, #{-rand(999)}%); }" }, # All negative
    -> { ".test { color: hsl(0, #{rand(9999)}%, #{rand(9999)}%); }" }, # Percentage overflow
    -> { '.test { color: hsl(NaN, NaN%, NaN%); }' }, # NaN values
    -> { ".test { color: hsla(0, 100%, 50%, \x00); }" }, # Null byte alpha
    -> { '.test { color: hsl(0turn, 100%, 50%); }' }, # Units on saturation/lightness
    -> { '.test { color: hsl(0 0 0); }' }, # Missing percentage signs

    # HWB chaos
    -> { ".test { color: hwb(#{rand(99_999)} #{rand(999)}% #{rand(999)}%); }" }, # Huge values
    -> { ".test { color: hwb(0 #{-rand(999)}% #{-rand(999)}%); }" }, # Negative whiteness/blackness
    -> { '.test { color: hwb(0 200% 200%); }' }, # Both > 100%
    -> { ".test { color: hwb(\x00 \x00 \x00); }" }, # Null bytes

    # Oklab/Oklch chaos
    -> { ".test { color: oklab(#{rand(999)} #{rand(999)} #{rand(999)}); }" }, # Huge Oklab values
    -> { ".test { color: oklab(#{-rand(99)} #{-rand(99)} #{-rand(99)}); }" }, # All negative
    -> { '.test { color: oklab(L L L); }' }, # Non-numeric
    -> { ".test { color: oklch(#{rand(999)} #{rand(999)} #{rand(99_999)}); }" }, # Huge oklch
    -> { ".test { color: oklch(0.5 0.2 #{-rand(999)}); }" }, # Negative hue
    -> { ".test { color: oklab(\x00 \x00 \x00); }" }, # Null bytes in oklab
    -> { ".test { color: oklch(1 1 #{'(' * rand(10)}360#{')' * rand(10)}); }" }, # Paren chaos

    # Lab/LCH chaos
    -> { ".test { color: lab(#{rand(999)}% #{rand(9999)} #{rand(9999)}); }" }, # Huge lab values
    -> { ".test { color: lab(-#{rand(999)}% #{-rand(999)} #{-rand(999)}); }" }, # Negative everything
    -> { ".test { color: lch(#{rand(999)}% #{rand(999)} #{rand(99_999)}); }" }, # Huge lch
    -> { ".test { color: lch(50% -#{rand(999)} 0); }" }, # Negative chroma
    -> { ".test { color: lab(\x00% \x00 \x00); }" }, # Null bytes in lab

    # Alpha channel chaos (all formats)
    -> { css.gsub(%r{/\s*[\d.]+\s*\)}, "/ #{rand(999)} )") }, # Alpha > 1 everywhere
    -> { css.gsub(%r{/\s*[\d.]+\s*\)}, "/ -#{rand(10)} )") }, # Negative alpha everywhere
    -> { css.gsub(%r{/\s*[\d.]+\s*\)}, '/ NaN )') }, # NaN alpha
    -> { css.gsub(%r{/\s*[\d.]+\s*\)}, "/ \x00 )") }, # Null byte alpha

    # Mixed color function chaos
    -> { '.test { color: rgb(oklab(0.5 0 0)); }' }, # Nested color functions
    -> { '.test { color: hsl(lab(50% 0 0)); }' }, # Wrong nesting
    -> { '.test { color: #rgb(255,0,0); }' }, # Hash + function
    -> { '.test { color: lab rgb hsl hwb oklab; }' }, # Function names as values

    # Binary corruption
    lambda {
      pos = rand(css.length)
      css.insert(pos, [0, 255, 222, 173, 190, 239].pack('C*').force_encoding('UTF-8'))
    }, # Binary injection
    -> { css.bytes.map { |b| rand < 0.05 ? rand(256) : b }.pack('C*').force_encoding('UTF-8') }, # Bit flips
    lambda {
      # Null bytes everywhere
      pos = rand(css.length)
      css.insert(pos, "\x00" * rand(10))
    },
    -> { css.gsub(/.{1,10}/) { |m| rand < 0.1 ? "\x00" : m } }, # Random null byte injection

    # Pure garbage
    -> { Array.new(rand(1000)) { rand(256).chr }.join.force_encoding('UTF-8') }, # Random bytes
    -> { "\xFF\xFE#{css}" }, # BOM corruption
    -> { css.tr('a-z', "\x00-\x1A") }, # Control characters

    # Parenthesis hell
    -> { css + ('(' * rand(100)) }, # Unmatched open parens
    -> { css + (')' * rand(100)) }, # Unmatched close parens
    -> { css.gsub('(', '((((').gsub(')', '))))') }, # Paren explosion
    -> { css.tr('({[', '(((').tr(')}]', ')))') }, # All brackets to parens
    -> { "((((((((#{css}))))))))" }, # Deep wrapping
    -> { css.gsub(';', '();();();') }, # Parens in weird places

    # Semicolon/colon chaos
    -> { css.gsub(':', ':::') }, # Triple colons
    -> { css.gsub(';', ';;;;') }, # Quadruple semicolons
    -> { css.tr(':;', ';:') }, # Swap colons and semicolons
    -> { css.gsub(/[;:]/, '') }, # Remove all delimiters

    # Whitespace extremes
    -> { css.gsub(/\s+/, '') }, # Remove ALL whitespace
    -> { css.gsub(/./) { |c| c + (' ' * rand(10)) } }, # Excessive spaces
    -> { css.gsub(/\s/, "\n\n\n\n") }, # Newline explosion
    -> { css.gsub(/\s/, "\t\t\t") }, # Tab explosion
    -> { ("\r\n" * rand(100)) + css }, # Windows line endings spam

    # Comment corruption
    -> { css.gsub('/*', '/*' * rand(5)) }, # Nested comment starts
    -> { "/*#{css}" }, # Unclosed comment
    -> { css.gsub('*/', '') }, # Remove comment ends
    -> { css.gsub(%r{[^/]}, '/**/') }, # Comment EVERYTHING

    # Backslash chaos (escape sequences)
    -> { css.gsub(/.{1,3}/) { |m| rand < 0.2 ? "\\#{m}" : m } }, # Random escapes
    -> { ('\\' * rand(50)) + css }, # Backslash prefix
    -> { css.gsub(/[{};:]/, '\\\\\\\\\1') }, # Escape important chars

    # Unicode chaos
    -> { css + ("\u{FEFF}" * rand(10)) }, # Zero-width no-break space
    -> { css + ("\u{200B}" * rand(10)) }, # Zero-width space
    -> { css.gsub(/\w/) { |c| "#{c}́" } }, # Combining diacritics

    # Length extremes
    -> { css * rand(10) }, # Repeat entire CSS
    -> { css[0..0] * rand(10_000) }, # Repeat first char many times
    -> { css + ('X' * rand(100_000)) } # Massive suffix
  ]

  result = mutations.sample.call
  result = +result # Unfreeze if frozen
  begin
    result.force_encoding('UTF-8')
  rescue StandardError
    result.force_encoding('ASCII-8BIT')
  end
  result
end

# Nesting-specific mutations (applied to clean CSS only, no binary corruption)
def mutate_nesting(css)
  mutations = [
    -> { css.gsub('{', '{ & { ') }, # Add nested & blocks everywhere
    -> { css.gsub(/}/, ' } }') }, # Add extra closing braces after nested
    -> { css.gsub('&', '& & &') }, # Multiply ampersands
    -> { css.delete('&').gsub('.', '&.') }, # Move & to wrong positions
    -> { css.gsub('{', '{ .nested { ') }, # Add implicit nesting everywhere
    -> { css + (' { & .child { color: red; }' * rand(10)) }, # Add unclosed nested blocks
    -> { ".wrapper { #{css} }" }, # Wrap entire CSS in nested block
    -> { css.gsub(/@media/, '@media (garbage) { @media') }, # Corrupt nested @media
    -> { css.gsub('&', '& & & & &') }, # Chain ampersands
    -> { css.gsub(/\.[\w-]+/) { |m| "#{m} { & #{m} { " } + (' }' * css.scan(/\.[\w-]+/).size) }, # Nest all class selectors
    -> { css.gsub(/\{[^{}]*\}/) { |m| "{ & #{m} }" } }, # Wrap blocks in & nesting
    -> { css.gsub(';', '; & .x { color: red; } ') }, # Insert nested rules after semicolons
    -> { ".a { .b { .c { .d { .e { #{css} } } } } }" }, # Deep wrapper nesting
    -> { css.gsub('{', '{ /* & */ { ') } # Comment out nesting markers
  ]

  mutations.sample.call
end

# Stats tracking
stats = {
  total: 0,
  parsed: 0,
  flatten_tested: 0,
  to_s_tested: 0,
  color_converted: 0,
  parse_errors: 0,
  depth_errors: 0,
  size_errors: 0,
  other_errors: 0,
  crashes: 0
}

# Configure timeout based on GC.stress mode
WORKER_TIMEOUT = ENV['FUZZ_GC_STRESS'] == '1' ? 300 : 10 # 5 minutes for GC.stress, 10 seconds normal

puts "Starting CSS parser fuzzer (#{ITERATIONS} iterations)..."
puts "RNG seed: #{RNG_SEED} (use this to reproduce crashes)"
puts "Clean corpus: #{CLEAN_CORPUS.length} samples (for mutations)"
puts "Full corpus: #{CORPUS.length} samples (direct testing)"
puts 'Strategy: 70% mutations, 15% nesting, 10% direct, 5% garbage'
puts "GC.stress: ENABLED (expect 100-1000x slowdown, #{WORKER_TIMEOUT}s timeout)" if ENV['FUZZ_GC_STRESS'] == '1'
puts ''

# Spawn a worker subprocess
def spawn_worker
  # Pass environment explicitly to ensure FUZZ_GC_STRESS is inherited
  env = ENV.to_h
  worker_path = File.join(__dir__, 'worker.rb')
  Open3.popen3(env, RbConfig.ruby, '-Ilib', worker_path)
end

# Send input to worker and check result
# Returns: [:success | :error | :crash, error_message, crashed_input, stderr_output]
def parse_in_worker(stdin, stdout, stderr, wait_thr, input, last_input)
  # Check if worker is still alive BEFORE writing
  unless wait_thr.alive?
    status = wait_thr.value
    signal = status.termsig
    # Worker died on PREVIOUS input, not this one - collect stderr
    stderr_output = begin
      stderr.read_nonblock(100_000)
    rescue StandardError
      ''
    end
    error_msg = signal ? "Signal #{signal} (#{Signal.signame(signal)})" : "Exit code #{status.exitstatus}"
    return [:crash, error_msg, last_input, stderr_output, false, false, false]
  end

  # Send length-prefixed input (non-blocking to handle large inputs)
  # Force binary encoding to avoid encoding conflicts
  data = [input.bytesize].pack('N') + input.b
  total_written = 0
  retries = 0
  max_retries = 100

  while total_written < data.bytesize
    begin
      written = stdin.write_nonblock(data[total_written..])
      total_written += written
      retries = 0 # Reset on successful write
    rescue IO::WaitWritable
      # Pipe buffer full - wait for reader to consume some data
      retries += 1
      if retries > max_retries
        # Worker hung - treat as crash
        return [:crash, 'Worker hung (pipe blocked)', input, '', false, false, false]
      end

      stdin.wait_writable(0.1) # 100ms timeout
      retry
    end
  end

  stdin.flush

  # Wait for response with timeout
  ready = stdout.wait_readable(WORKER_TIMEOUT)

  if ready.nil?
    # Timeout - worker hung, kill it
    begin
      Process.kill('KILL', wait_thr.pid)
    rescue StandardError
      nil
    end
    stderr_output = begin
      stderr.read_nonblock(100_000)
    rescue StandardError
      ''
    end
    [:crash, 'Timeout (infinite loop?)', input, stderr_output, false, false, false]
  elsif !wait_thr.alive?
    # Worker crashed DURING this input
    status = wait_thr.value
    signal = status.termsig
    stderr_output = begin
      stderr.read_nonblock(100_000)
    rescue StandardError
      ''
    end
    error_msg = signal ? "Signal #{signal} (#{Signal.signame(signal)})" : "Exit code #{status.exitstatus}"
    [:crash, error_msg, input, stderr_output, false, false, false]
  else
    # Read response
    response = stdout.gets
    return [:error, nil, nil, nil, false, false, false] if response.nil?

    response = response.force_encoding('UTF-8').scrub.strip

    if ENV['FUZZ_DEBUG'] == '1'
      # Read and print any stderr output (for FUZZ_DEBUG logging)
      begin
        if stderr
          stderr_data = stderr.read_nonblock(100_000)
          $stderr.write(stderr_data) unless stderr_data.empty?
        end
      rescue IO::WaitReadable, EOFError
        # No data available, that's fine
      end
    end

    case response
    when 'PARSE_ERR'
      [:parse_error, nil, nil, nil, false, false, false]
    when /^PARSE/
      # Extract which operations were tested
      flatten_tested = response.include?('+FLATTEN')
      to_s_tested = response.include?('+TOS')
      color_converted = response.include?('+COLOR')
      [:success, nil, nil, nil, flatten_tested, to_s_tested, color_converted]
    when 'DEPTH'
      [:depth_error, nil, nil, nil, false, false, false]
    when 'SIZE'
      [:size_error, nil, nil, nil, false, false, false]
    else
      [:error, nil, nil, nil, false, false, false]
    end
  end
rescue Errno::EPIPE, IOError
  # Pipe broken - worker already dead (check if it died on previous input)
  if wait_thr.alive?
    [:crash, 'Broken pipe', input, '', false, false, false]
  else
    status = wait_thr.value
    signal = status.termsig
    stderr_output = begin
      stderr.read_nonblock(100_000)
    rescue StandardError
      ''
    end
    error_msg = signal ? "Signal #{signal} (#{Signal.signame(signal)})" : "Exit code #{status.exitstatus}"
    [:crash, error_msg, last_input, stderr_output, false, false, false]
  end
end

start_time = Time.now
crash_file = File.join(__dir__, 'fuzz_last_input.css')

# Track last N inputs for debugging freezes
RECENT_INPUTS = [] # rubocop:disable Style/MutableConstant
MAX_RECENT = 20

# Trap Ctrl+C to dump recent inputs
Signal.trap('INT') do
  puts "\n\nInterrupted! Dumping last #{RECENT_INPUTS.length} inputs..."
  RECENT_INPUTS.each_with_index do |input, i|
    filename = File.join(__dir__, "fuzz_recent_#{i}.css")
    File.binwrite(filename, input)
    puts "  #{i}: #{filename} (#{input.bytesize} bytes)"
  end
  exit 1
end

# Spawn initial worker subprocess
stdin, stdout, stderr, wait_thr = spawn_worker
last_input = nil

ITERATIONS.times do |i|
  # Pick a seed and mutate it, or generate pure garbage occasionally
  r = rand
  input = if r < 0.70
            # Normal mutations on clean CSS (70%) - uses regex so needs valid UTF-8
            mutate(CLEAN_CORPUS.sample)
          elsif r < 0.85
            # Nesting-specific mutations on clean CSS (15%)
            mutate_nesting(CLEAN_CORPUS.sample)
          elsif r < 0.95
            # Direct CORPUS samples without mutation (10%) - includes all samples
            CORPUS.sample
          else
            # Pure garbage (5%)
            Array.new(rand(1000)) { rand(256).chr }.join
          end

  stats[:total] += 1

  # Track recent inputs for debugging
  RECENT_INPUTS << input
  RECENT_INPUTS.shift if RECENT_INPUTS.length > MAX_RECENT

  # Send to worker subprocess
  result, error, crashed_input, stderr_output, flatten_tested, to_s_tested, color_converted = parse_in_worker(stdin, stdout, stderr,
                                                                                                              wait_thr, input, last_input)
  last_input = input

  case result
  when :success
    stats[:parsed] += 1
    stats[:flatten_tested] += 1 if flatten_tested
    stats[:to_s_tested] += 1 if to_s_tested
    stats[:color_converted] += 1 if color_converted
  when :parse_error
    stats[:parse_errors] += 1
  when :depth_error
    stats[:depth_errors] += 1
  when :size_error
    stats[:size_errors] += 1
  when :error
    stats[:other_errors] += 1
  when :crash
    stats[:crashes] += 1

    # Use the actual crashed input (might be previous input if worker died between calls)
    actual_crash = crashed_input || input

    # Save crash files
    crash_save = File.join(__dir__, "fuzz_crash_#{Time.now.to_i}.css")
    crash_log = crash_save.sub(/\.css$/, '.log')

    File.binwrite(crash_save, actual_crash)
    File.binwrite(crash_file, actual_crash) # Also save as last input for easy debugging

    # Determine if this is a real crash (SEGV) or just broken pipe (worker disappeared)
    is_real_crash = stderr_output && !stderr_output.empty?

    # Save stderr output (stack trace, etc.)
    File.write(crash_log, stderr_output) if is_real_crash

    # Print crash to stderr so it doesn't get overwritten by progress line
    if is_real_crash
      warn "\n!!! CRASH FOUND (SEGV) !!!"
      warn "Saved crashing input to: #{crash_save}"
      warn "Saved crash output to: #{crash_log}"
    else
      warn "\n!!! WORKER DIED (#{error}) !!!"
      warn "Saved input to: #{crash_save}"
      warn 'Note: No crash dump (worker may have been OOM-killed or died on previous input)'
    end
    warn "Reproduce with: ruby scripts/fuzz_css_parser.rb #{ITERATIONS} #{RNG_SEED}"
    warn "Input size: #{actual_crash.length} bytes"
    warn "Input preview: #{actual_crash.inspect[0..200]}"
    warn "Error: #{error}" if is_real_crash
    if crashed_input != input && crashed_input
      warn 'Note: Crash detected on PREVIOUS input (worker died before processing current input)'
    end
    warn ''

    # Respawn worker to continue fuzzing
    begin
      stdin.close
    rescue StandardError
      nil
    end
    begin
      stdout.close
    rescue StandardError
      nil
    end
    begin
      stderr.close
    rescue StandardError
      nil
    end
    stdin, stdout, stderr, wait_thr = spawn_worker
  end

  # Progress
  next unless ((i + 1) % 1000).zero?

  elapsed = Time.now - start_time
  rate = (i + 1) / elapsed

  # Get worker memory usage (cross-platform)
  rss_mb = begin
    if File.exist?("/proc/#{wait_thr.pid}/status")
      # Linux: read from /proc filesystem
      status = File.read("/proc/#{wait_thr.pid}/status")
      if status =~ /VmRSS:\s+(\d+)\s+kB/
        Regexp.last_match(1).to_i / 1024.0
      else
        0.0
      end
    else
      # macOS/BSD: use ps command
      rss_kb = `ps -o rss= -p #{wait_thr.pid}`.strip.to_i
      rss_kb / 1024.0
    end
  rescue StandardError
    0.0
  end

  progress = "#{(i + 1).to_s.rjust(6)}/#{ITERATIONS}"
  iter_rate = "(#{rate.round(1).to_s.rjust(6)} iter/sec)"
  parsed = "Parsed: #{stats[:parsed].to_s.rjust(5)}"
  flattened = "Flattened: #{stats[:flatten_tested].to_s.rjust(5)}"
  to_s = "ToS: #{stats[:to_s_tested].to_s.rjust(4)}"
  color = "Color: #{stats[:color_converted].to_s.rjust(4)}"
  parse_err = "Err: #{stats[:parse_errors].to_s.rjust(4)}"
  crashes = "Crash: #{stats[:crashes].to_s.rjust(2)}"
  memory = "Mem: #{rss_mb.round(1).to_s.rjust(6)} MB"

  # Use \r to overwrite the same line
  print "\rProgress: #{progress} #{iter_rate} | #{parsed} | #{flattened} | #{to_s} | #{color} | #{parse_err} | #{crashes} | #{memory}"
  $stdout.flush
end

# Print newline after final progress update
puts ''

# Clean up worker subprocess
begin
  stdin.close
rescue StandardError
  nil
end
begin
  stdout.close
rescue StandardError
  nil
end
begin
  stderr.close
rescue StandardError
  nil
end
begin
  Process.kill('TERM', wait_thr.pid)
rescue StandardError
  nil
end
begin
  wait_thr.join
rescue StandardError
  nil
end

elapsed = Time.now - start_time

puts "\n#{'=' * 60}"
puts 'Fuzzing complete!'
puts "Time: #{elapsed.round(2)}s (#{(stats[:total] / elapsed).round(1)} iter/sec)"
puts "Total: #{stats[:total]}"
puts "Parsed: #{stats[:parsed]} (#{(stats[:parsed] * 100.0 / stats[:total]).round(1)}%)"
puts "Flatten tested: #{stats[:flatten_tested]} (#{(stats[:flatten_tested] * 100.0 / stats[:total]).round(1)}%)"
puts "ToS tested: #{stats[:to_s_tested]} (#{(stats[:to_s_tested] * 100.0 / stats[:total]).round(1)}%)"
puts "Color converted: #{stats[:color_converted]} (#{(stats[:color_converted] * 100.0 / stats[:total]).round(1)}%)"
puts "Parse Errors: #{stats[:parse_errors]} (#{(stats[:parse_errors] * 100.0 / stats[:total]).round(1)}%)"
puts "Depth Errors: #{stats[:depth_errors]} (#{(stats[:depth_errors] * 100.0 / stats[:total]).round(1)}%)"
puts "Size Errors: #{stats[:size_errors]} (#{(stats[:size_errors] * 100.0 / stats[:total]).round(1)}%)"
puts "Other Errors: #{stats[:other_errors]} (#{(stats[:other_errors] * 100.0 / stats[:total]).round(1)}%)"
puts "Crashes: #{stats[:crashes]}"
puts '=' * 60

exit(stats[:crashes].positive? ? 1 : 0)
