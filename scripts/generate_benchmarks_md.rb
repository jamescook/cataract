#!/usr/bin/env ruby
# frozen_string_literal: true

require 'json'
require 'erb'
require 'fileutils'

# Generate BENCHMARKS.md from benchmark JSON results
class BenchmarkDocGenerator
  RESULTS_DIR = File.expand_path('../benchmarks/.results', __dir__)
  TEMPLATE_PATH = File.expand_path('../benchmarks/templates/benchmarks.md.erb', __dir__)
  OUTPUT_PATH = File.expand_path('../BENCHMARKS.md', __dir__)

  def initialize(results_dir: RESULTS_DIR, output_path: OUTPUT_PATH)
    @results_dir = results_dir
    @output_path = output_path
    @metadata = load_metadata
    @premailer_data = load_benchmark_data('premailer')
    @parsing_data = load_benchmark_data('parsing')
    @serialization_data = load_benchmark_data('serialization')
    @specificity_data = load_benchmark_data('specificity')
    @merging_data = load_benchmark_data('merging')
    @yjit_data = load_benchmark_data('yjit')
  end

  def generate
    # Check if we have any data to generate
    if !@premailer_data && !@parsing_data && !@serialization_data &&
       !@specificity_data && !@merging_data && !@yjit_data
      puts '⚠ Warning: No benchmark data found. Run benchmarks first: rake benchmark'
      puts 'Available data files:'
      Dir.glob(File.join(@results_dir, '*.json')).each do |file|
        puts "  - #{File.basename(file)}"
      end
      return
    end

    template = ERB.new(File.read(TEMPLATE_PATH), trim_mode: '-')
    output = template.result(binding)

    File.write(@output_path, output)
    puts '✓ Generated BENCHMARKS.md'
    puts '  Included benchmarks:'
    puts '    - Premailer' if @premailer_data
    puts '    - Parsing' if @parsing_data
    puts '    - Serialization' if @serialization_data
    puts '    - Specificity' if @specificity_data
    puts '    - Merging' if @merging_data
    puts '    - YJIT' if @yjit_data

    missing = []
    missing << 'Premailer' unless @premailer_data
    missing << 'Parsing' unless @parsing_data
    missing << 'Serialization' unless @serialization_data
    missing << 'Specificity' unless @specificity_data
    missing << 'Merging' unless @merging_data
    missing << 'YJIT' unless @yjit_data

    return unless missing.any?

    puts '  Missing benchmarks:'
    missing.each { |name| puts "    - #{name}" }
  end

  private

  def load_metadata
    metadata_path = File.join(@results_dir, 'metadata.json')
    if File.exist?(metadata_path)
      JSON.parse(File.read(metadata_path))
    else
      warn '⚠ Warning: metadata.json not found. Run benchmarks first.' # :nocov:
      {}
    end
  end

  def load_benchmark_data(name)
    path = File.join(@results_dir, "#{name}.json")
    return nil unless File.exist?(path)

    JSON.parse(File.read(path))
  rescue JSON::ParserError => e
    warn "⚠ Warning: Failed to parse #{name}.json: #{e.message}" # :nocov:
    nil
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
    "#{speedup.round(2)}x faster"
  end

  def format_number(num)
    num.to_s.reverse.gsub(/(\d{3})(?=\d)/, '\\1,').reverse
  end

  # Access instance variables for ERB
  attr_reader :metadata, :premailer_data, :parsing_data, :serialization_data,
              :specificity_data, :merging_data, :yjit_data
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
