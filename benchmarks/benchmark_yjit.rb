#!/usr/bin/env ruby
# frozen_string_literal: true

# Benchmark Ruby-side operations with YJIT on vs off
# Compares Cataract performance with/without YJIT

require 'benchmark/ips'
require 'fileutils'

$LOAD_PATH.unshift File.expand_path('../lib', __dir__)
require 'cataract'

# State file for benchmark-ips to compare across runs
RESULTS_DIR = File.expand_path('.benchmark_results', __dir__)
FileUtils.mkdir_p(RESULTS_DIR)
RESULTS_FILE = File.join(RESULTS_DIR, 'yjit_benchmark.json')

# Sample CSS for parsing
SAMPLE_CSS = <<~CSS
  body { margin: 0; padding: 0; font-family: Arial, sans-serif; }
  .header { color: #333; padding: 20px; background: #f8f9fa; }
  .container { max-width: 1200px; margin: 0 auto; }
  div p { line-height: 1.6; }
  .container > .item { margin-bottom: 20px; }
  h1 + p { margin-top: 0; font-size: 1.2em; }
CSS

puts '=' * 80
puts 'Ruby-side Operations Benchmark'
puts '=' * 80
puts "Ruby version: #{RUBY_VERSION}"
if defined?(RubyVM::YJIT.enabled?) && RubyVM::YJIT.enabled?
  puts 'YJIT: ✅ Enabled'
else
  puts 'YJIT: ❌ Disabled'
end
puts '=' * 80
puts

puts "\n#{'=' * 80}"

Benchmark.ips do |x|
  x.config(time: 3, warmup: 1)

  yjit_label = defined?(RubyVM::YJIT.enabled?) && RubyVM::YJIT.enabled? ? ' (YJIT)' : ' (no YJIT)'

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

  x.save! RESULTS_FILE

  yjit_label = defined?(RubyVM::YJIT.enabled?) && RubyVM::YJIT.enabled? ? ' (YJIT)' : ' (no YJIT)'

  x.report("Cataract: declaration merging#{yjit_label}") do
    decls1 = Cataract::Declarations.new
    decls1['color'] = 'red'
    decls1['font-size'] = '16px'

    decls2 = Cataract::Declarations.new
    decls2['background'] = 'blue'
    decls2['margin'] = '10px'

    decls1.merge(decls2)
  end

  yjit_label = defined?(RubyVM::YJIT.enabled?) && RubyVM::YJIT.enabled? ? ' (YJIT)' : ' (no YJIT)'

  x.report("Cataract: to_s generation#{yjit_label}") do
    decls = Cataract::Declarations.new
    decls['color'] = 'red'
    decls['background'] = 'blue'
    decls['font-size'] = '16px'
    decls['margin'] = '10px'
    decls['padding'] = '5px'
    decls.to_s
  end

  yjit_label = defined?(RubyVM::YJIT.enabled?) && RubyVM::YJIT.enabled? ? ' (YJIT)' : ' (no YJIT)'

  x.report("Cataract: parse + iterate#{yjit_label}") do
    parser = Cataract::Parser.new
    parser.parse(SAMPLE_CSS)
    parser.each_selector do |_selector, declarations, _specificity|
      _ = declarations
    end
  end

  x.save! RESULTS_FILE

  x.compare!
end

puts

if RubyVM::YJIT.enabled?
  # Remove on 2nd run
  puts 'Removing results json'
  FileUtils.rm_f RESULTS_FILE
end
