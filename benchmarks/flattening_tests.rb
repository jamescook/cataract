# frozen_string_literal: true

# Shared test definitions for flattening benchmarks
module FlatteningTests
  def self.metadata
    {
      'test_cases' => [
        {
          'name' => 'No shorthand properties (large)',
          'id' => 'no_shorthand',
          'css' => (".test { color: red; background-color: blue; display: block; position: relative; width: 100px; height: 50px; }\n" * 100)
        },
        {
          'name' => 'Simple properties',
          'id' => 'simple',
          'css' => ".test { color: black; margin: 10px; }\n.test { padding: 5px; }"
        },
        {
          'name' => 'Cascade with specificity',
          'id' => 'cascade',
          'css' => ".test { color: black; }\n#test { color: red; }\n.test { margin: 10px; }"
        },
        {
          'name' => 'Important declarations',
          'id' => 'important',
          'css' => ".test { color: black !important; }\n#test { color: red; }\n.test { margin: 10px; }"
        },
        {
          'name' => 'Shorthand expansion',
          'id' => 'shorthand',
          'css' => ".test { margin: 10px 20px; }\n.test { margin-left: 5px; }\n.test { padding: 1em 2em 3em 4em; }"
        },
        {
          'name' => 'Complex flattening',
          'id' => 'complex',
          'css' => "body { margin: 0; padding: 0; }\n.container { width: 100%; margin: 0 auto; }\n#main { background: white; color: black; }\n.button { padding: 10px 20px; border: 1px solid #ccc; }\n.button:hover { background: #f0f0f0; }\n.button.primary { background: blue !important; color: white; }"
        }
      ]
    }
  end

  def sanity_checks
    case implementation.backend.id
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

  def benchmark_test_case(test_case)
    puts '=' * 80
    puts "TEST: #{test_case['name']} - #{implementation.label}"
    puts '=' * 80

    id = test_case['id']

    # Both backends run identical code; which one is exercised was decided
    # when `require 'cataract'` picked a backend.
    benchmark(id) do |x|
      x.config(time: 5, warmup: 2)

      cataract_rules = Cataract.parse_css(test_case['css'])

      x.report(result_name(id)) do
        Cataract.flatten(cataract_rules)
      end
    end
  end
end
