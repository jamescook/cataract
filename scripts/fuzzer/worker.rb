#!/usr/bin/env ruby
# frozen_string_literal: true

# Fuzzer worker process - runs in subprocess and parses CSS inputs from stdin
# Communicates via length-prefixed protocol

require 'cataract'
require 'cataract/color_conversion'

# Configure aggressive GC to help identify memory leaks
# Disable auto_compact - it can cause issues with C extensions holding pointers
GC.auto_compact = false
GC.config(
  malloc_limit: 1_000_000,
  malloc_limit_growth_factor: 1.1,   # Grow very slowly
  oldmalloc_limit_growth_factor: 1.1 # Grow very slowly
)

# Enable GC.stress mode if requested (VERY slow, but makes GC bugs reproducible)
if ENV['FUZZ_GC_STRESS'] == '1'
  GC.stress = true
  warn '[Worker] GC.stress enabled - expect 100-1000x slowdown'
end

COLOR_FORMATS = %i[hex rgb hsl hwb oklab oklch lab lch].freeze

# Read length-prefixed inputs and parse them
loop do
  # Read 4-byte length prefix (network byte order)
  len_bytes = $stdin.read(4)
  break if len_bytes.nil? || len_bytes.bytesize != 4

  length = len_bytes.unpack1('N')

  # Read CSS input
  css = $stdin.read(length)
  break if css.nil? || css.bytesize != length

  # Parse CSS (crash will kill subprocess)
  begin
    stylesheet = Cataract.parse_css(css)
    rules = stylesheet.rules.to_a
    merge_tested = false
    to_s_tested = false
    color_converted = false

    # Test merge with valid CSS followed by fuzzed CSS
    # This tests merge error handling when second rule set is invalid
    begin
      valid_stylesheet = Cataract.parse_css('body { margin: 0; color: red; }')
      valid_stylesheet.add_block(css) # Add fuzzed CSS to valid stylesheet
      valid_stylesheet.merge # Call merge on the stylesheet
      merge_tested = true
    rescue Cataract::Error
      # Expected - merge might fail on invalid CSS
    end

    # Test to_s on parsed rules occasionally
    # This tests serialization on fuzzed data
    if !rules.empty? && rand < 0.01
      stylesheet.to_s
      to_s_tested = true
    end

    if !rules.empty? && rand < 0.02
      stylesheet.to_formatted_s
      to_s_tested = true
    end

    # Test color conversion occasionally (10% chance)
    # This tests color parsing/conversion on fuzzed color values
    if rand < 0.1
      begin
        # Try random color format conversions
        from_format = COLOR_FORMATS.sample
        to_format = COLOR_FORMATS.sample
        stylesheet.convert_colors!(from: from_format, to: to_format)
        color_converted = true
      rescue Cataract::Error, ArgumentError
        # Expected - color conversion might fail on invalid colors
      end
    end

    # Report what was tested: PARSE [+MERGE] [+TOS] [+COLOR]
    output = 'PARSE'
    output += '+MERGE' if merge_tested
    output += '+TOS' if to_s_tested
    output += '+COLOR' if color_converted
    $stdout.write("#{output}\n")
  rescue Cataract::DepthError
    $stdout.write("DEPTH\n")
  rescue Cataract::SizeError
    $stdout.write("SIZE\n")
  rescue StandardError
    $stdout.write("ERR\n")
  end

  $stdout.flush
end
