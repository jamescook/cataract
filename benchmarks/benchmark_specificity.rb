# frozen_string_literal: true

require_relative 'benchmark_harness'
require_relative 'specificity_tests'

# Load the local development version, not installed gem
$LOAD_PATH.unshift File.expand_path('../lib', __dir__)
require 'cataract'

# CSS Specificity Calculation Benchmark
#
# Orchestration only - one subprocess per Implementation. The measuring
# happens in benchmark_specificity_workers.rb.
class SpecificityBenchmark < BenchmarkHarness
  def self.benchmark_name
    'specificity'
  end

  def self.description
    'Time to calculate CSS selector specificity values'
  end

  def self.metadata
    SpecificityTests.metadata
  end

  def sanity_checks
    # calculate_specificity isn't public API - go through Rule#specificity
    # like a real caller would. A fresh Rule each time means specificity is
    # nil, so #specificity always calculates for real rather than returning a
    # memoized value.
    rule = Cataract::Rule.make(id: 0, selector: 'div', declarations: [])
    raise 'Cataract sanity check failed' unless rule.specificity == 1
  end

  def call
    announce_variants
    run_all_variants(File.expand_path('benchmark_specificity_workers.rb', __dir__))
  end
end

# Run if executed directly
SpecificityBenchmark.run if __FILE__ == $PROGRAM_NAME
