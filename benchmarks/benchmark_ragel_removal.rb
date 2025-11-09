# frozen_string_literal: true

require 'benchmark/ips'

# Load the local development version, not installed gem
$LOAD_PATH.unshift File.expand_path('../lib', __dir__)
require 'cataract'

# Get current branch name
branch = `git rev-parse --abbrev-ref HEAD`.strip

puts '=' * 80
puts 'RAGEL REMOVAL BENCHMARK - Parsing Performance Comparison'
puts '=' * 80
puts "Current branch: #{branch}"
puts

# Load bootstrap.css fixture (large real-world CSS file)
fixtures_dir = File.expand_path('../test/fixtures', __dir__)
bootstrap_css = File.read(File.join(fixtures_dir, 'bootstrap.css'))

puts "Bootstrap CSS: #{bootstrap_css.lines.count} lines, #{bootstrap_css.bytesize} bytes"
puts

# Verify parsing works
puts 'Verifying parsing works...'
parser = Cataract::Stylesheet.new
parser.add_block(bootstrap_css)
puts "  ✅ Parsed successfully (#{parser.rules_count} rules)"
puts

puts '=' * 80
puts 'BENCHMARK: Bootstrap CSS Parsing'
puts '=' * 80
puts

Benchmark.ips do |x|
  x.config(time: 5, warmup: 2)

  x.report("#{branch}:parse_bootstrap") do
    parser = Cataract::Stylesheet.new
    parser.add_block(bootstrap_css)
  end

  x.compare!

  # Save results to file for cross-branch comparison
  x.save! 'test/.benchmark_results/ragel_removal.json'
  x.hold! 'test/.benchmark_results/ragel_removal.json'
end

puts
puts '=' * 80
puts 'Results saved to test/.benchmark_results/ragel_removal.json'
puts 'Switch git branches, recompile, and run again to compare!'
puts '=' * 80
