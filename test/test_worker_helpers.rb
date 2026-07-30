# frozen_string_literal: true

require 'test_helper'
require_relative '../benchmarks/worker_helpers'

class TestWorkerHelpers < Minitest::Test
  class DummyTestModule
    def self.yjit_applicable?(base_impl)
      base_impl != :native
    end
  end

  class DummyWorker
    include WorkerHelpers

    attr_accessor :impl_type

    public :determine_impl_type, :verify_jit_mode!
  end

  def setup
    @worker = DummyWorker.new
  end

  def teardown
    ENV.delete('CATARACT_BENCH_JIT')
  end

  def test_native_is_never_checked_regardless_of_env
    ENV['CATARACT_BENCH_JIT'] = 'zjit' # deliberately mismatched - native ignores it

    assert_equal :native, @worker.determine_impl_type(:native, DummyTestModule)
  end

  def test_verify_jit_mode_skips_when_no_expectation_set
    ENV.delete('CATARACT_BENCH_JIT')
    @worker.verify_jit_mode!(:none) # standalone/debug run - no error
  end

  def test_verify_jit_mode_passes_when_actual_matches_expected
    ENV['CATARACT_BENCH_JIT'] = 'zjit'
    @worker.verify_jit_mode!(:zjit) # no error
  end

  def test_verify_jit_mode_raises_when_actual_falls_back_to_none
    # This is the exact failure this check exists to catch: we asked for
    # ZJIT but the process silently fell back to the plain interpreter
    # (e.g. a Ruby build without ZJIT support ignoring --zjit).
    ENV['CATARACT_BENCH_JIT'] = 'zjit'

    error = assert_raises(RuntimeError) { @worker.verify_jit_mode!(:none) }
    expected_message = 'JIT mode mismatch: expected CATARACT_BENCH_JIT=zjit but RubyVM reports ' \
                       "none is active (#{RUBY_DESCRIPTION}) - was this Ruby built with YJIT/ZJIT support?"

    assert_equal expected_message, error.message
  end

  def test_verify_jit_mode_raises_when_actual_is_the_other_jit
    ENV['CATARACT_BENCH_JIT'] = 'yjit'
    assert_raises(RuntimeError) { @worker.verify_jit_mode!(:zjit) }
  end
end
