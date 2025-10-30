# frozen_string_literal: true

require 'ruby-prof'

$LOAD_PATH.unshift File.expand_path('../lib', __dir__)
require 'cataract'

bootstrap_css = File.read('test/fixtures/bootstrap.css')
stylesheet = Cataract.parse_css(bootstrap_css)

puts "Profiling Stylesheet#to_s on bootstrap.css (#{stylesheet.size} rules)"
puts ''

# Profile
RubyProf.start

10.times { stylesheet.to_s }

result = RubyProf.stop

# Print flat profile
printer = RubyProf::FlatPrinter.new(result)
printer.print($stdout, min_percent: 1)
