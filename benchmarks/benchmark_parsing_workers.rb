# frozen_string_literal: true

require_relative 'benchmark_harness'
require_relative 'parsing_tests'
require_relative 'worker_helpers'

# Load the local development version, not installed gem
$LOAD_PATH.unshift File.expand_path('../lib', __dir__)

# Worker benchmark: Cataract pure Ruby
class ParsingCataractPureBenchmark < BenchmarkHarness
  include ParsingTests
  include WorkerHelpers

  def self.benchmark_name
    'parsing_cataract_pure'
  end

  def self.description
    'CSS parsing with Cataract pure Ruby'
  end

  def self.metadata
    ParsingTests.metadata
  end

  def self.speedup_config
    ParsingTests.speedup_config
  end

  def initialize
    super
    self.impl_type = determine_impl_type_with_yjit(:pure, ParsingTests)
  end
end

# Worker benchmark: Cataract C extension
class ParsingCataractNativeBenchmark < BenchmarkHarness
  include ParsingTests
  include WorkerHelpers

  def self.benchmark_name
    'parsing_cataract_native'
  end

  def self.description
    'CSS parsing with Cataract C extension'
  end

  def self.metadata
    ParsingTests.metadata
  end

  def self.speedup_config
    ParsingTests.speedup_config
  end

  def initialize
    super
    self.impl_type = determine_impl_type_with_yjit(:native, ParsingTests)
  end
end

# CLI entry point - run the appropriate worker
if __FILE__ == $PROGRAM_NAME
  # Load Cataract (will be pure or native depending on CATARACT_PURE)
  require 'cataract'

  if Cataract::IMPLEMENTATION == :ruby
    ParsingCataractPureBenchmark.run(skip_finalize: true)
  else
    ParsingCataractNativeBenchmark.run(skip_finalize: true)
  end
end
