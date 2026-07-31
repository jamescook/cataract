# frozen_string_literal: true

require 'test_helper'
require_relative '../benchmarks/benchmark_formatting'

class TestBenchmarkFormatting < Minitest::Test
  include BenchmarkFormatting

  def result(ips)
    { 'central_tendency' => ips }
  end

  def test_scales_rates_to_thousands_and_millions
    assert_equal '435.4 i/s', format_ips(result(435.4), short: true)
    assert_equal '13.84K i/s', format_ips(result(13_840.0), short: true)
    assert_equal '1.91M i/s', format_ips(result(1_910_000.0), short: true)
  end

  def test_long_form_adds_time_per_operation
    assert_equal '10.0K i/s (100.0 μs)', format_ips(result(10_000.0))
    assert_equal '500.0 i/s (2.0 ms)', format_ips(result(500.0))
  end

  def test_a_missing_measurement_renders_as_na
    assert_equal BenchmarkFormatting::MISSING, format_ips(nil)
    assert_equal BenchmarkFormatting::MISSING, format_speedup(nil)
    assert_equal BenchmarkFormatting::MISSING, format_overhead(nil, result(10.0))
  end

  def test_a_ratio_below_one_reads_as_slower_not_faster
    assert_equal '1.79x slower', format_speedup(0.5596)
    refute_includes format_speedup(0.8), 'faster'
  end

  def test_a_ratio_at_or_above_one_reads_as_faster
    assert_equal '2.0x faster', format_speedup(2.0)
    assert_equal '1.0x faster', format_speedup(1.0)
  end

  def test_overhead_is_the_cost_of_turning_the_feature_on
    assert_equal '10.0% slower', format_overhead(result(110.0), result(100.0))
  end

  def test_overhead_within_a_percent_is_reported_as_noise
    assert_equal '~0% (within noise)', format_overhead(result(100.5), result(100.0))
  end

  def test_overhead_that_comes_out_negative_is_flagged_as_unexpected
    assert_equal '4.8% faster (unexpected)', format_overhead(result(100.0), result(105.0))
  end
end
