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

module BenchmarkSpecificity
  def self.run
    puts '=' * 60
    puts 'SPECIFICITY CALCULATION BENCHMARK'
    puts '=' * 60

    # Simple selectors
    simple_selectors = {
      'div' => 1,
      '.class' => 10,
      '#id' => 100
    }

    # Compound selectors
    compound_selectors = {
      'div.container' => 11,
      'div#main' => 101,
      'div.container#main' => 111
    }

    # Combinators
    combinator_selectors = {
      'div p' => 2,
      'div > p' => 2,
      'h1 + p' => 2,
      'div.container > p.intro' => 22
    }

    # Pseudo-classes and pseudo-elements
    pseudo_selectors = {
      'a:hover' => 11,
      'p::before' => 2,
      'li:first-child' => 11,
      'p:first-child::before' => 12
    }

    # :not() pseudo-class (CSS3)
    not_selectors = {
      '#s12:not(foo)' => 101,
      'div:not(.active)' => 11,
      '.button:not([disabled])' => 20
    }

    # Complex real-world selectors
    complex_selectors = {
      'ul#nav li.active a:hover' => 122,
      'div.wrapper > article#main > section.content > p:first-child' => 123,
      "[data-theme='dark'] body.admin #dashboard .widget a[href^='http']::before" => 143
    }

    benchmark_category('Simple Selectors', simple_selectors)
    benchmark_category('Compound Selectors', compound_selectors)
    benchmark_category('Combinators', combinator_selectors)
    benchmark_category('Pseudo-classes & Pseudo-elements', pseudo_selectors)
    benchmark_category(':not() Pseudo-class (CSS3)', not_selectors,
                       note: "css_parser has a bug - doesn't parse :not() content")
    benchmark_category('Complex Real-world Selectors', complex_selectors)

    # Special test: :not() overhead
    puts "\n#{'=' * 60}"
    puts 'OVERHEAD: :not() vs Simple Selector'
    puts '=' * 60
    simple = 'div.container#main'
    with_not = 'div.container#main:not(.disabled)'
    puts "Simple:    #{simple} => #{Cataract.calculate_specificity(simple)}"
    puts "With :not: #{with_not} => #{Cataract.calculate_specificity(with_not)}"

    Benchmark.ips do |x|
      x.config(time: 2, warmup: 1)

      x.report('simple') { Cataract.calculate_specificity(simple) }
      x.report('with :not()') { Cataract.calculate_specificity(with_not) }

      x.compare!
    end
  end

  def self.benchmark_category(name, selectors, note: nil)
    puts "\n#{'=' * 60}"
    puts "CATEGORY: #{name}"
    puts '=' * 60
    puts note if note

    if CSS_PARSER_AVAILABLE
      Benchmark.ips do |x|
        x.config(time: 2, warmup: 1)

        selectors.each_key do |selector|
          x.report("css_parser: #{selector}") do
            CssParser.calculate_specificity(selector)
          end

          x.report("cataract:   #{selector}") do
            Cataract.calculate_specificity(selector)
          end
        end

        x.compare!
      end
    else
      puts 'Install css_parser gem for comparison'

      Benchmark.ips do |x|
        x.config(time: 2, warmup: 1)

        selectors.each_key do |selector|
          x.report("cataract: #{selector}") do
            Cataract.calculate_specificity(selector)
          end
        end
      end
    end
  end
end

# Run the benchmark if this file is executed directly
BenchmarkSpecificity.run if __FILE__ == $PROGRAM_NAME
