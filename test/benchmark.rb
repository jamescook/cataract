require 'benchmark/ips'

# Load the local development version, not installed gem
$LOAD_PATH.unshift File.expand_path('../lib', __dir__)
require 'cataract'

begin
  require 'css_parser'
  CSS_PARSER_AVAILABLE = true
rescue LoadError
  CSS_PARSER_AVAILABLE = false
  puts "css_parser gem not available - install with: gem install css_parser"
end

module Benchmark
  def self.run
    # Verify we're using the local version
    puts "="*60
    puts "FAST CSS PARSER BENCHMARK (Development Version)"
    puts "="*60
    puts "Loading from: #{File.expand_path('../lib/cataract.rb', __dir__)}"
    
    # CSS1 test CSS
    test_css_css1 = %{
      /* Main layout with enhanced features */
      .header, .main-header {
        color: #3366cc;
        background: #ffffff;
        padding: 10px 15px;
        margin: 0 auto;
        border-radius: 4px;
        box-shadow: 0 2px 4px rgba(0,0,0,0.1)
      }

      .main-content, .content-wrapper {
        font-size: 16px;
        line-height: 1.5em;
        max-width: 1200px;
        width: 100%;
        padding: 20px;
        margin: 0 auto
      }

      #navigation, #main-nav {
        background: #f8f9fa;
        border: 1px solid #dee2e6;
        position: fixed;
        top: 0;
        z-index: 1000
      }

      body {
        margin: 0;
        padding: 0;
        font-family: Arial;
        background-color: #f5f5f5
      }

      .footer-links, .footer .links {
        text-decoration: none;
        color: #6c757d;
        font-size: 14px;
        padding: 5px 10px
      }

      /* Utility classes with various units */
      .text-large, .big-text {
        font-size: 1.25rem;
        font-weight: 600
      }

      .bg-dark, .dark-background {
        background-color: #343a40;
        color: #ffffff
      }

      #sidebar, .sidebar {
        width: 250px;
        height: 100vh;
        overflow-y: auto;
        padding: 1rem
      }

      .container, .wrapper, .content {
        max-width: 1140px;
        margin: 0 auto;
        padding: 0 15px
      }
    }

    # CSS2 test CSS with @media queries and combinators
    test_css_css2 = %{
      /* Base styles */
      body {
        margin: 0;
        padding: 0;
        font-family: Arial, sans-serif;
        background-color: #ffffff
      }

      .header {
        color: #333;
        padding: 20px;
        background: #f8f9fa
      }

      .container {
        max-width: 1200px;
        margin: 0 auto;
        padding: 0 15px
      }

      /* CSS2 Combinators */
      div p {
        line-height: 1.6
      }

      .container > .item {
        margin-bottom: 20px
      }

      h1 + p {
        margin-top: 0;
        font-size: 1.2em
      }

      .nav > ul > li {
        display: inline-block;
        padding: 0 15px
      }

      article > header > h1 {
        color: #2c3e50;
        font-size: 2rem
      }

      .sidebar ~ .content {
        margin-left: 260px
      }

      div.wrapper > article#main {
        padding: 20px;
        background: white
      }

      /* Print styles */
      @media print {
        body {
          margin: 0;
          color: #000;
          background: #fff
        }

        .header {
          padding: 10px;
          border-bottom: 1px solid #000
        }

        .no-print {
          display: none
        }
      }

      /* Mobile styles */
      @media screen {
        .mobile-menu {
          display: block;
          padding: 10px
        }

        .container {
          padding: 0 10px
        }
      }

      /* Multiple media types */
      @media screen, print {
        .universal {
          font-size: 14px;
          line-height: 1.5
        }

        #footer {
          margin-top: 20px;
          padding: 10px
        }
      }

      /* More base styles after media queries */
      .sidebar {
        width: 250px;
        float: left
      }

      #content {
        margin-left: 260px
      }
    }

    fast_parser = Cataract::Parser.new

    if fast_parser.using_c_extension?
      puts "Cataract: Using C extension ⚡"
    else
      puts "Cataract: Using pure Ruby fallback 🐌"
    end

    # Verify both test cases work before benchmarking
    puts "\nVerifying CSS1 test case..."
    begin
      fast_parser.parse(test_css_css1)
      puts "  ✅ CSS1 parsed successfully (#{fast_parser.rules_count} rules)"
    rescue => e
      puts "  ❌ ERROR: Failed to parse CSS1: #{e.message}"
      return
    end

    puts "Verifying CSS2 test case with @media queries..."
    begin
      fast_parser.parse(test_css_css2)
      puts "  ✅ CSS2 parsed successfully (#{fast_parser.rules_count} rules)"
    rescue => e
      puts "  ❌ ERROR: Failed to parse CSS2: #{e.message}"
      return
    end

    puts "="*60
    puts "BENCHMARK: CSS1 (#{test_css_css1.lines.count} lines, #{test_css_css1.length} chars)"
    puts "="*60

    if CSS_PARSER_AVAILABLE
      Benchmark.ips do |x|
        x.config(time: 5, warmup: 2)

        x.report("css_parser gem") do
          parser = CssParser::Parser.new(import: false, io_exceptions: false)
          parser.add_block!(test_css_css1)
        end

        x.report("cataract") do
          parser = Cataract::Parser.new
          parser.parse(test_css_css1)
        end

        x.compare!
      end
    else
      puts "Install css_parser gem for comparison benchmarks"

      Benchmark.ips do |x|
        x.config(time: 5, warmup: 2)

        x.report("cataract") do
          parser = Cataract::Parser.new
          parser.parse(test_css_css1)
        end
      end
    end

    puts "\n" + "="*60
    puts "BENCHMARK: CSS2 with @media (#{test_css_css2.lines.count} lines, #{test_css_css2.length} chars)"
    puts "="*60

    if CSS_PARSER_AVAILABLE
      Benchmark.ips do |x|
        x.config(time: 5, warmup: 2)

        x.report("css_parser gem") do
          parser = CssParser::Parser.new(import: false, io_exceptions: false)
          parser.add_block!(test_css_css2)
        end

        x.report("cataract") do
          parser = Cataract::Parser.new
          parser.parse(test_css_css2)
        end

        x.compare!
      end
    else
      Benchmark.ips do |x|
        x.config(time: 5, warmup: 2)

        x.report("cataract") do
          parser = Cataract::Parser.new
          parser.parse(test_css_css2)
        end
      end
    end

    puts "\n" + "="*60
    puts "CORRECTNESS COMPARISON (CSS2)"
    puts "="*60

    # Test functionality on CSS2
    fast_parser.parse(test_css_css2)
    puts "Cataract found #{fast_parser.rules_count} rules"

    if CSS_PARSER_AVAILABLE
      css_parser = CssParser::Parser.new(import: false, io_exceptions: false)
      css_parser.add_block!(test_css_css2)

      css_parser_rules = 0
      css_parser.each_selector { css_parser_rules += 1 }
      puts "css_parser found #{css_parser_rules} rules"

      if fast_parser.rules_count == css_parser_rules
        puts "✅ Same number of rules parsed"
      else
        puts "⚠️  Different number of rules parsed"
      end

      # Show a sample of what we parsed
      puts "\nSample Cataract output:"
      fast_parser.each_selector.first(5) do |selector, declarations, specificity|
        puts "  #{selector}: #{declarations} (spec: #{specificity})"
      end
    end
    
    puts "\n" + "="*60
    puts "BENCHMARK: Specificity Calculation"
    puts "="*60

    # Test complex specificity selectors
    complex_selectors = [
      "div",                                                      # 1
      "div.container",                                            # 11
      "#header",                                                  # 100
      "div.container#main",                                       # 111
      "div.container > p.intro",                                  # 22
      "ul#nav li.active a:hover",                                # 122
      "div.wrapper > article#main > section.content > p:first-child",  # 123
      "[data-theme='dark'] body.admin #dashboard .widget:nth-child(2n) a[href^='http']::before"  # 143
    ]

    if CSS_PARSER_AVAILABLE
      # Verify correctness first
      puts "\nVerifying specificity calculation matches css_parser:"
      complex_selectors.each do |selector|
        cataract_spec = Cataract.calculate_specificity(selector)

        # css_parser calculates specificity differently - it uses CssParser::RuleSet
        css_parser_parser = CssParser::Parser.new
        css_parser_parser.add_block!("#{selector} { color: red }")
        css_parser_spec = nil
        css_parser_parser.each_selector do |sel, decs, spec|
          css_parser_spec = spec if sel == selector
        end

        match = cataract_spec == css_parser_spec ? "✓" : "✗"
        puts "  #{match} #{selector.ljust(80)} Cataract: #{cataract_spec.to_s.rjust(3)}, css_parser: #{css_parser_spec.to_s.rjust(3)}"
      end

      puts "\nBenchmarking specificity calculation:"
      Benchmark.ips do |x|
        x.config(time: 3, warmup: 1)

        x.report("css_parser") do
          complex_selectors.each do |selector|
            parser = CssParser::Parser.new
            parser.add_block!("#{selector} { color: red }")
            parser.each_selector { |s, d, spec| spec }
          end
        end

        x.report("cataract") do
          complex_selectors.each do |selector|
            Cataract.calculate_specificity(selector)
          end
        end

        x.compare!
      end
    else
      puts "Install css_parser gem for comparison"

      Benchmark.ips do |x|
        x.config(time: 3, warmup: 1)

        x.report("cataract") do
          complex_selectors.each do |selector|
            Cataract.calculate_specificity(selector)
          end
        end
      end
    end

    puts "\n" + "="*60
    puts "EXTENSION INFO"
    puts "="*60
    
    if CATARACT_C_EXT
      puts "✅ C extension loaded successfully"
      
      # Check where the extension was loaded from
      extension_path = $LOADED_FEATURES.find { |f| f.include?('cataract') && f.end_with?('.bundle') }
      if extension_path
        puts "Extension path: #{extension_path}"
      end
    else
      puts "⚠️  Using Ruby fallback (C extension not available)"
    end
    
    puts "Ruby version: #{RUBY_VERSION}"
    puts "Platform: #{RUBY_PLATFORM}"
  end
end

# Run the benchmark if this file is executed directly
if __FILE__ == $0
  Benchmark.run
end
