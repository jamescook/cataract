#!/usr/bin/env ruby
# frozen_string_literal: true

# Benchmark string allocation optimization impact
# This compares parsing performance with rb_str_buf_new vs rb_str_new_cstr
#
# Usage:
#   1. Run without optimization:
#      rake compile && ruby test/benchmarks/benchmark_string_allocation.rb
#
#   2. Recompile with optimization:
#      CFLAGS="-DUSE_STR_BUF_OPTIMIZATION" rake compile
#
#   3. Run with optimization:
#      ruby test/benchmarks/benchmark_string_allocation.rb
#
# The benchmark will automatically detect which version is running and save
# results to a JSON file for comparison.

require 'benchmark/ips'

$LOAD_PATH.unshift File.expand_path('../../lib', __dir__)
require 'cataract'

# State files for benchmark-ips to compare across runs
# Store in project directory to persist between runs
# Use separate files for each test so we only compare like-to-like
RESULTS_DIR = File.expand_path('..', __dir__)
RESULTS_FILE_PARSE = File.join(RESULTS_DIR, 'benchmark_string_allocation_parse.json')
RESULTS_FILE_ITERATE = File.join(RESULTS_DIR, 'benchmark_string_allocation_iterate.json')
RESULTS_FILE_10X = File.join(RESULTS_DIR, 'benchmark_string_allocation_10x.json')

# Large CSS fixture - using Bootstrap 5 CSS for realistic benchmark
LARGE_CSS_FIXTURE = File.read(File.expand_path('../fixtures/bootstrap.css', __dir__))

# Detect which version we're running by checking the compile-time constant
actual_mode = Cataract::STRING_ALLOC_MODE
# Label based on what's actually running (buffer is the default/production mode)
mode_label = actual_mode == :buffer ? "buffer" : "dynamic"

puts "=" * 80
puts "String Allocation Optimization Benchmark"
puts "=" * 80
puts "Ruby version: #{RUBY_VERSION}"
puts "String allocation mode: #{actual_mode.inspect}"
if actual_mode == :buffer
  puts "  → Using rb_str_buf_new (pre-allocated buffers, production default)"
else
  puts "  → Using rb_str_new_cstr (dynamic allocation, disabled for comparison)"
end
puts "=" * 80
puts
puts "This benchmark focuses on at-rules that build selector strings:"
puts "  - @font-face (large descriptor blocks)"
puts "  - @property (selector with prelude)"
puts "  - @keyframes (selector building)"
puts "  - @page (selector with pseudo)"
puts "  - @counter-style (selector with name)"
puts
puts "CSS fixture: #{LARGE_CSS_FIXTURE.lines.count} lines, #{LARGE_CSS_FIXTURE.bytesize} bytes"
puts "=" * 80
puts

parser = Cataract::Parser.new
parser.parse(LARGE_CSS_FIXTURE)
GC.start
# Verify we actually parsed everything
raise "Parse failed" if parser.rules_count == 0

puts "\n" + "=" * 80
puts "TEST 1: Parse CSS with many at-rules"
puts "=" * 80

Benchmark.ips do |x|
  x.config(time: 10, warmup: 2)

  x.report(mode_label) do
    parser = Cataract::Parser.new
    parser.parse(LARGE_CSS_FIXTURE)
  end

  x.save! RESULTS_FILE_PARSE
  x.compare!
end

GC.start

puts "\n" + "=" * 80
puts "TEST 2: Parse + iterate through all rules"
puts "=" * 80

Benchmark.ips do |x|
  x.config(time: 10, warmup: 2)

  x.report(mode_label) do
    parser = Cataract::Parser.new
    parser.parse(LARGE_CSS_FIXTURE)

    count = 0
    parser.each_selector do |selector, declarations, specificity|
      # Force string to be used
      _ = selector.length
      _ = declarations.to_s
      count += 1
    end

    raise "No rules found" if count == 0
  end

  x.save! RESULTS_FILE_ITERATE
  x.compare!
end

GC.start

puts "\n" + "=" * 80
puts "TEST 3: Multiple parse operations (10x)"
puts "=" * 80

Benchmark.ips do |x|
  x.config(time: 10, warmup: 2)

  x.report(mode_label) do
    10.times do
      parser = Cataract::Parser.new
      parser.parse(LARGE_CSS_FIXTURE)
    end
  end

  x.save! RESULTS_FILE_10X
  x.compare!
end

puts "\n" + "=" * 80
puts "Results saved to:"
puts "  - #{RESULTS_FILE_PARSE}"
puts "  - #{RESULTS_FILE_ITERATE}"
puts "  - #{RESULTS_FILE_10X}"
puts ""
puts "To compare dynamic vs buffer (default):"
puts "  1. Run with dynamic: DISABLE_STR_BUF_OPTIMIZATION=1 rake compile && ruby test/benchmarks/benchmark_string_allocation.rb"
puts "  2. Run with buffer:  rake compile && ruby test/benchmarks/benchmark_string_allocation.rb"
puts "  3. Each test will automatically compare buffer vs dynamic"
puts ""
puts "The benchmark verifies the compilation mode via Cataract::STRING_ALLOC_MODE"
puts "  :dynamic = rb_str_new_cstr (dynamic allocation)"
puts "  :buffer  = rb_str_buf_new (pre-allocated, production default)"
puts "=" * 80
