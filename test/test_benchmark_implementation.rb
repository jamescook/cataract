# frozen_string_literal: true

require 'test_helper'
require_relative 'support/fake_vm'
require_relative '../benchmarks/implementation'

# Covers the benchmark harness's Implementation (a backend paired with a Ruby
# VM configuration), not Cataract::IMPLEMENTATION - see test_implementation.rb
# for that.
class TestBenchmarkImplementation < Minitest::Test
  def setup
    @native = Implementation.find(:native, :none)
    @interpreted = Implementation.find(:pure, :none)
    @yjit = Implementation.find(:pure, :yjit)
    @zjit = Implementation.find(:pure, :zjit)
  end

  def test_all_is_every_backend_crossed_with_the_modes_it_declares
    assert_equal %i[native_none pure_none pure_yjit pure_zjit], Implementation.all.map(&:id)
  end

  def test_all_only_contains_variants_their_backend_declares
    Implementation.all.each do |implementation|
      assert_includes implementation.backend.modes, implementation.mode
    end
  end

  def test_available_drops_variants_this_ruby_cannot_run
    # A 3.x has YJIT but no ZJIT, so it benchmarks three variants, not four.
    available = Implementation.available(FakeVM.with(:YJIT)).map(&:id)

    assert_equal %i[native_none pure_none pure_yjit], available
  end

  def test_available_is_everything_when_the_ruby_has_both_jits
    ruby_vm = FakeVM.new(YJIT: FakeVM::FakeJit.new(enabled: false),
                         ZJIT: FakeVM::FakeJit.new(enabled: false))

    assert_equal Implementation.all.map(&:id), Implementation.available(ruby_vm).map(&:id)
  end

  def test_id_pairs_both_axes
    assert_equal :pure_zjit, @zjit.id
    assert_equal :native_none, @native.id
  end

  def test_label_omits_the_mode_when_the_backend_only_runs_one_way
    assert_equal 'cataract', @native.label
    assert_equal 'cataract pure (ZJIT)', @zjit.label
    assert_equal 'cataract pure (no JIT)', @interpreted.label
  end

  def test_column_label_matches_the_benchmarks_md_headings
    assert_equal 'Native', @native.column_label
    assert_equal 'Pure (no JIT)', @interpreted.column_label
    assert_equal 'Pure (YJIT)', @yjit.column_label
    assert_equal 'Pure (ZJIT)', @zjit.column_label
  end

  def test_ruby_command_carries_the_modes_flags
    assert_equal ['ruby', '--zjit', 'worker.rb'], @zjit.ruby_command('worker.rb')
    assert_equal ['ruby', '--disable-yjit', 'worker.rb'], @native.ruby_command('worker.rb')
  end

  def test_env_states_the_expectation_on_both_axes
    env = @zjit.env

    assert_equal '1', env[Backend::SELECTION_ENV_VAR]
    assert_equal 'pure', env[Backend::ENV_VAR]
    assert_equal 'zjit', env[RubyMode::ENV_VAR]
  end

  def test_env_unsets_the_pure_selector_for_the_native_backend
    assert_nil @native.env.fetch(Backend::SELECTION_ENV_VAR)
    assert_equal 'native', @native.env[Backend::ENV_VAR]
  end

  def test_result_fields_carry_both_axes_separately
    assert_equal({ 'implementation' => 'pure_zjit', 'backend' => 'pure', 'jit' => 'zjit' },
                 @zjit.result_fields)
  end

  def test_produced_matches_only_its_own_rows
    row = { 'implementation' => 'pure_zjit' }

    assert @zjit.produced?(row)
    refute @yjit.produced?(row)
    refute @interpreted.produced?(row)
  end

  def test_value_equality_so_implementations_can_be_compared_and_hashed
    assert_equal Implementation.find(:pure, :zjit), @zjit
    refute_equal @yjit, @zjit
    assert_equal 1, [Implementation.find(:pure, :zjit), @zjit].uniq.size
  end

  def test_current_pairs_the_loaded_backend_with_the_active_mode
    current = Implementation.current(env: {}, backend: Backend::PURE, mode: RubyMode::ZJIT)

    assert_equal @zjit, current
  end

  def test_current_accepts_a_run_matching_what_was_asked_for
    env = { Backend::ENV_VAR => 'pure', RubyMode::ENV_VAR => 'zjit' }

    assert_equal @zjit, Implementation.current(env: env, backend: Backend::PURE, mode: RubyMode::ZJIT)
  end

  def test_current_refuses_a_run_under_a_mislabeled_jit
    env = { Backend::ENV_VAR => 'pure', RubyMode::ENV_VAR => 'zjit' }

    assert_raises(RubyMode::Mismatch) do
      Implementation.current(env: env, backend: Backend::PURE, mode: RubyMode::NO_JIT)
    end
  end

  def test_current_refuses_a_run_under_a_mislabeled_backend
    env = { Backend::ENV_VAR => 'pure', RubyMode::ENV_VAR => 'none' }

    assert_raises(Backend::Mismatch) do
      Implementation.current(env: env, backend: Backend::NATIVE, mode: RubyMode::NO_JIT)
    end
  end
end
