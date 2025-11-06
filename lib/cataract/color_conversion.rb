# frozen_string_literal: true

# Color conversion utilities for Cataract
#
# This is an optional extension that adds color conversion capabilities to Cataract::Stylesheet.
# Load it explicitly to add the convert_colors! method:
#
#   require 'cataract/color_conversion'
#
# Usage:
#   sheet = Cataract.parse_css('.button { color: #ff0000; }')
#   sheet.convert_colors!(to: :rgb)
#   sheet.to_css  # => ".button { color: rgb(255 0 0); }"
#
# This extension is loaded on-demand to reduce memory footprint for users who
# don't need color conversion functionality.

require 'cataract/cataract_color'
