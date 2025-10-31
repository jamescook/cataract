# frozen_string_literal: true

require 'benchmark/ips'
require 'json'
require 'fileutils'
require_relative 'system_metadata'
require_relative 'speedup_calculator'

# Base class for all benchmarks. Provides structure and automatic JSON output.
#
# Usage:
#   class MyBenchmark < BenchmarkHarness
#     def self.benchmark_name
#       'my_benchmark'
#     end
#
#     def self.description
#       'What this benchmark measures'
#     end
#
#     def self.metadata
#       { 'key' => 'value' } # Optional metadata for docs
#     end
#
#     def self.sanity_checks
#       # Optional: verify code works before benchmarking
#       raise "Sanity check failed!" unless something_works
#     end
#
#     def self.call
#       run_test_case_1
#       run_test_case_2
#     end
#
#     private
#
#     def self.run_test_case_1
#       benchmark('test_case_1') do |x|
#         x.config(time: 5, warmup: 2)
#         x.report('label') { ... }
#         x.compare!
#       end
#     end
#   end
class BenchmarkHarness
  RESULTS_DIR = File.expand_path('.results', __dir__)

  class << self
    # Abstract methods - must be implemented by subclasses
    def benchmark_name
      raise NotImplementedError, "#{self} must implement .benchmark_name"
    end

    def description
      raise NotImplementedError, "#{self} must implement .description"
    end

    def metadata
      {} # Optional, can be overridden
    end

    def sanity_checks
      # Optional, can be overridden
    end

    def call
      raise NotImplementedError, "#{self} must implement .call"
    end

    # Optional: Define how to calculate speedups for this benchmark
    # Override this to customize speedup calculation
    #
    # IMPORTANT: Result names must follow convention "tool_name: test_case_id"
    #
    # @return [Hash] Configuration for SpeedupCalculator
    #   {
    #     baseline_matcher: Proc,      # Returns true for baseline results
    #     comparison_matcher: Proc,    # Returns true for comparison results
    #     test_case_key: Symbol        # Key in test_cases metadata matching test_case_id
    #   }
    def speedup_config
      # Default: compare css_parser (baseline) vs cataract (comparison)
      # Match to test_cases by 'fixture' key
      {
        baseline_matcher: SpeedupCalculator::Matchers.css_parser,
        comparison_matcher: SpeedupCalculator::Matchers.cataract,
        test_case_key: :fixture
      }
    end

    # Main entry point - handles setup, execution, and cleanup
    def run
      instance = new
      setup
      instance.sanity_checks if instance.respond_to?(:sanity_checks, true)
      instance.call
      finalize(instance)
    rescue StandardError => e
      puts "❌ Benchmark failed: #{e.message}"
      puts e.backtrace.first(5).join("\n")
      exit 1
    end

    private

    def setup
      FileUtils.mkdir_p(RESULTS_DIR)

      # Collect system metadata once per run
      unless File.exist?(File.join(RESULTS_DIR, 'metadata.json'))
        SystemMetadata.collect
      end

      # Print header
      puts "\n\n"
      puts '=' * 80
      puts "#{benchmark_name.upcase.tr('_', ' ')} BENCHMARK"
      puts "Measures: #{description}"
      puts '=' * 80
      puts
    end

    def finalize(instance)
      # Combine all JSON files for this benchmark into one
      return unless instance.instance_variable_defined?(:@json_files) && instance.instance_variable_get(:@json_files)&.any?

      json_files = instance.instance_variable_get(:@json_files)

      combined_data = {
        'name' => benchmark_name,
        'description' => description,
        'metadata' => metadata,
        'timestamp' => Time.now.iso8601,
        'results' => []
      }

      # Read all the individual JSON files
      json_files.each do |filename|
        path = File.join(RESULTS_DIR, filename)
        next unless File.exist?(path)

        data = JSON.parse(File.read(path))
        combined_data['results'].concat(data) if data.is_a?(Array)
      end

      # Calculate speedups using configured strategy
      config = speedup_config
      if config
        calculator = SpeedupCalculator.new(
          results: combined_data['results'],
          test_cases: combined_data['metadata']['test_cases'],
          baseline_matcher: config[:baseline_matcher],
          comparison_matcher: config[:comparison_matcher],
          test_case_key: config[:test_case_key]
        )

        speedup_stats = calculator.calculate
        combined_data['metadata']['speedups'] = speedup_stats if speedup_stats
      end

      # Write combined file
      combined_path = File.join(RESULTS_DIR, "#{benchmark_name}.json")
      File.write(combined_path, JSON.pretty_generate(combined_data))

      # Clean up individual files
      json_files.each do |filename|
        File.delete(File.join(RESULTS_DIR, filename))
      end

      puts "\n✓ Results saved to #{combined_path}"
    end
  end

  # Instance methods
  protected

  def benchmark(test_case_name)
    json_filename = "#{self.class.benchmark_name}_#{test_case_name}.json"
    json_path = File.join(RESULTS_DIR, json_filename)

    Benchmark.ips do |x|
      # Automatically enable JSON output
      x.json!(json_path)

      # Let the benchmark configure and run
      yield x
    end

    # Track that we created this file
    @json_files ||= []
    @json_files << json_filename
  end
end
