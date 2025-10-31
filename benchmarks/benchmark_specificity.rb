# frozen_string_literal: true

require_relative 'benchmark_harness'

# Load the local development version, not installed gem
$LOAD_PATH.unshift File.expand_path('../lib', __dir__)
require 'cataract'

# CSS Specificity Calculation Benchmark
class SpecificityBenchmark < BenchmarkHarness
  def self.benchmark_name
    'specificity'
  end

  def self.description
    'Time to calculate CSS selector specificity values'
  end

  def self.metadata
    {
      'test_cases' => [
        {
          'name' => 'Simple Selectors',
          'key' => 'simple',
          'selectors' => { 'div' => 1, '.class' => 10, '#id' => 100 }
        },
        {
          'name' => 'Compound Selectors',
          'key' => 'compound',
          'selectors' => { 'div.container' => 11, 'div#main' => 101, 'div.container#main' => 111 }
        },
        {
          'name' => 'Combinators',
          'key' => 'combinators',
          'selectors' => { 'div p' => 2, 'div > p' => 2, 'h1 + p' => 2, 'div.container > p.intro' => 22 }
        },
        {
          'name' => 'Pseudo-classes & Pseudo-elements',
          'key' => 'pseudo',
          'selectors' => { 'a:hover' => 11, 'p::before' => 2, 'li:first-child' => 11, 'p:first-child::before' => 12 }
        },
        {
          'name' => ':not() Pseudo-class (CSS3)',
          'key' => 'not',
          'selectors' => { '#s12:not(foo)' => 101, 'div:not(.active)' => 11, '.button:not([disabled])' => 20 },
          'note' => "css_parser has a bug - doesn't parse :not() content"
        },
        {
          'name' => 'Complex Real-world Selectors',
          'key' => 'complex',
          'selectors' => {
            'ul#nav li.active a:hover' => 122,
            'div.wrapper > article#main > section.content > p:first-child' => 123,
            "[data-theme='dark'] body.admin #dashboard .widget a[href^='http']::before" => 143
          }
        }
      ]
    }
  end

  def self.speedup_config
    {
      baseline_matcher: SpeedupCalculator::Matchers.css_parser,
      comparison_matcher: SpeedupCalculator::Matchers.cataract,
      test_case_key: :key
    }
  end

  def sanity_checks
    require 'css_parser'

    # Verify Cataract calculations
    raise 'Cataract simple selector failed' unless Cataract.calculate_specificity('div') == 1
    raise 'Cataract class selector failed' unless Cataract.calculate_specificity('.class') == 10
    raise 'Cataract id selector failed' unless Cataract.calculate_specificity('#id') == 100
  end

  def call
    self.class.metadata['test_cases'].each do |test_case|
      benchmark_category(test_case)
    end
  end

  private

  def benchmark_category(test_case)
    puts '=' * 80
    puts "TEST: #{test_case['name']}"
    puts test_case['note'] if test_case['note']
    puts '=' * 80

    key = test_case['key']
    selectors = test_case['selectors']

    # Show individual selector examples in terminal output
    puts 'Selectors tested:'
    selectors.each do |selector, expected_specificity|
      puts "  #{selector} => #{expected_specificity}"
    end
    puts

    benchmark(key) do |x|
      x.config(time: 2, warmup: 1)

      # Report aggregated results per test case for speedup calculation
      x.report("css_parser: #{key}") do
        selectors.each_key do |selector|
          CssParser.calculate_specificity(selector)
        end
      end

      x.report("cataract: #{key}") do
        selectors.each_key do |selector|
          Cataract.calculate_specificity(selector)
        end
      end

      x.compare!
    end
  end
end

# Run if executed directly
SpecificityBenchmark.run if __FILE__ == $PROGRAM_NAME
