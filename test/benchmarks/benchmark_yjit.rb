#!/usr/bin/env ruby
# frozen_string_literal: true

# Benchmark Ruby-side operations with YJIT on vs off
# Compares Cataract vs css_parser for operations like property access, merging, etc.

require 'benchmark/ips'
require 'tmpdir'

$LOAD_PATH.unshift File.expand_path('../../lib', __dir__)
require 'cataract'

begin
  require 'css_parser'
  CSS_PARSER_AVAILABLE = true
rescue LoadError
  CSS_PARSER_AVAILABLE = false
  puts "css_parser gem not available - install with: gem install css_parser"
end

# State file for benchmark-ips to compare across runs
RESULTS_FILE = File.join(File.expand_path('../.benchmark_results', __dir__), 'yjit_benchmark.json')

# Sample CSS for parsing
SAMPLE_CSS = <<~CSS
  body { margin: 0; padding: 0; font-family: Arial, sans-serif; }
  .header { color: #333; padding: 20px; background: #f8f9fa; }
  .container { max-width: 1200px; margin: 0 auto; }
  div p { line-height: 1.6; }
  .container > .item { margin-bottom: 20px; }
  h1 + p { margin-top: 0; font-size: 1.2em; }
CSS

puts "=" * 80
puts "Ruby-side Operations Benchmark"
puts "=" * 80
puts "Ruby version: #{RUBY_VERSION}"
if defined?(RubyVM::YJIT.enabled?) && RubyVM::YJIT.enabled?
  puts "YJIT: ✅ Enabled"
else
  puts "YJIT: ❌ Disabled"
end
puts "=" * 80
puts

puts "\n" + "=" * 80
puts "TEST 1: Property Access (get/set)"
puts "=" * 80

Benchmark.ips do |x|
  x.config(time: 3, warmup: 1)

  yjit_label = defined?(RubyVM::YJIT.enabled?) && RubyVM::YJIT.enabled? ? " (YJIT)" : " (no YJIT)"

  x.report("Cataract: property access#{yjit_label}") do
    decls = Cataract::Declarations.new
    decls['color'] = 'red'
    decls['background'] = 'blue'
    decls['font-size'] = '16px'
    decls['margin'] = '10px'
    decls['padding'] = '5px'
    _ = decls['color']
    _ = decls['background']
    _ = decls['font-size']
  end

  if CSS_PARSER_AVAILABLE
    x.report("css_parser: property access#{yjit_label}") do
      parser = CssParser::Parser.new
      parser.add_block!('.test { color: red; background: blue; font-size: 16px; margin: 10px; padding: 5px; }')
      _ = parser.find_by_selector('.test')
    end
  end

  x.save! RESULTS_FILE
  x.compare!
end

puts "\n" + "=" * 80
puts "TEST 2: Declaration Merging"
puts "=" * 80

Benchmark.ips do |x|
  x.config(time: 3, warmup: 1)

  yjit_label = defined?(RubyVM::YJIT.enabled?) && RubyVM::YJIT.enabled? ? " (YJIT)" : " (no YJIT)"

  x.report("Cataract: declaration merging#{yjit_label}") do
    decls1 = Cataract::Declarations.new
    decls1['color'] = 'red'
    decls1['font-size'] = '16px'

    decls2 = Cataract::Declarations.new
    decls2['background'] = 'blue'
    decls2['margin'] = '10px'

    decls1.merge(decls2)
  end

  x.save! RESULTS_FILE
  x.compare!
end

puts "\n" + "=" * 80
puts "TEST 3: CSS String Generation (to_s)"
puts "=" * 80

Benchmark.ips do |x|
  x.config(time: 3, warmup: 1)

  yjit_label = defined?(RubyVM::YJIT.enabled?) && RubyVM::YJIT.enabled? ? " (YJIT)" : " (no YJIT)"

  x.report("Cataract: to_s generation#{yjit_label}") do
    decls = Cataract::Declarations.new
    decls['color'] = 'red'
    decls['background'] = 'blue'
    decls['font-size'] = '16px'
    decls['margin'] = '10px'
    decls['padding'] = '5px'
    decls.to_s
  end

  if CSS_PARSER_AVAILABLE
    x.report("css_parser: to_s generation#{yjit_label}") do
      parser = CssParser::Parser.new
      parser.add_block!('.test { color: red; background: blue; font-size: 16px; margin: 10px; padding: 5px; }')
      parser.to_s
    end
  end

  x.save! RESULTS_FILE
  x.compare!
end

puts "\n" + "=" * 80
puts "TEST 4: Parse + Iterate"
puts "=" * 80

Benchmark.ips do |x|
  x.config(time: 3, warmup: 1)

  yjit_label = defined?(RubyVM::YJIT.enabled?) && RubyVM::YJIT.enabled? ? " (YJIT)" : " (no YJIT)"

  x.report("Cataract: parse + iterate#{yjit_label}") do
    parser = Cataract::Parser.new
    parser.parse(SAMPLE_CSS)
    parser.each_selector do |selector, declarations, specificity|
      _ = declarations
    end
  end

  if CSS_PARSER_AVAILABLE
    x.report("css_parser: parse + iterate#{yjit_label}") do
      parser = CssParser::Parser.new
      parser.add_block!(SAMPLE_CSS)
      parser.each_selector do |selector, declarations, specificity|
        _ = declarations
      end
    end
  end

  x.save! RESULTS_FILE
  x.compare!
end

puts "\n" + "=" * 80
puts "Results saved to: #{RESULTS_FILE}"
puts ""
puts "=" * 80
