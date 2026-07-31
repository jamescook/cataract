# frozen_string_literal: true

# Exercises the pure Ruby backend under a real WebAssembly/WASI runtime.
#
# Run by .github/workflows/ci-wasm.yml, not by `rake test`. It uses plain
# raises rather than minitest so it depends on nothing beyond the stdlib the
# ruby.wasm distribution ships - gem resolution is its own source of failure
# and isn't what this is measuring.
#
# WASI 0.2 defines wasi:sockets, but ruby.wasm's prebuilt binaries target
# preview1, which has no connect or DNS, and they ship no socket extension
# either - so net/http and resolv can't load, and the C extension isn't built
# for wasm at all. What must work is everything that doesn't need them:
# parsing, serializing, flattening, specificity, and import resolution through
# a caller-supplied fetcher or the filesystem.

require 'cataract'

@failures = []

def check(name)
  result = yield
  raise "returned #{result.inspect}" unless result

  puts "  ok   #{name}"
rescue StandardError, LoadError => e
  @failures << "#{name}: #{e.class}: #{e.message}"
  puts "  FAIL #{name}: #{e.class}: #{e.message}"
end

puts "ruby #{RUBY_VERSION} #{RUBY_PLATFORM} (#{RUBY_ENGINE})"
puts "cataract backend: #{Cataract::IMPLEMENTATION}"
raise 'expected the pure Ruby backend under WASI' unless Cataract::IMPLEMENTATION == :ruby

puts "\nno networking stdlib should be loaded by require alone"
check('net/http, open-uri, resolv all absent') do
  $LOADED_FEATURES.grep(%r{/(net/http|open-uri|resolv|ssrf_filter)}).empty?
end

puts "\nparsing"
check('basic rule') { Cataract::Stylesheet.parse('body { color: red; }').rules_count == 1 }
check('media query') { Cataract::Stylesheet.parse('@media print { a { color: #000; } }').rules_count == 1 }
check('nesting') { Cataract::Stylesheet.parse('.a { color: red; .b { color: blue; } }').rules_count.positive? }
check('at-rules preserved') { Cataract::Stylesheet.parse('@supports (display: grid) { .g { display: grid; } }').to_s.include?('@supports') }

puts "\nserializing"
check('to_s round-trips') do
  Cataract::Stylesheet.parse('body { color: red; }').to_s.include?('color: red')
end
check('to_formatted_s') { !Cataract::Stylesheet.parse('body { color: red; }').to_formatted_s.empty? }

puts "\nspecificity"
check('#id beats .class') do
  Cataract::Rule.make(id: 0, selector: '#a', declarations: []).specificity >
    Cataract::Rule.make(id: 1, selector: '.a', declarations: []).specificity
end

puts "\nflattening"
check('cascade resolves') do
  flat = Cataract.flatten(Cataract.parse_css('.a { color: red; } .a { color: blue; }'))
  flat.rules.first.declarations.any? { |d| d.value == 'blue' }
end
check('layered background keeps every layer') do
  flat = Cataract.flatten(Cataract.parse_css('.a { background: url(x.png), url(y.png) }'))
  flat.rules.first.declarations.to_h { |d| [d.property, d.value] }['background'] == 'url(x.png), url(y.png)'
end

puts "\n@import"
check('parses without resolving') do
  Cataract::Stylesheet.parse('@import url("other.css"); body { color: red; }').imports.size == 1
end
check('resolves via a caller-supplied fetcher') do
  fetcher = ->(_url, _opts) { 'h1 { color: blue; }' }
  css = '@import url("https://example.com/other.css"); body { color: red; }'
  Cataract::Stylesheet.parse(css, import: { fetcher: fetcher }).rules_count == 2
end
check('resolves a file:// import from a WASI preopen') do
  dir = File.expand_path('fixtures', __dir__)
  css = '@import url("imported.css"); body { color: red; }'
  sheet = Cataract::Stylesheet.parse(
    css, import: { base_path: dir, allowed_schemes: %w[file], extensions: %w[css] }
  )
  sheet.rules_count == 2
end

puts
if @failures.empty?
  puts 'All WASI checks passed.'
else
  puts "#{@failures.size} failure(s):"
  @failures.each { |f| puts "  - #{f}" }
  exit 1
end
