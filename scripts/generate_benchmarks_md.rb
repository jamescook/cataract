#!/usr/bin/env ruby
# frozen_string_literal: true

require 'json'
require 'erb'
require 'fileutils'
require_relative '../benchmarks/benchmark_formatting'
require_relative '../benchmarks/implementation'
require_relative '../benchmarks/result_table'
require_relative '../benchmarks/speedup_calculator'

# Generate BENCHMARKS.md from benchmark JSON results.
#
# The template describes layout; the objects describe meaning. Column
# headings, which implementations exist, and which comparisons are worth
# reporting all come from Implementation, so the doc can only ever claim what
# was actually measured.
class BenchmarkDocGenerator
  include BenchmarkFormatting

  RESULTS_DIR = File.expand_path('../benchmarks/.results', __dir__)
  TEMPLATE_PATH = File.expand_path('../benchmarks/templates/benchmarks.md.erb', __dir__)
  OUTPUT_PATH = File.expand_path('../BENCHMARKS.md', __dir__)

  BENCHMARKS = %w[parsing serialization specificity flattening].freeze

  def initialize(results_dir: RESULTS_DIR, output_path: OUTPUT_PATH, verbose: true)
    @results_dir = results_dir
    @output_path = output_path
    @verbose = verbose
    @metadata = load_metadata
    @parsing_data = load_benchmark_data('parsing')
    @serialization_data = load_benchmark_data('serialization')
    @specificity_data = load_benchmark_data('specificity')
    @flattening_data = load_benchmark_data('flattening')
  end

  def generate
    if all_data.compact.empty?
      # :nocov:
      report_no_data if @verbose
      # :nocov:
      return
    end

    template = ERB.new(File.read(TEMPLATE_PATH), trim_mode: '-')
    File.write(@output_path, template.result(binding))

    report_coverage if @verbose
  end

  # Comparisons reported under each benchmark's "Speedups" heading, in order.
  # Each entry is [label, baseline, comparison]; the figure shown is
  # comparison / baseline, so a ratio below 1 reads as "slower".
  def self.speedup_comparisons
    native = Implementation.find(:native, :none)
    interpreted = Implementation.find(:pure, :none)
    yjit = Implementation.find(:pure, :yjit)
    zjit = Implementation.find(:pure, :zjit)

    [
      ["Native vs #{interpreted.column_label}", interpreted, native],
      ["Native vs #{yjit.column_label}", yjit, native],
      ["Native vs #{zjit.column_label}", zjit, native],
      ['YJIT impact on Pure Ruby', interpreted, yjit],
      ['ZJIT impact on Pure Ruby', interpreted, zjit],
      ['ZJIT vs YJIT', yjit, zjit]
    ]
  end

  private

  # Read by the ERB template.
  attr_reader :metadata, :parsing_data, :serialization_data, :specificity_data, :flattening_data

  def all_data
    [@parsing_data, @serialization_data, @specificity_data, @flattening_data]
  end

  def load_metadata
    metadata_path = File.join(@results_dir, 'metadata.json')
    return JSON.parse(File.read(metadata_path)) if File.exist?(metadata_path)

    # :nocov:
    warn 'Warning: metadata.json not found. Run benchmarks first.'
    {}
    # :nocov:
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

  # Template helpers

  # One row per test case, one column per implementation that produced
  # measurements.
  def result_table(data, test_cases: nil, row_header: 'Test Case')
    ResultTable.new(
      results: data['results'],
      test_cases: test_cases || data['metadata']['test_cases'],
      implementations: Implementation.all,
      row_header: row_header
    ).to_markdown
  end

  # What turning a feature on costs, per implementation.
  def overhead_table(data, without_id:, with_id:)
    OverheadTable.new(
      results: data['results'],
      implementations: Implementation.all,
      without_id: without_id,
      with_id: with_id
    ).to_markdown
  end

  def speedup_rows(data)
    return '' unless data

    self.class.speedup_comparisons.filter_map do |label, baseline, comparison|
      speedup = average_speedup(data, baseline: baseline, comparison: comparison)
      "| #{label} | #{format_speedup(speedup)} (avg) |" if speedup
    end.join("\n")
  end

  # @return [Float, nil] mean speedup across the test cases both
  #   implementations measured, or nil if they share none
  def average_speedup(data, baseline:, comparison:)
    return nil unless data && data['results'] && data['metadata']

    SpeedupCalculator.new(
      results: data['results'],
      test_cases: data['metadata']['test_cases'] || [],
      baseline: baseline,
      comparison: comparison
    ).calculate&.fetch('avg')
  end

  # :nocov:
  def report_no_data
    puts 'Warning: No benchmark data found. Run benchmarks first: rake benchmark'
    puts 'Available data files:'
    Dir.glob(File.join(@results_dir, '*.json')).each { |file| puts "  - #{File.basename(file)}" }
  end

  def report_coverage
    included, missing = BENCHMARKS.zip(all_data).partition(&:last)

    puts 'Generated BENCHMARKS.md'
    puts '  Included benchmarks:'
    included.map(&:first).each { |name| puts "    - #{name.capitalize}" }
    return if missing.empty?

    puts '  Missing benchmarks:'
    missing.map(&:first).each { |name| puts "    - #{name.capitalize}" }
  end
  # :nocov:
end

# Run if called directly
# :nocov:
if __FILE__ == $PROGRAM_NAME
  unless Dir.exist?(BenchmarkDocGenerator::RESULTS_DIR)
    puts "Error: No benchmark results found at #{BenchmarkDocGenerator::RESULTS_DIR}"
    puts 'Run benchmarks first: rake benchmark'
    exit 1
  end

  BenchmarkDocGenerator.new.generate
end
# :nocov:
