# frozen_string_literal: true

require 'benchmark/ips'

# Load the local development version, not installed gem
$LOAD_PATH.unshift File.expand_path('../lib', __dir__)
require 'cataract'

begin
  require 'css_parser'
  CSS_PARSER_AVAILABLE = true
rescue LoadError
  CSS_PARSER_AVAILABLE = false
  puts 'css_parser gem not available - install with: gem install css_parser'
  exit 1
end

module BenchmarkSerialization
  def self.run
    puts '=' * 60
    puts 'CSS SERIALIZATION (to_s) BENCHMARK'
    puts '=' * 60
    puts "Loading from: #{File.expand_path('../../lib/cataract.rb', __dir__)}"

    # Load Bootstrap CSS (real-world example)
    bootstrap_path = File.expand_path('../../test/fixtures/bootstrap.css', __dir__)
    unless File.exist?(bootstrap_path)
      puts "ERROR: Bootstrap CSS fixture not found at #{bootstrap_path}"
      exit 1
    end

    css = File.read(bootstrap_path)

    puts "\n#{'=' * 60}"
    puts 'CORRECTNESS VALIDATION'
    puts '=' * 60
    puts "Input: Bootstrap CSS (#{css.length} bytes)"

    # Parse with both libraries
    cataract_sheet = Cataract.parse_css(css)

    css_parser = CssParser::Parser.new
    css_parser.add_block!(css)

    # Serialize
    cataract_output = cataract_sheet.to_s
    css_parser_output = css_parser.to_s

    puts "Cataract output: #{cataract_output.length} bytes (#{cataract_sheet.size} rules)"
    puts "css_parser output: #{css_parser_output.length} bytes"

    # Basic sanity check - outputs should be similar in size
    size_ratio = cataract_output.length.to_f / css_parser_output.length
    if size_ratio > 0.8 && size_ratio < 1.2
      puts "✅ Output sizes are similar (ratio: #{size_ratio.round(2)})"
    else
      puts "⚠️  Output sizes differ significantly (ratio: #{size_ratio.round(2)})"
    end

    # Check that output can be re-parsed
    begin
      reparsed = Cataract.parse_css(cataract_output)
      puts "✅ Cataract output can be re-parsed (#{reparsed.size} rules)"
    rescue StandardError => e
      puts "❌ Cataract output failed to re-parse: #{e.message}"
    end

    puts "\n#{'=' * 60}"
    puts 'PERFORMANCE BENCHMARK'
    puts '=' * 60
    puts 'Testing: Serialization (to_s) only on pre-parsed Bootstrap CSS'
    puts '(Parsing done once before benchmark, not included in measurements)'

    # Pre-parse CSS once (outside benchmark loop)
    cataract_parsed = Cataract.parse_css(css)

    css_parser_parsed = CssParser::Parser.new
    css_parser_parsed.add_block!(css)

    Benchmark.ips do |x|
      x.config(time: 5, warmup: 2)

      x.report('css_parser (all)') do
        # Clear memoization if any
        if css_parser_parsed.instance_variable_defined?(:@css_string)
          css_parser_parsed.instance_variable_set(:@css_string,
                                                  nil)
        end
        css_parser_parsed.to_s
      end

      x.report('cataract (all)') do
        # Clear memoization
        cataract_parsed.instance_variable_set(:@serialized, nil)
        cataract_parsed.to_s
      end

      x.compare!
    end

    puts "\n#{'=' * 60}"
    puts 'MEDIA TYPE FILTERING BENCHMARK (Parser API)'
    puts '=' * 60
    puts 'Testing: to_s(:print) to filter only print-specific rules'
    puts 'Note: Using Parser API (css_parser compatible) not Stylesheet'

    # Pre-parse using Parser API for media filtering
    cataract_parser = Cataract::Parser.new
    cataract_parser.add_block!(css)

    css_parser_for_filter = CssParser::Parser.new
    css_parser_for_filter.add_block!(css)

    Benchmark.ips do |x|
      x.config(time: 5, warmup: 2)

      x.report('css_parser (print)') do
        if css_parser_for_filter.instance_variable_defined?(:@css_string)
          css_parser_for_filter.instance_variable_set(:@css_string,
                                                      nil)
        end
        css_parser_for_filter.to_s(:print)
      end

      x.report('cataract (print)') do
        cataract_parser.to_s(:print)
      end

      x.compare!
    end

    puts "\n#{'=' * 60}"
    puts 'NOTES'
    puts '=' * 60
    puts 'This benchmark tests the full parse→serialize pipeline:'
    puts '  • CSS parsing into internal structure'
    puts '  • Merging duplicate selectors'
    puts '  • Serializing back to CSS string'
    puts ''
    puts "Cataract's to_s is implemented in C (stylesheet.c) for performance."
    puts 'The hash structure groups rules by media query for efficient output.'
    puts '=' * 60
  end
end

# Run the benchmark if this file is executed directly
BenchmarkSerialization.run if __FILE__ == $PROGRAM_NAME
