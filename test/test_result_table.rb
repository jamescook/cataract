# frozen_string_literal: true

require 'test_helper'
require_relative '../benchmarks/result_table'
require_relative '../benchmarks/implementation'

class TestResultTable < Minitest::Test
  def setup
    @native = Implementation.find(:native, :none)
    @interpreted = Implementation.find(:pure, :none)
    @zjit = Implementation.find(:pure, :zjit)
    @columns = [@native, @interpreted, @zjit]
  end

  def row(id, implementation, ips)
    { 'name' => "#{implementation.backend.label}: #{id}", 'implementation' => implementation.id.to_s,
      'central_tendency' => ips }
  end

  def table(results, test_cases, **)
    ResultTable.new(results: results, test_cases: test_cases, implementations: @columns, **).to_markdown
  end

  def test_headings_come_from_the_implementations_themselves
    markdown = table([row('small', @native, 1000.0)], [{ 'id' => 'small', 'name' => 'Small CSS' }])

    assert_equal '| Test Case | Native |', markdown.lines.first.chomp
  end

  def test_row_header_is_configurable
    markdown = table([row('small', @native, 1000.0)], [{ 'id' => 'small', 'name' => 'Small CSS' }],
                     row_header: 'Configuration')

    assert_includes markdown.lines.first, '| Configuration |'
  end

  def test_renders_one_cell_per_implementation
    results = [row('small', @native, 37_580.0), row('small', @interpreted, 3330.0), row('small', @zjit, 7560.0)]

    markdown = table(results, [{ 'id' => 'small', 'name' => 'Small CSS' }])

    assert_includes markdown, '| Small CSS | 37.58K i/s | 3.33K i/s | 7.56K i/s |'
  end

  def test_a_pairing_that_was_not_run_renders_as_na
    results = [row('small', @native, 1000.0), row('small', @interpreted, 100.0), row('small', @zjit, 200.0),
               row('large', @native, 500.0), row('large', @interpreted, 50.0)]

    markdown = table(results, [{ 'id' => 'large', 'name' => 'Large CSS' }])

    assert_includes markdown, '| Large CSS | 500.0 i/s | 50.0 i/s | N/A |'
  end

  def test_omits_columns_nothing_was_measured_for
    markdown = table([row('small', @native, 1000.0)], [{ 'id' => 'small', 'name' => 'Small CSS' }])

    assert_equal '| Test Case | Native |', markdown.lines.first.chomp
    refute_includes markdown, 'Pure'
  end

  def test_renders_nothing_when_there_are_no_measurements
    assert_equal '', table([], [{ 'id' => 'small', 'name' => 'Small CSS' }])
  end

  # Regression: ids overlap, and matching by substring published one
  # workload's numbers under another workload's name.
  def test_a_test_case_never_borrows_a_longer_ids_numbers
    results = [row('bootstrap_compact', @native, 1050.0), row('compact', @native, 15_900.0)]
    test_cases = [{ 'id' => 'bootstrap_compact', 'name' => 'to_s (Bootstrap)' },
                  { 'id' => 'compact', 'name' => 'to_s (Compact utilities)' }]

    markdown = table(results, test_cases)

    assert_includes markdown, '| to_s (Bootstrap) | 1.05K i/s |'
    assert_includes markdown, '| to_s (Compact utilities) | 15.9K i/s |'
  end
end

class TestOverheadTable < Minitest::Test
  def setup
    @native = Implementation.find(:native, :none)
    @interpreted = Implementation.find(:pure, :none)
    @columns = [@native, @interpreted]
  end

  def row(id, implementation, ips)
    { 'name' => "#{implementation.backend.label}: #{id}", 'implementation' => implementation.id.to_s,
      'central_tendency' => ips }
  end

  def table(results)
    OverheadTable.new(results: results, implementations: @columns,
                      without_id: 'error checking off', with_id: 'error checking on').to_markdown
  end

  def test_reports_one_row_per_implementation
    results = [row('error checking off', @native, 110.0), row('error checking on', @native, 100.0),
               row('error checking off', @interpreted, 120.0), row('error checking on', @interpreted, 100.0)]

    markdown = table(results)

    assert_includes markdown, '| Native | 10.0% slower |'
    assert_includes markdown, '| Pure (no JIT) | 20.0% slower |'
  end

  def test_skips_an_implementation_missing_either_side
    results = [row('error checking off', @native, 110.0), row('error checking on', @native, 100.0),
               row('error checking off', @interpreted, 120.0)]

    markdown = table(results)

    assert_includes markdown, '| Native |'
    refute_includes markdown, '| Pure (no JIT) |'
  end

  def test_renders_nothing_when_no_implementation_has_both_sides
    assert_equal '', table([])
  end
end
