# frozen_string_literal: true

require 'benchmark/ips'
require 'cataract'

# Test values
MARGIN_VALUES = [
  '10px',
  '10px 20px',
  '10px 20px 30px',
  '10px 20px 30px 40px',
  '10px calc(100% - 20px)',
  '10px !important'
].freeze

BORDER_VALUES = [
  '1px solid red',
  '2px dashed blue',
  'thin dotted #000'
].freeze

FONT_VALUES = [
  '12px Arial',
  "bold 14px/1.5 'Helvetica Neue', sans-serif"
].freeze

puts "\n=== Shorthand Expansion Benchmark ==="
puts "Benchmarking Cataract shorthand expansion\n\n"

# Margin expansion
puts '--- Margin Expansion (4 values) ---'
Benchmark.ips do |x|
  x.config(time: 5, warmup: 2)

  x.report('Cataract') do
    Cataract._expand_margin('10px 20px 30px 40px')
  end

  x.compare!
end

# Margin with calc()
puts "\n--- Margin with calc() ---"
Benchmark.ips do |x|
  x.config(time: 5, warmup: 2)

  x.report('Cataract') do
    Cataract._expand_margin('10px calc(100% - 20px)')
  end

  x.compare!
end

# Margin with !important
puts "\n--- Margin with !important ---"
Benchmark.ips do |x|
  x.config(time: 5, warmup: 2)

  x.report('Cataract') do
    Cataract._expand_margin('10px !important')
  end

  x.compare!
end

# Border expansion
puts "\n--- Border Expansion ---"
Benchmark.ips do |x|
  x.config(time: 5, warmup: 2)

  x.report('Cataract') do
    Cataract._expand_border('1px solid red')
  end

  x.compare!
end

# Font expansion
puts "\n--- Font Expansion ---"
Benchmark.ips do |x|
  x.config(time: 5, warmup: 2)

  x.report('Cataract') do
    Cataract._expand_font("bold 14px/1.5 'Helvetica Neue', sans-serif")
  end

  x.compare!
end

puts "\n=== Summary ==="
puts 'Cataract uses a C implementation with Ragel state machine for value splitting'
