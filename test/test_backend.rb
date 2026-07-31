# frozen_string_literal: true

require 'test_helper'
require_relative '../benchmarks/backend'

class TestBackend < Minitest::Test
  def test_all_backends_in_display_order
    assert_equal %i[native pure], Backend::ALL.map(&:id)
  end

  def test_fetch_accepts_symbol_or_string
    assert_same Backend::PURE, Backend.fetch(:pure)
    assert_same Backend::PURE, Backend.fetch('pure')
  end

  def test_fetch_raises_on_unknown_backend
    error = assert_raises(ArgumentError) { Backend.fetch(:jruby) }

    assert_includes error.message, 'unknown backend'
    assert_includes error.message, 'native, pure'
  end

  def test_native_declares_one_mode_because_a_jit_cannot_speed_up_c
    assert_equal [RubyMode::NO_JIT], Backend::NATIVE.modes
  end

  def test_pure_declares_every_jit_mode
    assert_equal RubyMode::ALL, Backend::PURE.modes
  end

  def test_selection_env_requests_the_right_backend_at_require_time
    assert_equal '1', Backend::PURE.selection_env[Backend::SELECTION_ENV_VAR]
    assert_nil Backend::NATIVE.selection_env.fetch(Backend::SELECTION_ENV_VAR)
  end

  def test_active_maps_what_cataract_loaded_onto_a_backend
    assert_same Backend::PURE, Backend.active(:ruby)
    assert_same Backend::NATIVE, Backend.active(:native)
  end

  def test_active_defaults_to_the_cataract_actually_loaded_here
    expected = Cataract::IMPLEMENTATION == :ruby ? Backend::PURE : Backend::NATIVE

    assert_same expected, Backend.active
  end

  def test_expected_is_nil_when_unset_so_workers_can_run_standalone
    assert_nil Backend.expected({})
  end

  def test_expected_reads_the_backend_the_parent_asked_for
    assert_same Backend::PURE, Backend.expected(Backend::ENV_VAR => 'pure')
  end

  def test_verify_returns_the_actual_backend_when_it_matches
    assert_same Backend::PURE, Backend.verify!(actual: Backend::PURE, expected: Backend::PURE)
  end

  def test_verify_skips_the_check_when_nothing_was_expected
    assert_same Backend::NATIVE, Backend.verify!(actual: Backend::NATIVE, expected: nil)
  end

  def test_verify_raises_when_the_wrong_backend_loaded
    # Measuring the C extension while believing it's pure Ruby is exactly as
    # misleading as measuring the interpreter while believing it's ZJIT.
    error = assert_raises(Backend::Mismatch) do
      Backend.verify!(actual: Backend::NATIVE, expected: Backend::PURE)
    end

    assert_includes error.message, 'expected to have loaded the cataract pure backend'
    assert_includes error.message, 'reports cataract is loaded'
  end
end
