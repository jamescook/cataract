# frozen_string_literal: true

# Shared test definitions for parsing benchmarks
module ParsingTests
  # Determines if YJIT testing is applicable for a given implementation
  def self.yjit_applicable?(impl_type)
    base_impl = impl_type.to_s.sub(/_with_yjit|_without_yjit/, '').to_sym
    base_impl != :native
  end

  def self.metadata
    # Create a temporary instance to access fixture data
    instance = Class.new do
      include ParsingTests
      def fixtures_dir
        File.expand_path('../test/fixtures', __dir__)
      end
      def css1
        @css1 ||= File.read(File.join(fixtures_dir, 'css1_sample.css'))
      end
      def css2
        @css2 ||= File.read(File.join(fixtures_dir, 'css2_sample.css'))
      end
    end.new

    {
      'test_cases' => [
        {
          'name' => "Small CSS (#{instance.css1.lines.count} lines, #{(instance.css1.length / 1024.0).round(1)}KB)",
          'fixture' => 'small',
          'lines' => instance.css1.lines.count,
          'bytes' => instance.css1.length
        },
        {
          'name' => "Medium CSS with @media (#{instance.css2.lines.count} lines, #{(instance.css2.length / 1024.0).round(1)}KB)",
          'fixture' => 'medium with @media',
          'lines' => instance.css2.lines.count,
          'bytes' => instance.css2.length
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
      test_case_key: :fixture
    }
  end

  # Must be set by including class before calling methods
  attr_accessor :impl_type

  def sanity_checks
    case base_impl_type
    when :css_parser
      require 'css_parser'
      # Basic sanity check for css_parser
      parser = CssParser::Parser.new(import: false, io_exceptions: false)
      parser.add_block!(css1)
      raise 'css_parser sanity check failed' if parser.to_s.empty?
    when :pure, :native
      # Verify fixtures parse correctly with Cataract
      parser = Cataract::Stylesheet.new
      parser.add_block(css1)
      raise 'CSS1 sanity check failed: expected rules' if parser.rules_count.zero?

      parser = Cataract::Stylesheet.new
      parser.add_block(css2)
      raise 'CSS2 sanity check failed: expected rules' if parser.rules_count.zero?
    end
  end

  def base_impl_type
    impl_type.to_s.sub(/_with_yjit|_without_yjit/, '').to_sym
  end

  def call
    run_css1_benchmark
    run_css2_benchmark
  end

  def css1
    @css1 ||= File.read(File.join(fixtures_dir, 'css1_sample.css'))
  end

  def css2
    @css2 ||= File.read(File.join(fixtures_dir, 'css2_sample.css'))
  end

  private

  def fixtures_dir
    @fixtures_dir ||= File.expand_path('../test/fixtures', __dir__)
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

    yjit_suffix = if ParsingTests.yjit_applicable?(impl_type)
                    impl_type.to_s.include?('with_yjit') ? ' (YJIT)' : ' (no YJIT)'
                  else
                    ''
                  end

    "#{base_label}#{yjit_suffix}"
  end

  def run_css1_benchmark
    puts '=' * 80
    puts "TEST: Small CSS (#{css1.lines.count} lines, #{css1.length} chars) - #{implementation_label}"
    puts '=' * 80

    benchmark('css1') do |x|
      x.config(time: 5, warmup: 2)

      case base_impl_type
      when :css_parser
        x.report('css_parser gem: small') do
          parser = CssParser::Parser.new(import: false, io_exceptions: false)
          parser.add_block!(css1)
        end
      when :pure
        x.report('cataract pure: small') do
          parser = Cataract::Stylesheet.new
          parser.add_block(css1)
        end
      when :native
        x.report('cataract: small') do
          parser = Cataract::Stylesheet.new
          parser.add_block(css1)
        end
      end
    end
  end

  def run_css2_benchmark
    puts "\n#{'=' * 80}"
    puts "TEST: Medium CSS with @media (#{css2.lines.count} lines, #{css2.length} chars) - #{implementation_label}"
    puts '=' * 80

    benchmark('css2') do |x|
      x.config(time: 5, warmup: 2)

      case base_impl_type
      when :css_parser
        x.report('css_parser gem: medium with @media') do
          parser = CssParser::Parser.new(import: false, io_exceptions: false)
          parser.add_block!(css2)
        end
      when :pure
        x.report('cataract pure: medium with @media') do
          parser = Cataract::Stylesheet.new
          parser.add_block(css2)
        end
      when :native
        x.report('cataract: medium with @media') do
          parser = Cataract::Stylesheet.new
          parser.add_block(css2)
        end
      end
    end
  end
end
