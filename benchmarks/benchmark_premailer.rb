#!/usr/bin/env ruby
# frozen_string_literal: true

require 'benchmark/ips'
require 'fileutils'

# Load the local development version, not installed gem
$LOAD_PATH.unshift File.expand_path('../lib', __dir__)
require 'cataract'

begin
  require 'premailer'
  PREMAILER_AVAILABLE = true
rescue LoadError
  PREMAILER_AVAILABLE = false
  puts 'premailer gem not available - install with: gem install premailer'
  exit 1
end

module BenchmarkPremailer
  def self.run
    puts '=' * 80
    puts 'PREMAILER BENCHMARK - css_parser vs Cataract'
    puts '=' * 80
    puts "Cataract version: #{Cataract::VERSION}"
    puts "Premailer version: #{Premailer::VERSION}"
    puts '=' * 80
    puts

    # Load HTML fixture
    fixtures_dir = File.expand_path('premailer_fixtures', __dir__)
    html_path = File.join(fixtures_dir, 'email.html')
    html_content = File.read(html_path)

    # Verify premailer actually inlines CSS
    puts 'Verifying CSS inlining...'
    Cataract.restore_CssParser! if defined?(CssParser::CATARACT_SHIM)

    # Load CSS files explicitly
    css_files = [
      File.join(fixtures_dir, 'base.css'),
      File.join(fixtures_dir, 'email.css')
    ]

    premailer = Premailer.new(
      html_content,
      with_html_string: true,
      css: css_files,
      adapter: :nokogiri
    )
    result = premailer.to_inline_css

    # Check that styles were actually inlined
    if result.include?('style=')
      puts "✓ CSS successfully inlined (found #{result.scan('style="').length} inline styles)"
    else
      puts '✗ WARNING: No inline styles found - CSS may not be loading properly'
    end
    puts

    # Warmup to ensure fair comparison
    puts 'Warming up...'
    2.times do
      # css_parser
      Cataract.restore_CssParser! if defined?(CssParser::CATARACT_SHIM)
      premailer = Premailer.new(html_content, with_html_string: true, css: css_files, adapter: :nokogiri)
      premailer.to_inline_css

      # Cataract
      Cataract.mimic_CssParser!
      premailer = Premailer.new(html_content, with_html_string: true, css: css_files, adapter: :nokogiri)
      premailer.to_inline_css
      Cataract.restore_CssParser!
    end
    puts

    # Memory usage comparison
    puts '=' * 80
    puts 'MEMORY USAGE'
    puts '=' * 80
    puts

    # css_parser memory
    GC.start
    before = GC.stat(:total_allocated_objects)
    Cataract.restore_CssParser! if defined?(CssParser::CATARACT_SHIM)
    premailer = Premailer.new(html_content, with_html_string: true, css: css_files, adapter: :nokogiri)
    premailer.to_inline_css
    css_parser_allocations = GC.stat(:total_allocated_objects) - before

    # Cataract memory
    GC.start
    before = GC.stat(:total_allocated_objects)
    Cataract.mimic_CssParser!
    premailer = Premailer.new(html_content, with_html_string: true, css: css_files, adapter: :nokogiri)
    premailer.to_inline_css
    cataract_allocations = GC.stat(:total_allocated_objects) - before
    Cataract.restore_CssParser!

    puts "css_parser allocations: #{css_parser_allocations}"
    puts "Cataract allocations:   #{cataract_allocations}"
    if css_parser_allocations.positive?
      reduction = ((css_parser_allocations - cataract_allocations).to_f / css_parser_allocations * 100).round(1)
      puts "Reduction: #{reduction}%"
    end
    puts

    # Performance benchmark
    puts '=' * 80
    puts 'PERFORMANCE BENCHMARK'
    puts '=' * 80
    puts

    # Use ENV var to control which version to benchmark
    # This allows us to run the script twice and compare results
    use_cataract = ENV['USE_CATARACT'] == '1'
    state_file = '/tmp/benchmark_premailer_ips.json'
    is_second_run = File.exist?(state_file)

    if use_cataract
      puts 'Benchmarking with Cataract shim...'
      Cataract.mimic_CssParser!
    else
      puts 'Benchmarking with css_parser...'
      Cataract.restore_CssParser! if defined?(CssParser::CATARACT_SHIM)
    end
    puts

    label = use_cataract ? 'premailer + Cataract' : 'premailer + css_parser'

    Benchmark.ips do |x|
      x.config(time: 10, warmup: 3)

      x.report(label) do
        premailer = Premailer.new(
          html_content,
          with_html_string: true,
          css: css_files,
          adapter: :nokogiri
        )
        premailer.to_inline_css
      end

      x.save! state_file
      x.compare!
    end

    # Restore after benchmarking
    Cataract.restore_CssParser! if use_cataract

    # Clean up state file after second run
    FileUtils.rm_f(state_file) if is_second_run

    # Print instructions if this was the first run
    return if is_second_run

    puts
    puts '=' * 80
    puts 'First benchmark complete. Now run with Cataract:'
    puts '  USE_CATARACT=1 ruby test/benchmarks/benchmark_premailer.rb'
    puts '=' * 80
  end
end

# Run if called directly
BenchmarkPremailer.run if __FILE__ == $PROGRAM_NAME
