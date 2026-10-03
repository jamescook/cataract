# frozen_string_literal: true

# The serialization benchmark's test cases (benchmarks/serialization_tests.rb)
# as a program Spinel can compile. Ids, warm-up and measuring time match that
# file; as there, parsing happens once, outside what is measured.
#
# Run as: serialization <test/fixtures dir>

require 'cataract'
require_relative 'measure'

fixtures = ARGV[0]

bootstrap_css = File.read(File.join(fixtures, 'bootstrap.css'))
compact_css = File.read(File.join(fixtures, 'serialization_compact.css'))
nested_css = File.read(File.join(fixtures, 'serialization_nested.css'))
selector_lists_css = File.read(File.join(fixtures, 'serialization_selector_lists.css'))

SpinelBench.header

bootstrap = Cataract.parse_css(bootstrap_css)
SpinelBench.measure('bootstrap_compact', 2.0, 5.0) do
  bootstrap.to_s
end

compact = Cataract.parse_css(compact_css)
SpinelBench.measure('compact', 2.0, 5.0) do
  compact.to_s
end

nested = Cataract.parse_css(nested_css)
SpinelBench.measure('formatted_nested', 2.0, 5.0) do
  nested.to_formatted_s
end

selector_lists = Cataract::Stylesheet.parse(selector_lists_css, parser: { selector_lists: true })
SpinelBench.measure('selector_lists', 2.0, 5.0) do
  selector_lists.to_s
end

media = Cataract::Stylesheet.new
media.add_block(bootstrap_css)
SpinelBench.measure('media_print', 2.0, 5.0) do
  media.to_s(media: :print)
end
