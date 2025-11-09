# frozen_string_literal: true

require_relative 'benchmark_harness'

# Load the local development version, not installed gem
$LOAD_PATH.unshift File.expand_path('../lib', __dir__)
require 'cataract'

# CSS Merging Benchmark
class MergingBenchmark < BenchmarkHarness
  def self.benchmark_name
    'merging'
  end

  def self.description
    'Time to merge multiple CSS rule sets with same selector'
  end

  def self.metadata
    {
      'test_cases' => [
        {
          'name' => 'No shorthand properties (large)',
          'key' => 'no_shorthand',
          'css' => (".test { color: red; background-color: blue; display: block; position: relative; width: 100px; height: 50px; }\n" * 100)
        },
        {
          'name' => 'Simple properties',
          'key' => 'simple',
          'css' => ".test { color: black; margin: 10px; }\n.test { padding: 5px; }"
        },
        {
          'name' => 'Cascade with specificity',
          'key' => 'cascade',
          'css' => ".test { color: black; }\n#test { color: red; }\n.test { margin: 10px; }"
        },
        {
          'name' => 'Important declarations',
          'key' => 'important',
          'css' => ".test { color: black !important; }\n#test { color: red; }\n.test { margin: 10px; }"
        },
        {
          'name' => 'Shorthand expansion',
          'key' => 'shorthand',
          'css' => ".test { margin: 10px 20px; }\n.test { margin-left: 5px; }\n.test { padding: 1em 2em 3em 4em; }"
        },
        {
          'name' => 'Complex merging',
          'key' => 'complex',
          'css' => "body { margin: 0; padding: 0; }\n.container { width: 100%; margin: 0 auto; }\n#main { background: white; color: black; }\n.button { padding: 10px 20px; border: 1px solid #ccc; }\n.button:hover { background: #f0f0f0; }\n.button.primary { background: blue !important; color: white; }"
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

    # Verify merging works correctly
    css = ".test { color: black; }\n.test { margin: 10px; }"
    cataract_rules = Cataract.parse_css(css)
    cataract_merged = Cataract.merge(cataract_rules)

    raise 'Cataract merge failed' if cataract_merged.rules.empty?

    merged_decls = cataract_merged.rules.first.declarations
    raise 'Cataract merge incorrect' unless merged_decls.any? { |d| d.property == 'color' }
  end

  def call
    self.class.metadata['test_cases'].each do |test_case|
      benchmark_test_case(test_case)
    end
  end

  private

  def benchmark_test_case(test_case)
    puts '=' * 80
    puts "TEST: #{test_case['name']}"
    puts '=' * 80

    key = test_case['key']
    css = test_case['css']

    # Pre-parse the CSS for both implementations
    cataract_rules = Cataract.parse_css(css)

    parser = CssParser::Parser.new
    parser.add_block!(css)
    rule_sets = []
    parser.each_selector do |selector, declarations, _specificity|
      rule_sets << CssParser::RuleSet.new(selectors: selector, block: declarations)
    end

    benchmark(key) do |x|
      x.config(time: 5, warmup: 2)

      x.report("css_parser: #{key}") do
        CssParser.merge(rule_sets)
      end

      x.report("cataract: #{key}") do
        Cataract.merge(cataract_rules)
      end

      x.compare!
    end
  end
end

# Run if executed directly
MergingBenchmark.run if __FILE__ == $PROGRAM_NAME
