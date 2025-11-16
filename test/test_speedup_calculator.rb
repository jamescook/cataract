# frozen_string_literal: true

require 'test_helper'
require_relative '../benchmarks/speedup_calculator'
require 'json'

class TestSpeedupCalculator < Minitest::Test
  def setup
    @fixtures_dir = File.expand_path('fixtures/benchmarks', __dir__)
  end

  def test_parsing_speedup_calculation
    # Load real parsing benchmark results
    data = JSON.parse(File.read(File.join(@fixtures_dir, 'parsing_sample.json')))

    calculator = SpeedupCalculator.new(
      results: data['results'],
      test_cases: data['metadata']['test_cases'],
      baseline_matcher: SpeedupCalculator::Matchers.cataract_pure_without_yjit,
      comparison_matcher: SpeedupCalculator::Matchers.cataract_native,
      test_case_key: :fixture
    )

    speedups = calculator.calculate

    # Verify speedup stats structure
    assert speedups, 'Speedups should not be nil'
    assert_includes speedups.keys, 'min'
    assert_includes speedups.keys, 'max'
    assert_includes speedups.keys, 'avg'

    # Verify speedup values are positive and reasonable
    assert_operator speedups['min'], :>, 1.0, 'Min speedup should be > 1x'
    assert_operator speedups['max'], :>=, speedups['min'], 'Max speedup should be >= min'
    assert_operator speedups['avg'], :>=, speedups['min'], 'Avg speedup should be >= min'
    assert_operator speedups['avg'], :<=, speedups['max'], 'Avg speedup should be <= max'

    # Verify test cases were annotated with speedups
    data['metadata']['test_cases'].each do |test_case|
      assert test_case.key?('speedup'), "Test case '#{test_case['name']}' should have speedup annotated"
      assert_operator test_case['speedup'], :>, 1.0, "Speedup for '#{test_case['name']}' should be > 1x"
    end
  end

  def test_yjit_speedup_calculation
    # Load real YJIT benchmark results (no test_cases array, just operations)
    data = JSON.parse(File.read(File.join(@fixtures_dir, 'yjit_sample.json')))

    calculator = SpeedupCalculator.new(
      results: data['results'],
      test_cases: data['metadata']['operations'],
      baseline_matcher: SpeedupCalculator::Matchers.without_yjit,
      comparison_matcher: SpeedupCalculator::Matchers.with_yjit,
      test_case_key: nil # No test_case_key for operations array
    )

    speedups = calculator.calculate

    # Verify speedup stats
    assert speedups, 'Speedups should not be nil'
    assert_operator speedups['min'], :>, 0.0, 'Min speedup should be positive'
    assert_operator speedups['max'], :>=, speedups['min']
    assert_operator speedups['avg'], :>=, speedups['min']
    assert_operator speedups['avg'], :<=, speedups['max']
  end

  def test_speedup_calculation_with_sample_data
    # Create minimal sample data for testing pure Ruby vs native
    results = [
      { 'name' => 'pure_without_yjit: test1', 'implementation' => 'pure_without_yjit', 'central_tendency' => 100.0 },
      { 'name' => 'native: test1', 'implementation' => 'native', 'central_tendency' => 500.0 },
      { 'name' => 'pure_without_yjit: test2', 'implementation' => 'pure_without_yjit', 'central_tendency' => 200.0 },
      { 'name' => 'native: test2', 'implementation' => 'native', 'central_tendency' => 800.0 }
    ]

    test_cases = [
      { 'name' => 'Test 1', 'key' => 'test1' },
      { 'name' => 'Test 2', 'key' => 'test2' }
    ]

    calculator = SpeedupCalculator.new(
      results: results,
      test_cases: test_cases,
      baseline_matcher: SpeedupCalculator::Matchers.cataract_pure_without_yjit,
      comparison_matcher: SpeedupCalculator::Matchers.cataract_native,
      test_case_key: :key
    )

    speedups = calculator.calculate

    # Verify calculations
    # test1: 500/100 = 5.0x
    # test2: 800/200 = 4.0x
    assert_in_delta(4.0, speedups['min'])
    assert_in_delta(5.0, speedups['max'])
    assert_in_delta(4.5, speedups['avg'])

    # Verify test cases were annotated
    assert_in_delta(5.0, test_cases[0]['speedup'])
    assert_in_delta(4.0, test_cases[1]['speedup'])
  end

  def test_speedup_calculation_with_no_matches
    # No matching baseline/comparison pairs
    results = [
      { 'name' => 'pure_without_yjit: test1', 'implementation' => 'pure_without_yjit', 'central_tendency' => 100.0 },
      { 'name' => 'other_tool: test2', 'implementation' => 'other', 'central_tendency' => 200.0 }
    ]

    calculator = SpeedupCalculator.new(
      results: results,
      test_cases: [],
      baseline_matcher: SpeedupCalculator::Matchers.cataract_pure_without_yjit,
      comparison_matcher: SpeedupCalculator::Matchers.cataract_native,
      test_case_key: nil
    )

    speedups = calculator.calculate

    # Should return nil when no pairs found
    assert_nil speedups
  end

  def test_matchers
    # Test cataract pure matchers
    assert SpeedupCalculator::Matchers.cataract_pure_without_yjit.call({ 'implementation' => 'pure_without_yjit' })
    refute SpeedupCalculator::Matchers.cataract_pure_without_yjit.call({ 'implementation' => 'pure_with_yjit' })
    refute SpeedupCalculator::Matchers.cataract_pure_without_yjit.call({ 'implementation' => 'native' })

    assert SpeedupCalculator::Matchers.cataract_pure_with_yjit.call({ 'implementation' => 'pure_with_yjit' })
    refute SpeedupCalculator::Matchers.cataract_pure_with_yjit.call({ 'implementation' => 'pure_without_yjit' })

    # Test cataract native matcher
    assert SpeedupCalculator::Matchers.cataract_native.call({ 'implementation' => 'native' })
    refute SpeedupCalculator::Matchers.cataract_native.call({ 'implementation' => 'pure_without_yjit' })

    # Test cataract matcher (backwards compatibility - matches native)
    assert SpeedupCalculator::Matchers.cataract.call({ 'implementation' => 'native' })
    refute SpeedupCalculator::Matchers.cataract.call({ 'implementation' => 'pure_without_yjit' })

    # Test YJIT matchers
    assert SpeedupCalculator::Matchers.with_yjit.call({ 'implementation' => 'pure_with_yjit' })
    refute SpeedupCalculator::Matchers.with_yjit.call({ 'implementation' => 'pure_without_yjit' })

    assert SpeedupCalculator::Matchers.without_yjit.call({ 'implementation' => 'pure_without_yjit' })
    refute SpeedupCalculator::Matchers.without_yjit.call({ 'implementation' => 'pure_with_yjit' })
  end
end
