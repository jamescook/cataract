# frozen_string_literal: true

# The flattening benchmark's test cases (benchmarks/flattening_tests.rb) as a
# program Spinel can compile. The CSS is not repeated here: the orchestrator
# writes each test case's to <dir>/<id>.css from the same metadata the other
# implementations measure. As there, parsing happens once, outside what is
# measured.
#
# Run as: flattening <dir> <id>...

require 'cataract'
require_relative 'measure'

dir = ARGV[0]

SpinelBench.header

ARGV.drop(1).each do |id|
  sheet = Cataract.parse_css(File.read(File.join(dir, "#{id}.css")))

  SpinelBench.measure(id, 2.0, 5.0) do
    Cataract.flatten(sheet)
  end
end
