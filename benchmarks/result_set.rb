# frozen_string_literal: true

# The measurements from one benchmark, indexed for lookup by test case and
# implementation.
#
# Lookup is by whole id, never substring: benchmark ids overlap ('shorthand'
# and 'no_shorthand', 'compact' and 'bootstrap_compact'), and a substring
# match returns a different test case's numbers.
class ResultSet
  # Result names follow "label: test_case_id".
  def self.test_case_id(result)
    result['name'].split(':').last.strip
  end

  attr_reader :rows

  def initialize(rows)
    @rows = rows || []
    @index = @rows.to_h { |row| [[self.class.test_case_id(row), row['implementation']], row] }
  end

  # @param test_case_id [String] id from the benchmark's metadata
  # @param implementation [Implementation]
  # @return [Hash, nil] the measurement, or nil if that pairing wasn't run
  def find(test_case_id, implementation)
    @index[[test_case_id, implementation.id.to_s]]
  end

  # The given implementations that produced measurements here, in the order
  # given. Lets a table omit columns nothing was measured for.
  def implementations_among(candidates)
    present = @rows.each_with_object({}) { |row, seen| seen[row['implementation']] = true }
    candidates.select { |implementation| present.key?(implementation.id.to_s) }
  end
end
