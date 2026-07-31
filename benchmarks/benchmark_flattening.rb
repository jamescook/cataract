# frozen_string_literal: true

require_relative 'benchmark_harness'
require_relative 'flattening_tests'

# Load the local development version, not installed gem
$LOAD_PATH.unshift File.expand_path('../lib', __dir__)
require 'cataract'

# CSS Flattening Benchmark
#
# Orchestration only - one subprocess per Implementation. The measuring
# happens in benchmark_flattening_workers.rb.
class FlatteningBenchmark < BenchmarkHarness
  def self.benchmark_name
    'flattening'
  end

  def self.description
    'Time to flatten multiple CSS rule sets with same selector'
  end

  def self.metadata
    FlatteningTests.metadata
  end

  def sanity_checks
    css = ".test { color: black; }\n.test { margin: 10px; }"
    cataract_flattened = Cataract.flatten(Cataract.parse_css(css))
    raise 'Cataract sanity check failed' if cataract_flattened.rules.empty?
  end

  def call
    announce_variants
    run_all_variants(File.expand_path('benchmark_flattening_workers.rb', __dir__))
  end
end

# Run if executed directly
FlatteningBenchmark.run if __FILE__ == $PROGRAM_NAME
