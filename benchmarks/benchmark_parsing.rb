# frozen_string_literal: true

require_relative 'benchmark_harness'

# Load the local development version, not installed gem
$LOAD_PATH.unshift File.expand_path('../lib', __dir__)
require 'cataract'

# CSS Parsing Performance Benchmark
class ParsingBenchmark < BenchmarkHarness
  def self.benchmark_name
    'parsing'
  end

  def self.description
    'Time to parse CSS into internal data structures'
  end

  def self.metadata
    instance = new
    {
      'test_cases' => [
        {
          'name' => "Small CSS (#{instance.css1.lines.count} lines, #{(instance.css1.length / 1024.0).round(1)}KB)",
          'fixture' => 'CSS1',
          'lines' => instance.css1.lines.count,
          'bytes' => instance.css1.length
        },
        {
          'name' => "Medium CSS with @media (#{instance.css2.lines.count} lines, #{(instance.css2.length / 1024.0).round(1)}KB)",
          'fixture' => 'CSS2',
          'lines' => instance.css2.lines.count,
          'bytes' => instance.css2.length
        }
      ]
      # speedups will be calculated automatically by harness
    }
  end

  # Uses default speedup_config from harness (css_parser vs cataract, test_case_key: :fixture)

  def sanity_checks
    # Check css_parser gem is available
    require 'css_parser'

    # Verify fixtures parse correctly
    parser = Cataract::Parser.new
    parser.parse(css1)
    raise 'CSS1 sanity check failed: expected rules' if parser.rules_count.zero?

    parser = Cataract::Parser.new
    parser.parse(css2)
    raise 'CSS2 sanity check failed: expected rules' if parser.rules_count.zero?
  end

  def call
    run_css1_benchmark
    run_css2_benchmark
    show_correctness_comparison
  end

  def css1
    @css1 ||= File.read(File.join(fixtures_dir, 'css1_sample.css'))
  end

  def css2
    @css2 ||= File.read(File.join(fixtures_dir, 'css2_sample.css'))
  end

  private

  def fixtures_dir
    @fixtures_dir ||= File.expand_path('../test/fixtures', __dir__)
  end

  def run_css1_benchmark
    puts '=' * 80
    puts "TEST: CSS1 (#{css1.lines.count} lines, #{css1.length} chars)"
    puts '=' * 80

    benchmark('css1') do |x|
      x.config(time: 5, warmup: 2)

      x.report('css_parser gem: CSS1') do
        parser = CssParser::Parser.new(import: false, io_exceptions: false)
        parser.add_block!(css1)
      end

      x.report('cataract: CSS1') do
        parser = Cataract::Parser.new
        parser.parse(css1)
      end

      x.compare!
    end
  end

  def run_css2_benchmark
    puts "\n#{'=' * 80}"
    puts "TEST: CSS2 with @media (#{css2.lines.count} lines, #{css2.length} chars)"
    puts '=' * 80

    benchmark('css2') do |x|
      x.config(time: 5, warmup: 2)

      x.report('css_parser gem: CSS2') do
        parser = CssParser::Parser.new(import: false, io_exceptions: false)
        parser.add_block!(css2)
      end

      x.report('cataract: CSS2') do
        parser = Cataract::Parser.new
        parser.parse(css2)
      end

      x.compare!
    end
  end

  def show_correctness_comparison
    puts "\n#{'=' * 80}"
    puts 'CORRECTNESS VALIDATION (CSS2)'
    puts '=' * 80

    # Test Cataract
    parser = Cataract::Parser.new
    parser.parse(css2)
    cataract_rules = parser.rules_count
    puts "Cataract found #{cataract_rules} rules"

    # Test css_parser
    css_parser = CssParser::Parser.new(import: false, io_exceptions: false)
    css_parser.add_block!(css2)
    css_parser_rules = 0
    css_parser.each_selector { css_parser_rules += 1 }
    puts "css_parser found #{css_parser_rules} rules"

    unless cataract_rules == css_parser_rules
      puts '⚠️  Different number of rules parsed'
      puts '    Note: css_parser has a known bug with ::after pseudo-elements'
      puts '    (it concatenates them with previous rules instead of parsing separately)'
    end

    # Show sample output
    puts "\nSample Cataract output:"
    parser.each_selector.first(5).each do |selector, declarations, specificity|
      puts "  #{selector}: #{declarations} (spec: #{specificity})"
    end
  end
end

# Run if executed directly
ParsingBenchmark.run if __FILE__ == $PROGRAM_NAME
