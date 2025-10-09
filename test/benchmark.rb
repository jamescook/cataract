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
    
    # Enhanced test CSS with new features
    test_css = %{
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
    
    puts "CSS: #{test_css.lines.count} lines, #{test_css.length} chars"
    
    fast_parser = Cataract::Parser.new
    
    if fast_parser.using_c_extension?
      puts "Cataract: Using C extension ⚡"
    else
      puts "Cataract: Using pure Ruby fallback 🐌"
    end
    
    # Verify it works before benchmarking
    begin
      result = fast_parser.parse(test_css)
      puts "Cataract parsed rules successfully"
    rescue => e
      puts "ERROR: Cataract failed to parse test CSS: #{e.message}"
      puts "Make sure you've run 'rake compile' first"
      return
    end
    
    puts "="*60
    
    if CSS_PARSER_AVAILABLE
      Benchmark.ips do |x|
        x.config(time: 10, warmup: 3)
        
        x.report("css_parser gem") do
          parser = CssParser::Parser.new(import: false, io_exceptions: false)
          parser.add_block!(test_css)
        end
        
        x.report("cataract") do
          parser = Cataract::Parser.new
          parser.parse(test_css)
        end
        
        x.compare!
      end
    else
      puts "Install css_parser gem for comparison benchmarks"
      
      Benchmark.ips do |x|
        x.config(time: 5, warmup: 2)
        
        x.report("cataract") do
          parser = Cataract::Parser.new
          parser.parse(test_css)
        end
      end
    end
    
    puts "\n" + "="*60
    puts "CORRECTNESS COMPARISON"
    puts "="*60
    
    # Test functionality
    fast_parser.parse(test_css)
    puts "Cataract found #{fast_parser.rules_count} rules"
    
    if CSS_PARSER_AVAILABLE
      css_parser = CssParser::Parser.new(import: false, io_exceptions: false)
      css_parser.add_block!(test_css)
      
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
      fast_parser.each_selector.first(3) do |selector, declarations, specificity|
        puts "  #{selector}: #{declarations} (spec: #{specificity})"
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
