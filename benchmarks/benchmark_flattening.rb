# frozen_string_literal: true

require 'tmpdir'
require_relative 'benchmark_harness'
require_relative 'flattening_tests'

# Load the local development version, not installed gem
$LOAD_PATH.unshift File.expand_path('../lib', __dir__)
require 'cataract'

# CSS Flattening Benchmark
#
# Orchestration only - one subprocess per Implementation. The measuring
# happens in benchmark_flattening_workers.rb.
class FlatteningBenchmark < BenchmarkHarness
  def self.benchmark_name
    'flattening'
  end

  def self.description
    'Time to flatten multiple CSS rule sets with same selector'
  end

  def self.metadata
    FlatteningTests.metadata
  end

  def sanity_checks
    css = ".test { color: black; }\n.test { margin: 10px; }"
    cataract_flattened = Cataract.flatten(Cataract.parse_css(css))
    raise 'Cataract sanity check failed' if cataract_flattened.rules.empty?
  end

  def call
    announce_variants
    Dir.mktmpdir('cataract-flattening') do |dir|
      run_all_variants(File.expand_path('benchmark_flattening_workers.rb', __dir__),
                       compiled_program: compiled_program(dir))
    end
  end

  private

  # The compiled program reads each test case's CSS from a file, so it comes
  # from the same metadata the other implementations measure rather than from
  # a second copy.
  def compiled_program(dir)
    ids = FlatteningTests.metadata['test_cases'].map do |test_case|
      File.write(File.join(dir, "#{test_case['id']}.css"), test_case['css'])
      test_case['id']
    end

    CompiledProgram.new(source: File.expand_path('spinel/flattening.rb', __dir__), args: [dir, *ids])
  end
end

# Run if executed directly
FlatteningBenchmark.run if __FILE__ == $PROGRAM_NAME
