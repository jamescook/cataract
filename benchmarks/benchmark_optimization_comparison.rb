#!/usr/bin/env ruby
# frozen_string_literal: true

require 'benchmark/ips'
require 'optparse'

# Load the local development version, not installed gem
$LOAD_PATH.unshift File.expand_path('../lib', __dir__)
require 'cataract'

# =============================================================================
# Generic Optimization Comparison Benchmark
# =============================================================================
#
# This benchmark compares performance between different compile-time
# optimizations using benchmark-ips's hold! functionality.
#
# Usage:
#   1. Compile with baseline configuration:
#      $ rake clean compile
#      $ ruby test/benchmarks/benchmark_optimization_comparison.rb --baseline
#
#   2. In same terminal, compile with optimization:
#      $ rake clean && env USE_LIKELY_UNLIKELY=1 rake compile
#      $ ruby test/benchmarks/benchmark_optimization_comparison.rb --optimized
#
#   3. benchmark-ips will show comparison results from both runs
#
# The benchmark tests merge/cascade performance on bootstrap.css (~10k rules).
# =============================================================================

module OptimizationBenchmark
  def self.run(variant: nil)
    puts '=' * 80
    puts 'OPTIMIZATION COMPARISON BENCHMARK'
    puts '=' * 80

    # Display current compile-time flags
    puts "\nCurrently compiled with:"
    Cataract::COMPILE_FLAGS.each do |flag, enabled|
      status = enabled ? '✓ ENABLED' : '✗ disabled'
      puts "  #{flag}: #{status}"
    end
    puts ''

    # Load bootstrap.css fixture
    fixtures_dir = File.expand_path('../test/fixtures', __dir__)
    bootstrap_css_path = File.join(fixtures_dir, 'bootstrap.css')

    unless File.exist?(bootstrap_css_path)
      puts "❌ ERROR: bootstrap.css not found at #{bootstrap_css_path}"
      exit 1
    end

    bootstrap_css = File.read(bootstrap_css_path)
    puts 'Test file: bootstrap.css'
    puts "  Lines: #{bootstrap_css.lines.count}"
    puts "  Size: #{bootstrap_css.bytesize} bytes (#{(bootstrap_css.bytesize / 1024.0).round(1)} KB)"

    # Parse once to get rules for merge benchmark
    puts "\nParsing bootstrap.css to get rules..."
    parser = Cataract::Stylesheet.new
    begin
      parser.add_block(bootstrap_css)
      rules = parser.instance_variable_get(:@raw_rules) # Get raw rules array
      puts "  ✅ Parsed successfully (#{rules.length} rules)"
    rescue StandardError => e
      puts "  ❌ ERROR: Failed to parse: #{e.message}"
      exit 1
    end

    # Verify merge works before benchmarking
    puts "\nVerifying merge..."
    begin
      merged = Cataract.apply_cascade(rules)
      puts "  ✅ Merged successfully (#{merged.length} declarations)"
    rescue StandardError => e
      puts "  ❌ ERROR: Failed to merge: #{e.message}"
      exit 1
    end

    # Auto-detect variant if not specified
    if variant.nil?
      # Check any optimization flag
      has_optimization = Cataract::COMPILE_FLAGS.any? do |flag, enabled|
        enabled && flag != :str_buf_optimization && flag != :debug
      end
      variant = has_optimization ? 'optimized' : 'baseline'
    end

    puts "\n#{'=' * 80}"
    puts "RUNNING BENCHMARK (variant: #{variant})"
    puts '=' * 80
    puts 'Timing: 20s measurement, 5s warmup'
    puts ''

    Benchmark.ips do |x|
      x.config(time: 20, warmup: 5)

      x.report("merge_bootstrap_#{variant}") do
        Cataract.apply_cascade(rules)
      end
    end

    puts "\n#{'=' * 80}"
    puts "DONE - #{variant}"
    puts '=' * 80
  end

  def self.print_usage
    puts <<~USAGE
      Usage: #{$PROGRAM_NAME}

      This benchmark will automatically detect which variant is compiled
      and run the appropriate test.

      Workflow:
        # 1. Build baseline
        rake clean && rake compile
        ruby test/benchmarks/benchmark_optimization_comparison.rb --baseline

        # 2. Build with optimization (e.g., LIKELY/UNLIKELY)
        rake clean && USE_LIKELY_UNLIKELY=1 rake compile
        ruby test/benchmarks/benchmark_optimization_comparison.rb --optimized

        # 3. Compare results (benchmark-ips will show comparison automatically)

      Specific optimization flags:
        LIKELY/UNLIKELY:
          USE_LIKELY_UNLIKELY=1 rake compile

        Loop unrolling (raw CFLAGS still work):
          CFLAGS="-funroll-loops" rake compile

        Aggressive optimization:
          CFLAGS="-O3 -march=native -funroll-loops" rake compile
    USAGE
  end
end

# =============================================================================
# Main
# =============================================================================

if __FILE__ == $PROGRAM_NAME
  require 'optparse'

  variant = nil

  OptionParser.new do |opts|
    opts.banner = "Usage: #{$PROGRAM_NAME} [options]"

    opts.on('--baseline', 'Run benchmark labeled as baseline') do
      variant = 'baseline'
    end

    opts.on('--optimized', 'Run benchmark labeled as optimized') do
      variant = 'optimized'
    end

    opts.on('-h', '--help', 'Show this help message') do
      OptimizationBenchmark.print_usage
      exit 0
    end
  end.parse!

  OptimizationBenchmark.run(variant: variant)
end
