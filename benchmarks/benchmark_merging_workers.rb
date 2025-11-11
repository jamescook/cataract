# frozen_string_literal: true

require_relative 'benchmark_harness'
require_relative 'merging_tests'
require_relative 'worker_helpers'

# Load the local development version, not installed gem
$LOAD_PATH.unshift File.expand_path('../lib', __dir__)

# Worker benchmark: css_parser gem
class MergingCssParserBenchmark < BenchmarkHarness
  include MergingTests
  include WorkerHelpers

  def self.benchmark_name
    'merging_css_parser'
  end

  def self.description
    'CSS merging with css_parser gem'
  end

  def self.metadata
    MergingTests.metadata
  end

  def self.speedup_config
    MergingTests.speedup_config
  end

  def initialize
    super
    self.impl_type = determine_impl_type_with_yjit(:css_parser, MergingTests)
  end
end

# Worker benchmark: Cataract pure Ruby
class MergingCataractPureBenchmark < BenchmarkHarness
  include MergingTests
  include WorkerHelpers

  def self.benchmark_name
    'merging_cataract_pure'
  end

  def self.description
    'CSS merging with Cataract pure Ruby'
  end

  def self.metadata
    MergingTests.metadata
  end

  def self.speedup_config
    MergingTests.speedup_config
  end

  def initialize
    super
    self.impl_type = determine_impl_type_with_yjit(:pure, MergingTests)
  end
end

# Worker benchmark: Cataract C extension
class MergingCataractNativeBenchmark < BenchmarkHarness
  include MergingTests
  include WorkerHelpers

  def self.benchmark_name
    'merging_cataract_native'
  end

  def self.description
    'CSS merging with Cataract C extension'
  end

  def self.metadata
    MergingTests.metadata
  end

  def self.speedup_config
    MergingTests.speedup_config
  end

  def initialize
    super
    self.impl_type = determine_impl_type_with_yjit(:native, MergingTests)
  end
end

# CLI entry point - run the appropriate worker
if __FILE__ == $PROGRAM_NAME
  if ENV['MERGING_CSS_PARSER']
    require 'css_parser'
    MergingCssParserBenchmark.run(skip_finalize: true)
  else
    require 'cataract'

    if Cataract::IMPLEMENTATION == :ruby
      MergingCataractPureBenchmark.run(skip_finalize: true)
    else
      MergingCataractNativeBenchmark.run(skip_finalize: true)
    end
  end
end
