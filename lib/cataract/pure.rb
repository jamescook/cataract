# frozen_string_literal: true

# Pure Ruby implementation of Cataract CSS parser
#
# This is a character-by-character parser that closely mirrors the C implementation.
# ==================================================================
# NO REGEXP ALLOWED - consume chars one at a time like the C version.
# ==================================================================
#
# Load this instead of the C extension with:
#   require 'cataract/pure'
#
# Or run tests with:
#   CATARACT_PURE=1 rake test

# Check if C extension is already loaded
if defined?(Cataract::NATIVE_EXTENSION_LOADED)
  raise LoadError, "Cataract C extension is already loaded. Cannot load pure Ruby version."
end

# Define base module and error classes first
module Cataract
  class Error < StandardError; end
  class DepthError < Error; end
  class SizeError < Error; end
end

require_relative 'version'

# Define structs that are normally defined in C land
# These must be defined BEFORE loading the Ruby decorator files
module Cataract
  # Rule struct: (id, selector, declarations, specificity, parent_rule_id, nesting_style)
  # - id: Integer (0-indexed position in @rules array)
  # - selector: String (fully resolved/flattened selector)
  # - declarations: Array of Declaration
  # - specificity: Integer | nil (calculated lazily)
  # - parent_rule_id: Integer | nil (parent rule ID for nested rules)
  # - nesting_style: Integer | nil (0=implicit, 1=explicit, nil=not nested)
  Rule = Struct.new(:id, :selector, :declarations, :specificity, :parent_rule_id, :nesting_style)

  # Declaration struct: (property, value, important)
  # - property: String (CSS property name, lowercased)
  # - value: String (CSS property value)
  # - important: Boolean (true if !important)
  Declaration = Struct.new(:property, :value, :important)

  # AtRule struct: (id, selector, content, specificity)
  # Matches Rule interface for duck-typing
  # - id: Integer (0-indexed position in @rules array)
  # - selector: String (e.g., "@keyframes fade", "@font-face")
  # - content: Array of Rule or Declaration
  # - specificity: Always nil for at-rules
  AtRule = Struct.new(:id, :selector, :content, :specificity)

  # Declarations class for to_s method (used in merge operations)
  class Declarations < Array
    def to_s
      map { |d| "#{d.property}: #{d.value}#{d.important ? ' !important' : ''}" }.join('; ')
    end
  end
end

# Now load the Ruby decorator files that add methods to these structs
require_relative 'rule'
require_relative 'at_rule'
require_relative 'stylesheet_scope'
require_relative 'stylesheet'
require_relative 'declarations'
require_relative 'import_resolver'

# Add to_s method to Declarations class for pure Ruby mode
module Cataract
  class Declarations
    # Serialize declarations to CSS string
    def to_s
      result = String.new
      @values.each_with_index do |decl, i|
        result << decl.property
        result << ": "
        result << decl.value
        result << " !important" if decl.important
        result << ";"
        result << " " if i < @values.length - 1  # Add space after semicolon except for last
      end
      result
    end
  end
end

module Cataract
  # Flag to indicate pure Ruby version is loaded
  PURE_RUBY_LOADED = true

  # Compile flags (mimic C version)
  COMPILE_FLAGS = {
    debug: false,
    str_buf_optimization: false,
    pure_ruby: true
  }.freeze

  # ============================================================================
  # CORE PARSING
  # ============================================================================

  # Parse CSS string and return hash with rules, media_index, charset, etc.
  #
  # @param css_string [String] CSS to parse
  # @return [Hash] {
  #   rules: Array<Rule>,           # Flat array of Rule/AtRule structs
  #   _media_index: Hash,           # Symbol => Array of rule IDs
  #   charset: String|nil,          # @charset value if present
  #   _has_nesting: Boolean         # Whether any nested rules exist
  # }
  def self._parse_css(css_string)
    parser = Parser.new(css_string)
    parser.parse
  end

  # Check if a character is whitespace (space, tab, newline, CR)
  # @param char [String] Single character
  # @return [Boolean] true if whitespace
  def self.is_whitespace?(char)
    char == ' ' || char == "\t" || char == "\n" || char == "\r"
  end

  # Check if char is a letter (a-z, A-Z)
  def self.letter?(char)
    (char >= 'a' && char <= 'z') || (char >= 'A' && char <= 'Z')
  end

  # Check if char is a digit (0-9)
  def self.digit?(char)
    char >= '0' && char <= '9'
  end

  # Check if char is alphanumeric, hyphen, or underscore (CSS identifier char)
  def self.ident_char?(char)
    letter?(char) || digit?(char) || char == '-' || char == '_'
  end

  # Parse media query symbol into array of media types
  #
  # @param media_query_sym [Symbol] Media query as symbol (e.g., :screen, :"print, screen")
  # @return [Array<Symbol>] Array of individual media types
  #
  # @example
  #   parse_media_types(:screen) #=> [:screen]
  #   parse_media_types(:"print, screen") #=> [:print, :screen]
  def self.parse_media_types(media_query_sym)
    query = media_query_sym.to_s
    types = []

    i = 0
    len = query.length

    kwords = %w[and or not only]

    while i < len
      # Skip whitespace
      while i < len && is_whitespace?(query[i])
        i += 1
      end
      break if i >= len

      # Check for opening paren - skip conditions like "(min-width: 768px)"
      if query[i] == '('
        # Skip to matching closing paren
        paren_depth = 1
        i += 1
        while i < len && paren_depth > 0
          if query[i] == '('
            paren_depth += 1
          elsif query[i] == ')'
            paren_depth -= 1
          end
          i += 1
        end
        next
      end

      # Find end of word (media type or keyword)
      word_start = i
      c = query[i]
      while i < len && !is_whitespace?(c) && c != ',' && c != '(' && c != ':'
        i += 1
        c = query[i] if i < len
      end

      if i > word_start
        word = query[word_start...i]

        # Check if this is a media feature (followed by ':')
        is_media_feature = (i < len && query[i] == ':')

        # Check if it's a keyword (and, or, not, only)
        is_keyword = kwords.include?(word)

        if !is_keyword && !is_media_feature
          # This is a media type - add it as symbol
          types << word.to_sym
        end
      end

      # Skip to comma or end
      while i < len && query[i] != ','
        if query[i] == '('
          # Skip condition
          paren_depth = 1
          i += 1
          while i < len && paren_depth > 0
            if query[i] == '('
              paren_depth += 1
            elsif query[i] == ')'
              paren_depth -= 1
            end
            i += 1
          end
        else
          i += 1
        end
      end

      i += 1 if i < len && query[i] == ','  # Skip comma
    end

    types
  end

  # Parse CSS declarations from string
  #
  # @param declarations_string [String] CSS declarations (e.g., "color: red; font-size: 14px")
  # @return [Array<Declaration>] Array of Declaration structs
  def self.parse_declarations(declarations_string)
    # TODO: Implement declaration parsing
    # Char-by-char, no regexp
    []
  end

  # Calculate CSS specificity for a selector
  #
  # @param selector [String] CSS selector
  # @return [Integer] Specificity value
  #
  # Specificity calculation (per CSS spec):
  # - Count IDs (#id) - each worth 100
  # - Count classes/attributes/pseudo-classes (.class, [attr], :pseudo) - each worth 10
  # - Count elements/pseudo-elements (div, ::before) - each worth 1
  def self.calculate_specificity(selector)
    return 0 if selector.nil? || selector.empty?

    # Counters for specificity components
    id_count = 0
    class_count = 0
    attr_count = 0
    pseudo_class_count = 0
    pseudo_element_count = 0
    element_count = 0

    i = 0
    len = selector.length

    pseudo_element_kwords = %w[before after first-line first-letter selection]

    while i < len
      c = selector[i]

      # Skip whitespace and combinators
      if c == ' ' || c == "\t" || c == "\n" || c == "\r" || c == '>' || c == '+' || c == '~' || c == ','
        i += 1
        next
      end

      # ID selector: #id
      if c == '#'
        id_count += 1
        i += 1
        # Skip the identifier
        while i < len && ident_char?(selector[i])
          i += 1
        end
        next
      end

      # Class selector: .class
      if c == '.'
        class_count += 1
        i += 1
        # Skip the identifier
        while i < len && ident_char?(selector[i])
          i += 1
        end
        next
      end

      # Attribute selector: [attr]
      if c == '['
        attr_count += 1
        i += 1
        # Skip to closing bracket
        bracket_depth = 1
        while i < len && bracket_depth > 0
          if selector[i] == '['
            bracket_depth += 1
          elsif selector[i] == ']'
            bracket_depth -= 1
          end
          i += 1
        end
        next
      end

      # Pseudo-element (::) or pseudo-class (:)
      if c == ':'
        i += 1
        is_pseudo_element = false

        # Check for double colon (::)
        if i < len && selector[i] == ':'
          is_pseudo_element = true
          i += 1
        end

        # Extract pseudo name
        pseudo_start = i
        while i < len && ident_char?(selector[i])
          i += 1
        end
        pseudo_name = selector[pseudo_start...i]

        # Check for legacy pseudo-elements (single colon but should be double)
        is_legacy_pseudo_element = false
        if !is_pseudo_element && !pseudo_name.empty?
          is_legacy_pseudo_element = pseudo_element_kwords.include?(pseudo_name)
        end

        # Check for :not() - it doesn't count itself, but its content does
        is_not = (pseudo_name == 'not')

        # Skip function arguments if present
        if i < len && selector[i] == '('
          i += 1
          paren_depth = 1

          # If it's :not(), calculate specificity of the content
          if is_not
            not_content_start = i

            # Find closing paren
            while i < len && paren_depth > 0
              if selector[i] == '('
                paren_depth += 1
              elsif selector[i] == ')'
                paren_depth -= 1
              end
              i += 1 if paren_depth > 0
            end

            not_content = selector[not_content_start...i]

            # Recursively calculate specificity of :not() content
            if !not_content.empty?
              not_specificity = calculate_specificity(not_content)

              # Add :not() content's specificity to our counts
              additional_a = not_specificity / 100
              additional_b = (not_specificity % 100) / 10
              additional_c = not_specificity % 10

              id_count += additional_a
              class_count += additional_b
              element_count += additional_c
            end

            i += 1  # Skip closing paren
          else
            # Skip other function arguments
            while i < len && paren_depth > 0
              if selector[i] == '('
                paren_depth += 1
              elsif selector[i] == ')'
                paren_depth -= 1
              end
              i += 1
            end

            # Count the pseudo-class/element
            if is_pseudo_element || is_legacy_pseudo_element
              pseudo_element_count += 1
            else
              pseudo_class_count += 1
            end
          end
        else
          # No function arguments - count the pseudo-class/element
          if is_not
            # :not without parens is invalid, but don't count it
          elsif is_pseudo_element || is_legacy_pseudo_element
            pseudo_element_count += 1
          else
            pseudo_class_count += 1
          end
        end
        next
      end

      # Universal selector: *
      if c == '*'
        # Universal selector has specificity 0, don't count
        i += 1
        next
      end

      # Type selector (element name): div, span, etc.
      if letter?(c)
        element_count += 1
        # Skip the identifier
        while i < len && ident_char?(selector[i])
          i += 1
        end
        next
      end

      # Unknown character, skip it
      i += 1
    end

    # Calculate specificity using W3C formula
    specificity = (id_count * 100) +
                  ((class_count + attr_count + pseudo_class_count) * 10) +
                  ((element_count + pseudo_element_count) * 1)

    specificity
  end

  # Extract @import statements from CSS
  #
  # @param css_string [String] CSS to scan for @imports
  # @return [Array<Hash>] Array of import hashes with :url, :media, :full_match
  def self.extract_imports(css_string)
    imports = []

    i = 0
    len = css_string.length

    while i < len
      # Skip whitespace and comments
      while i < len
        c = css_string[i]
        if is_whitespace?(c)
          i += 1
        elsif i + 1 < len && css_string[i] == '/' && css_string[i + 1] == '*'
          # Skip /* */ comment
          i += 2
          while i + 1 < len && !(css_string[i] == '*' && css_string[i + 1] == '/')
            i += 1
          end
          i += 2 if i + 1 < len  # Skip */
        else
          break
        end
      end

      break if i >= len

      # Check for @import (case-insensitive)
      if i + 7 <= len && css_string[i...i+7].downcase == '@import'
        import_start = i
        i += 7

        # Skip whitespace after @import
        while i < len && is_whitespace?(css_string[i])
          i += 1
        end

        # Check for optional url(
        has_url_function = false
        if i + 4 <= len && css_string[i...i+4].downcase == 'url('
          has_url_function = true
          i += 4
          while i < len && is_whitespace?(css_string[i])
            i += 1
          end
        end

        # Find opening quote
        if i >= len || (css_string[i] != '"' && css_string[i] != "'")
          # Invalid @import, skip to next semicolon
          while i < len && css_string[i] != ';'
            i += 1
          end
          i += 1 if i < len  # Skip semicolon
          next
        end

        quote_char = css_string[i]
        i += 1  # Skip opening quote

        url_start = i

        # Find closing quote (handle escaped quotes)
        while i < len && css_string[i] != quote_char
          if css_string[i] == '\\' && i + 1 < len
            i += 2  # Skip escaped character
          else
            i += 1
          end
        end

        break if i >= len  # Unterminated string

        url_end = i
        i += 1  # Skip closing quote

        # Skip closing paren if we had url(
        if has_url_function
          while i < len && is_whitespace?(css_string[i])
            i += 1
          end
          if i < len && css_string[i] == ')'
            i += 1
          end
        end

        # Skip whitespace before optional media query or semicolon
        while i < len && is_whitespace?(css_string[i])
          i += 1
        end

        # Check for optional media query (everything until semicolon)
        media_start = nil
        media_end = nil

        if i < len && css_string[i] != ';'
          media_start = i

          # Find semicolon
          while i < len && css_string[i] != ';'
            i += 1
          end

          media_end = i

          # Trim trailing whitespace from media query
          while media_end > media_start && is_whitespace?(css_string[media_end - 1])
            media_end -= 1
          end
        end

        # Skip semicolon
        i += 1 if i < len && css_string[i] == ';'

        import_end = i

        # Build result hash
        url = css_string[url_start...url_end]
        media = media_start && media_end > media_start ? css_string[media_start...media_end] : nil
        full_match = css_string[import_start...import_end]

        imports << { url: url, media: media, full_match: full_match }
      else
        i += 1
      end
    end

    imports
  end

  # ============================================================================
  # SERIALIZATION
  # ============================================================================

  # Serialize stylesheet to compact CSS string
  #
  # @param rules [Array<Rule>] Array of rules
  # @param media_index [Hash] Media query symbol => array of rule IDs
  # @param charset [String, nil] @charset value
  # @param has_nesting [Boolean] Whether any nested rules exist
  # @return [String] Compact CSS string
  def self._stylesheet_to_s(rules, media_index, charset, has_nesting)
    result = String.new

    # Add @charset if present
    unless charset.nil?
      result << "@charset \"#{charset}\";\n"
    end

    # Fast path: no nesting - use simple algorithm
    unless has_nesting
      return stylesheet_to_s_original(rules, media_index, result)
    end

    # TODO: Implement nesting support
    # For now, just use the simple algorithm
    stylesheet_to_s_original(rules, media_index, result)
  end

  # Helper: serialize rules without nesting support
  def self.stylesheet_to_s_original(rules, media_index, result)
    # Build rule_id => media_symbol map
    rule_to_media = {}
    media_index.each do |media_sym, rule_ids|
      rule_ids.each do |rule_id|
        rule_to_media[rule_id] = media_sym
      end
    end

    # Iterate through rules in insertion order, grouping consecutive media queries
    current_media = nil
    in_media_block = false

    rules.each do |rule|
      rule_media = rule_to_media[rule.id]

      if rule_media.nil?
        # Not in any media query - close any open media block first
        if in_media_block
          result << "}\n"
          in_media_block = false
          current_media = nil
        end

        # Output rule directly
        serialize_rule(result, rule)
      else
        # This rule is in a media query
        # Check if media query changed from previous rule
        if current_media.nil? || current_media != rule_media
          # Close previous media block if open
          if in_media_block
            result << "}\n"
          end

          # Open new media block
          current_media = rule_media
          result << "@media #{current_media} {\n"
          in_media_block = true
        end

        # Serialize rule inside media block
        serialize_rule(result, rule)
      end
    end

    # Close final media block if still open
    if in_media_block
      result << "}\n"
    end

    result
  end

  # Helper: serialize a single rule
  def self.serialize_rule(result, rule)
    # Check if this is an AtRule
    if rule.is_a?(AtRule)
      serialize_at_rule(result, rule)
      return
    end

    # Regular Rule serialization
    result << rule.selector
    result << " { "
    serialize_declarations(result, rule.declarations)
    result << " }\n"
  end

  # Helper: serialize declarations
  def self.serialize_declarations(result, declarations)
    declarations.each_with_index do |decl, i|
      result << decl.property
      result << ": "
      result << decl.value

      if decl.important
        result << " !important"
      end

      result << ";"

      # Add space after semicolon except for last declaration
      if i < declarations.length - 1
        result << " "
      end
    end
  end

  # Helper: serialize an at-rule (@keyframes, @font-face, etc)
  def self.serialize_at_rule(result, at_rule)
    result << at_rule.selector
    result << " {\n"

    # Check if content is rules or declarations
    if at_rule.content.length > 0
      first = at_rule.content[0]

      if first.is_a?(Rule)
        # Serialize as nested rules (e.g., @keyframes)
        at_rule.content.each do |nested_rule|
          result << "  "
          result << nested_rule.selector
          result << " { "
          serialize_declarations(result, nested_rule.declarations)
          result << " }\n"
        end
      else
        # Serialize as declarations (e.g., @font-face)
        result << "  "
        serialize_declarations(result, at_rule.content)
        result << "\n"
      end
    end

    result << "}\n"
  end

  # Serialize stylesheet to formatted CSS string (with indentation)
  #
  # @param rules [Array<Rule>] Array of rules
  # @param media_index [Hash] Media query symbol => array of rule IDs
  # @param charset [String, nil] @charset value
  # @param has_nesting [Boolean] Whether any nested rules exist
  # @return [String] Formatted CSS string
  def self._stylesheet_to_formatted_s(rules, media_index, charset, has_nesting)
    result = String.new

    # Add @charset if present
    unless charset.nil?
      result << "@charset \"#{charset}\";\n"
    end

    # Fast path: no nesting - use simple algorithm
    unless has_nesting
      return stylesheet_to_formatted_s_original(rules, media_index, result)
    end

    # TODO: Implement nesting support
    # For now, just use the simple algorithm
    stylesheet_to_formatted_s_original(rules, media_index, result)
  end

  # Helper: formatted serialization without nesting support
  def self.stylesheet_to_formatted_s_original(rules, media_index, result)
    # Build rule_id => media_symbol map
    rule_to_media = {}
    media_index.each do |media_sym, rule_ids|
      rule_ids.each do |rule_id|
        rule_to_media[rule_id] = media_sym
      end
    end

    # Iterate through rules, grouping consecutive media queries
    current_media = nil
    in_media_block = false

    rules.each do |rule|
      rule_media = rule_to_media[rule.id]

      if rule_media.nil?
        # Not in any media query - close any open media block first
        if in_media_block
          result << "}\n"
          in_media_block = false
          current_media = nil
        end

        # Output rule with no indentation
        serialize_rule_formatted(result, rule, "")
      else
        # This rule is in a media query
        if current_media.nil? || current_media != rule_media
          # Close previous media block if open
          if in_media_block
            result << "}\n"
          else
            # Add blank line before @media if transitioning from non-media rules
            if result.length > 0
              result << "\n"
            end
          end

          # Open new media block
          current_media = rule_media
          result << "@media #{current_media} {\n"
          in_media_block = true
        end

        # Serialize rule inside media block with 2-space indentation
        serialize_rule_formatted(result, rule, "  ")
      end
    end

    # Close final media block if still open
    if in_media_block
      result << "}\n"
    end

    result
  end

  # Helper: serialize a single rule with formatting
  def self.serialize_rule_formatted(result, rule, indent)
    # Check if this is an AtRule
    if rule.is_a?(AtRule)
      serialize_at_rule_formatted(result, rule, indent)
      return
    end

    # Regular Rule serialization with formatting
    # Selector line with opening brace
    result << indent
    result << rule.selector
    result << " {\n"

    # Declarations on their own line with extra indentation
    result << indent
    result << "  "
    serialize_declarations(result, rule.declarations)
    result << "\n"

    # Closing brace
    result << indent
    result << "}\n"
  end

  # Helper: serialize an at-rule with formatting
  def self.serialize_at_rule_formatted(result, at_rule, indent)
    result << indent
    result << at_rule.selector
    result << " {\n"

    # Check if content is rules or declarations
    if at_rule.content.length > 0
      first = at_rule.content[0]

      if first.is_a?(Rule)
        # Serialize as nested rules (e.g., @keyframes) with formatting
        at_rule.content.each do |nested_rule|
          # Nested selector with opening brace (2-space indent)
          result << indent
          result << "  "
          result << nested_rule.selector
          result << " {\n"

          # Declarations on their own line (4-space indent)
          result << indent
          result << "    "
          serialize_declarations(result, nested_rule.declarations)
          result << "\n"

          # Closing brace (2-space indent)
          result << indent
          result << "  }\n"
        end
      else
        # Serialize as declarations (e.g., @font-face)
        result << indent
        result << "  "
        serialize_declarations(result, at_rule.content)
        result << "\n"
      end
    end

    result << indent
    result << "}\n"
  end

  # ============================================================================
  # MERGING (Skip for now - focus on parsing/serialization first)
  # ============================================================================

  # Merge stylesheet rules according to CSS cascade rules
  #
  # @param stylesheet [Stylesheet] Stylesheet to merge
  # @return [Stylesheet] New stylesheet with merged rules
  def self.merge(stylesheet)
    # TODO: Implement merge logic
    # - Apply cascade rules (specificity, !important, source order)
    # - Expand shorthand properties
    # - Recreate shorthands where possible
    raise NotImplementedError, "merge() not yet implemented in pure Ruby version"
  end

  # ============================================================================
  # INTERNAL PARSER
  # ============================================================================

  # Pure Ruby CSS parser - char-by-char, NO REGEXP
  class Parser
    # Maximum parse depth (prevent infinite recursion)
    MAX_PARSE_DEPTH = 10

    # Maximum media queries (prevent symbol table exhaustion)
    MAX_MEDIA_QUERIES = 1000

    # Maximum property name/value lengths
    MAX_PROPERTY_NAME_LENGTH = 256
    MAX_PROPERTY_VALUE_LENGTH = 32768

    attr_reader :css, :pos, :len

    def initialize(css_string, parent_media_sym: nil)
      @css = css_string.dup.freeze
      @pos = 0
      @len = @css.bytesize
      @parent_media_sym = parent_media_sym

      # Parser state
      @rules = []                    # Flat array of Rule structs
      @media_index = {}              # Symbol => Array of rule IDs
      @rule_id_counter = 0           # Next rule ID (0-indexed)
      @media_query_count = 0         # Safety limit
      @media_cache = {}              # Parse-time cache: string => parsed media types
      @has_nesting = false           # Set to true if any nested rules found
      @depth = 0                     # Current recursion depth
      @charset = nil                 # @charset declaration
    end

    def parse
      # Skip @import statements at the beginning (they're handled by ImportResolver)
      # Per CSS spec, @import must come before all rules (except @charset)
      skip_imports

      # Main parsing loop - char-by-char, NO REGEXP
      while !eof?
        skip_ws_and_comments
        break if eof?

        # Peek at next char to determine what to parse
        char = peek_char

        # Check for at-rules (@media, @charset, etc)
        if char == '@'
          parse_at_rule
          next
        end

        # Must be a selector-based rule
        selector = parse_selector
        next if selector.nil? || selector.empty?

        declarations = parse_declarations

        # Split comma-separated selectors into individual rules
        # "html, body, p" => ["html", "body", "p"]
        selectors = selector.split(',').map(&:strip)

        selectors.each do |individual_selector|
          next if individual_selector.empty?

          # Create Rule struct
          rule = Rule.new(
            @rule_id_counter,    # id
            individual_selector, # selector
            declarations,        # declarations
            nil,                 # specificity (calculated lazily)
            nil,                 # parent_rule_id
            nil                  # nesting_style
          )

          @rules << rule
          @rule_id_counter += 1
        end
      end

      {
        rules: @rules,
        _media_index: @media_index,
        charset: @charset,
        _has_nesting: @has_nesting
      }
    end

    private

    # Check if we're at end of input
    def eof?
      @pos >= @len
    end

    # Peek current char without advancing
    def peek_char
      return nil if eof?
      @css[@pos]
    end

    # Read current char and advance position
    def read_char
      return nil if eof?
      char = @css[@pos]
      @pos += 1
      char
    end

    # Delegate to module-level helper methods
    def whitespace?(char)
      Cataract.is_whitespace?(char)
    end

    def letter?(char)
      Cataract.letter?(char)
    end

    def digit?(char)
      Cataract.digit?(char)
    end

    def ident_char?(char)
      Cataract.ident_char?(char)
    end

    # Skip whitespace
    def skip_whitespace
      @pos += 1 while !eof? && whitespace?(peek_char)
    end

    # Skip CSS comments /* ... */
    def skip_comment
      return false unless peek_char == '/' && @css[@pos + 1] == '*'

      @pos += 2 # Skip /*
      while @pos + 1 < @len
        if @css[@pos] == '*' && @css[@pos + 1] == '/'
          @pos += 2 # Skip */
          return true
        end
        @pos += 1
      end
      true
    end

    # Skip whitespace and comments
    def skip_ws_and_comments
      loop do
        old_pos = @pos
        skip_whitespace
        skip_comment
        break if @pos == old_pos # No progress made
      end
    end

    # Find matching closing brace
    # Translated from C: see ext/cataract/css_parser.c find_matching_brace
    def find_matching_brace(start_pos)
      depth = 1
      pos = start_pos

      while pos < @len && depth > 0
        if @css[pos] == '{'
          depth += 1
        elsif @css[pos] == '}'
          depth -= 1
        end
        pos += 1 if depth > 0
      end

      pos
    end

    # Find matching closing paren
    def find_matching_paren(start_pos)
      # TODO: Track depth, handle nested parens
      # Return position of matching ')' or len if not found
      start_pos
    end

    # Parse selector (read until '{')
    def parse_selector
      start_pos = @pos

      # Read until we find '{'
      while !eof? && peek_char != '{'
        @pos += 1
      end

      # If we hit EOF without finding '{', return nil
      return nil if eof?

      # Extract selector text
      selector_text = @css[start_pos...@pos]

      # Skip the '{'
      @pos += 1 if peek_char == '{'

      # Trim whitespace from selector
      selector_text.strip
    end

    # Parse declaration block (inside { ... })
    # Assumes we're already past the opening '{'
    def parse_declarations
      declarations = []

      # Read until we find the closing '}'
      while !eof?
        skip_ws_and_comments
        break if eof?

        # Check for closing brace
        if peek_char == '}'
          @pos += 1 # consume '}'
          break
        end

        # Parse property name (read until ':')
        property_start = @pos
        while !eof? && peek_char != ':' && peek_char != ';' && peek_char != '}'
          @pos += 1
        end

        # Skip if no colon found (malformed)
        if eof? || peek_char != ':'
          # Try to recover by finding next ; or }
          skip_to_semicolon_or_brace
          next
        end

        property = @css[property_start...@pos].strip.downcase
        @pos += 1 # skip ':'

        skip_ws_and_comments

        # Parse value (read until ';' or '}')
        value_start = @pos
        important = false

        while !eof? && peek_char != ';' && peek_char != '}'
          @pos += 1
        end

        value = @css[value_start...@pos].strip

        # Check for !important (char-by-char, no regexp)
        if value.length > 10
          # Scan backwards to find !important
          i = value.length - 1
          # Skip trailing whitespace
          i -= 1 while i >= 0 && (value[i] == ' ' || value[i] == '\t')

          # Check for 'important' (9 chars)
          if i >= 8 && value[i-8..i] == 'important'
            i -= 9
            # Skip whitespace before 'important'
            i -= 1 while i >= 0 && (value[i] == ' ' || value[i] == '\t')
            # Check for '!'
            if i >= 0 && value[i] == '!'
              important = true
              # Remove everything from '!' onwards
              value = value[0...i].strip
            end
          end
        end

        # Skip semicolon if present
        @pos += 1 if peek_char == ';'

        # Create Declaration struct
        declarations << Declaration.new(property, value, important)
      end

      declarations
    end

    # Parse at-rule (@media, @supports, @charset, @keyframes, @font-face, etc)
    # Translated from C: see ext/cataract/css_parser.c lines 962-1128
    def parse_at_rule
      at_rule_start = @pos  # Points to '@'
      @pos += 1 # skip '@'

      # Find end of at-rule name (stop at whitespace or opening brace)
      name_start = @pos
      while !eof? && !whitespace?(peek_char) && peek_char != '{'
        @pos += 1
      end

      at_rule_name = @css[name_start...@pos]

      # Handle @charset specially - it's just @charset "value";
      if at_rule_name == 'charset'
        skip_ws_and_comments
        # Read until semicolon
        value_start = @pos
        while !eof? && peek_char != ';'
          @pos += 1
        end

        charset_value = @css[value_start...@pos].strip
        # Remove quotes (char-by-char)
        result = String.new
        charset_value.each_char do |c|
          result << c unless c == '"' || c == "'"
        end
        @charset = result

        @pos += 1 if peek_char == ';' # consume semicolon
        return
      end

      # Handle conditional group at-rules: @supports, @layer, @container, @scope
      # These behave like @media but don't affect media context
      if %w[supports layer container scope].include?(at_rule_name)
        skip_ws_and_comments

        # Skip to opening brace
        while !eof? && peek_char != '{'
          @pos += 1
        end

        return if eof? || peek_char != '{'

        @pos += 1 # skip '{'

        # Find matching closing brace
        block_start = @pos
        block_end = find_matching_brace(@pos)

        # Recursively parse block content (preserve parent media context)
        nested_parser = Parser.new(@css[block_start...block_end], parent_media_sym: @parent_media_sym)
        nested_result = nested_parser.parse

        # Merge nested media_index into ours
        nested_result[:_media_index].each do |media, rule_ids|
          @media_index[media] ||= []
          @media_index[media].concat(rule_ids.map { |rid| @rule_id_counter + rid })
        end

        # Add nested rules to main rules array
        nested_result[:rules].each do |rule|
          rule.id = @rule_id_counter
          @rule_id_counter += 1
          @rules << rule
        end

        # Move position past the closing brace
        @pos = block_end
        @pos += 1 if @pos < @len && @css[@pos] == '}'

        return
      end

      # Handle @media specially - parse content and track in media_index
      if at_rule_name == 'media'
        skip_ws_and_comments

        # Find media query (up to opening brace)
        mq_start = @pos
        while !eof? && peek_char != '{'
          @pos += 1
        end

        return if eof? || peek_char != '{'

        mq_end = @pos
        # Trim trailing whitespace
        while mq_end > mq_start && whitespace?(@css[mq_end - 1])
          mq_end -= 1
        end

        child_media_string = @css[mq_start...mq_end]
        child_media_sym = child_media_string.to_sym

        # Combine with parent media context
        combined_media_sym = combine_media_queries(@parent_media_sym, child_media_sym)

        # Check media query limit
        if !@media_index.key?(combined_media_sym)
          @media_query_count += 1
          if @media_query_count > MAX_MEDIA_QUERIES
            raise SizeError, "Too many media queries: exceeded maximum of #{MAX_MEDIA_QUERIES}"
          end
        end

        @pos += 1 # skip '{'

        # Find matching closing brace
        block_start = @pos
        block_end = find_matching_brace(@pos)

        # Parse the content with the combined media context
        nested_parser = Parser.new(@css[block_start...block_end], parent_media_sym: combined_media_sym)
        nested_result = nested_parser.parse

        # Merge nested media_index into ours (for nested @media)
        nested_result[:_media_index].each do |media, rule_ids|
          @media_index[media] ||= []
          @media_index[media].concat(rule_ids.map { |rid| @rule_id_counter + rid })
        end

        # Add nested rules to main rules array and update media_index
        nested_result[:rules].each do |rule|
          rule.id = @rule_id_counter

          # Add to full query symbol
          @media_index[combined_media_sym] ||= []
          @media_index[combined_media_sym] << @rule_id_counter

          # Extract media types and add to each (if different from full query)
          media_types = Cataract.parse_media_types(combined_media_sym)
          media_types.each do |media_type|
            # Only add if different from combined_media_sym to avoid duplication
            if media_type != combined_media_sym
              @media_index[media_type] ||= []
              @media_index[media_type] << @rule_id_counter
            end
          end

          @rule_id_counter += 1
          @rules << rule
        end

        # Move position past the closing brace
        @pos = block_end
        @pos += 1 if @pos < @len && @css[@pos] == '}'

        return
      end

      # Check for @keyframes (contains <rule-list>)
      is_keyframes = at_rule_name == 'keyframes' ||
                     at_rule_name == '-webkit-keyframes' ||
                     at_rule_name == '-moz-keyframes'

      if is_keyframes
        # Build full selector string: "@keyframes fade"
        selector_start = at_rule_start  # Points to '@'

        # Skip to opening brace
        while !eof? && peek_char != '{'
          @pos += 1
        end

        return if eof? || peek_char != '{'

        selector_end = @pos
        # Trim trailing whitespace
        while selector_end > selector_start && whitespace?(@css[selector_end - 1])
          selector_end -= 1
        end
        selector = @css[selector_start...selector_end]

        @pos += 1 # skip '{'

        # Find matching closing brace
        block_start = @pos
        block_end = find_matching_brace(@pos)

        # Parse keyframe blocks as rules (0%/from/to etc)
        # Create a nested parser context
        nested_parser = Parser.new(@css[block_start...block_end])
        nested_result = nested_parser.parse
        content = nested_result[:rules]

        # Move position past the closing brace
        @pos = block_end
        # The closing brace should be at block_end
        @pos += 1 if @pos < @len && @css[@pos] == '}'

        # Get rule ID and increment
        rule_id = @rule_id_counter
        @rule_id_counter += 1

        # Create AtRule with nested rules
        at_rule = AtRule.new(rule_id, selector, content, nil)
        @rules << at_rule

        return
      end

      # Check for @font-face (contains <declaration-list>)
      if at_rule_name == 'font-face'
        # Build selector string: "@font-face"
        selector_start = at_rule_start  # Points to '@'

        # Skip to opening brace
        while !eof? && peek_char != '{'
          @pos += 1
        end

        return if eof? || peek_char != '{'

        selector_end = @pos
        # Trim trailing whitespace
        while selector_end > selector_start && whitespace?(@css[selector_end - 1])
          selector_end -= 1
        end
        selector = @css[selector_start...selector_end]

        @pos += 1 # skip '{'

        # Find matching closing brace
        decl_start = @pos
        decl_end = find_matching_brace(@pos)

        # Parse declarations
        content = parse_declarations_block(decl_start, decl_end)

        # Move position past the closing brace
        @pos = decl_end
        # The closing brace should be at decl_end
        @pos += 1 if @pos < @len && @css[@pos] == '}'

        # Get rule ID and increment
        rule_id = @rule_id_counter
        @rule_id_counter += 1

        # Create AtRule with declarations
        at_rule = AtRule.new(rule_id, selector, content, nil)
        @rules << at_rule

        return
      end

      # Unknown at-rule (@property, @page, @counter-style, etc.)
      # Treat as a regular selector-based rule with declarations
      selector_start = at_rule_start  # Points to '@'

      # Skip to opening brace
      while !eof? && peek_char != '{'
        @pos += 1
      end

      return if eof? || peek_char != '{'

      selector_end = @pos
      # Trim trailing whitespace
      while selector_end > selector_start && whitespace?(@css[selector_end - 1])
        selector_end -= 1
      end
      selector = @css[selector_start...selector_end]

      @pos += 1 # skip '{'

      # Parse declarations
      declarations = parse_declarations

      # Create Rule with declarations
      rule = Rule.new(
        @rule_id_counter,    # id
        selector,            # selector (e.g., "@property --main-color")
        declarations,        # declarations
        nil,                 # specificity
        nil,                 # parent_rule_id
        nil                  # nesting_style
      )

      @rules << rule
      @rule_id_counter += 1
    end

    # Check if block contains nested selectors vs just declarations
    def has_nested_selectors?(start_pos, end_pos)
      # TODO: Look for &, ., #, [, :, *, >, +, ~, @ followed by {
      # Return true if nested selectors found
      false
    end

    # Resolve nested selector against parent
    def resolve_nested_selector(parent_selector, nested_selector)
      # TODO: Handle & replacement (explicit nesting)
      # Handle implicit nesting (prepend parent)
      # Return [resolved_selector, nesting_style]
      [nested_selector, 0]
    end

    # Lowercase property name (CSS properties are ASCII)
    def lowercase_property(str)
      # Simple ASCII lowercase (no encoding issues)
      str.downcase
    end

    # Combine parent and child media queries
    # Translated from C: see ext/cataract/css_parser.c combine_media_queries
    # Examples:
    #   parent="screen", child="min-width: 500px" => "screen and (min-width: 500px)"
    #   parent=nil, child="print" => "print"
    def combine_media_queries(parent, child)
      return child if parent.nil?
      return parent if child.nil?

      # Combine: "parent and child"
      parent_str = parent.to_s
      child_str = child.to_s

      combined = parent_str + " and "

      # If child is a condition (contains ':'), wrap it in parentheses
      if child_str.include?(':')
        # Add parens if not already present
        if child_str.start_with?('(') && child_str.end_with?(')')
          combined += child_str
        else
          combined += '(' + child_str + ')'
        end
      else
        combined += child_str
      end

      combined.to_sym
    end

    # Skip to next semicolon or closing brace (error recovery)
    def skip_to_semicolon_or_brace
      while !eof? && peek_char != ';' && peek_char != '}'
        @pos += 1
      end
      @pos += 1 if peek_char == ';' # consume semicolon
    end

    # Skip to next rule (error recovery for at-rules we don't handle yet)
    def skip_to_next_rule
      depth = 0
      while !eof?
        char = peek_char
        if char == '{'
          depth += 1
        elsif char == '}'
          depth -= 1
          if depth <= 0
            @pos += 1 # consume final '}'
            break
          end
        end
        @pos += 1
      end
    end

    # Skip @import statements at the beginning of CSS
    # Per CSS spec, @import must come before all rules (except @charset)
    def skip_imports
      while !eof?
        # Skip whitespace
        while !eof? && whitespace?(peek_char)
          @pos += 1
        end
        break if eof?

        # Skip comments
        if @pos + 1 < @len && @css[@pos] == '/' && @css[@pos + 1] == '*'
          @pos += 2
          while @pos + 1 < @len
            if @css[@pos] == '*' && @css[@pos + 1] == '/'
              @pos += 2
              break
            end
            @pos += 1
          end
          next
        end

        # Check for @import
        if @pos + 7 <= @len && @css[@pos] == '@' && @css[@pos+1...@pos+7].downcase == 'import'
          # Check that it's followed by whitespace or quote
          if @pos + 7 >= @len || whitespace?(@css[@pos + 7]) || @css[@pos + 7] == "'" || @css[@pos + 7] == '"'
            # Skip to semicolon
            while !eof? && peek_char != ';'
              @pos += 1
            end
            @pos += 1 if !eof?  # Skip semicolon
            next
          end
        end

        # Hit non-@import content, stop skipping
        break
      end
    end

    # Parse a block of declarations given start/end positions
    # Used for @font-face and other at-rules
    # Translated from C: see ext/cataract/css_parser.c parse_declarations
    def parse_declarations_block(start_pos, end_pos)
      declarations = []
      pos = start_pos

      while pos < end_pos
        # Skip whitespace
        while pos < end_pos && whitespace?(@css[pos])
          pos += 1
        end
        break if pos >= end_pos

        # Parse property name (read until ':')
        prop_start = pos
        while pos < end_pos && @css[pos] != ':' && @css[pos] != ';' && @css[pos] != '}'
          pos += 1
        end

        # Skip if no colon found (malformed)
        if pos >= end_pos || @css[pos] != ':'
          # Try to recover by finding next semicolon
          while pos < end_pos && @css[pos] != ';'
            pos += 1
          end
          pos += 1 if pos < end_pos && @css[pos] == ';'
          next
        end

        prop_end = pos
        # Trim trailing whitespace from property
        while prop_end > prop_start && whitespace?(@css[prop_end - 1])
          prop_end -= 1
        end

        property = @css[prop_start...prop_end].downcase

        pos += 1  # Skip ':'

        # Skip leading whitespace in value
        while pos < end_pos && whitespace?(@css[pos])
          pos += 1
        end

        # Parse value (read until ';' or '}')
        val_start = pos
        while pos < end_pos && @css[pos] != ';' && @css[pos] != '}'
          pos += 1
        end
        val_end = pos

        # Trim trailing whitespace from value
        while val_end > val_start && whitespace?(@css[val_end - 1])
          val_end -= 1
        end

        value = @css[val_start...val_end]

        pos += 1 if pos < end_pos && @css[pos] == ';'

        # Create Declaration struct (at-rules don't use !important)
        declarations << Declaration.new(property, value, false)
      end

      declarations
    end
  end

  # ============================================================================
  # SPECIFICITY CALCULATOR
  # ============================================================================

  # Char-by-char specificity calculator (NO REGEXP)
  class SpecificityCalculator
    def initialize(selector)
      @selector = selector
      @pos = 0
      @len = selector.bytesize

      @id_count = 0        # #id selectors (worth 100 each)
      @class_count = 0     # .class, [attr], :pseudo (worth 10 each)
      @element_count = 0   # element, ::pseudo-element (worth 1 each)
    end

    def calculate
      # TODO: Parse selector char-by-char
      # Count IDs, classes/attrs/pseudos, elements
      # Return specificity value

      @id_count * 100 + @class_count * 10 + @element_count
    end
  end

  # ============================================================================
  # SERIALIZER
  # ============================================================================

  # Char-by-char CSS serializer (NO REGEXP)
  class Serializer
    def initialize(rules, media_index, charset, has_nesting, formatted: false)
      @rules = rules
      @media_index = media_index
      @charset = charset
      @has_nesting = has_nesting
      @formatted = formatted
      @output = String.new(encoding: Encoding::UTF_8)
    end

    def serialize
      # TODO: Build CSS string
      # - Handle @charset
      # - Group rules by media query
      # - Handle nesting
      # - Format with or without indentation

      @output
    end

    private

    def append(str)
      @output << str
    end

    def newline
      @output << "\n" if @formatted
    end

    def indent(level)
      @output << ("  " * level) if @formatted
    end
  end
end
