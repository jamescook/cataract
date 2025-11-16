# frozen_string_literal: true

require_relative 'benchmark_harness'
require_relative 'serialization_tests'
require_relative 'worker_helpers'

# Load the local development version, not installed gem
$LOAD_PATH.unshift File.expand_path('../lib', __dir__)

# Worker benchmark: Cataract pure Ruby
class SerializationCataractPureBenchmark < BenchmarkHarness
  include SerializationTests
  include WorkerHelpers

  def self.benchmark_name
    'serialization_cataract_pure'
  end

  def self.description
    'CSS serialization with Cataract pure Ruby'
  end

  def self.metadata
    SerializationTests.metadata
  end

  def self.speedup_config
    SerializationTests.speedup_config
  end

  def initialize
    super
    self.impl_type = determine_impl_type_with_yjit(:pure, SerializationTests)
  end
end

# Worker benchmark: Cataract C extension
class SerializationCataractNativeBenchmark < BenchmarkHarness
  include SerializationTests
  include WorkerHelpers

  def self.benchmark_name
    'serialization_cataract_native'
  end

  def self.description
    'CSS serialization with Cataract C extension'
  end

  def self.metadata
    SerializationTests.metadata
  end

  def self.speedup_config
    SerializationTests.speedup_config
  end

  def initialize
    super
    self.impl_type = determine_impl_type_with_yjit(:native, SerializationTests)
  end
end

# CLI entry point - run the appropriate worker
if __FILE__ == $PROGRAM_NAME
  require 'cataract'

  if Cataract::IMPLEMENTATION == :ruby
    SerializationCataractPureBenchmark.run(skip_finalize: true)
  else
    SerializationCataractNativeBenchmark.run(skip_finalize: true)
  end
end
