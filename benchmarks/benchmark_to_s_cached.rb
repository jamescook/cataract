# frozen_string_literal: true

require 'benchmark/ips'

$LOAD_PATH.unshift File.expand_path('../lib', __dir__)
require 'cataract'

puts '=' * 60
puts 'CACHED to_s BENCHMARK'
puts '=' * 60
puts ''

bootstrap_css = File.read('test/fixtures/bootstrap.css')

puts 'Comparing:'
puts '  - Fresh parse → to_s (first call, uncached)'
puts '  - Repeated to_s (cached, should be instant)'
puts ''

Benchmark.ips do |x|
  x.config(time: 10, warmup: 3)

  x.report('parse + to_s (uncached)') do
    stylesheet = Cataract.parse_css(bootstrap_css)
    stylesheet.to_s
  end

  x.report('to_s (cached)') do
    # Parse once outside the benchmark
    stylesheet = Cataract.parse_css(bootstrap_css)
    stylesheet.to_s # Prime cache

    # Now benchmark cached access
    stylesheet.to_s
  end

  x.compare!
end

puts ''
puts '=' * 60
puts 'Real-world scenario: Multiple to_s calls'
puts '=' * 60
puts ''

stylesheet = Cataract.parse_css(bootstrap_css)

puts 'Calling to_s 10 times...'
require 'benchmark'
time = Benchmark.measure do
  10.times { stylesheet.to_s }
end

puts "Total time: #{time.real.round(4)}s"
puts 'First call does all work, next 9 are free!'
