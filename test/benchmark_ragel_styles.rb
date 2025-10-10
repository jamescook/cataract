#!/usr/bin/env ruby
# frozen_string_literal: true

# Benchmark different Ragel code generation styles
# Runs each style in a separate Ruby process to ensure fresh .so loading

require 'fileutils'
require 'shellwords'
require 'tmpdir'

# Ragel styles to test (excluding -G2 which takes too long to compile)
STYLES = %w[-T0 -T1 -F0 -F1 -G0 -G1]

# Use system temp directory for benchmark results
RESULTS_FILE = File.join(Dir.tmpdir, 'benchmark_ragel_styles.json')
FileUtils.rm_f(RESULTS_FILE)

puts "Ragel Style Benchmark"
puts "=" * 80
puts "Testing styles: #{STYLES.join(', ')}"
puts "Each style will be compiled and benchmarked in a separate process."
puts "Results file: #{RESULTS_FILE}"
puts "=" * 80

# Run each style in a separate Ruby process
STYLES.each do |style|
  puts "\n" + "="*80
  puts "Benchmarking: #{style}"
  puts "="*80

  # Compile with the specific style
  system({'RAGEL_STYLE' => style}, 'rake clean > /dev/null 2>&1')
  unless system({'RAGEL_STYLE' => style}, 'rake compile')
    abort("Failed to compile with #{style}")
  end

  # Run benchmark in a separate process
  # Each process saves results and compares against previous runs
  worker_code = <<~RUBY
    require 'benchmark/ips'
    require 'cataract'

    sample_css = File.exist?('test/fixtures/sample.css') ?
      File.read('test/fixtures/sample.css') :
      "body { margin: 0; padding: 0 }\\n.header { color: blue; font-size: 16px }"

    Benchmark.ips do |x|
      x.config(time: 5, warmup: 2)

      x.report('#{style}') do
        parser = Cataract::Parser.new
        parser.parse(sample_css)
      end

      x.save! '#{RESULTS_FILE}'
      x.compare!
    end
  RUBY

  unless system("ruby -I lib -e #{Shellwords.escape(worker_code)}")
    abort("Failed to benchmark #{style}")
  end
end

puts "\n" + "="*80
puts "Benchmark complete!"
puts "="*80
