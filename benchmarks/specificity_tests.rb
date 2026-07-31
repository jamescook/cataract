# frozen_string_literal: true

# Shared test definitions for specificity benchmarks
module SpecificityTests
  def self.metadata
    {
      'test_cases' => [
        {
          'name' => 'Simple Selectors',
          'id' => 'simple',
          'selectors' => { 'div' => 1, '.class' => 10, '#id' => 100 }
        },
        {
          'name' => 'Compound Selectors',
          'id' => 'compound',
          'selectors' => { 'div.container' => 11, 'div#main' => 101, 'div.container#main' => 111 }
        },
        {
          'name' => 'Combinators',
          'id' => 'combinators',
          'selectors' => { 'div p' => 2, 'div > p' => 2, 'h1 + p' => 2, 'div.container > p.intro' => 22 }
        },
        {
          'name' => 'Pseudo-classes & Pseudo-elements',
          'id' => 'pseudo',
          'selectors' => { 'a:hover' => 11, 'p::before' => 2, 'li:first-child' => 11, 'p:first-child::before' => 12 }
        },
        {
          'name' => ':not() Pseudo-class (CSS3)',
          'id' => 'not',
          'selectors' => { '#s12:not(foo)' => 101, 'div:not(.active)' => 11, '.button:not([disabled])' => 20 }
        },
        {
          'name' => 'Complex Real-world Selectors',
          'id' => 'complex',
          'selectors' => {
            'ul#nav li.active a:hover' => 122,
            'div.wrapper > article#main > section.content > p:first-child' => 123,
            "[data-theme='dark'] body.admin #dashboard .widget a[href^='http']::before" => 143
          }
        }
      ]
    }
  end

  def sanity_checks
    case implementation.backend.id
    when :pure, :native
      # Verify Cataract calculations
      raise 'Cataract simple selector failed' unless specificity_of('div') == 1
      raise 'Cataract class selector failed' unless specificity_of('.class') == 10
      raise 'Cataract id selector failed' unless specificity_of('#id') == 100
    end
  end

  # calculate_specificity isn't public API - go through Rule#specificity like
  # a real caller would. A fresh Rule each time means specificity is nil, so
  # #specificity always calculates for real rather than returning a memoized
  # value.
  def specificity_of(selector)
    Cataract::Rule.make(id: 0, selector: selector, declarations: []).specificity
  end

  def call
    self.class.metadata['test_cases'].each do |test_case|
      benchmark_category(test_case)
    end
  end

  private

  def benchmark_category(test_case)
    puts '=' * 80
    puts "TEST: #{test_case['name']} - #{implementation.label}"
    puts test_case['note'] if test_case['note']
    puts '=' * 80

    id = test_case['id']
    selectors = test_case['selectors']

    # Show individual selector examples in terminal output
    puts 'Selectors tested:'
    selectors.each do |selector, expected_specificity|
      puts "  #{selector} => #{expected_specificity}"
    end
    puts

    # Both backends run identical code; which one is exercised was decided
    # when `require 'cataract'` picked a backend.
    benchmark(id) do |x|
      x.config(time: 2, warmup: 1)

      x.report(result_name(id)) do
        selectors.each_key { |selector| specificity_of(selector) }
      end
    end
  end
end
