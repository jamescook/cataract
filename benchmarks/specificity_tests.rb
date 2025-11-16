# frozen_string_literal: true

# Shared test definitions for specificity benchmarks
module SpecificityTests
  # Determines if YJIT testing is applicable for a given implementation
  def self.yjit_applicable?(impl_type)
    base_impl = impl_type.to_s.sub(/_with_yjit|_without_yjit/, '').to_sym
    base_impl != :native
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
          'selectors' => { '#s12:not(foo)' => 101, 'div:not(.active)' => 11, '.button:not([disabled])' => 20 }
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
    # Compare cataract pure without YJIT (baseline) vs cataract native (comparison)
    # For fair comparison, compare both without YJIT optimizations
    {
      baseline_matcher: SpeedupCalculator::Matchers.cataract_pure_without_yjit,
      comparison_matcher: SpeedupCalculator::Matchers.cataract_native,
      test_case_key: :key
    }
  end

  # Must be set by including class before calling methods
  attr_accessor :impl_type

  def base_impl_type
    impl_type.to_s.sub(/_with_yjit|_without_yjit/, '').to_sym
  end

  def sanity_checks
    case base_impl_type
    when :pure, :native
      # Verify Cataract calculations
      raise 'Cataract simple selector failed' unless Cataract.calculate_specificity('div') == 1
      raise 'Cataract class selector failed' unless Cataract.calculate_specificity('.class') == 10
      raise 'Cataract id selector failed' unless Cataract.calculate_specificity('#id') == 100
    end
  end

  def call
    self.class.metadata['test_cases'].each do |test_case|
      benchmark_category(test_case)
    end
  end

  private

  def implementation_label
    base_label = case base_impl_type
                 when :pure
                   'cataract pure'
                 when :native
                   'cataract'
                 end

    yjit_suffix = if SpecificityTests.yjit_applicable?(impl_type)
                    impl_type.to_s.include?('with_yjit') ? ' (YJIT)' : ' (no YJIT)'
                  else
                    ''
                  end

    "#{base_label}#{yjit_suffix}"
  end

  def benchmark_category(test_case)
    puts '=' * 80
    puts "TEST: #{test_case['name']} - #{implementation_label}"
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

      case base_impl_type
      when :pure
        x.report("cataract pure: #{key}") do
          selectors.each_key do |selector|
            Cataract.calculate_specificity(selector)
          end
        end

      when :native
        x.report("cataract: #{key}") do
          selectors.each_key do |selector|
            Cataract.calculate_specificity(selector)
          end
        end
      end
    end
  end
end
