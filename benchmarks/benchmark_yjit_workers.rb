# frozen_string_literal: true

require_relative 'benchmark_harness'
require_relative 'yjit_tests'

# Load the local development version, not installed gem
$LOAD_PATH.unshift File.expand_path('../lib', __dir__)
require 'cataract'

# Worker benchmark: YJIT disabled
# Called via subprocess with --disable-yjit flag
class YjitWithoutBenchmark < BenchmarkHarness
  include YjitTests

  def self.benchmark_name
    'yjit_without'
  end

  def self.description
    'Ruby-side operations without YJIT'
  end

  def self.metadata
    YjitTests.metadata
  end

  def self.speedup_config
    YjitTests.speedup_config
  end
end

# Worker benchmark: YJIT enabled
# Called via subprocess with --yjit flag
class YjitWithBenchmark < BenchmarkHarness
  include YjitTests

  def self.benchmark_name
    'yjit_with'
  end

  def self.description
    'Ruby-side operations with YJIT'
  end

  def self.metadata
    YjitTests.metadata
  end

  def self.speedup_config
    YjitTests.speedup_config
  end
end

# CLI entry point - run the appropriate worker based on YJIT status
if __FILE__ == $PROGRAM_NAME
  if defined?(RubyVM::YJIT.enabled?) && RubyVM::YJIT.enabled?
    YjitWithBenchmark.run
  else
    YjitWithoutBenchmark.run
  end
end
