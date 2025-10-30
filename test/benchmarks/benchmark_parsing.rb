# frozen_string_literal: true

require 'benchmark/ips'

# Load the local development version, not installed gem
$LOAD_PATH.unshift File.expand_path('../../lib', __dir__)
require 'cataract'

begin
  require 'css_parser'
  CSS_PARSER_AVAILABLE = true
rescue LoadError
  CSS_PARSER_AVAILABLE = false
  puts 'css_parser gem not available - install with: gem install css_parser'
end

module BenchmarkParsing
  def self.run
    puts '=' * 60
    puts 'CSS PARSING BENCHMARK'
    puts '=' * 60
    puts "Loading from: #{File.expand_path('../../lib/cataract.rb', __dir__)}"

    # Load CSS fixtures
    fixtures_dir = File.expand_path('../fixtures', __dir__)
    test_css_css1 = File.read(File.join(fixtures_dir, 'css1_sample.css'))
    test_css_css2 = File.read(File.join(fixtures_dir, 'css2_sample.css'))

    fast_parser = Cataract::Parser.new

    # Verify both test cases work before benchmarking
    puts "\nVerifying CSS1 test case..."
    begin
      fast_parser.parse(test_css_css1)
      puts "  ✅ CSS1 parsed successfully (#{fast_parser.rules_count} rules)"
    rescue StandardError => e
      puts "  ❌ ERROR: Failed to parse CSS1: #{e.message}"
      return
    end

    puts 'Verifying CSS2 test case with @media queries...'
    begin
      fast_parser.parse(test_css_css2)
      puts "  ✅ CSS2 parsed successfully (#{fast_parser.rules_count} rules)"
    rescue StandardError => e
      puts "  ❌ ERROR: Failed to parse CSS2: #{e.message}"
      return
    end

    puts '=' * 60
    puts "BENCHMARK: CSS1 (#{test_css_css1.lines.count} lines, #{test_css_css1.length} chars)"
    puts '=' * 60

    if CSS_PARSER_AVAILABLE
      Benchmark.ips do |x|
        x.config(time: 5, warmup: 2)

        x.report('css_parser gem') do
          parser = CssParser::Parser.new(import: false, io_exceptions: false)
          parser.add_block!(test_css_css1)
        end

        x.report('cataract') do
          parser = Cataract::Parser.new
          parser.parse(test_css_css1)
        end

        x.compare!
      end
    else
      puts 'Install css_parser gem for comparison benchmarks'

      Benchmark.ips do |x|
        x.config(time: 5, warmup: 2)

        x.report('cataract') do
          parser = Cataract::Parser.new
          parser.parse(test_css_css1)
        end
      end
    end

    puts "\n#{'=' * 60}"
    puts "BENCHMARK: CSS2 with @media (#{test_css_css2.lines.count} lines, #{test_css_css2.length} chars)"
    puts '=' * 60

    if CSS_PARSER_AVAILABLE
      Benchmark.ips do |x|
        x.config(time: 5, warmup: 2)

        x.report('css_parser gem') do
          parser = CssParser::Parser.new(import: false, io_exceptions: false)
          parser.add_block!(test_css_css2)
        end

        x.report('cataract') do
          parser = Cataract::Parser.new
          parser.parse(test_css_css2)
        end

        x.compare!
      end
    else
      Benchmark.ips do |x|
        x.config(time: 5, warmup: 2)

        x.report('cataract') do
          parser = Cataract::Parser.new
          parser.parse(test_css_css2)
        end
      end
    end

    puts "\n#{'=' * 60}"
    puts 'CORRECTNESS COMPARISON (CSS2)'
    puts '=' * 60

    # Test functionality on CSS2
    # Use fresh parser to avoid accumulating rules from previous parses
    fresh_parser = Cataract::Parser.new
    fresh_parser.parse(test_css_css2)
    puts "Cataract found #{fresh_parser.rules_count} rules"

    return unless CSS_PARSER_AVAILABLE

    css_parser = CssParser::Parser.new(import: false, io_exceptions: false)
    css_parser.add_block!(test_css_css2)

    css_parser_rules = 0
    css_parser.each_selector { css_parser_rules += 1 }
    puts "css_parser found #{css_parser_rules} rules"

    if fresh_parser.rules_count == css_parser_rules
      puts '✅ Same number of rules parsed'
    else
      puts '⚠️  Different number of rules parsed'
      puts '    Note: css_parser has a known bug with ::after pseudo-elements'
      puts '    (it concatenates them with previous rules instead of parsing separately)'
    end

    # Show a sample of what we parsed
    puts "\nSample Cataract output:"
    fresh_parser.each_selector.first(5).each do |selector, declarations, specificity|
      puts "  #{selector}: #{declarations} (spec: #{specificity})"
    end
  end
end

# Run the benchmark if this file is executed directly
BenchmarkParsing.run if __FILE__ == $PROGRAM_NAME
