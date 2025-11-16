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

      def compact_path
        File.expand_path('../test/fixtures/serialization_compact.css', __dir__)
      end

      def nested_path
        File.expand_path('../test/fixtures/serialization_nested.css', __dir__)
      end

      def selector_lists_path
        File.expand_path('../test/fixtures/serialization_selector_lists.css', __dir__)
      end

      def bootstrap_css
        @bootstrap_css ||= File.read(bootstrap_path)
      end

      def compact_css
        @compact_css ||= File.read(compact_path)
      end

      def nested_css
        @nested_css ||= File.read(nested_path)
      end

      def selector_lists_css
        @selector_lists_css ||= File.read(selector_lists_path)
      end
    end.new

    {
      'test_cases' => [
        {
          'name' => "to_s (Bootstrap - #{(instance.bootstrap_css.length / 1024.0).round}KB)",
          'key' => 'bootstrap_compact',
          'bytes' => instance.bootstrap_css.length,
          'method' => 'to_s'
        },
        {
          'name' => "to_s (Compact utilities - #{(instance.compact_css.length / 1024.0).round(1)}KB)",
          'key' => 'compact',
          'bytes' => instance.compact_css.length,
          'method' => 'to_s'
        },
        {
          'name' => "to_formatted_s (Nested CSS - #{(instance.nested_css.length / 1024.0).round(1)}KB)",
          'key' => 'formatted_nested',
          'bytes' => instance.nested_css.length,
          'method' => 'to_formatted_s'
        },
        {
          'name' => "to_s with selector_lists (#{(instance.selector_lists_css.length / 1024.0).round(1)}KB)",
          'key' => 'selector_lists',
          'bytes' => instance.selector_lists_css.length,
          'method' => 'to_s',
          'selector_lists' => true
        },
        {
          'name' => 'Media filtering (Bootstrap print only)',
          'key' => 'media_print',
          'bytes' => instance.bootstrap_css.length,
          'method' => 'to_s',
          'media' => 'print'
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
    # Verify fixtures exist
    raise "Bootstrap CSS fixture not found at #{bootstrap_path}" unless File.exist?(bootstrap_path)
    raise "Compact CSS fixture not found at #{compact_path}" unless File.exist?(compact_path)
    raise "Nested CSS fixture not found at #{nested_path}" unless File.exist?(nested_path)
    raise "Selector lists CSS fixture not found at #{selector_lists_path}" unless File.exist?(selector_lists_path)

    case base_impl_type
    when :pure, :native
      # Verify parsing and serialization work
      cataract_sheet = Cataract.parse_css(bootstrap_css)
      raise 'Failed to parse Bootstrap CSS' if cataract_sheet.empty?

      cataract_output = cataract_sheet.to_s
      raise 'Serialization produced empty output' if cataract_output.empty?

      # Verify output can be re-parsed
      reparsed = Cataract.parse_css(cataract_output)
      raise 'Failed to re-parse serialized output' if reparsed.empty?

      # Verify to_formatted_s works
      formatted = cataract_sheet.to_formatted_s
      raise 'Formatted serialization produced empty output' if formatted.empty?
    end
  end

  def call
    run_bootstrap_compact_benchmark
    run_compact_benchmark
    run_formatted_nested_benchmark
    run_selector_lists_benchmark
    run_media_filtering_benchmark
  end

  def bootstrap_css
    @bootstrap_css ||= File.read(bootstrap_path)
  end

  def compact_css
    @compact_css ||= File.read(compact_path)
  end

  def nested_css
    @nested_css ||= File.read(nested_path)
  end

  def selector_lists_css
    @selector_lists_css ||= File.read(selector_lists_path)
  end

  private

  def bootstrap_path
    @bootstrap_path ||= File.expand_path('../test/fixtures/bootstrap.css', __dir__)
  end

  def compact_path
    @compact_path ||= File.expand_path('../test/fixtures/serialization_compact.css', __dir__)
  end

  def nested_path
    @nested_path ||= File.expand_path('../test/fixtures/serialization_nested.css', __dir__)
  end

  def selector_lists_path
    @selector_lists_path ||= File.expand_path('../test/fixtures/serialization_selector_lists.css', __dir__)
  end

  def implementation_label
    base_label = case base_impl_type
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

  def run_bootstrap_compact_benchmark
    puts '=' * 80
    puts "TEST: to_s (Bootstrap) - #{implementation_label}"
    puts '=' * 80
    puts '(Parsing done once before benchmark, not included in measurements)'

    benchmark('bootstrap_compact') do |x|
      x.config(time: 5, warmup: 2)

      # Pre-parse CSS once
      cataract_parsed = Cataract.parse_css(bootstrap_css)

      x.report("#{base_impl_type}: bootstrap_compact") do
        cataract_parsed.to_s
      end
    end
  end

  def run_compact_benchmark
    puts "\n#{'=' * 80}"
    puts "TEST: to_s (Compact utilities) - #{implementation_label}"
    puts '=' * 80
    puts '(Many simple rules, minimal whitespace when serialized)'

    benchmark('compact') do |x|
      x.config(time: 5, warmup: 2)

      # Pre-parse CSS once
      cataract_parsed = Cataract.parse_css(compact_css)

      x.report("#{base_impl_type}: compact") do
        cataract_parsed.to_s
      end
    end
  end

  def run_formatted_nested_benchmark
    puts "\n#{'=' * 80}"
    puts "TEST: to_formatted_s (Nested CSS) - #{implementation_label}"
    puts '=' * 80
    puts '(Nested selectors and media queries, formatted with indentation)'

    benchmark('formatted_nested') do |x|
      x.config(time: 5, warmup: 2)

      # Pre-parse CSS once
      cataract_parsed = Cataract.parse_css(nested_css)

      x.report("#{base_impl_type}: formatted_nested") do
        cataract_parsed.to_formatted_s
      end
    end
  end

  def run_selector_lists_benchmark
    puts "\n#{'=' * 80}"
    puts "TEST: to_s with selector_lists tracking - #{implementation_label}"
    puts '=' * 80
    puts '(Many comma-separated selector lists to test tracking overhead)'

    benchmark('selector_lists') do |x|
      x.config(time: 5, warmup: 2)

      # Pre-parse CSS once with selector_lists enabled
      cataract_parsed = Cataract::Stylesheet.parse(selector_lists_css, parser: { selector_lists: true })

      x.report("#{base_impl_type}: selector_lists") do
        cataract_parsed.to_s
      end
    end
  end

  def run_media_filtering_benchmark
    puts "\n#{'=' * 80}"
    puts "TEST: Media filtering - to_s(media: :print) - #{implementation_label}"
    puts '=' * 80
    puts '(Bootstrap CSS filtered to print media only)'

    benchmark('media_print') do |x|
      x.config(time: 5, warmup: 2)

      # Use Stylesheet API for media filtering
      cataract_parser = Cataract::Stylesheet.new
      cataract_parser.add_block(bootstrap_css)

      x.report("#{base_impl_type}: media_print") do
        cataract_parser.to_s(media: :print)
      end
    end
  end
end
