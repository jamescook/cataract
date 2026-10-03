# frozen_string_literal: true

# The parsing benchmark's test cases (benchmarks/parsing_tests.rb) as a
# program Spinel can compile. Ids, warm-up and measuring time match that file.
#
# Run as: parsing <test/fixtures dir> <benchmarks/fixtures dir>

require 'cataract'
require_relative 'measure'

fixtures = ARGV[0]
benchmark_fixtures = ARGV[1]

css1 = File.read(File.join(fixtures, 'css1_sample.css'))
css2 = File.read(File.join(fixtures, 'css2_sample.css'))
selector_lists_css = File.read(File.join(benchmark_fixtures, 'selector_lists.css'))

SpinelBench.header

SpinelBench.measure('small', 2.0, 5.0) do
  parser = Cataract::Stylesheet.new
  parser.add_block(css1)
end

SpinelBench.measure('medium with @media', 2.0, 5.0) do
  parser = Cataract::Stylesheet.new
  parser.add_block(css2)
end

SpinelBench.measure('selector lists', 2.0, 5.0) do
  parser = Cataract::Stylesheet.new(parser: { selector_lists: true })
  parser.add_block(selector_lists_css)
end

SpinelBench.measure('selector lists (disabled)', 2.0, 5.0) do
  parser = Cataract::Stylesheet.new(parser: { selector_lists: false })
  parser.add_block(selector_lists_css)
end

SpinelBench.measure('error checking off', 2.0, 5.0) do
  parser = Cataract::Stylesheet.new
  parser.add_block(css2)
end

SpinelBench.measure('error checking on', 2.0, 5.0) do
  parser = Cataract::Stylesheet.new(parser: { raise_parse_errors: true })
  parser.add_block(css2)
end
