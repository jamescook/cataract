# frozen_string_literal: true

# The specificity benchmark's test cases (benchmarks/specificity_tests.rb) as
# a program Spinel can compile. The selectors are not repeated here: the
# orchestrator writes each test case's list to <dir>/<id>.txt, one selector a
# line, from the same metadata the other implementations measure.
#
# The measured block is shaped as it is there - a Hash keyed by selector,
# walked with each_key, through a specificity_of method - so the two do the
# same work per iteration and differ only in what runs it.
#
# Run as: specificity <dir> <id>...

require 'cataract'
require_relative 'measure'

def specificity_of(selector)
  Cataract::Rule.make(id: 0, selector: selector, declarations: []).specificity
end

dir = ARGV[0]

SpinelBench.header

ARGV.drop(1).each do |id|
  selectors = {}
  File.read(File.join(dir, "#{id}.txt")).split("\n").each { |selector| selectors[selector] = 0 }

  SpinelBench.measure(id, 1.0, 2.0) do
    selectors.each_key { |selector| specificity_of(selector) }
  end
end
