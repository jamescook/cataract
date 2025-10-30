# frozen_string_literal: true

require 'benchmark/ips'

# Load the local development version, not installed gem
$LOAD_PATH.unshift File.expand_path('../lib', __dir__)
require 'cataract'

begin
  require 'css_parser'
  CSS_PARSER_AVAILABLE = true
rescue LoadError
  CSS_PARSER_AVAILABLE = false
  puts 'css_parser gem not available - install with: gem install css_parser'
  exit 1
end

module BenchmarkMerging
  def self.run
    puts "\n\n"
    puts '=' * 60
    puts 'CSS MERGING BENCHMARK'
    puts 'Measures: Time to merge multiple CSS rule sets with same selector'
    puts '=' * 60

    # Test cases for merging
    test_cases = {
      'Simple properties' => <<~CSS,
        .test { color: black; margin: 10px; }
        .test { padding: 5px; }
      CSS

      'Cascade with specificity' => <<~CSS,
        .test { color: black; }
        #test { color: red; }
        .test { margin: 10px; }
      CSS

      'Important declarations' => <<~CSS,
        .test { color: black !important; }
        #test { color: red; }
        .test { margin: 10px; }
      CSS

      'Shorthand expansion' => <<~CSS,
        .test { margin: 10px 20px; }
        .test { margin-left: 5px; }
        .test { padding: 1em 2em 3em 4em; }
      CSS

      'Complex merging' => <<~CSS
        body { margin: 0; padding: 0; }
        .container { width: 100%; margin: 0 auto; }
        #main { background: white; color: black; }
        .button { padding: 10px 20px; border: 1px solid #ccc; }
        .button:hover { background: #f0f0f0; }
        .button.primary { background: blue !important; color: white; }
      CSS
    }

    # Verify correctness before benchmarking
    puts "\n#{'=' * 60}"
    puts 'CORRECTNESS VALIDATION'
    puts '=' * 60

    test_cases.each do |name, css|
      puts "\n#{'-' * 60}"
      puts "Test case: #{name}"
      puts '-' * 60

      # Parse and merge with Cataract
      cataract_rules = Cataract.parse_css(css)
      cataract_merged = Cataract.merge(cataract_rules)

      # Convert to hash for comparison
      cataract_hash = cataract_merged.each_with_object({}) do |decl, hash|
        value = decl.value
        value = "#{value} !important" if decl.important
        hash[decl.property] = value
      end

      # Parse and merge with css_parser
      parser = CssParser::Parser.new
      parser.add_block!(css)

      # Get all rule sets
      rule_sets = []
      parser.each_selector do |selector, declarations, _specificity|
        rule_set = CssParser::RuleSet.new(selector, declarations)
        rule_sets << rule_set
      end

      # Merge using css_parser
      css_parser_merged = CssParser.merge(rule_sets)

      # Convert to hash
      css_parser_hash = {}
      css_parser_merged.each_declaration do |property, value, is_important|
        # css_parser returns value without !important, need to append if flagged
        css_parser_hash[property] = is_important ? "#{value} !important" : value
      end

      # Compare
      puts "Cataract result (#{cataract_hash.length} properties):"
      cataract_hash.sort.each do |prop, val|
        puts "  #{prop}: #{val}"
      end

      puts "\ncss_parser result (#{css_parser_hash.length} properties):"
      css_parser_hash.sort.each do |prop, val|
        puts "  #{prop}: #{val}"
      end

      # Check if they match
      if cataract_hash.keys.sort == css_parser_hash.keys.sort
        all_match = cataract_hash.all? do |prop, val|
          # Normalize whitespace for comparison
          cataract_val = val.gsub(/\s+/, ' ').strip
          css_parser_val = css_parser_hash[prop].gsub(/\s+/, ' ').strip
          cataract_val == css_parser_val
        end

        if all_match
          puts "\n✅ Results match perfectly!"
        else
          puts "\n⚠️  Same properties, different values:"
          cataract_hash.each do |prop, val|
            cataract_val = val.gsub(/\s+/, ' ').strip
            css_parser_val = css_parser_hash[prop].gsub(/\s+/, ' ').strip
            next unless cataract_val != css_parser_val

            puts "  #{prop}:"
            puts "    cataract:    '#{cataract_val}'"
            puts "    css_parser:  '#{css_parser_val}'"
          end
        end
      else
        puts "\n⚠️  Different properties found:"
        only_cataract = cataract_hash.keys - css_parser_hash.keys
        only_css_parser = css_parser_hash.keys - cataract_hash.keys
        puts "  Only in cataract: #{only_cataract.sort.join(', ')}" unless only_cataract.empty?
        puts "  Only in css_parser: #{only_css_parser.sort.join(', ')}" unless only_css_parser.empty?
      end
    end

    # Benchmarking
    puts "\n\n#{'=' * 60}"
    puts 'PERFORMANCE BENCHMARK'
    puts '=' * 60

    test_cases.each do |name, css|
      puts "\n#{name}"
      puts '-' * 60

      # Pre-parse the CSS for both
      cataract_rules = Cataract.parse_css(css)

      parser = CssParser::Parser.new
      parser.add_block!(css)
      rule_sets = []
      parser.each_selector do |selector, declarations, _specificity|
        rule_sets << CssParser::RuleSet.new(selector, declarations)
      end

      Benchmark.ips do |x|
        x.config(time: 5, warmup: 2)

        x.report('css_parser') do
          CssParser.merge(rule_sets)
        end

        x.report('cataract') do
          Cataract.merge(cataract_rules)
        end

        x.compare!
      end
    end

    puts "\n#{'=' * 60}"
    puts 'NOTES'
    puts '=' * 60
    puts 'Both implementations perform CSS cascade resolution:'
    puts '  • Specificity-based cascade (ID > class > element)'
    puts '  • !important declaration handling'
    puts '  • Shorthand property expansion'
    puts '  • Shorthand property creation from longhand'
    puts ''
    puts 'Cataract implements all merge logic in C for maximum performance.'
    puts '=' * 60
  end
end

# Run the benchmark if this file is executed directly
BenchmarkMerging.run if __FILE__ == $PROGRAM_NAME
