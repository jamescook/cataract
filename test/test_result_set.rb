# frozen_string_literal: true

require 'test_helper'
require_relative '../benchmarks/result_set'
require_relative '../benchmarks/implementation'

class TestResultSet < Minitest::Test
  def setup
    @pure = Implementation.find(:pure, :none)
    @native = Implementation.find(:native, :none)
  end

  def row(name, implementation, ips)
    { 'name' => name, 'implementation' => implementation.id.to_s, 'central_tendency' => ips }
  end

  def test_extracts_the_test_case_id_from_a_result_name
    assert_equal 'selector lists', ResultSet.test_case_id('name' => 'cataract pure: selector lists')
  end

  def test_finds_a_measurement_by_test_case_and_implementation
    set = ResultSet.new([row('cataract pure: small', @pure, 100.0), row('cataract: small', @native, 900.0)])

    assert_in_delta(100.0, set.find('small', @pure)['central_tendency'])
    assert_in_delta(900.0, set.find('small', @native)['central_tendency'])
  end

  def test_returns_nil_when_a_pairing_was_never_run
    set = ResultSet.new([row('cataract pure: small', @pure, 100.0)])

    assert_nil set.find('small', @native)
    assert_nil set.find('large', @pure)
  end

  # The regression these exact lookups exist to prevent. Real benchmark ids
  # overlap: matching by substring silently returned another test case's
  # numbers, so BENCHMARKS.md published two identical rows for two different
  # workloads.
  def test_an_id_never_matches_a_longer_id_that_contains_it
    set = ResultSet.new([
                          row('cataract pure: bootstrap_compact', @pure, 300.0),
                          row('cataract pure: compact', @pure, 1200.0)
                        ])

    assert_in_delta(1200.0, set.find('compact', @pure)['central_tendency'])
    assert_in_delta(300.0, set.find('bootstrap_compact', @pure)['central_tendency'])
  end

  def test_an_id_never_matches_a_longer_id_that_ends_with_it
    set = ResultSet.new([
                          row('cataract pure: no_shorthand', @pure, 2840.0),
                          row('cataract pure: shorthand', @pure, 12_290.0)
                        ])

    assert_in_delta(12_290.0, set.find('shorthand', @pure)['central_tendency'])
    assert_in_delta(2840.0, set.find('no_shorthand', @pure)['central_tendency'])
  end

  def test_implementations_among_keeps_only_those_with_measurements
    set = ResultSet.new([row('cataract pure: small', @pure, 100.0)])

    assert_equal [@pure], set.implementations_among([@native, @pure])
  end

  def test_implementations_among_preserves_the_order_it_was_given
    set = ResultSet.new([row('cataract pure: small', @pure, 100.0), row('cataract: small', @native, 900.0)])

    assert_equal [@native, @pure], set.implementations_among([@native, @pure])
  end

  def test_tolerates_no_results_at_all
    set = ResultSet.new(nil)

    assert_empty set.rows
    assert_nil set.find('small', @pure)
    assert_empty set.implementations_among([@pure])
  end
end
