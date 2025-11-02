# frozen_string_literal: true

# Generic speedup calculator for benchmark results
# Compares "baseline" vs "comparison" results and calculates speedup stats
#
# CONVENTION: Result names must use format "tool_name: test_case_id"
# Example: "css_parser: CSS1", "cataract: CSS1"
class SpeedupCalculator
  # @param results [Array<Hash>] Array of benchmark results with 'name' and 'central_tendency'
  # @param test_cases [Array<Hash>] Array of test case metadata to annotate with speedups
  # @param baseline_matcher [Proc] Block that returns true if result is baseline (e.g., css_parser)
  # @param comparison_matcher [Proc] Block that returns true if result is comparison (e.g., cataract)
  # @param test_case_key [Symbol] Key in test_cases hash to match against test case id from result name
  def initialize(results:, test_cases:, baseline_matcher:, comparison_matcher:, test_case_key: nil)
    @results = results
    @test_cases = test_cases
    @baseline_matcher = baseline_matcher
    @comparison_matcher = comparison_matcher
    @test_case_key = test_case_key
  end

  # Calculate speedups and return stats hash
  # Also annotates test_cases with individual speedups if test_case_key provided
  # @return [Hash] { min: Float, max: Float, avg: Float } or nil if no pairs found
  def calculate
    speedups = []

    # Group results by test case (everything after ':')
    grouped = @results.group_by { |result| extract_test_case(result['name']) }

    grouped.each do |test_case_id, group_results|
      baseline = group_results.find(&@baseline_matcher)
      comparison = group_results.find(&@comparison_matcher)

      next unless baseline && comparison

      speedup = comparison['central_tendency'].to_f / baseline['central_tendency']
      speedups << speedup

      # Annotate test case metadata if provided
      if @test_case_key && @test_cases
        test_case = @test_cases.find { |tc| tc[@test_case_key.to_s] == test_case_id }
        test_case['speedup'] = speedup.round(2) if test_case
      end
    end

    return nil if speedups.empty?

    {
      'min' => speedups.min.round(2),
      'max' => speedups.max.round(2),
      'avg' => (speedups.sum / speedups.size).round(2)
    }
  end

  private

  # Extract test case id from result name
  # "css_parser: CSS1" -> "CSS1"
  # "cataract gem: all" -> "all"
  def extract_test_case(name)
    name.split(':').last.strip
  end

  # Common matchers
  class Matchers
    def self.css_parser
      ->(result) { result['name'].include?('css_parser') }
    end

    def self.cataract
      ->(result) { result['name'].include?('cataract') }
    end

    def self.with_yjit
      ->(result) { result['name'].include?('YJIT') && !result['name'].include?('no YJIT') }
    end

    def self.without_yjit
      ->(result) { result['name'].include?('no YJIT') }
    end
  end
end
