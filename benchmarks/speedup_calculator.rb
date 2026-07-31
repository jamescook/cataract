# frozen_string_literal: true

require_relative 'implementation'

# Compares two implementations across every test case they share and reports
# the spread of speedups.
#
# CONVENTION: benchmark-ips report names must be "label: test_case_id", where
# test_case_id exactly matches the 'id' of an entry in the benchmark's
# metadata. Example: "cataract pure: selector lists".
class SpeedupCalculator
  # @param results [Array<Hash>] benchmark result rows
  # @param test_cases [Array<Hash>] test case metadata, annotated in place with per-case speedups
  # @param baseline [Implementation] the implementation being compared against
  # @param comparison [Implementation] the implementation whose speedup is reported
  def initialize(results:, test_cases:, baseline:, comparison:)
    @results = results
    @test_cases = test_cases
    @baseline = baseline
    @comparison = comparison
  end

  # @return [Hash, nil] { 'min' => Float, 'max' => Float, 'avg' => Float }, or
  #   nil when the two implementations share no test case
  def calculate
    speedups = []

    @results.group_by { |result| test_case_id(result) }.each do |id, group|
      baseline = group.find { |result| @baseline.produced?(result) }
      comparison = group.find { |result| @comparison.produced?(result) }
      next unless baseline && comparison

      speedup = comparison['central_tendency'].to_f / baseline['central_tendency']
      speedups << speedup
      annotate(id, speedup)
    end

    return nil if speedups.empty?

    {
      'min' => speedups.min.round(2),
      'max' => speedups.max.round(2),
      'avg' => (speedups.sum / speedups.size).round(2)
    }
  end

  private

  # "cataract pure: selector lists" -> "selector lists"
  def test_case_id(result)
    result['name'].split(':').last.strip
  end

  def annotate(id, speedup)
    return unless @test_cases

    test_case = @test_cases.find { |tc| tc['id'] == id }
    test_case['speedup'] = speedup.round(2) if test_case
  end
end
