# frozen_string_literal: true

require_relative 'benchmark_harness'
require_relative 'serialization_tests'

# Load the local development version, not installed gem
$LOAD_PATH.unshift File.expand_path('../lib', __dir__)
require 'cataract'

# CSS Serialization Performance Benchmark
#
# Orchestration only - one subprocess per Implementation. The measuring
# happens in benchmark_serialization_workers.rb.
class SerializationBenchmark < BenchmarkHarness
  def self.benchmark_name
    'serialization'
  end

  def self.description
    'Time to convert parsed CSS back to string format'
  end

  def self.metadata
    SerializationTests.metadata
  end

  def sanity_checks
    bootstrap_path = File.expand_path('../test/fixtures/bootstrap.css', __dir__)
    raise "Bootstrap CSS fixture not found at #{bootstrap_path}" unless File.exist?(bootstrap_path)

    # Verify cataract works
    cataract_sheet = Cataract.parse_css(File.read(bootstrap_path))
    raise 'Cataract sanity check failed' if cataract_sheet.empty?
    raise 'Cataract serialization failed' if cataract_sheet.to_s.empty?
  end

  def call
    announce_variants
    run_all_variants(File.expand_path('benchmark_serialization_workers.rb', __dir__))
  end
end

# Run if executed directly
SerializationBenchmark.run if __FILE__ == $PROGRAM_NAME
