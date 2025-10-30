# frozen_string_literal: true

require 'benchmark/ips'

$LOAD_PATH.unshift File.expand_path('../lib', __dir__)
require 'cataract'

# Get current git branch
branch = `git rev-parse --abbrev-ref HEAD 2>/dev/null`.strip
branch = 'unknown' if branch.empty?

puts '=' * 60
puts "Value Splitter Benchmark: #{branch}"
puts '=' * 60
puts ''

# Test cases covering different scenarios
test_cases = {
  'simple' => '1px 2px 3px 4px',
  'functions' => '10px calc(100% - 20px) 5px',
  'rgb' => 'rgb(255, 0, 0) blue rgba(0, 0, 0, 0.5)',
  'quotes' => "'Helvetica Neue', Arial, sans-serif",
  'complex' => "10px calc(100% - 20px) 'Font Name' rgb(255, 0, 0)",
  'long' => '1px 2px 3px 4px 5px 6px 7px 8px 9px 10px 11px 12px 13px 14px 15px'
}

puts 'Test cases:'
test_cases.each do |name, value|
  result = Cataract.split_value(value)
  puts "  #{name}: '#{value}' => #{result.length} tokens"
end
puts ''

Benchmark.ips do |x|
  x.config(time: 10, warmup: 3)

  test_cases.each do |name, value|
    x.report("#{branch}:#{name.ljust(12)}") do
      Cataract.split_value(value)
    end
  end

  x.compare!

  # Save results to file for cross-branch comparison
  x.save! 'test/.benchmark_results/value_splitter.json'
  x.hold! 'test/.benchmark_results/value_splitter.json'
end

puts ''
puts '=' * 60
puts 'Results saved to test/.benchmark_results/value_splitter.json'
puts 'Switch git branches and run again to compare!'
puts '=' * 60
