#!/usr/bin/env ruby
# frozen_string_literal: true

# Visual test generator for Cataract color conversions
# Generates an HTML file showing color conversions across all supported formats

require 'erb'
require 'fileutils'

# Add lib to load path
$LOAD_PATH.unshift File.expand_path('../../lib', __dir__)
require 'cataract'

# Sample of named colors to test (diverse hues, saturations, lightness)
SAMPLE_COLORS = %w[
  red
  green
  blue
  yellow
  cyan
  magenta
  white
  black
  gray
  silver
  maroon
  olive
  lime
  aqua
  teal
  navy
  fuchsia
  purple
  orange
  pink
  coral
  tomato
  gold
  indigo
  violet
  brown
  tan
  khaki
  salmon
  crimson
  chocolate
  peru
  sienna
  steelblue
  skyblue
  turquoise
  orchid
  plum
  lavender
].freeze

def convert_color(color_str, from_format, to_format)
  css = ".test { color: #{color_str}; }"
  sheet = Cataract.parse_css(css)
  sheet.convert_colors!(from: from_format, to: to_format)
  decls = Cataract::Declarations.new(sheet.declarations)
  decls['color']
end

def auto_detect_convert(color_str, to_format)
  css = ".test { color: #{color_str}; }"
  sheet = Cataract.parse_css(css)
  sheet.convert_colors!(to: to_format)
  decls = Cataract::Declarations.new(sheet.declarations)
  decls['color']
end

def hex_difference(hex1, hex2)
  # Parse hex colors and calculate RGB distance
  r1, g1, b1 = hex1.scan(/[0-9a-f]{2}/i).map { |h| h.to_i(16) }
  r2, g2, b2 = hex2.scan(/[0-9a-f]{2}/i).map { |h| h.to_i(16) }

  Math.sqrt(((r1 - r2)**2) + ((g1 - g2)**2) + ((b1 - b2)**2))
end

# Generate forward conversion tests (named → rgb → hwb → hsl → oklab → lab → lch)
def generate_forward_tests(colors)
  colors.map do |color_name|
    # Start with named color
    named = color_name

    # Convert through each format in sequence
    rgb = convert_color(named, :named, :rgb)
    hwb = convert_color(rgb, :rgb, :hwb)
    hsl = convert_color(hwb, :hwb, :hsl)
    oklab = convert_color(hsl, :hsl, :oklab)
    lab = convert_color(oklab, :oklab, :lab)
    lch = convert_color(lab, :lab, :lch)

    {
      name: color_name,
      named: named,
      rgb: rgb,
      hwb: hwb,
      hsl: hsl,
      oklab: oklab,
      lab: lab,
      lch: lch
    }
  end
end

# Generate reverse conversion tests (lch → lab → oklab → hsl → hwb → rgb → hex)
def generate_reverse_tests(colors)
  colors.map do |color_name|
    # Get original hex value
    original_hex = convert_color(color_name, :named, :hex)

    # Convert to LCH first
    lch = convert_color(color_name, :named, :lch)

    # Convert back through the chain
    lab = convert_color(lch, :lch, :lab)
    oklab = convert_color(lab, :lab, :oklab)
    hsl = convert_color(oklab, :oklab, :hsl)
    hwb = convert_color(hsl, :hsl, :hwb)
    rgb = convert_color(hwb, :hwb, :rgb)
    hex = convert_color(rgb, :rgb, :hex)

    # Calculate match quality
    diff = hex_difference(original_hex, hex)
    match_class = if diff.zero?
                    'perfect'
                  elsif diff < 2
                    'close'
                  else
                    'off'
                  end

    match_symbol = case match_class
                   when 'perfect' then '✓'
                   when 'close' then '≈'
                   else '✗'
                   end

    {
      name: color_name,
      original_hex: original_hex,
      lch: lch,
      lab: lab,
      oklab: oklab,
      hsl: hsl,
      hwb: hwb,
      rgb: rgb,
      hex: hex,
      match_class: match_class,
      match_symbol: match_symbol,
      diff: diff
    }
  end
end

# Calculate statistics
def calculate_stats(forward_tests, reverse_tests)
  perfect = reverse_tests.count { |t| t[:match_class] == 'perfect' }
  close = reverse_tests.count { |t| t[:match_class] == 'close' }

  {
    total_tests: forward_tests.length,
    perfect_matches: perfect,
    close_matches: close,
    formats_tested: 7 # hex, rgb, hwb, hsl, oklab, lab, lch
  }
end

# Main execution
puts 'Generating color conversion visual test...'
puts "Testing #{SAMPLE_COLORS.length} colors..."

# Generate test data
forward_tests = generate_forward_tests(SAMPLE_COLORS)
puts '✓ Generated forward conversion tests'

reverse_tests = generate_reverse_tests(SAMPLE_COLORS)
puts '✓ Generated reverse conversion tests'

stats = calculate_stats(forward_tests, reverse_tests)
puts '✓ Calculated statistics'

# Load ERB template
template_path = File.join(__dir__, 'template.html.erb')
template = ERB.new(File.read(template_path), trim_mode: '-')

# Render HTML
html = template.result(binding)

# Write output
output_path = File.join(__dir__, 'color_conversion_test.html')
File.write(output_path, html)

puts "\n✓ Generated: #{output_path}"
puts "\nStatistics:"
puts "  Total colors tested: #{stats[:total_tests]}"
puts "  Perfect round-trips: #{stats[:perfect_matches]}"
puts "  Close matches: #{stats[:close_matches]}"
puts "  Formats: #{stats[:formats_tested]}"
puts "\nOpen #{output_path} in a browser to view the results."
