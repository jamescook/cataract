# frozen_string_literal: true

require 'erb'
require 'uri'
require_relative '../../lib/cataract'
require_relative 'analyzers/properties'
require_relative 'analyzers/colors'
require_relative 'analyzers/specificity'
require_relative 'analyzers/important'

module CSSAnalyzer
  # Main analyzer orchestrator that coordinates all analysis modules
  class Analyzer
    attr_reader :stylesheet, :source, :options, :timings

    def initialize(source, options = {})
      @source = source
      @options = {
        top: 20,
        use_shim: false
      }.merge(options)
      @timings = {}

      # Load shim if requested
      if @options[:use_shim]
        require_relative '../../lib/cataract/css_parser_compat'
        Cataract.mimic_CssParser!
      end

      # Load CSS based on source type
      @stylesheet = load_css(source)
    end

    # Run all analyses and collect results
    def analyze_all
      {
        summary: analyze_summary,
        properties: Analyzers::Properties.new(stylesheet, options).analyze,
        colors: Analyzers::Colors.new(stylesheet, options).analyze,
        specificity: Analyzers::Specificity.new(stylesheet, options).analyze,
        important: Analyzers::Important.new(stylesheet, options).analyze
      }
    end

    # Generate summary statistics
    def analyze_summary
      {
        total_rules: stylesheet.size,
        file_name: source_name,
        file_path: source,
        generated_at: Time.now
      }
    end

    # Generate HTML report
    def generate_report
      analysis = analyze_all
      template = ERB.new(template_content, trim_mode: '-')
      template.result(binding)
    end

    # Save report to file or stdout
    def save_report
      report = generate_report

      if options[:output]
        File.write(options[:output], report)
        puts "Report saved to #{options[:output]}"
      else
        puts report
      end

      # Also save the parsed CSS for debugging
      save_parsed_css
    end

    # Save parsed CSS to a file for debugging/comparison
    def save_parsed_css
      # Generate a unique filename based on source and shim usage
      source_slug = @source.gsub(%r{[:/]}, '_').gsub(/[^a-zA-Z0-9_.-]/, '')
      shim_suffix = @options[:use_shim] ? '-shim' : '-direct'
      filename = "parsed-css-#{source_slug}#{shim_suffix}.css"

      # Serialize stylesheet to CSS
      css_output = @stylesheet.to_s

      File.write(filename, css_output)
      warn "Parsed CSS saved to #{filename} (#{@stylesheet.size} rules, #{css_output.length} bytes)"
    end

    private

    def load_css(source)
      # Check if it's a URL
      if /\A#{URI::DEFAULT_PARSER.make_regexp(%w[http https])}\z/.match?(source)
        load_from_url(source)
      elsif File.exist?(source)
        # Local file
        Cataract::Stylesheet.load_file(source)
      else
        raise ArgumentError, "Invalid source: #{source} (not a valid URL or file path)"
      end
    end

    def load_from_url(url)
      # Check if it's a direct CSS file
      if url.end_with?('.css')
        Cataract::Stylesheet.load_uri(url)
      else
        # It's a webpage - use Premailer to fetch and combine all CSS
        load_from_webpage(url)
      end
    end

    def load_from_webpage(url)
      require 'premailer'

      # Fetch webpage and extract CSS
      fetch_start = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      premailer = Premailer.new(url, with_html_string: false)
      @timings[:fetch] = Process.clock_gettime(Process::CLOCK_MONOTONIC) - fetch_start

      # Get CSS parser from Premailer
      parser = premailer.instance_variable_get(:@css_parser)

      # If using Cataract shim, parser is already a Cataract::Stylesheet - use it directly
      if defined?(CssParser::CATARACT_SHIM) && CssParser::CATARACT_SHIM
        @timings[:premailer_parse] = 0  # Already parsed by Premailer/Cataract
        @timings[:cataract_parse] = 0   # No reparsing needed
        parser # Return the Cataract::Stylesheet directly
      else
        # Not using shim - parser is real css_parser, get CSS string and reparse
        parse_start = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        css_string = parser.to_s
        @timings[:premailer_parse] = Process.clock_gettime(Process::CLOCK_MONOTONIC) - parse_start

        # Parse it with Cataract
        cataract_start = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        stylesheet = Cataract.parse_css(css_string)
        @timings[:cataract_parse] = Process.clock_gettime(Process::CLOCK_MONOTONIC) - cataract_start

        stylesheet
      end
    end

    def source_name
      if /\A#{URI::DEFAULT_PARSER.make_regexp(%w[http https])}\z/.match?(source)
        uri = URI.parse(source)
        if source.end_with?('.css')
          File.basename(uri.path)
        else
          uri.host
        end
      else
        File.basename(source)
      end
    end

    def template_content
      template_path = File.join(__dir__, 'templates', 'report.html.erb')
      File.read(template_path)
    end
  end
end
