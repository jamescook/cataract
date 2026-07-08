# frozen_string_literal: true

# Cataract is a high-performance CSS parser written in C with a Ruby interface.
#
# It provides fast CSS parsing, rule querying, cascade merging, and serialization.
# Designed for performance-critical applications that need to process large amounts of CSS.
#
# Pure Ruby and native each live entirely under their own Backends::Pure /
# Backends::Native namespace (no shared method/constant is ever defined by
# a backend directly on Cataract or on a shared value type), so both can be
# required in the same process - e.g. to compare their output directly.
# Backends.active is the one this process picked by default (below); it's
# what shared value types (Stylesheet, Declarations, Rule) fall back to
# when they aren't otherwise told which backend produced them.
#
# @example Basic usage
#   require 'cataract'
#
#   # Parse CSS
#   sheet = Cataract.parse_css("body { color: red; } h1 { color: blue; }")
#
#   # Query rules
#   sheet.select(&:selector?).each { |rule| puts "#{rule.selector}: #{rule.declarations}" }
#
#   # Flatten with cascade rules
#   flattened = sheet.flatten
#
# @see Stylesheet Main class for working with parsed CSS
# @see Rule Represents individual CSS rules
module Cataract
  module Backends
    class << self
      attr_accessor :active
    end
  end
end

if %w[1 true].include?(ENV.fetch('CATARACT_PURE', nil)) || RUBY_ENGINE == 'jruby'
  require_relative 'cataract/pure'
  Cataract::Backends.active = Cataract::Backends::Pure
else
  require_relative 'cataract/native'
  Cataract::Backends.active = Cataract::Backends::Native
end

module Cataract
  # Mirror the active backend's identity constants at the top level.
  #
  # Native is a Module (IMPLEMENTATION/COMPILE_FLAGS live on it directly);
  # Pure is a frozen instance (they live on its class instead), so reach
  # through .class only when active isn't already a Module itself.
  backend_const_holder = Backends.active.is_a?(Module) ? Backends.active : Backends.active.class
  IMPLEMENTATION = backend_const_holder::IMPLEMENTATION
  COMPILE_FLAGS = backend_const_holder::COMPILE_FLAGS
  NATIVE_EXTENSION_LOADED = true if defined?(Backends::Native) && Backends.active == Backends::Native
  PURE_RUBY_LOADED = true if defined?(Backends::Pure) && Backends.active == Backends::Pure

  class << self
    # Parse a CSS string into a Stylesheet object.
    #
    # This is the main entry point for parsing CSS. It returns a Stylesheet
    # object that can be queried, modified, and serialized.
    #
    # @param css [String] The CSS string to parse
    # @param imports [Boolean, Hash] Whether to resolve @import statements.
    #   Pass true to enable with defaults, or a hash with options:
    #   - allowed_schemes: Array of allowed URI schemes (default: ['https'])
    #   - extensions: Array of allowed file extensions (default: ['css'])
    #   - max_depth: Maximum import nesting depth (default: 5)
    #   - base_path: Base directory for resolving relative imports
    # @return [Stylesheet] A new Stylesheet containing the parsed CSS rules
    # @raise [IOError] If import resolution fails and io_exceptions option is enabled
    #
    # @example Parse simple CSS
    #   sheet = Cataract.parse_css("body { color: red; }")
    #   sheet.size #=> 1
    #
    # @example Parse with imports
    #   sheet = Cataract.parse_css("@import 'style.css';", imports: true)
    #
    # @example Parse with import options
    #   sheet = Cataract.parse_css(css, imports: {
    #     allowed_schemes: ['https', 'file'],
    #     base_path: '/path/to/css'
    #   })
    #
    # @see Stylesheet#parse
    # @see Stylesheet.parse
    def parse_css(css, **options)
      Stylesheet.parse(css, **options)
    end

    # Flatten CSS rules according to CSS cascade rules.
    #
    # Takes a Stylesheet or CSS string and flattens all rules according to CSS cascade
    # precedence rules. Returns a new Stylesheet with flattened rules containing
    # the final computed declarations.
    #
    # @param stylesheet_or_css [Stylesheet, String] The stylesheet to flatten, or a CSS string to parse and flatten
    # @return [Stylesheet] A new Stylesheet with flattened rules
    #
    # Flatten rules (in order of precedence):
    # 1. !important declarations win over non-important
    # 2. Higher specificity wins
    # 3. Later declarations with same specificity and importance win
    # 4. Shorthand properties are created from longhand when possible (e.g., margin-* -> margin)
    #
    # @example Flatten a stylesheet
    #   sheet = Cataract.parse_css(".test { color: red; } #test { color: blue; }")
    #   flattened = Cataract.flatten(sheet)
    #   flattened.rules.first.declarations #=> [#<Declaration property="color" value="blue" important=false>]
    #
    # @example Flatten with !important
    #   sheet = Cataract.parse_css(".test { color: red !important; } #test { color: blue; }")
    #   flattened = Cataract.flatten(sheet)
    #   flattened.rules.first.declarations #=> [#<Declaration property="color" value="red" important=true>]
    #
    # @example Shorthand creation
    #   css = ".test { margin-top: 10px; margin-right: 10px; margin-bottom: 10px; margin-left: 10px; }"
    #   flattened = Cataract.flatten(Cataract.parse_css(css))
    #   # flattened contains single "margin: 10px" declaration instead of four longhand properties
    #
    # @note This is a module-level convenience method. The same functionality is available
    #   as an instance method: `stylesheet.flatten`
    #
    # @see Stylesheet#flatten
    def flatten(stylesheet_or_css)
      stylesheet_or_css = Stylesheet.parse(stylesheet_or_css) if stylesheet_or_css.is_a?(String)
      stylesheet_or_css.flatten
    end
  end
end
