# frozen_string_literal: true

require 'test_helper'
require 'tmpdir'
require_relative '../benchmarks/benchmark_harness'
require_relative '../benchmarks/result_set'
require_relative '../benchmarks/results_directory'

# End-to-end test of the harness machinery against a fake benchmark that
# measures nothing. Real subprocesses, real result files, real combining -
# just no expensive workload, so this runs in seconds.
#
# This covers the seam that unit tests can't: a benchmark that never launches,
# a variant that lands in the wrong configuration, results that don't get
# stamped or combined.
class TestBenchmarkPlumbing < Minitest::Test
  WORKER = File.expand_path('support/fake_benchmark_worker.rb', __dir__)

  class FakeBenchmark < BenchmarkHarness
    def self.benchmark_name
      'fake'
    end

    def self.description
      'Harness plumbing check'
    end

    def self.metadata
      { 'test_cases' => [{ 'name' => 'Tiny', 'id' => 'tiny' }] }
    end

    def call
      run_all_variants(WORKER)
    end
  end

  def setup
    @tmpdir = Dir.mktmpdir
    @results = ResultsDirectory.new(@tmpdir).create
    @combined = nil
  end

  def teardown
    FileUtils.rm_rf(@tmpdir)
  end

  # Runs the whole pipeline once and memoizes, since every assertion below
  # inspects a different part of the same output.
  def combined
    @combined ||= begin
      capture_io { FakeBenchmark.new(results: @results).call }
      @results.read('fake.json')
    end
  end

  def test_runs_one_subprocess_per_implementation
    produced = combined['results'].map { |row| row['implementation'] }.uniq.sort

    assert_equal Implementation.all.map { |i| i.id.to_s }.sort, produced
  end

  def test_every_result_carries_both_axes
    combined['results'].each do |row|
      implementation = Implementation.all.find { |i| i.produced?(row) }

      refute_nil implementation, "unrecognized implementation #{row['implementation'].inspect}"
      assert_equal implementation.backend.id.to_s, row['backend']
      assert_equal implementation.mode.id.to_s, row['jit']
    end
  end

  def test_jit_runs_report_that_they_compiled_something
    # Guards the case a timing alone can't distinguish: a JIT that was enabled
    # but never compiled the code being measured.
    jitted = combined['results'].reject { |row| row['jit'] == 'none' }

    refute_empty jitted
    jitted.each do |row|
      assert_operator row.dig('jit_stats', 'compiled_iseq_count'), :>, 0,
                      "#{row['implementation']} reported no compiled iseqs"
    end
  end

  def test_interpreter_runs_report_no_jit_stats
    combined['results'].select { |row| row['jit'] == 'none' }.each do |row|
      assert_empty row['jit_stats']
    end
  end

  def test_result_names_follow_the_label_colon_id_convention
    combined['results'].each do |row|
      assert_equal 'tiny', ResultSet.test_case_id(row)
    end
  end

  def test_computes_speedups_between_the_configured_pair
    assert_operator combined['metadata']['speedups']['avg'], :>, 0
  end

  def test_carries_benchmark_identity_into_the_combined_file
    assert_equal 'fake', combined['name']
    assert_equal 'Harness plumbing check', combined['description']
  end

  def test_cleans_up_the_per_variant_worker_files
    combined # run the pipeline

    # metadata.json is written by each worker's setup and is meant to survive;
    # the per-variant fake_<impl>_<case>.json files are not.
    leftovers = @results.glob('fake_*.json').map { |path| File.basename(path) }

    assert_empty leftovers
  end

  def test_writes_nothing_outside_the_results_directory_it_was_given
    combined

    refute_path_exists File.join(ResultsDirectory::DEFAULT_PATH, 'fake.json')
  end

  class FailingBenchmark < FakeBenchmark
    def call
      run_all_variants(File.expand_path('support/no_such_worker.rb', __dir__))
    end
  end

  # Every script `rake benchmark` invokes has to actually start a benchmark
  # when executed. A file that defines its class but never calls .run exits 0
  # immediately, and the whole rake task then "succeeds" in silence.
  ORCHESTRATORS = %w[parsing serialization specificity flattening].freeze
  STUB = File.expand_path('support/entrypoint_stub.rb', __dir__)

  ORCHESTRATORS.each do |name|
    define_method(:"test_#{name}_orchestrator_starts_when_executed") do
      assert_starts_a_benchmark File.expand_path("../benchmarks/benchmark_#{name}.rb", __dir__)
    end

    define_method(:"test_#{name}_worker_starts_when_executed") do
      assert_starts_a_benchmark File.expand_path("../benchmarks/benchmark_#{name}_workers.rb", __dir__)
    end
  end

  def assert_starts_a_benchmark(script)
    output = IO.popen([{ 'CATARACT_PURE' => nil }, 'ruby', '-r', STUB, script], err: %i[child out], &:read)

    assert_match(/ENTRYPOINT /, output,
                 "#{File.basename(script)} exited without starting a benchmark:\n#{output}")
  end

  def test_a_variant_that_fails_aborts_instead_of_reporting_partial_results
    error = assert_raises(RuntimeError) do
      capture_io { FailingBenchmark.new(results: @results).call }
    end

    assert_match(/benchmark failed/, error.message)
    refute_path_exists @results.join('fake.json')
  end
end
