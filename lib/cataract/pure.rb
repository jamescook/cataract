# frozen_string_literal: true

# Pure Ruby implementation of Cataract CSS parser
#
# This is a character-by-character parser that closely mirrors the C implementation.
# ==================================================================
# NO REGEXP ALLOWED - consume chars one at a time like the C version.
# ==================================================================
#
# Load this instead of the C extension by setting CATARACT_PURE before
# requiring 'cataract' (not by requiring this file directly - lib/cataract.rb
# is what sets up Cataract::Backends.active and the top-level identity
# constants like IMPLEMENTATION; this file alone does not):
#   ENV['CATARACT_PURE'] = '1'
#   require 'cataract'
#
# Or run tests with:
#   CATARACT_PURE=1 rake test
#
# Everything backend-specific here lives under Cataract::Backends::Pure -
# nothing is defined directly on Cataract itself, so this file can be loaded
# in the same process as the native backend without either clobbering the
# other. The one exception is Stylesheet#convert_colors! below: color
# conversion has no pure-Ruby implementation at all, so the stub simply
# raises - native's real implementation (ext/cataract_color, loaded
# separately and only opt-in) defines its own convert_colors! and is
# unaffected by this file being loaded or not.

require_relative 'error'

require_relative 'version'
require_relative 'constants'

# Load struct definitions and supporting files
# (These are also loaded by lib/cataract/native.rb, but we need them here for direct require)
require_relative 'declaration'
require_relative 'rule'
require_relative 'at_rule'
require_relative 'media_query'
require_relative 'conditional_group'
require_relative 'import_statement'
require_relative 'stylesheet_scope'
require_relative 'stylesheet'
require_relative 'declarations'
require_relative 'import_resolver'

# Load pure Ruby implementation modules
require_relative 'pure/byte_constants'
require_relative 'pure/specificity'
require_relative 'pure/serializer'
require_relative 'pure/parser'
require_relative 'pure/flatten'
require_relative 'pure/declarations'

module Cataract
  module Backends
    class PureImpl
      # Flag to indicate the pure Ruby backend is loaded
      PURE_RUBY_LOADED = true

      # Implementation type constant
      IMPLEMENTATION = :ruby

      # Compile flags (mimic C version)
      COMPILE_FLAGS = {
        debug: false,
        str_buf_optimization: false,
        pure_ruby: true
      }.freeze

      # Parse CSS string and return hash with rules, media_index, charset, etc.
      # Called by Stylesheet#add_block - not meant for direct use.
      #
      # @param css_string [String] CSS to parse
      # @param parser_options [Hash] Parser configuration options
      # @option parser_options [Boolean] :selector_lists (true) Track selector lists
      # @return [Hash] {
      #   rules: Array<Rule>,           # Flat array of Rule/AtRule structs
      #   _media_index: Hash,           # Symbol => Array of rule IDs
      #   charset: String|nil,          # @charset value if present
      #   _has_nesting: Boolean         # Whether any nested rules exist
      # }
      def parse(css_string, parser_options = {})
        parser = Parser.new(css_string, parser_options: parser_options)
        parser.parse
      end

      # Flatten stylesheet rules according to CSS cascade rules
      #
      # @param stylesheet [Stylesheet] Stylesheet to flatten
      # @return [Stylesheet] New stylesheet with flattened rules
      def flatten(stylesheet)
        Flatten.flatten(stylesheet, mutate: false)
      end

      # Expand a single shorthand declaration into longhand declarations.
      # Called by Rule#expanded_declarations - not meant for direct use.
      #
      # @param decl [Declaration] Declaration to expand
      # @return [Array<Declaration>] Array of expanded longhand declarations
      def expand_shorthand(decl)
        Flatten.expand_shorthand(decl)
      end
    end

    # The active-facing constant is a single frozen instance, not the class
    # itself - none of PureImpl's methods touch instance state, so one shared
    # instance is exactly as safe as the bare module this replaces, while
    # giving its methods genuine instance-level `private` instead of
    # `private_class_method`.
    Pure = PureImpl.new.freeze
  end

  class Stylesheet
    # Color conversion has no pure-Ruby implementation.
    #
    # @raise [NotImplementedError] Always raises - not implemented for pure Ruby
    def convert_colors!(*_args)
      raise NotImplementedError, 'convert_colors! is not yet implemented in Cataract'
    end
  end
end
