# frozen_string_literal: true

require_relative 'benchmark_harness'
require_relative 'flattening_tests'
require_relative 'worker_helpers'

# Load the local development version, not installed gem
$LOAD_PATH.unshift File.expand_path('../lib', __dir__)

# Worker benchmark: Cataract pure Ruby
class MergingCataractPureBenchmark < BenchmarkHarness
  include FlatteningTests
  include WorkerHelpers

  def self.benchmark_name
    'flattening_cataract_pure'
  end

  def self.description
    'CSS flattening with Cataract pure Ruby'
  end

  def self.metadata
    FlatteningTests.metadata
  end

  def self.speedup_config
    FlatteningTests.speedup_config
  end

  def initialize
    super
    self.impl_type = determine_impl_type_with_yjit(:pure, FlatteningTests)
  end
end

# Worker benchmark: Cataract C extension
class MergingCataractNativeBenchmark < BenchmarkHarness
  include FlatteningTests
  include WorkerHelpers

  def self.benchmark_name
    'flattening_cataract_native'
  end

  def self.description
    'CSS flattening with Cataract C extension'
  end

  def self.metadata
    FlatteningTests.metadata
  end

  def self.speedup_config
    FlatteningTests.speedup_config
  end

  def initialize
    super
    self.impl_type = determine_impl_type_with_yjit(:native, FlatteningTests)
  end
end

# CLI entry point - run the appropriate worker
if __FILE__ == $PROGRAM_NAME
  require 'cataract'

  if Cataract::IMPLEMENTATION == :ruby
    MergingCataractPureBenchmark.run(skip_finalize: true)
  else
    MergingCataractNativeBenchmark.run(skip_finalize: true)
  end
end
