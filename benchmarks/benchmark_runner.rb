# frozen_string_literal: true

require 'benchmark/ips'
require 'json'
require 'fileutils'

# Unified benchmark runner that outputs both human-readable console output
# and structured JSON for documentation generation.
class BenchmarkRunner
  RESULTS_DIR = File.expand_path('.results', __dir__)

  attr_reader :name, :description, :metadata

  # @param name [String] Short name for this benchmark (e.g., "parsing", "specificity")
  # @param description [String] One-line description of what's being measured
  # @param metadata [Hash] Additional metadata (fixture info, test cases, etc.)
  def initialize(name:, description:, metadata: {})
    @name = name
    @description = description
    @metadata = metadata
    @results = []

    FileUtils.mkdir_p(RESULTS_DIR)
  end

  # Run a benchmark-ips block and capture results
  # @yield [Benchmark::IPS::Job] The benchmark-ips job
  def run(&block)
    json_path = File.join(RESULTS_DIR, "#{@name}.json")

    Benchmark.ips do |x|
      # Allow benchmark to configure itself
      yield x

      # Enable JSON output
      x.json!(json_path)
    end

    # Read the generated JSON and enhance with metadata
    raw_data = JSON.parse(File.read(json_path))
    enhanced_data = {
      'name' => @name,
      'description' => @description,
      'metadata' => @metadata,
      'timestamp' => Time.now.iso8601,
      'results' => raw_data
    }

    File.write(json_path, JSON.pretty_generate(enhanced_data))
  end

  # Helper to format results as a comparison hash
  # @param label [String] Label for this result
  # @param baseline [String] Baseline label to compare against
  # @return [Hash] Structured comparison data
  def self.format_comparison(label:, baseline:, results:)
    baseline_result = results.find { |r| r['name'] == baseline }
    comparison_result = results.find { |r| r['name'] == label }

    return nil unless baseline_result && comparison_result

    speedup = comparison_result['central_tendency'].to_f / baseline_result['central_tendency'].to_f

    {
      'label' => label,
      'baseline' => baseline,
      'speedup' => speedup.round(2)
    }
  end
end
