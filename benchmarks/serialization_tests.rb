# frozen_string_literal: true

# Shared test definitions for serialization benchmarks
module SerializationTests
  # Determines if YJIT testing is applicable for a given implementation
  def self.yjit_applicable?(impl_type)
    base_impl = impl_type.to_s.sub(/_with_yjit|_without_yjit/, '').to_sym
    base_impl != :native
  end

  def self.metadata
    # Create a temporary instance to access fixture data
    instance = Class.new do
      def bootstrap_path
        File.expand_path('../test/fixtures/bootstrap.css', __dir__)
      end

      def bootstrap_css
        @bootstrap_css ||= File.read(bootstrap_path)
      end
    end.new

    {
      'test_cases' => [
        {
          'name' => "Full Serialization (Bootstrap CSS - #{(instance.bootstrap_css.length / 1024.0).round}KB)",
          'key' => 'all',
          'bytes' => instance.bootstrap_css.length
        },
        {
          'name' => 'Media Type Filtering (print only)',
          'key' => 'print',
          'bytes' => instance.bootstrap_css.length
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
    # Verify Bootstrap fixture exists
    raise "Bootstrap CSS fixture not found at #{bootstrap_path}" unless File.exist?(bootstrap_path)

    case base_impl_type
    when :css_parser
      require 'css_parser'
      # Basic sanity check
      parser = CssParser::Parser.new
      parser.add_block!(bootstrap_css)
      raise 'css_parser sanity check failed' if parser.to_s.empty?
    when :pure, :native
      # Verify parsing and serialization work
      cataract_sheet = Cataract.parse_css(bootstrap_css)
      raise 'Failed to parse Bootstrap CSS' if cataract_sheet.empty?

      cataract_output = cataract_sheet.to_s
      raise 'Serialization produced empty output' if cataract_output.empty?

      # Verify output can be re-parsed
      reparsed = Cataract.parse_css(cataract_output)
      raise 'Failed to re-parse serialized output' if reparsed.empty?
    end
  end

  def call
    run_full_serialization_benchmark
    run_media_filtering_benchmark
  end

  def bootstrap_css
    @bootstrap_css ||= File.read(bootstrap_path)
  end

  private

  def bootstrap_path
    @bootstrap_path ||= File.expand_path('../test/fixtures/bootstrap.css', __dir__)
  end

  def implementation_label
    base_label = case base_impl_type
                 when :css_parser
                   'css_parser gem'
                 when :pure
                   'cataract pure'
                 when :native
                   'cataract'
                 end

    yjit_suffix = if SerializationTests.yjit_applicable?(impl_type)
                    impl_type.to_s.include?('with_yjit') ? ' (YJIT)' : ' (no YJIT)'
                  else
                    ''
                  end

    "#{base_label}#{yjit_suffix}"
  end

  def run_full_serialization_benchmark
    puts '=' * 80
    puts "TEST: Full serialization (to_s) - #{implementation_label}"
    puts '=' * 80
    puts '(Parsing done once before benchmark, not included in measurements)'

    benchmark('all') do |x|
      x.config(time: 5, warmup: 2)

      case base_impl_type
      when :css_parser
        # Pre-parse CSS once (outside benchmark loop)
        css_parser_parsed = CssParser::Parser.new
        css_parser_parsed.add_block!(bootstrap_css)

        x.report('css_parser gem: all') do
          css_parser_parsed.to_s
        end

      when :pure
        # Pre-parse CSS once
        cataract_parsed = Cataract.parse_css(bootstrap_css)

        x.report('cataract pure: all') do
          cataract_parsed.to_s
        end

      when :native
        # Pre-parse CSS once
        cataract_parsed = Cataract.parse_css(bootstrap_css)

        x.report('cataract: all') do
          cataract_parsed.to_s
        end
      end
    end
  end

  def run_media_filtering_benchmark
    puts "\n#{'=' * 80}"
    puts "TEST: Media type filtering - to_s(:print) - #{implementation_label}"
    puts '=' * 80

    benchmark('print') do |x|
      x.config(time: 5, warmup: 2)

      case base_impl_type
      when :css_parser
        css_parser_for_filter = CssParser::Parser.new
        css_parser_for_filter.add_block!(bootstrap_css)

        x.report('css_parser gem: print') do
          css_parser_for_filter.to_s(:print)
        end

      when :pure
        # Use Stylesheet API for media filtering
        cataract_parser = Cataract::Stylesheet.new
        cataract_parser.add_block(bootstrap_css)

        x.report('cataract pure: print') do
          cataract_parser.to_s(media: :print)
        end

      when :native
        # Use Stylesheet API for media filtering
        cataract_parser = Cataract::Stylesheet.new
        cataract_parser.add_block(bootstrap_css)

        x.report('cataract: print') do
          cataract_parser.to_s(media: :print)
        end
      end
    end
  end
end
