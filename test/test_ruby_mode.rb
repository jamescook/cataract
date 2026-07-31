# frozen_string_literal: true

require 'test_helper'
require_relative 'support/fake_vm'
require_relative '../benchmarks/ruby_mode'

class TestRubyMode < Minitest::Test
  def test_all_modes_are_distinct_and_named
    assert_equal %i[none yjit zjit], RubyMode::ALL.map(&:id)
    assert_equal RubyMode::ALL.size, RubyMode::ALL.map(&:label).uniq.size
  end

  def test_fetch_accepts_symbol_or_string
    assert_same RubyMode::ZJIT, RubyMode.fetch(:zjit)
    assert_same RubyMode::ZJIT, RubyMode.fetch('zjit')
  end

  def test_fetch_raises_on_unknown_mode
    error = assert_raises(ArgumentError) { RubyMode.fetch(:jit_that_does_not_exist) }

    assert_includes error.message, 'unknown Ruby mode'
    assert_includes error.message, 'none, yjit, zjit'
  end

  def test_each_mode_carries_the_flags_that_launch_it
    assert_equal ['--disable-yjit'], RubyMode::NO_JIT.cli_flags
    assert_equal ['--yjit'], RubyMode::YJIT.cli_flags
    assert_equal ['--zjit'], RubyMode::ZJIT.cli_flags
  end

  # Detection is exercised against a stand-in VM so all three modes are
  # covered, not just whichever one this test process happens to be in.

  def test_detects_yjit
    vm = FakeVM.with(:YJIT)

    assert_same RubyMode::YJIT, RubyMode.active(vm)
  end

  def test_detects_zjit
    vm = FakeVM.with(:ZJIT)

    assert_same RubyMode::ZJIT, RubyMode.active(vm)
  end

  def test_a_vm_with_no_jit_support_at_all_is_no_jit
    assert_same RubyMode::NO_JIT, RubyMode.active(FakeVM.without_jits)
  end

  def test_a_jit_that_is_present_but_switched_off_is_no_jit
    # The exact silent fallback the verification exists to catch: the
    # constant is there, so a naive `defined?` check would call it enabled.
    vm = FakeVM.with(:ZJIT, enabled: false)

    assert_same RubyMode::NO_JIT, RubyMode.active(vm)
  end

  def test_exactly_one_mode_is_active_for_any_vm
    [FakeVM.with(:YJIT), FakeVM.with(:ZJIT), FakeVM.without_jits, RubyVM].each do |vm|
      active = RubyMode::ALL.select { |mode| mode.active?(vm) }

      assert_equal 1, active.size, "expected exactly one active mode, got #{active.map(&:id).inspect}"
    end
  end

  def test_expected_is_nil_when_unset_so_workers_can_run_standalone
    assert_nil RubyMode.expected({})
  end

  def test_expected_reads_the_mode_the_parent_asked_for
    assert_same RubyMode::ZJIT, RubyMode.expected(RubyMode::ENV_VAR => 'zjit')
  end

  def test_verify_returns_the_actual_mode_when_it_matches
    assert_same RubyMode::ZJIT, RubyMode.verify!(actual: RubyMode::ZJIT, expected: RubyMode::ZJIT)
  end

  def test_verify_skips_the_check_when_nothing_was_expected
    assert_same RubyMode::NO_JIT, RubyMode.verify!(actual: RubyMode::NO_JIT, expected: nil)
  end

  def test_verify_raises_when_a_jit_silently_fell_back_to_the_interpreter
    error = assert_raises(RubyMode::Mismatch) do
      RubyMode.verify!(actual: RubyMode::NO_JIT, expected: RubyMode::ZJIT, ruby_description: 'ruby 4.0.6 (test)')
    end

    assert_includes error.message, 'expected to be running under ZJIT'
    assert_includes error.message, "#{RubyMode::ENV_VAR}=zjit"
    assert_includes error.message, 'reports no JIT is active'
    assert_includes error.message, 'ruby 4.0.6 (test)'
  end

  def test_verify_raises_when_the_other_jit_is_active
    assert_raises(RubyMode::Mismatch) do
      RubyMode.verify!(actual: RubyMode::YJIT, expected: RubyMode::ZJIT)
    end
  end

  def test_no_jit_reports_no_stats
    assert_empty RubyMode::NO_JIT.stats(FakeVM.without_jits)
  end

  def test_yjit_stats_are_read_from_its_own_vocabulary
    vm = FakeVM.with(:YJIT, stats: { compiled_iseq_count: 412, compilation_failure: 2,
                                     compile_time_ns: 900, code_region_size: 4096 })

    assert_equal({ 'compiled_iseq_count' => 412, 'failed_iseq_count' => 2,
                   'compile_time_ns' => 900, 'code_region_bytes' => 4096 },
                 RubyMode::YJIT.stats(vm))
  end

  def test_zjit_stats_are_read_from_its_own_vocabulary
    # ZJIT names the same two concepts differently; consumers see only the
    # shared keys, so the two JITs stay comparable release over release.
    vm = FakeVM.with(:ZJIT, stats: { compiled_iseq_count: 208, failed_iseq_count: 3,
                                     compile_time_ns: 700, code_region_bytes: 2048 })

    assert_equal({ 'compiled_iseq_count' => 208, 'failed_iseq_count' => 3,
                   'compile_time_ns' => 700, 'code_region_bytes' => 2048 },
                 RubyMode::ZJIT.stats(vm))
  end

  def test_jit_enabled_is_false_for_a_constant_the_vm_does_not_define
    refute RubyMode.jit_enabled?(FakeVM.without_jits, :YJIT)
  end
end
