# frozen_string_literal: true

require 'test_helper'
require_relative '../benchmarks/speedup_calculator'
require_relative '../benchmarks/implementation'

class TestSpeedupCalculator < Minitest::Test
  def setup
    @native = Implementation.find(:native, :none)
    @interpreted = Implementation.find(:pure, :none)
    @yjit = Implementation.find(:pure, :yjit)
    @zjit = Implementation.find(:pure, :zjit)
  end

  def row(id, implementation, ips)
    { 'name' => "#{implementation.backend.label}: #{id}", 'implementation' => implementation.id.to_s,
      'central_tendency' => ips }
  end

  def calculate(results, baseline:, comparison:, test_cases: [])
    SpeedupCalculator.new(results: results, test_cases: test_cases,
                          baseline: baseline, comparison: comparison).calculate
  end

  def test_reports_the_spread_across_test_cases
    results = [row('small', @interpreted, 100.0), row('small', @native, 1000.0),
               row('large', @interpreted, 100.0), row('large', @native, 500.0)]

    stats = calculate(results, baseline: @interpreted, comparison: @native)

    assert_in_delta(5.0, stats['min'])
    assert_in_delta(10.0, stats['max'])
    assert_in_delta(7.5, stats['avg'])
  end

  def test_a_comparison_that_lost_yields_a_ratio_below_one
    results = [row('small', @yjit, 100.0), row('small', @zjit, 80.0)]

    assert_in_delta(0.8, calculate(results, baseline: @yjit, comparison: @zjit)['avg'])
  end

  def test_annotates_each_test_case_with_its_own_speedup
    results = [row('small', @interpreted, 100.0), row('small', @native, 1000.0)]
    test_cases = [{ 'id' => 'small', 'name' => 'Small CSS' }]

    calculate(results, test_cases: test_cases, baseline: @interpreted, comparison: @native)

    assert_in_delta(10.0, test_cases.first['speedup'])
  end

  def test_skips_test_cases_only_one_side_measured
    results = [row('small', @interpreted, 100.0), row('small', @native, 1000.0),
               row('large', @interpreted, 100.0)]

    assert_in_delta(10.0, calculate(results, baseline: @interpreted, comparison: @native)['avg'])
  end

  def test_returns_nil_when_the_two_share_no_test_case
    results = [row('small', @interpreted, 100.0), row('large', @native, 1000.0)]

    assert_nil calculate(results, baseline: @interpreted, comparison: @native)
  end

  def test_returns_nil_when_there_are_no_results
    assert_nil calculate([], baseline: @interpreted, comparison: @native)
  end

  def test_the_two_jits_are_told_apart_by_implementation_not_by_report_name
    # Both JIT rows carry the same report label; only the stamped
    # implementation distinguishes them.
    results = [row('small', @yjit, 214.8), row('small', @zjit, 127.3)]

    assert_in_delta(0.59, calculate(results, baseline: @yjit, comparison: @zjit)['avg'], 0.01)
    assert_in_delta(1.69, calculate(results, baseline: @zjit, comparison: @yjit)['avg'], 0.01)
  end

  def test_a_test_case_id_containing_a_colon_is_split_at_the_last_one
    results = [{ 'name' => 'cataract pure: a: b', 'implementation' => @interpreted.id.to_s,
                 'central_tendency' => 100.0 },
               { 'name' => 'cataract: a: b', 'implementation' => @native.id.to_s, 'central_tendency' => 200.0 }]

    assert_in_delta(2.0, calculate(results, baseline: @interpreted, comparison: @native)['avg'])
  end
end
