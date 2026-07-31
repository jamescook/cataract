# frozen_string_literal: true

require_relative 'benchmark_harness'
require_relative 'specificity_tests'
require_relative 'worker_helpers'

# Load the local development version, not installed gem
$LOAD_PATH.unshift File.expand_path('../lib', __dir__)

# Measures specificity calculation for whichever configuration this process
# was launched as. One class covers every variant: WorkerHelpers reads the
# backend and JIT off the running VM and verifies them, so there is nothing
# per-variant to subclass.
class SpecificityWorkerBenchmark < BenchmarkHarness
  include SpecificityTests
  include WorkerHelpers

  def self.benchmark_name
    'specificity'
  end

  def self.description
    'CSS selector specificity calculation'
  end

  def self.metadata
    SpecificityTests.metadata
  end
end

# CLI entry point
if __FILE__ == $PROGRAM_NAME
  require 'cataract'
  SpecificityWorkerBenchmark.run(skip_finalize: true)
end
