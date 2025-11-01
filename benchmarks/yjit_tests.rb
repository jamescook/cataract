# frozen_string_literal: true

# Shared test logic for YJIT benchmarks
# Extended by both YjitWithoutBenchmark and YjitWithBenchmark
module YjitTests
  SAMPLE_CSS = <<~CSS
    body { margin: 0; padding: 0; font-family: Arial, sans-serif; }
    .header { color: #333; padding: 20px; background: #f8f9fa; }
    .container { max-width: 1200px; margin: 0 auto; }
    div p { line-height: 1.6; }
    .container > .item { margin-bottom: 20px; }
    h1 + p { margin-top: 0; font-size: 1.2em; }
  CSS

  def self.metadata
    {
      'operations' => [
        'property access',
        'declaration merging',
        'to_s generation',
        'parse + iterate'
      ],
      'note' => 'C extension performance is the same regardless of YJIT. This measures Ruby code.'
    }
  end

  def self.speedup_config
    # Compare without YJIT (baseline) vs with YJIT (comparison)
    {
      baseline_matcher: SpeedupCalculator::Matchers.without_yjit,
      comparison_matcher: SpeedupCalculator::Matchers.with_yjit,
      test_case_key: nil # No test_cases array, just operations
    }
  end

  def sanity_checks
    # Verify basic operations work
    decls = Cataract::Declarations.new
    decls['color'] = 'red'
    raise 'Property access failed' unless decls['color']

    parser = Cataract::Stylesheet.new
    parser.parse(SAMPLE_CSS)
    raise 'Parse failed' if parser.rules_count.zero?
  end

  def call
    run_property_access_benchmark
    run_declaration_merging_benchmark
    run_to_s_benchmark
    run_parse_iterate_benchmark
  end

  private

  def yjit_label
    @yjit_label ||= defined?(RubyVM::YJIT.enabled?) && RubyVM::YJIT.enabled? ? 'YJIT' : 'no YJIT'
  end

  def run_property_access_benchmark
    puts '=' * 80
    puts "TEST: Property access (get/set) - #{yjit_label}"
    puts '=' * 80

    benchmark('property_access') do |x|
      x.config(time: 3, warmup: 1)

      x.report("#{yjit_label}: property access") do
        decls = Cataract::Declarations.new
        decls['color'] = 'red'
        decls['background'] = 'blue'
        decls['font-size'] = '16px'
        decls['margin'] = '10px'
        decls['padding'] = '5px'
        _ = decls['color']
        _ = decls['background']
        _ = decls['font-size']
      end
    end
  end

  def run_declaration_merging_benchmark
    puts "\n#{'=' * 80}"
    puts "TEST: Declaration merging - #{yjit_label}"
    puts '=' * 80

    benchmark('declaration_merging') do |x|
      x.config(time: 3, warmup: 1)

      x.report("#{yjit_label}: declaration merging") do
        decls1 = Cataract::Declarations.new
        decls1['color'] = 'red'
        decls1['font-size'] = '16px'

        decls2 = Cataract::Declarations.new
        decls2['background'] = 'blue'
        decls2['margin'] = '10px'

        decls1.merge(decls2)
      end
    end
  end

  def run_to_s_benchmark
    puts "\n#{'=' * 80}"
    puts "TEST: to_s generation - #{yjit_label}"
    puts '=' * 80

    benchmark('to_s') do |x|
      x.config(time: 3, warmup: 1)

      x.report("#{yjit_label}: to_s generation") do
        decls = Cataract::Declarations.new
        decls['color'] = 'red'
        decls['background'] = 'blue'
        decls['font-size'] = '16px'
        decls['margin'] = '10px'
        decls['padding'] = '5px'
        decls.to_s
      end
    end
  end

  def run_parse_iterate_benchmark
    puts "\n#{'=' * 80}"
    puts "TEST: Parse + iterate - #{yjit_label}"
    puts '=' * 80

    benchmark('parse_iterate') do |x|
      x.config(time: 3, warmup: 1)

      x.report("#{yjit_label}: parse + iterate") do
        parser = Cataract::Stylesheet.new
        parser.parse(SAMPLE_CSS)
        parser.each_selector do |_selector, declarations, _specificity|
          _ = declarations
        end
      end
    end
  end
end
