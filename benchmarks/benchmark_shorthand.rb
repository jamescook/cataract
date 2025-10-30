# frozen_string_literal: true

require 'benchmark/ips'

$LOAD_PATH.unshift File.expand_path('../lib', __dir__)
require 'cataract'

# Get current git branch
branch = `git rev-parse --abbrev-ref HEAD 2>/dev/null`.strip
branch = 'unknown' if branch.empty?

puts '=' * 60
puts "Shorthand Expansion/Creation Benchmark: #{branch}"
puts '=' * 60
puts ''

# Test cases for expansion
expansion_tests = {
  'margin' => '10px 20px',
  'padding' => '5px 10px 15px 20px',
  'border' => '1px solid red',
  'border-color' => 'red blue',
  'font' => 'bold 14px/1.5 Arial, sans-serif',
  'background' => 'url(image.png) no-repeat center/cover'
}

# Test cases for shorthand creation
creation_tests = {
  'margin' => {
    'margin-top' => '10px',
    'margin-right' => '20px',
    'margin-bottom' => '10px',
    'margin-left' => '20px'
  },
  'border' => {
    'border-width' => '1px',
    'border-style' => 'solid',
    'border-color' => 'red'
  },
  'font' => {
    'font-style' => 'italic',
    'font-weight' => 'bold',
    'font-size' => '14px',
    'line-height' => '1.5',
    'font-family' => 'Arial, sans-serif'
  }
}

puts 'Expansion test cases:'
expansion_tests.each do |prop, value|
  puts "  #{prop}: '#{value}'"
end
puts ''

puts 'Shorthand creation test cases:'
creation_tests.each do |name, props|
  puts "  #{name}: #{props.length} properties"
end
puts ''

Benchmark.ips do |x|
  x.config(time: 10, warmup: 3)

  # Benchmark expansions
  x.report("#{branch}:expand_margin      ") do
    Cataract.expand_margin(expansion_tests['margin'])
  end

  x.report("#{branch}:expand_padding     ") do
    Cataract.expand_padding(expansion_tests['padding'])
  end

  x.report("#{branch}:expand_border      ") do
    Cataract.expand_border(expansion_tests['border'])
  end

  x.report("#{branch}:expand_font        ") do
    Cataract.expand_font(expansion_tests['font'])
  end

  x.report("#{branch}:expand_background  ") do
    Cataract.expand_background(expansion_tests['background'])
  end

  # Benchmark shorthand creation
  x.report("#{branch}:create_margin      ") do
    Cataract.create_margin_shorthand(creation_tests['margin'])
  end

  x.report("#{branch}:create_border      ") do
    Cataract.create_border_shorthand(creation_tests['border'])
  end

  x.report("#{branch}:create_font        ") do
    Cataract.create_font_shorthand(creation_tests['font'])
  end

  x.compare!

  # Save results to file for cross-branch comparison
  x.save! 'test/.benchmark_results/shorthand.json'
  x.hold! 'test/.benchmark_results/shorthand.json'
end

puts ''
puts '=' * 60
puts 'Results saved to test/.benchmark_results/shorthand.json'
puts 'Switch git branches and run again to compare!'
puts '=' * 60
