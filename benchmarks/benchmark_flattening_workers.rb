# frozen_string_literal: true

require_relative 'benchmark_harness'
require_relative 'flattening_tests'
require_relative 'worker_helpers'

# Load the local development version, not installed gem
$LOAD_PATH.unshift File.expand_path('../lib', __dir__)

# Measures CSS flattening for whichever configuration this process was
# launched as. One class covers every variant: WorkerHelpers reads the
# backend and JIT off the running VM and verifies them, so there is nothing
# per-variant to subclass.
class FlatteningWorkerBenchmark < BenchmarkHarness
  include FlatteningTests
  include WorkerHelpers

  def self.benchmark_name
    'flattening'
  end

  def self.description
    'CSS flattening (cascade)'
  end

  def self.metadata
    FlatteningTests.metadata
  end
end

# CLI entry point
if __FILE__ == $PROGRAM_NAME
  require 'cataract'
  FlatteningWorkerBenchmark.run(skip_finalize: true)
end
