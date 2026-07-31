# frozen_string_literal: true

require_relative 'benchmark_harness'
require_relative 'parsing_tests'
require_relative 'worker_helpers'

# Load the local development version, not installed gem
$LOAD_PATH.unshift File.expand_path('../lib', __dir__)

# Measures CSS parsing for whichever configuration this process was launched
# as. One class covers every variant: WorkerHelpers reads the backend and JIT
# off the running VM and verifies them, so there is nothing per-variant to
# subclass.
class ParsingWorkerBenchmark < BenchmarkHarness
  include ParsingTests
  include WorkerHelpers

  def self.benchmark_name
    'parsing'
  end

  def self.description
    'CSS parsing'
  end

  def self.metadata
    ParsingTests.metadata
  end
end

# CLI entry point
if __FILE__ == $PROGRAM_NAME
  require 'cataract'
  ParsingWorkerBenchmark.run(skip_finalize: true)
end
