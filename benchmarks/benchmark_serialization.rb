# frozen_string_literal: true

require_relative 'benchmark_harness'

# Load the local development version, not installed gem
$LOAD_PATH.unshift File.expand_path('../lib', __dir__)
require 'cataract'

# CSS Serialization Performance Benchmark
class SerializationBenchmark < BenchmarkHarness
  def self.benchmark_name
    'serialization'
  end

  def self.description
    'Time to convert parsed CSS back to string format'
  end

  def self.metadata
    instance = new
    {
      'test_cases' => [
        {
          'name' => "Full Serialization (Bootstrap CSS - #{(instance.bootstrap_css.length / 1024.0).round}KB)",
          'key' => 'all',
          'bytes' => instance.bootstrap_css.length
        },
        {
          'name' => 'Media Type Filtering (print only)',
          'key' => 'print',
          'bytes' => instance.bootstrap_css.length
        }
      ]
    }
  end

  # Uses default speedup_config (test_case_key differs from parsing)
  def self.speedup_config
    {
      baseline_matcher: SpeedupCalculator::Matchers.css_parser,
      comparison_matcher: SpeedupCalculator::Matchers.cataract,
      test_case_key: :key # serialization uses 'key' not 'fixture'
    }
  end

  def sanity_checks
    # Check css_parser gem is available
    require 'css_parser'

    # Verify Bootstrap fixture exists
    raise "Bootstrap CSS fixture not found at #{bootstrap_path}" unless File.exist?(bootstrap_path)

    # Verify parsing and serialization work
    cataract_sheet = Cataract.parse_css(bootstrap_css)
    raise 'Failed to parse Bootstrap CSS' if cataract_sheet.empty?

    cataract_output = cataract_sheet.to_s
    raise 'Serialization produced empty output' if cataract_output.empty?

    # Verify output can be re-parsed
    reparsed = Cataract.parse_css(cataract_output)
    raise 'Failed to re-parse serialized output' if reparsed.empty?
  end

  def call
    validate_correctness
    run_full_serialization_benchmark
    run_media_filtering_benchmark
  end

  def bootstrap_css
    @bootstrap_css ||= File.read(bootstrap_path)
  end

  private

  def bootstrap_path
    @bootstrap_path ||= File.expand_path('../test/fixtures/bootstrap.css', __dir__)
  end

  def validate_correctness
    puts '=' * 80
    puts 'CORRECTNESS VALIDATION'
    puts '=' * 80
    puts "Input: Bootstrap CSS (#{bootstrap_css.length} bytes)"

    # Parse with both libraries
    cataract_sheet = Cataract.parse_css(bootstrap_css)
    css_parser = CssParser::Parser.new
    css_parser.add_block!(bootstrap_css)

    # Serialize
    cataract_output = cataract_sheet.to_s
    css_parser_output = css_parser.to_s

    puts "Cataract output: #{cataract_output.length} bytes (#{cataract_sheet.size} rules)"
    puts "css_parser output: #{css_parser_output.length} bytes"

    # Basic sanity check - outputs should be similar in size
    size_ratio = cataract_output.length.to_f / css_parser_output.length
    unless size_ratio > 0.8 && size_ratio < 1.2
      puts "⚠️  Output sizes differ significantly (ratio: #{size_ratio.round(2)})"
    end

    # Check that output can be re-parsed
    begin
      reparsed = Cataract.parse_css(cataract_output)
      puts "Re-parsed output: #{reparsed.size} rules"
    rescue StandardError => e
      puts "❌ Failed to re-parse: #{e.message}"
      raise
    end
  end

  def run_full_serialization_benchmark
    puts "\n#{'=' * 80}"
    puts 'TEST: Full serialization (to_s)'
    puts '=' * 80
    puts '(Parsing done once before benchmark, not included in measurements)'

    # Pre-parse CSS once (outside benchmark loop)
    cataract_parsed = Cataract.parse_css(bootstrap_css)
    css_parser_parsed = CssParser::Parser.new
    css_parser_parsed.add_block!(bootstrap_css)

    benchmark('all') do |x|
      x.config(time: 5, warmup: 2)

      x.report('css_parser: all') do
        # Clear memoization if any
        if css_parser_parsed.instance_variable_defined?(:@css_string)
          css_parser_parsed.instance_variable_set(:@css_string, nil)
        end
        css_parser_parsed.to_s
      end

      x.report('cataract: all') do
        # Clear memoization
        cataract_parsed.instance_variable_set(:@serialized, nil)
        cataract_parsed.to_s
      end

      x.compare!
    end
  end

  def run_media_filtering_benchmark
    puts "\n#{'=' * 80}"
    puts 'TEST: Media type filtering - to_s(:print)'
    puts '=' * 80
    puts 'Note: Using Parser API (css_parser compatible) not Stylesheet'

    # Pre-parse using Parser API for media filtering
    cataract_parser = Cataract::Stylesheet.new
    cataract_parser.add_block!(bootstrap_css)

    css_parser_for_filter = CssParser::Parser.new
    css_parser_for_filter.add_block!(bootstrap_css)

    benchmark('print') do |x|
      x.config(time: 5, warmup: 2)

      x.report('css_parser: print') do
        if css_parser_for_filter.instance_variable_defined?(:@css_string)
          css_parser_for_filter.instance_variable_set(:@css_string, nil)
        end
        css_parser_for_filter.to_s(:print)
      end

      x.report('cataract: print') do
        cataract_parser.to_s(:print)
      end

      x.compare!
    end
  end
end

# Run if executed directly
SerializationBenchmark.run if __FILE__ == $PROGRAM_NAME
