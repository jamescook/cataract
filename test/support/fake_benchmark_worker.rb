# frozen_string_literal: true

# A benchmark worker that measures nothing meaningful, on purpose.
#
# It exists so the harness plumbing - launching one subprocess per
# Implementation, verifying each landed in the configuration it was asked for,
# stamping results, combining them, computing speedups - can be tested in
# seconds instead of by running the real benchmarks.
require_relative '../../benchmarks/benchmark_harness'
require_relative '../../benchmarks/worker_helpers'

$LOAD_PATH.unshift File.expand_path('../../lib', __dir__)

module FakeTests
  def self.metadata
    { 'test_cases' => [{ 'name' => 'Tiny', 'id' => 'tiny' }] }
  end

  def call
    benchmark('tiny') do |x|
      # As short as benchmark-ips allows: this measures the harness, not Ruby.
      x.config(time: 0.01, warmup: 0)
      x.report(result_name('tiny')) { 1 + 1 }
    end
  end
end

class FakeWorkerBenchmark < BenchmarkHarness
  include FakeTests
  include WorkerHelpers

  def self.benchmark_name
    'fake'
  end

  def self.description
    'Harness plumbing check'
  end

  def self.metadata
    FakeTests.metadata
  end
end

if __FILE__ == $PROGRAM_NAME
  require 'cataract'
  FakeWorkerBenchmark.run(skip_finalize: true)
end
