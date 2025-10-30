# frozen_string_literal: true

require 'benchmark/ips'

$LOAD_PATH.unshift File.expand_path('../lib', __dir__)
require 'cataract'

puts '=' * 60
puts 'Stylesheet#to_s: Ruby vs C Implementation'
puts '=' * 60
puts ''

bootstrap_css = File.read('test/fixtures/bootstrap.css')
stylesheet = Cataract.parse_css(bootstrap_css)

puts "Parsing bootstrap.css: #{stylesheet.size} rules"
puts ''

# Verify both versions produce same output
ruby_output = stylesheet.to_s
c_output = Cataract.stylesheet_to_s_c(stylesheet.rules)

if ruby_output == c_output
  puts '✓ Ruby and C versions produce identical output'
else
  puts '✗ WARNING: Ruby and C versions produce different output!'
  puts "Ruby length: #{ruby_output.length}"
  puts "C length: #{c_output.length}"

  # Find first difference
  ruby_output.chars.each_with_index do |char, i|
    next unless char != c_output[i]

    puts "First difference at position #{i}:"
    puts "  Ruby: #{ruby_output[(i - 20)..(i + 20)].inspect}"
    puts "  C:    #{c_output[(i - 20)..(i + 20)].inspect}"
    break
  end
end

puts ''
puts 'Benchmarking to_s only (cache cleared each iteration)...'
puts ''

# Parse once outside benchmark
PARSER = Cataract.parse_css(bootstrap_css)

Benchmark.ips do |x|
  x.config(time: 10, warmup: 3)

  x.report('Ruby (serialize_to_css)') do
    PARSER.instance_variable_set(:@serialized, nil)  # Clear cache
    PARSER.to_s
  end

  x.report('C (stylesheet_to_s_c)') do
    PARSER.instance_variable_set(:@serialized, nil)  # Clear cache (apples-to-apples)
    Cataract.stylesheet_to_s_c(PARSER.rules)
  end

  x.compare!
end
