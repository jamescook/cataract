# frozen_string_literal: true

require_relative 'benchmark_harness'
require_relative 'specificity_tests'
require_relative 'worker_helpers'

# Load the local development version, not installed gem
$LOAD_PATH.unshift File.expand_path('../lib', __dir__)

# Worker benchmark: css_parser gem
class SpecificityCssParserBenchmark < BenchmarkHarness
  include SpecificityTests
  include WorkerHelpers

  def self.benchmark_name
    'specificity_css_parser'
  end

  def self.description
    'CSS specificity calculation with css_parser gem'
  end

  def self.metadata
    SpecificityTests.metadata
  end

  def self.speedup_config
    SpecificityTests.speedup_config
  end

  def initialize
    super
    self.impl_type = determine_impl_type_with_yjit(:css_parser, SpecificityTests)
  end
end

# Worker benchmark: Cataract pure Ruby
class SpecificityCataractPureBenchmark < BenchmarkHarness
  include SpecificityTests
  include WorkerHelpers

  def self.benchmark_name
    'specificity_cataract_pure'
  end

  def self.description
    'CSS specificity calculation with Cataract pure Ruby'
  end

  def self.metadata
    SpecificityTests.metadata
  end

  def self.speedup_config
    SpecificityTests.speedup_config
  end

  def initialize
    super
    self.impl_type = determine_impl_type_with_yjit(:pure, SpecificityTests)
  end
end

# Worker benchmark: Cataract C extension
class SpecificityCataractNativeBenchmark < BenchmarkHarness
  include SpecificityTests
  include WorkerHelpers

  def self.benchmark_name
    'specificity_cataract_native'
  end

  def self.description
    'CSS specificity calculation with Cataract C extension'
  end

  def self.metadata
    SpecificityTests.metadata
  end

  def self.speedup_config
    SpecificityTests.speedup_config
  end

  def initialize
    super
    self.impl_type = determine_impl_type_with_yjit(:native, SpecificityTests)
  end
end

# CLI entry point - run the appropriate worker
if __FILE__ == $PROGRAM_NAME
  if ENV['SPECIFICITY_CSS_PARSER']
    require 'css_parser'
    SpecificityCssParserBenchmark.run(skip_finalize: true)
  else
    require 'cataract'

    if Cataract::IMPLEMENTATION == :ruby
      SpecificityCataractPureBenchmark.run(skip_finalize: true)
    else
      SpecificityCataractNativeBenchmark.run(skip_finalize: true)
    end
  end
end
