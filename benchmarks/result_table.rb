# frozen_string_literal: true

require_relative 'benchmark_formatting'
require_relative 'result_set'

# A markdown table of one measurement per test case per implementation.
#
# Headings and cells are read off the same Implementation objects, so a
# column heading always names what produced its numbers.
class ResultTable
  include BenchmarkFormatting

  # @param results [Array<Hash>] result rows for one benchmark
  # @param test_cases [Array<Hash>] metadata entries, each with 'id' and 'name'
  # @param implementations [Array<Implementation>] columns, in display order
  # @param row_header [String] heading for the leftmost column
  def initialize(results:, test_cases:, implementations:, row_header: 'Test Case')
    @results = ResultSet.new(results)
    @test_cases = test_cases || []
    @implementations = @results.implementations_among(implementations)
    @row_header = row_header
  end

  def to_markdown
    return '' if @implementations.empty?

    [heading_row, divider_row, *body_rows].join("\n")
  end

  private

  def heading_row
    row(@row_header, @implementations.map(&:column_label))
  end

  def divider_row
    row('-' * @row_header.length, @implementations.map { |impl| '-' * impl.column_label.length })
  end

  def body_rows
    @test_cases.map do |test_case|
      cells = @implementations.map do |implementation|
        format_ips(@results.find(test_case['id'], implementation), short: true)
      end
      row(test_case['name'], cells)
    end
  end

  def row(first, rest)
    "| #{[first, *rest].join(' | ')} |"
  end
end

# A markdown table of what enabling a feature costs each implementation,
# measured as the gap between two test cases of the same benchmark.
class OverheadTable
  include BenchmarkFormatting

  # @param without_id [String] test case id measured with the feature off
  # @param with_id [String] test case id measured with the feature on
  def initialize(results:, implementations:, without_id:, with_id:)
    @results = ResultSet.new(results)
    @implementations = @results.implementations_among(implementations)
    @without_id = without_id
    @with_id = with_id
  end

  def to_markdown
    rows = @implementations.filter_map do |implementation|
      without = @results.find(@without_id, implementation)
      with = @results.find(@with_id, implementation)
      next unless without && with

      "| #{implementation.column_label} | #{format_overhead(without, with)} |"
    end
    return '' if rows.empty?

    ['| Implementation | Overhead |', '|----------------|----------|', *rows].join("\n")
  end
end
