# frozen_string_literal: true

require_relative 'benchmark_harness'
require_relative 'parsing_tests'

# Load the local development version, not installed gem
$LOAD_PATH.unshift File.expand_path('../lib', __dir__)
require 'cataract'

# CSS Parsing Performance Benchmark
#
# Orchestration only - one subprocess per Implementation. The measuring
# happens in benchmark_parsing_workers.rb.
class ParsingBenchmark < BenchmarkHarness
  def self.benchmark_name
    'parsing'
  end

  def self.description
    'Time to parse CSS into internal data structures'
  end

  def self.metadata
    ParsingTests.metadata
  end

  def sanity_checks
    # Verify fixtures exist
    fixtures_dir = File.expand_path('../test/fixtures', __dir__)
    css1_path = File.join(fixtures_dir, 'css1_sample.css')
    css2_path = File.join(fixtures_dir, 'css2_sample.css')

    raise "CSS fixture not found: #{css1_path}" unless File.exist?(css1_path)
    raise "CSS fixture not found: #{css2_path}" unless File.exist?(css2_path)

    # Verify cataract works
    parser = Cataract::Stylesheet.new
    parser.add_block('body { color: red; }')
    raise 'Cataract sanity check failed' if parser.rules_count.zero?
  end

  def call
    announce_variants
    run_all_variants(File.expand_path('benchmark_parsing_workers.rb', __dir__))
  end
end

# Run if executed directly
ParsingBenchmark.run if __FILE__ == $PROGRAM_NAME
