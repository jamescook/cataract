#!/usr/bin/env ruby
# frozen_string_literal: true

require 'json'
require 'erb'
require 'fileutils'
require_relative '../benchmarks/speedup_calculator'

# Generate BENCHMARKS.md from benchmark JSON results
class BenchmarkDocGenerator
  RESULTS_DIR = File.expand_path('../benchmarks/.results', __dir__)
  TEMPLATE_PATH = File.expand_path('../benchmarks/templates/benchmarks.md.erb', __dir__)
  OUTPUT_PATH = File.expand_path('../BENCHMARKS.md', __dir__)

  def initialize(results_dir: RESULTS_DIR, output_path: OUTPUT_PATH, verbose: true)
    @results_dir = results_dir
    @output_path = output_path
    @verbose = verbose
    @metadata = load_metadata
    @parsing_data = load_benchmark_data('parsing')
    @serialization_data = load_benchmark_data('serialization')
    @specificity_data = load_benchmark_data('specificity')
    @flattening_data = load_benchmark_data('flattening')
    @yjit_data = load_benchmark_data('yjit')
  end

  def generate
    # Check if we have any data to generate
    if !@parsing_data && !@serialization_data &&
       !@specificity_data && !@flattening_data && !@yjit_data
      # :nocov:
      if @verbose
        puts 'Warning: No benchmark data found. Run benchmarks first: rake benchmark'
        puts 'Available data files:'
        Dir.glob(File.join(@results_dir, '*.json')).each do |file|
          puts "  - #{File.basename(file)}"
        end
      end
      # :nocov:
      return
    end

    template = ERB.new(File.read(TEMPLATE_PATH), trim_mode: '-')
    output = template.result(binding)

    File.write(@output_path, output)

    return unless @verbose

    # :nocov:
    puts 'Generated BENCHMARKS.md'
    puts '  Included benchmarks:'
    puts '    - Parsing' if @parsing_data
    puts '    - Serialization' if @serialization_data
    puts '    - Specificity' if @specificity_data
    puts '    - Merging' if @flattening_data
    puts '    - YJIT' if @yjit_data

    missing = []
    missing << 'Parsing' unless @parsing_data
    missing << 'Serialization' unless @serialization_data
    missing << 'Specificity' unless @specificity_data
    missing << 'Flattening' unless @flattening_data
    missing << 'YJIT' unless @yjit_data

    return unless missing.any?

    puts '  Missing benchmarks:'
    missing.each { |name| puts "    - #{name}" }
    # :nocov:
  end

  private

  def load_metadata
    metadata_path = File.join(@results_dir, 'metadata.json')
    if File.exist?(metadata_path)
      JSON.parse(File.read(metadata_path))
    else
      # :nocov:
      warn 'Warning: metadata.json not found. Run benchmarks first.'
      {}
      # :nocov:
    end
  end

  def load_benchmark_data(name)
    path = File.join(@results_dir, "#{name}.json")
    return nil unless File.exist?(path)

    JSON.parse(File.read(path))
  rescue JSON::ParserError => e
    # :nocov:
    warn "Warning: Failed to parse #{name}.json: #{e.message}"
    nil
    # :nocov:
  end

  # Formatting helpers for ERB template

  def format_ips(result, short: false)
    ips = result['central_tendency']

    formatted = if ips >= 1_000_000
                  "#{(ips / 1_000_000.0).round(2)}M"
                elsif ips >= 1_000
                  "#{(ips / 1_000.0).round(2)}K"
                else
                  ips.round(1).to_s
                end

    if short
      "#{formatted} i/s"
    else
      time_per_op = format_time_per_op(result)
      "#{formatted} i/s (#{time_per_op})"
    end
  end

  def format_time_per_op(result)
    ips = result['central_tendency']
    time_us = 1_000_000.0 / ips

    if time_us >= 1_000
      "#{(time_us / 1_000).round(2)} ms"
    else
      "#{time_us.round(2)} μs"
    end
  end

  def format_speedup(speedup)
    return "N/A" if speedup.nil?
    "#{speedup.round(2)}x faster"
  end

  def format_number(num)
    num.to_s.reverse.gsub(/(\d{3})(?=\d)/, '\\1,').reverse
  end

  # Calculate speedup using SpeedupCalculator (proper per-test-case averaging)
  # @param data [Hash] Benchmark data with 'results' and 'metadata'
  # @param baseline_matcher [Proc] Matcher for baseline results
  # @param comparison_matcher [Proc] Matcher for comparison results
  # @param test_case_key [Symbol] Key in test_cases to match test case IDs
  # @return [Float, nil] Average speedup or nil if no matches
  def calculate_speedup(data, baseline_matcher:, comparison_matcher:, test_case_key: nil)
    return nil unless data && data['results'] && data['metadata']

    test_cases = data['metadata']['test_cases'] || []

    calculator = SpeedupCalculator.new(
      results: data['results'],
      test_cases: test_cases,
      baseline_matcher: baseline_matcher,
      comparison_matcher: comparison_matcher,
      test_case_key: test_case_key
    )

    speedup_stats = calculator.calculate
    speedup_stats ? speedup_stats['avg'] : nil
  end

  # Generate speedup table for a benchmark
  # @param data [Hash] Benchmark data with 'results' and 'metadata'
  # @param test_case_key [Symbol] Key in test_cases to match test case IDs
  # @return [String] Markdown table rows for speedups
  def speedup_rows(data, test_case_key:)
    return '' unless data

    rows = []

    # Native vs Pure (no YJIT) - from pre-calculated metadata if available
    if data['metadata'] && data['metadata']['speedups']
      rows << "| Native vs Pure (no YJIT) | #{format_speedup(data['metadata']['speedups']['avg'])} (avg) |"
    end

    # Native vs Pure (YJIT)
    native_vs_pure_yjit = calculate_speedup(
      data,
      baseline_matcher: SpeedupCalculator::Matchers.cataract_pure_with_yjit,
      comparison_matcher: SpeedupCalculator::Matchers.cataract_native,
      test_case_key: test_case_key
    )
    rows << "| Native vs Pure (YJIT) | #{format_speedup(native_vs_pure_yjit)} (avg) |" if native_vs_pure_yjit

    # YJIT impact on Pure Ruby
    yjit_impact = calculate_speedup(
      data,
      baseline_matcher: SpeedupCalculator::Matchers.cataract_pure_without_yjit,
      comparison_matcher: SpeedupCalculator::Matchers.cataract_pure_with_yjit,
      test_case_key: test_case_key
    )
    rows << "| YJIT impact on Pure Ruby | #{format_speedup(yjit_impact)} (avg) |" if yjit_impact

    rows.join("\n")
  end

  # Access instance variables for ERB
  attr_reader :metadata, :parsing_data, :serialization_data,
              :specificity_data, :flattening_data, :yjit_data
end

# Run if called directly
# :nocov:
if __FILE__ == $PROGRAM_NAME
  unless Dir.exist?(BenchmarkDocGenerator::RESULTS_DIR)
    puts "Error: No benchmark results found at #{BenchmarkDocGenerator::RESULTS_DIR}"
    puts 'Run benchmarks first: rake benchmark'
    exit 1
  end

  generator = BenchmarkDocGenerator.new
  generator.generate
end
# :nocov:
