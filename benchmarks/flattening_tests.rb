# frozen_string_literal: true

# Shared test definitions for flattening benchmarks
module FlatteningTests
  # Determines if YJIT testing is applicable for a given implementation
  def self.yjit_applicable?(impl_type)
    base_impl = impl_type.to_s.sub(/_with_yjit|_without_yjit/, '').to_sym
    base_impl != :native
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
          'name' => 'Complex flattening',
          'key' => 'complex',
          'css' => "body { margin: 0; padding: 0; }\n.container { width: 100%; margin: 0 auto; }\n#main { background: white; color: black; }\n.button { padding: 10px 20px; border: 1px solid #ccc; }\n.button:hover { background: #f0f0f0; }\n.button.primary { background: blue !important; color: white; }"
        }
      ]
    }
  end

  def self.speedup_config
    # Compare cataract pure without YJIT (baseline) vs cataract native (comparison)
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
      # Verify flattening works correctly with Cataract
      css = ".test { color: black; }\n.test { margin: 10px; }"
      cataract_rules = Cataract.parse_css(css)
      cataract_flattened = Cataract.flatten(cataract_rules)

      raise 'Cataract flatten failed' if cataract_flattened.rules.empty?

      flattened_decls = cataract_flattened.rules.first.declarations
      raise 'Cataract flatten incorrect' unless flattened_decls.any? { |d| d.property == 'color' }
    end
  end

  def call
    self.class.metadata['test_cases'].each do |test_case|
      benchmark_test_case(test_case)
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

    yjit_suffix = if FlatteningTests.yjit_applicable?(impl_type)
                    impl_type.to_s.include?('with_yjit') ? ' (YJIT)' : ' (no YJIT)'
                  else
                    ''
                  end

    "#{base_label}#{yjit_suffix}"
  end

  def benchmark_test_case(test_case)
    puts '=' * 80
    puts "TEST: #{test_case['name']} - #{implementation_label}"
    puts '=' * 80

    key = test_case['key']
    css = test_case['css']

    benchmark(key) do |x|
      x.config(time: 5, warmup: 2)

      case base_impl_type
      when :pure
        # Cataract pure Ruby
        cataract_rules = Cataract.parse_css(css)

        x.report("cataract pure: #{key}") do
          Cataract.flatten(cataract_rules)
        end

      when :native
        # Cataract C extension
        cataract_rules = Cataract.parse_css(css)

        x.report("cataract: #{key}") do
          Cataract.flatten(cataract_rules)
        end
      end
    end
  end
end
