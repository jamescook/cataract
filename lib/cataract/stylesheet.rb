# frozen_string_literal: true

module Cataract
  # Represents a parsed CSS stylesheet with rule management and merging capabilities.
  #
  # The Stylesheet class stores parsed CSS rules in a flat array structure that preserves
  # insertion order. Media queries are tracked via an index that maps media query symbols
  # to rule IDs, allowing efficient filtering and serialization.
  #
  # @example Parse and query CSS
  #   sheet = Cataract::Stylesheet.parse("body { color: red; }")
  #   sheet.size #=> 1
  #   sheet.rules.first.selector #=> "body"
  #
  # @example Work with media queries
  #   sheet = Cataract.parse_css("@media print { .footer { color: blue; } }")
  #   sheet.media_queries #=> [:print]
  #   sheet.with_media(:print).first.selector #=> ".footer"
  #
  # @attr_reader [Array<Rule>] rules Array of parsed CSS rules
  # @attr_reader [String, nil] charset The @charset declaration if present
  # @attr_reader [Array<ImportStatement>] imports Array of @import statements
  class Stylesheet
    include Enumerable

    # @return [Array<Rule>] Array of parsed CSS rules
    attr_reader :rules

    # @return [Array<MediaQuery>] Array of media query objects
    attr_reader :media_queries

    # @return [Hash<Symbol, Array<Integer>>] Cached index mapping media query text to rule IDs
    # Lazily build and return media_index.
    # Only builds the index when first accessed, not eagerly during parse.
    #
    # @return [Hash{Symbol => Array<Integer>}] Hash mapping media types to rule IDs
    def media_index
      # If media_index is empty but we have rules with media_query_id, build it
      if @media_index.empty? && @rules.any? { |r| r.respond_to?(:media_query_id) && r.media_query_id }
        @media_index = {}

        # First, build a reverse lookup: media_query_id => list_id (if in a list)
        mq_id_to_list_id = {}
        @_media_query_lists.each do |list_id, mq_ids|
          mq_ids.each { |mq_id| mq_id_to_list_id[mq_id] = list_id }
        end

        @rules.each do |rule|
          next unless rule.media_query_id

          # Check if this rule's media_query_id is part of a list
          list_id = mq_id_to_list_id[rule.media_query_id]

          if list_id
            # This rule is in a compound media query (e.g., "@media screen, print")
            # Index it under ALL media types in the list
            mq_ids = @_media_query_lists[list_id]
            mq_ids.each do |mq_id|
              mq = @media_queries[mq_id]
              next unless mq

              media_type = mq.type
              @media_index[media_type] ||= []
              @media_index[media_type] << rule.id
            end
          else
            # Single media query - index under its type
            mq = @media_queries[rule.media_query_id]
            next unless mq

            media_type = mq.type
            @media_index[media_type] ||= []
            @media_index[media_type] << rule.id
          end
        end

        # Deduplicate arrays once at the end
        @media_index.each_value(&:uniq!)
      end

      @media_index
    end

    # @return [String, nil] The @charset declaration if present
    attr_reader :charset

    # @return [Array<ImportStatement>] Array of @import statements
    attr_reader :imports

    # Create a new empty stylesheet.
    #
    # @param options [Hash] Configuration options
    # @option options [Boolean, Hash] :import (false) Enable @import resolution.
    #   Pass true for defaults, or a hash with:
    #   - :allowed_schemes [Array<String>] URI schemes to allow (default: ['https'])
    #   - :extensions [Array<String>] File extensions to allow (default: ['css'])
    #   - :max_depth [Integer] Maximum import nesting (default: 5)
    # @option options [Boolean] :io_exceptions (true) Whether to raise exceptions
    #   on I/O errors (file not found, network errors, etc.)
    # @option options [String] :base_uri (nil) Base URI for resolving relative URLs
    #   and @import paths. Used for both URL conversion and import resolution.
    # @option options [String] :base_dir (nil) Base directory for resolving local
    #   file @import paths.
    # @option options [Boolean] :absolute_paths (false) Convert relative URLs in
    #   url() values to absolute URLs using base_uri.
    # @option options [Proc] :uri_resolver (nil) Custom proc for resolving relative URIs.
    #   Takes (base_uri, relative_uri) and returns absolute URI string.
    #   Defaults to using Ruby's URI.parse(base).merge(relative).to_s
    # @option options [Hash] :parser ({}) Parser configuration options
    #   - :selector_lists [Boolean] (true) Track selector lists for W3C-compliant serialization
    def initialize(options = {})
      # Type validation
      raise TypeError, "options must be a Hash, got #{options.class}" unless options.is_a?(Hash)

      # Support :imports as alias for :import (backwards compatibility)
      options[:import] = options.delete(:imports) if options.key?(:imports) && !options.key?(:import)

      @options = {
        import: false,
        io_exceptions: true,
        base_uri: nil,
        base_dir: nil,
        absolute_paths: false,
        uri_resolver: nil,
        parser: {},
        raise_parse_errors: false
      }.merge(options)

      # Type validation for specific options
      if @options[:import_fetcher] && !@options[:import_fetcher].respond_to?(:call)
        raise TypeError, "import_fetcher must be a Proc or callable, got #{@options[:import_fetcher].class}"
      end

      if @options[:base_uri] && !@options[:base_uri].is_a?(String)
        raise TypeError, "base_uri must be a String, got #{@options[:base_uri].class}"
      end

      if @options[:uri_resolver] && !@options[:uri_resolver].respond_to?(:call)
        raise TypeError, "uri_resolver must be a Proc or callable, got #{@options[:uri_resolver].class}"
      end

      # Parser options with defaults (stored for passing to parser)
      @parser_options = {
        selector_lists: true,
        raise_parse_errors: @options[:raise_parse_errors]
      }.merge(@options[:parser] || {})

      @rules = [] # Flat array of Rule structs
      @media_queries = [] # Array of MediaQuery objects
      @_next_media_query_id = 0 # Counter for MediaQuery IDs
      @media_index = {} # Hash: Symbol => Array of rule IDs (cached index, can be rebuilt from rules)
      @_selector_lists = {} # Hash: list_id => Array of rule IDs (for "h1, h2" grouping)
      @_next_selector_list_id = 0 # Counter for selector list IDs
      @_media_query_lists = {} # Hash: list_id => Array of MediaQuery IDs (for "screen, print" grouping)
      @_next_media_query_list_id = 0 # Counter for media query list IDs
      @charset = nil
      @imports = [] # Array of ImportStatement objects
      @_has_nesting = nil # Set by parser (nil or boolean)
      @_last_rule_id = nil # Tracks next rule ID for add_block
      @selectors = nil # Memoized cache of selectors
      @_custom_properties = nil # Memoized cache of custom properties
    end

    # Initialize copy for proper deep duplication.
    #
    # Ensures that dup/clone creates a proper deep copy of the stylesheet,
    # duplicating internal arrays and hashes so mutations don't affect the original.
    #
    # @param source [Stylesheet] Source stylesheet being copied
    def initialize_copy(source)
      super
      @rules = source.instance_variable_get(:@rules).dup
      @media_queries = source.instance_variable_get(:@media_queries).dup
      @_next_media_query_id = source.instance_variable_get(:@_next_media_query_id)
      @media_index = source.instance_variable_get(:@media_index).transform_values(&:dup)
      @imports = source.instance_variable_get(:@imports).dup
      @_selector_lists = source.instance_variable_get(:@_selector_lists).transform_values(&:dup)
      @_next_selector_list_id = source.instance_variable_get(:@_next_selector_list_id)
      @_media_query_lists = source.instance_variable_get(:@_media_query_lists).transform_values(&:dup)
      @_next_media_query_list_id = source.instance_variable_get(:@_next_media_query_list_id)
      @parser_options = source.instance_variable_get(:@parser_options).dup
      clear_memoized_caches
      @_hash = nil # Clear cached hash
    end

    # Parse CSS and return a new Stylesheet
    #
    # @param css [String] CSS string to parse
    # @param options [Hash] Options passed to Stylesheet.new
    # @return [Stylesheet] Parsed stylesheet
    def self.parse(css, **options)
      sheet = new(options)
      sheet.add_block(css)
      sheet
    end

    # Load CSS from a file and return a new Stylesheet.
    #
    # @param filename [String] Path to the CSS file
    # @param base_dir [String] Base directory for resolving the filename (default: '.')
    # @param options [Hash] Options passed to Stylesheet.new
    # @return [Stylesheet] A new Stylesheet containing the parsed CSS
    def self.load_file(filename, base_dir = '.', **options)
      sheet = new(options)
      sheet.load_file(filename, base_dir)
      sheet
    end

    # Load CSS from a URI and return a new Stylesheet.
    #
    # @param uri [String] URI to load CSS from (http://, https://, or file://)
    # @param options [Hash] Options passed to Stylesheet.new
    # @return [Stylesheet] A new Stylesheet containing the parsed CSS
    def self.load_uri(uri, **options)
      sheet = new(options)
      sheet.load_uri(uri, options)
      sheet
    end

    # Iterate over all rules (required by Enumerable).
    #
    # Yields both selector-based rules (Rule) and at-rules (AtRule).
    # Use rule.selector? to filter for selector-based rules only.
    #
    # @yield [rule] Block to execute for each rule
    # @yieldparam rule [Rule, AtRule] The rule object
    # @return [Enumerator] Returns enumerator if no block given
    #
    # @example Iterate over all rules
    #   sheet.each { |rule| puts rule.selector }
    #
    # @example Filter to selector-based rules only
    #   sheet.select(&:selector?).each { |rule| puts rule.specificity }
    def each(&)
      return enum_for(:each) unless block_given?

      @rules.each(&)
    end

    def [](offset)
      return unless @rules

      @rules[offset]
    end

    # Filter rules by media query symbol(s).
    #
    # Returns a chainable StylesheetScope that can be further filtered.
    #
    # @param media [Symbol, Array<Symbol>] Media query symbol(s) to filter by
    # @return [StylesheetScope] Scope with media filter applied
    #
    # @example Get print media rules
    #   sheet.with_media(:print).each { |rule| puts rule.selector }
    #   sheet.with_media(:print).select(&:selector?).map(&:selector)
    #
    # @example Get rules from multiple media queries
    #   sheet.with_media([:screen, :print]).map(&:selector)
    #
    # @example Chain filters
    #   sheet.with_media(:print).with_specificity(10..).to_a
    def with_media(media)
      StylesheetScope.new(self, media: media)
    end

    # Filter rules by CSS specificity.
    #
    # Returns a chainable StylesheetScope that can be further filtered.
    #
    # @param specificity [Integer, Range] Specificity value or range
    # @return [StylesheetScope] Scope with specificity filter applied
    #
    # @example Get high-specificity rules
    #   sheet.with_specificity(100..).each { |rule| puts rule.selector }
    #
    # @example Get exact specificity
    #   sheet.with_specificity(10).map(&:selector)
    #
    # @example Chain with media filter
    #   sheet.with_media(:print).with_specificity(10..50).to_a
    def with_specificity(specificity)
      StylesheetScope.new(self, specificity: specificity)
    end

    # Filter rules by CSS selector.
    #
    # Returns a chainable StylesheetScope that can be further filtered.
    # Supports both exact string matching and regular expression patterns.
    #
    # @param selector [String, Regexp] CSS selector to match (exact or pattern)
    # @return [StylesheetScope] Scope with selector filter applied
    #
    # @example Find body rules (exact match)
    #   sheet.with_selector('body').to_a
    #
    # @example Find all .btn-* classes (pattern match)
    #   sheet.with_selector(/\.btn-/).map(&:selector)
    #
    # @example Find body rules in print media
    #   sheet.with_media(:print).with_selector('body').each { |r| puts r }
    #
    # @example Chain multiple filters
    #   sheet.with_selector('.header').with_specificity(10..).to_a
    def with_selector(selector)
      StylesheetScope.new(self, selector: selector)
    end

    # Filter rules by CSS property name and optional value.
    #
    # Returns a chainable StylesheetScope that can be further filtered.
    #
    # @param property [String] CSS property name to match
    # @param value [String, nil] Optional property value to match
    # @param prefix_match [Boolean] Whether to match by prefix (default: false)
    # @return [StylesheetScope] Scope with property filter applied
    #
    # @example Find all rules with color property
    #   sheet.with_property('color').map(&:selector)
    #
    # @example Find rules with position: absolute
    #   sheet.with_property('position', 'absolute').to_a
    #
    # @example Find all margin-related properties (margin, margin-top, etc.)
    #   sheet.with_property('margin', prefix_match: true).to_a
    #
    # @example Chain with media filter
    #   sheet.with_media(:screen).with_property('z-index').to_a
    def with_property(property, value = nil, prefix_match: false)
      StylesheetScope.new(self, property: property, property_value: value, property_prefix_match: prefix_match)
    end

    # Filter to only base rules (rules not inside any @media query).
    #
    # Returns a chainable StylesheetScope that can be further filtered.
    #
    # @return [StylesheetScope] Scope with base_only filter applied
    #
    # @example Get base rules only
    #   sheet.base_only.map(&:selector)
    #
    # @example Chain with property filter
    #   sheet.base_only.with_property('color').to_a
    def base_only
      StylesheetScope.new(self, base_only: true)
    end

    # Filter by at-rule type.
    #
    # Returns a chainable StylesheetScope that can be further filtered.
    #
    # @param type [Symbol] At-rule type to match (:keyframes, :font_face, etc.)
    # @return [StylesheetScope] Scope with at-rule type filter applied
    #
    # @example Find all @keyframes
    #   sheet.with_at_rule_type(:keyframes).map(&:selector)
    #
    # @example Find all @font-face
    #   sheet.with_at_rule_type(:font_face).to_a
    #
    # @example Chain with media filter
    #   sheet.with_media(:screen).with_at_rule_type(:keyframes).to_a
    def with_at_rule_type(type)
      StylesheetScope.new(self, at_rule_type: type)
    end

    # Filter to rules with !important declarations.
    #
    # Returns a chainable StylesheetScope that can be further filtered.
    #
    # @param property [String, nil] Optional property name to match
    # @return [StylesheetScope] Scope with important filter applied
    #
    # @example Find all rules with any !important
    #   sheet.with_important.map(&:selector)
    #
    # @example Find rules with color !important
    #   sheet.with_important('color').to_a
    #
    # @example Chain with media filter
    #   sheet.with_media(:screen).with_important.to_a
    def with_important(property = nil)
      StylesheetScope.new(self, important: true, important_property: property)
    end

    # Get all rules without media query (rules that apply to all media)
    #
    # @return [Array<Rule>] Rules with no media query
    def base_rules
      # Rules not in any media_index entry
      media_rule_ids = media_index.values.flatten.uniq
      @rules.select.with_index { |_rule, idx| !media_rule_ids.include?(idx) }
    end

    # Get all selectors
    #
    # @return [Array<String>] Array of all selectors
    def selectors
      @selectors ||= @rules.map(&:selector)
    end

    # Get all custom property (CSS variable) definitions organized by media context.
    #
    # Returns a hash mapping media contexts to custom property hashes.
    # Custom properties are CSS variables that start with -- (e.g., --primary-color).
    # The :root key contains base-level properties (not inside any @media block).
    # When the same custom property is defined multiple times within the same context,
    # the last definition in source order is used.
    #
    # @param media [Symbol, Array<Symbol>, nil] Optional filter for specific media contexts
    #   - nil (default) - Return all media contexts including :root
    #   - :root - Return only base-level properties
    #   - :print, :screen, etc. - Return only properties from specified media context(s)
    #   - [:root, :print] - Return multiple contexts
    #
    # @return [Hash{Symbol => Hash{String => String}}] Media contexts mapped to custom properties
    #
    # @example All custom properties across all contexts
    #   css = ':root { --color: red; } @media print { :root { --color: green; } }'
    #   sheet = Cataract::Stylesheet.parse(css)
    #   sheet.custom_properties #=> { :root => { '--color' => 'red' }, :print => { '--color' => 'green' } }
    #
    # @example Filter to specific media context
    #   sheet.custom_properties(media: :print) #=> { :print => { '--color' => 'green' } }
    #
    # @example Filter to multiple contexts
    #   sheet.custom_properties(media: [:root, :print]) #=> { :root => {...}, :print => {...} }
    #
    # @example Only base-level properties
    #   css = ':root { --spacing: 8px; }'
    #   sheet = Cataract::Stylesheet.parse(css)
    #   sheet.custom_properties #=> { :root => { '--spacing' => '8px' } }
    def custom_properties(media: nil)
      @_custom_properties ||= build_custom_properties
      return @_custom_properties if media.nil?

      # Filter by media if requested
      media_array = media.is_a?(Array) ? media : [media]
      @_custom_properties.slice(*media_array)
    end

    # Serialize to CSS string
    #
    # Converts the stylesheet to a CSS string. Optionally filters output
    # to only include rules from specific media queries.
    #
    # @param media [Symbol, Array<Symbol>] Media type(s) to include (default: :all)
    #   - :all - Output all rules including base rules and all media queries
    #   - :screen, :print, etc. - Output only rules from specified media query
    #   - [:screen, :print] - Output rules from multiple media queries
    #
    # Important: When filtering to specific media types, base rules (rules not
    # inside any @media block) are NOT included. Only rules explicitly inside
    # the requested @media queries are output. Use :all to include base rules.
    # @return [String] CSS string
    #
    # @example Get all CSS
    #   sheet.to_s                 # => "body { color: black; } @media print { .footer { color: red; } }"
    #   sheet.to_s(media: :all)    # => "body { color: black; } @media print { .footer { color: red; } }"
    #
    # @example Filter to specific media type (excludes base rules)
    #   sheet.to_s(media: :print)  # => "@media print { .footer { color: red; } }"
    #   # Note: base rules like "body { color: black; }" are NOT included
    #
    # @example Filter to multiple media types
    #   sheet.to_s(media: [:screen, :print])  # => "@media screen { ... } @media print { ... }"
    def to_s(media: :all)
      which_media = media
      # Normalize to array for consistent filtering
      which_media_array = which_media.is_a?(Array) ? which_media : [which_media]

      # If :all is present, return everything (no filtering)
      if which_media_array.include?(:all)
        Cataract.stylesheet_to_s(@rules, @charset, @_has_nesting || false, @_selector_lists, @media_queries, @_media_query_lists)
      else
        # Collect all rule IDs that match the requested media types
        matching_rule_ids = []
        mi = media_index # Build media_index if needed
        which_media_array.each do |media_sym|
          if mi[media_sym]
            matching_rule_ids.concat(mi[media_sym])
          end
        end
        matching_rule_ids.uniq! # Dedupe: same rule can be in multiple media indexes

        # Build filtered rules array (keep original IDs, no recreation needed)
        filtered_rules = matching_rule_ids.sort.map! { |rule_id| @rules[rule_id] }

        # Serialize with filtered data
        Cataract.stylesheet_to_s(filtered_rules, @charset, @_has_nesting || false, @_selector_lists, @media_queries, @_media_query_lists)
      end
    end
    alias to_css to_s

    # Serialize to formatted CSS string with indentation and newlines.
    #
    # Converts the stylesheet to a human-readable CSS string with proper indentation.
    # Rules are formatted with each declaration on its own line, and media queries
    # are properly indented. Optionally filters output to specific media queries.
    #
    # @param which_media [Symbol, Array<Symbol>] Optional media filter (default: :all)
    #   - :all - Output all rules including base rules and all media queries
    #   - :screen, :print, etc. - Output only rules from specified media query
    #   - [:screen, :print] - Output rules from multiple media queries
    #
    # @return [String] Formatted CSS string
    #
    # @example Get all CSS formatted
    #   sheet.to_formatted_s
    #   # => "body {\n  color: black;\n}\n@media print {\n  .footer {\n    color: red;\n  }\n}\n"
    #
    # @example Filter to specific media type
    #   sheet.to_formatted_s(:print)
    #
    # @see #to_s For compact single-line output
    def to_formatted_s(media: :all)
      which_media = media
      # Normalize to array for consistent filtering
      which_media_array = which_media.is_a?(Array) ? which_media : [which_media]

      # If :all is present, return everything (no filtering)
      if which_media_array.include?(:all)
        Cataract.stylesheet_to_formatted_s(@rules, @charset, @_has_nesting || false, @_selector_lists, @media_queries, @_media_query_lists)
      else
        # Collect all rule IDs that match the requested media types
        matching_rule_ids = []
        mi = media_index # Build media_index if needed

        # Include rules not in any media query (they apply to all media)
        media_rule_ids = mi.values.flatten.uniq
        all_rule_ids = (0...@rules.length).to_a
        non_media_rule_ids = all_rule_ids - media_rule_ids
        matching_rule_ids.concat(non_media_rule_ids)

        # Include rules from requested media types
        which_media_array.each do |media_sym|
          if mi[media_sym]
            matching_rule_ids.concat(mi[media_sym])
          end
        end
        matching_rule_ids.uniq! # Dedupe: same rule can be in multiple media indexes

        # Build filtered rules array (keep original IDs, no recreation needed)
        filtered_rules = matching_rule_ids.sort.map! { |rule_id| @rules[rule_id] }

        # Serialize with filtered data
        Cataract.stylesheet_to_formatted_s(filtered_rules, @charset, @_has_nesting || false, @_selector_lists, @media_queries, @_media_query_lists)
      end
    end

    # Get number of rules
    #
    # @return [Integer] Number of rules
    def size
      @rules.length
    end
    alias length size
    alias rules_count size

    # Check if stylesheet is empty
    #
    # @return [Boolean] true if no rules
    def empty?
      @rules.empty?
    end

    # Clear all rules
    #
    # @return [self] Returns self for method chaining
    def clear!
      @rules.clear
      @media_index.clear
      @charset = nil
      clear_memoized_caches
      self
    end

    # Load CSS from a local file and add to this stylesheet.
    #
    # @param filename [String] Path to the CSS file
    # @param base_dir [String] Base directory for resolving the filename (default: '.')
    # @return [self] Returns self for method chaining
    def load_file(filename, base_dir = '.', _media_types = :all)
      # Normalize file path and convert to file:// URI
      file_path = File.expand_path(filename, base_dir)
      file_uri = "file://#{file_path}"

      # Delegate to load_uri which handles imports and base_path
      load_uri(file_uri)
    end

    # Load CSS from a URI and add to this stylesheet.
    #
    # @param uri [String] URI to load CSS from (http://, https://, or file://)
    # @param options [Hash] Additional options
    # @return [self] Returns self for method chaining
    def load_uri(uri, options = {})
      require 'uri'
      require 'net/http'

      uri_obj = URI(uri)
      css_content = nil
      file_path = nil

      case uri_obj.scheme
      when 'http', 'https'
        response = Net::HTTP.get_response(uri_obj)
        unless response.is_a?(Net::HTTPSuccess)
          raise IOError, "Failed to load URI: #{uri} (#{response.code} #{response.message})"
        end

        css_content = response.body
      when 'file', nil
        # file:// URI or relative path
        path = uri_obj.scheme == 'file' ? uri_obj.path : uri
        # Handle base_uri if provided
        if options[:base_uri]
          base = URI(options[:base_uri])
          path = File.join(base.path, path) if base.scheme == 'file' || base.scheme.nil?
        end
        file_path = File.expand_path(path)

        # If imports are enabled and base_path not already set, set it for resolving relative imports
        if @options[:import].is_a?(Hash) && @options[:import][:base_path].nil?
          file_dir = File.dirname(file_path)
          @options[:import] = @options[:import].merge(base_path: file_dir)
        end

        css_content = File.read(file_path)
      else
        raise ArgumentError, "Unsupported URI scheme: #{uri_obj.scheme}"
      end

      add_block(css_content)
      self
    rescue Errno::ENOENT
      raise IOError, "File not found: #{uri}" if @options[:io_exceptions]

      self
    rescue StandardError => e
      raise IOError, "Error loading URI: #{uri} - #{e.message}" if @options[:io_exceptions]

      self
    end

    # Remove rules from the stylesheet
    #
    # @param rules_or_css [String, Rule, AtRule, Array<Rule, AtRule>] Rules to remove.
    #   Can be a CSS string to parse (selectors will be matched), a single Rule/AtRule object,
    #   or an array of Rule/AtRule objects.
    # @param media_types [Symbol, Array<Symbol>, nil] Optional media types to filter removal.
    #   Only removes rules that match these media types. Pass :all to include base rules.
    # @return [self] Returns self for method chaining
    #
    # @example Remove rules by CSS string
    #   sheet.remove_rules!('.header { }')
    #   sheet.remove_rules!('.header { } .footer { }')
    #
    # @example Remove rules from specific media type
    #   sheet.remove_rules!('.header { }', media_types: :screen)
    #
    # @example Remove specific rule objects
    #   rules = sheet.select { |r| r.selector =~ /\.btn-/ }
    #   sheet.remove_rules!(rules)
    #
    # @example Remove rules with media filtering
    #   sheet.remove_rules!(sheet.with_selector('.header'), media_types: :print)
    def remove_rules!(rules_or_css, media_types: nil)
      # Determine if we're matching by selector (CSS string) or by object identity (rule objects)
      if rules_or_css.is_a?(String)
        # Parse CSS string and extract selectors for matching
        parsed = Stylesheet.parse(rules_or_css)
        selectors_to_remove = parsed.rules.filter_map(&:selector).to_set
        match_by_selector = true
      else
        # Use rule objects directly
        rules_to_remove = rules_or_css.is_a?(Array) ? rules_or_css : [rules_or_css]
        return self if rules_to_remove.empty?

        match_by_selector = false
      end

      # Normalize media_types to array
      filter_media = media_types ? Array(media_types).map(&:to_sym) : nil

      # Find rule IDs to remove
      rule_ids_to_remove = []
      @rules.each_with_index do |rule, rule_id|
        # Check if this rule matches
        matches = if match_by_selector
                    # Match by selector for CSS string input
                    selectors_to_remove.include?(rule.selector)
                  else
                    # Match by object equality for rule collection input
                    rules_to_remove.any?(rule)
                  end
        next unless matches

        # Check media type match if filter is specified
        if filter_media
          rule_media_types = media_index.select { |_media, ids| ids.include?(rule_id) }.keys

          # If rule is not in any media query (base rule), skip unless :all is specified
          if rule_media_types.empty?
            next unless filter_media.include?(:all)
          else
            # Check if rule's media types intersect with filter
            next unless rule_media_types.intersect?(filter_media)
          end
        end

        rule_ids_to_remove << rule_id
      end

      # Remove rules and update media_index (sort in reverse to maintain indices during deletion)
      rule_ids_to_remove.sort.reverse_each do |rule_id|
        @rules.delete_at(rule_id)

        # Remove from media_index and update IDs for rules after this one
        @media_index.each_value do |ids|
          ids.delete(rule_id)
          # Decrement IDs greater than removed ID
          ids.map! { |id| id > rule_id ? id - 1 : id }
        end
      end

      # Clean up empty media_index entries
      @media_index.delete_if { |_media, ids| ids.empty? }

      # Clean up unused MediaQuery objects (those not referenced by any rule)
      used_mq_ids = @rules.filter_map { |r| r.media_query_id if r.is_a?(Rule) }.to_set
      @media_queries.select! { |mq| used_mq_ids.include?(mq.id) }

      # Update rule IDs in remaining rules
      @rules.each_with_index { |rule, new_id| rule.id = new_id }

      clear_memoized_caches

      self
    end

    # Add CSS block to stylesheet
    #
    # @param css [String] CSS string to add
    # @param fix_braces [Boolean] Automatically close missing braces
    # @param media_types [Symbol, Array<Symbol>] Optional media query to wrap CSS in
    # @param base_uri [String, nil] Override constructor's base_uri for this block
    # @param base_dir [String, nil] Override constructor's base_dir for this block
    # @param absolute_paths [Boolean, nil] Override constructor's absolute_paths for this block
    # @return [self] Returns self for method chaining
    def add_block(css, fix_braces: false, media_types: nil, base_uri: nil, base_dir: nil, absolute_paths: nil)
      css += ' }' if fix_braces && !css.strip.end_with?('}')

      # Convenience wrapper: wrap in @media if media_types specified
      if media_types
        media_list = Array(media_types).join(', ')
        css = "@media #{media_list} { #{css} }"
      end

      # Determine effective options (per-call overrides or constructor defaults)
      effective_base_uri = base_uri || @options[:base_uri]
      effective_base_dir = base_dir || @options[:base_dir]
      effective_absolute_paths = absolute_paths.nil? ? @options[:absolute_paths] : absolute_paths

      # Get current rule ID offset
      offset = @_last_rule_id || 0

      # Build parser options with URL conversion settings
      parse_options = @parser_options.dup
      if effective_absolute_paths && effective_base_uri
        parse_options[:base_uri] = effective_base_uri
        parse_options[:absolute_paths] = true
        parse_options[:uri_resolver] = @options[:uri_resolver] || Cataract::DEFAULT_URI_RESOLVER
      end

      # Parse CSS first (this extracts @import statements into result[:imports])
      result = Cataract._parse_css(css, parse_options)

      # Merge selector_lists with offsetted IDs
      list_id_offset = @_next_selector_list_id
      if result[:_selector_lists] && !result[:_selector_lists].empty?
        result[:_selector_lists].each do |list_id, rule_ids|
          new_list_id = list_id + list_id_offset
          offsetted_rule_ids = rule_ids.map { |id| id + offset }
          @_selector_lists[new_list_id] = offsetted_rule_ids
        end
        @_next_selector_list_id = list_id_offset + result[:_selector_lists].size
      end

      # Merge media_query_lists with offsetted IDs
      media_query_id_offset = @_next_media_query_id
      mq_list_id_offset = @_next_media_query_list_id
      if result[:_media_query_lists] && !result[:_media_query_lists].empty?
        result[:_media_query_lists].each do |list_id, mq_ids|
          new_list_id = list_id + mq_list_id_offset
          offsetted_mq_ids = mq_ids.map { |id| id + media_query_id_offset }
          @_media_query_lists[new_list_id] = offsetted_mq_ids
        end
        @_next_media_query_list_id = mq_list_id_offset + result[:_media_query_lists].size
      end

      # Merge rules with offsetted IDs
      new_rules = result[:rules]
      new_rules.each do |rule|
        rule.id += offset
        # Update selector_list_id to point to offsetted list (only for Rule, not AtRule)
        if rule.is_a?(Rule) && rule.selector_list_id
          rule.selector_list_id += list_id_offset
        end
        # Update media_query_id to point to offsetted MediaQuery
        if rule.is_a?(Rule) && rule.media_query_id
          rule.media_query_id += media_query_id_offset
        end
        @rules << rule
      end

      # Merge media_index with offsetted IDs
      result[:_media_index].each do |media_sym, rule_ids|
        offsetted_ids = rule_ids.map { |id| id + offset }
        if @media_index[media_sym]
          @media_index[media_sym].concat(offsetted_ids)
        else
          @media_index[media_sym] = offsetted_ids
        end
      end

      # Merge media_queries with offsetted IDs
      if result[:media_queries]
        result[:media_queries].each do |mq|
          mq.id += media_query_id_offset
          @media_queries << mq
        end
        @_next_media_query_id += result[:media_queries].length
      end

      # Update last rule ID
      @_last_rule_id = offset + new_rules.length

      # Merge imports with offsetted IDs
      if result[:imports]
        new_imports = result[:imports]
        new_imports.each do |import|
          import.id += offset
          # Update media_query_id to point to offsetted MediaQuery
          if import.media_query_id
            import.media_query_id += media_query_id_offset
          end
          @imports << import
        end

        # Resolve imports if configured
        if @options[:import]
          # Extract imported_urls and depth from options
          if @options[:import].is_a?(Hash)
            imported_urls = @options[:import][:imported_urls] || []
            depth = @options[:import][:depth] || 0
          else
            imported_urls = []
            depth = 0
          end

          # Build import options with base_uri/base_dir for URL resolution
          import_opts = @options[:import].is_a?(Hash) ? @options[:import].dup : {}
          import_opts[:base_uri] = effective_base_uri if effective_base_uri
          import_opts[:base_path] = effective_base_dir if effective_base_dir

          resolve_imports(new_imports, import_opts, imported_urls: imported_urls, depth: depth)
        end
      end

      # Set charset if not already set
      @charset ||= result[:charset]

      # Track if we have any nesting (for serialization optimization)
      @_has_nesting = result[:_has_nesting]

      clear_memoized_caches

      self
    end

    # Add a single rule
    #
    # @param selector [String] CSS selector
    # @param declarations [String] CSS declarations (property: value pairs)
    # @param media_types [Symbol, Array<Symbol>] Optional media types to wrap rule in
    # @return [self] Returns self for method chaining
    def add_rule(selector:, declarations:, media_types: nil)
      # Wrap in CSS syntax and add as block
      css = "#{selector} { #{declarations} }"
      add_block(css, media_types: media_types)
    end

    # Convert to hash
    #
    # @return [Hash] Hash representation
    def to_h
      {
        rules: @rules,
        charset: @charset
      }
    end

    def inspect
      total_rules = size
      if total_rules.zero?
        '#<Cataract::Stylesheet empty>'
      else
        preview = @rules.first(3).map(&:selector).join(', ')
        more = total_rules > 3 ? ', ...' : ''
        "#<Cataract::Stylesheet #{total_rules} rules: #{preview}#{more}>"
      end
    end

    # Compare stylesheets for equality.
    #
    # Two stylesheets are equal if they have the same rules in the same order
    # and the same media queries. Rule equality uses shorthand-aware comparison.
    # Order matters because CSS cascade depends on rule order.
    #
    # Charset is ignored since it's file encoding metadata, not semantic content.
    #
    # @param other [Object] Object to compare with
    # @return [Boolean] true if stylesheets are equal
    def ==(other)
      return false unless other.is_a?(Stylesheet)
      return false unless rules == other.rules
      return false unless @media_queries == other.instance_variable_get(:@media_queries)

      true
    end
    alias eql? ==

    # Generate hash code for this stylesheet.
    #
    # Hash is based on rules and media_queries to match equality semantics.
    #
    # @return [Integer] hash code
    def hash
      @_hash ||= [self.class, rules, @media_queries].hash # rubocop:disable Naming/MemoizedInstanceVariableName
    end

    # Flatten all rules in this stylesheet according to CSS cascade rules.
    #
    # Applies specificity and !important precedence rules to compute the final
    # set of declarations. Also recreates shorthand properties from longhand
    # properties where possible.
    #
    # @return [Stylesheet] New stylesheet with cascade applied
    def flatten
      Cataract.flatten(self)
    end
    alias cascade flatten

    # Deprecated: Use flatten instead
    def merge
      warn 'Stylesheet#merge is deprecated, use #flatten instead', uplevel: 1
      flatten
    end

    # Flatten rules in-place, mutating the receiver.
    #
    # This is a convenience method that updates the stylesheet's internal
    # rules and media_index with the flattened result. The Stylesheet object
    # itself is mutated (same object_id), but note that the C flatten function
    # still allocates new arrays internally.
    #
    # @return [self] Returns self for method chaining
    def flatten!
      flattened = Cataract.flatten(self)
      @rules = flattened.instance_variable_get(:@rules)
      @media_index = flattened.instance_variable_get(:@media_index)
      @_has_nesting = flattened.instance_variable_get(:@_has_nesting)
      self
    end
    alias cascade! flatten!

    # Deprecated: Use flatten! instead
    def merge!
      warn 'Stylesheet#merge! is deprecated, use #flatten! instead', uplevel: 1
      flatten!
    end

    # Concatenate another stylesheet's rules into this one and apply cascade.
    #
    # Adds all rules from the other stylesheet to this one, then applies
    # CSS cascade to resolve conflicts. Media queries are merged.
    #
    # @param other [Stylesheet] Stylesheet to concatenate
    # @return [self] Returns self for method chaining
    def concat(other)
      raise ArgumentError, 'Argument must be a Stylesheet' unless other.is_a?(Stylesheet)

      # Get the current offset for rule IDs
      offset = @rules.length

      # Add rules with updated IDs
      other.rules.each do |rule|
        new_rule = rule.dup
        new_rule.id = @rules.length
        @rules << new_rule
      end

      # Merge media_index with offsetted IDs
      other.instance_variable_get(:@media_index).each do |media_sym, rule_ids|
        offsetted_ids = rule_ids.map { |id| id + offset }
        if @media_index[media_sym]
          @media_index[media_sym].concat(offsetted_ids)
        else
          @media_index[media_sym] = offsetted_ids
        end
      end

      # Update nesting flag if other has nesting
      other_has_nesting = other.instance_variable_get(:@_has_nesting)
      @_has_nesting = true if other_has_nesting

      clear_memoized_caches

      # Apply cascade in-place
      flatten!
    end

    # Combine two stylesheets into a new one and apply cascade.
    #
    # Creates a new stylesheet containing rules from both stylesheets,
    # then applies CSS cascade to resolve conflicts.
    #
    # @param other [Stylesheet] Stylesheet to combine with
    # @return [Stylesheet] New stylesheet with combined and cascaded rules
    def +(other)
      result = dup
      result.concat(other)
      result
    end

    # Remove matching rules from this stylesheet.
    #
    # Creates a new stylesheet with rules that don't match any rules in the
    # other stylesheet. Uses Rule#== for matching (shorthand-aware).
    # Does NOT apply cascade to the result.
    #
    # @param other [Stylesheet] Stylesheet containing rules to remove
    # @return [Stylesheet] New stylesheet with matching rules removed
    def -(other)
      raise ArgumentError, 'Argument must be a Stylesheet' unless other.is_a?(Stylesheet)

      result = dup

      # Remove matching rules using Rule#==
      rules_to_remove_ids = []
      result.rules.each_with_index do |rule, idx|
        rules_to_remove_ids << idx if other.rules.include?(rule)
      end

      # Remove in reverse order to maintain indices
      rules_to_remove_ids.reverse_each do |idx|
        result.rules.delete_at(idx)

        # Update media_index: remove this rule ID and decrement higher IDs
        result.instance_variable_get(:@media_index).each_value do |ids|
          ids.delete(idx)
          ids.map! { |id| id > idx ? id - 1 : id }
        end
      end

      # Re-index remaining rules
      result.rules.each_with_index { |rule, new_id| rule.id = new_id }

      # Clean up empty media_index entries
      result.instance_variable_get(:@media_index).delete_if { |_media, ids| ids.empty? }

      # Clean up unused MediaQuery objects and rebuild ID mapping
      used_mq_ids = Set.new
      result.rules.each do |rule|
        used_mq_ids << rule.media_query_id if rule.respond_to?(:media_query_id) && rule.media_query_id
      end

      # Build old_id => new_id mapping
      # Keep MediaQuery objects that are used, maintaining their IDs
      old_to_new_mq_id = {}
      kept_mqs = []
      result.instance_variable_get(:@media_queries).each do |mq|
        next unless used_mq_ids.include?(mq.id)

        old_to_new_mq_id[mq.id] = kept_mqs.size
        mq.id = kept_mqs.size
        kept_mqs << mq
      end

      # Replace media_queries array with kept ones
      result.instance_variable_set(:@media_queries, kept_mqs)

      # Update media_query_id references in rules
      result.rules.each do |rule|
        if rule.respond_to?(:media_query_id) && rule.media_query_id
          rule.media_query_id = old_to_new_mq_id[rule.media_query_id]
        end
      end

      # Update media_query_lists with new IDs
      result.instance_variable_get(:@_media_query_lists).each_value do |mq_ids|
        mq_ids.map! { |mq_id| old_to_new_mq_id[mq_id] }.compact!
      end

      # Clean up media_query_lists that are now empty
      result.instance_variable_get(:@_media_query_lists).delete_if { |_list_id, mq_ids| mq_ids.empty? }

      # Clear memoized cache
      result.instance_variable_set(:@selectors, nil)
      result.instance_variable_set(:@_hash, nil)

      result
    end

    private

    # @private
    # Internal index mapping media query symbols to rule IDs for efficient filtering.
    # This is an implementation detail and should not be relied upon by external code.
    # @return [Hash<Symbol, Array<Integer>>]
    attr_reader :_media_index

    # Resolve @import statements by fetching and merging imported stylesheets
    #
    # @param imports [Array<ImportStatement>] Import statements to resolve
    # @param options [Hash] Import resolution options
    # @param imported_urls [Array<String>] URLs already imported (for circular detection)
    # @param depth [Integer] Current import depth (for depth limit)
    # @return [void]
    def resolve_imports(imports, options, imported_urls: [], depth: 0)
      # Normalize options with safe defaults
      opts = ImportResolver.normalize_options(options)

      # Check depth limit
      if depth > opts[:max_depth]
        raise ImportError, "Import nesting too deep: exceeded maximum depth of #{opts[:max_depth]}"
      end

      # Get or create fetcher
      fetcher = opts[:fetcher] || ImportResolver::DefaultFetcher.new

      imports.each do |import|
        next if import.resolved # Skip already resolved imports

        url = import.url
        import_media_query_id = import.media_query_id

        # Validate URL
        ImportResolver.validate_url(url, opts)

        # Check for circular references
        raise ImportError, "Circular import detected: #{url}" if imported_urls.include?(url)

        # Fetch imported CSS
        imported_css = fetcher.call(url, opts)

        # Parse imported CSS recursively
        imported_urls_copy = imported_urls.dup
        imported_urls_copy << url

        # Determine the base URI for the imported file
        # This becomes the new base for resolving relative URLs in the imported CSS
        imported_base_uri = ImportResolver.normalize_url(url, base_path: opts[:base_path], base_uri: opts[:base_uri]).to_s

        # Build parse options for imported CSS
        parse_opts = {
          import: opts.merge(imported_urls: imported_urls_copy, depth: depth + 1, base_uri: imported_base_uri),
          parser: @parser_options.dup # Inherit parent's parser options (including selector_lists)
        }

        # If URL conversion is enabled (base_uri present), enable it for imported files too
        if opts[:base_uri]
          parse_opts[:absolute_paths] = true
          parse_opts[:base_uri] = imported_base_uri
          parse_opts[:uri_resolver] = opts[:uri_resolver]
        end

        # Pass parent import's media query context to parser so nested imports can combine
        if import_media_query_id
          parent_mq = @media_queries[import_media_query_id]
          parse_opts[:parser][:parent_import_media_type] = parent_mq.type
          parse_opts[:parser][:parent_import_media_conditions] = parent_mq.conditions
        end

        imported_sheet = Stylesheet.parse(imported_css, **parse_opts)

        # Wrap rules in @media if import had media query
        if import_media_query_id
          # Get the import's MediaQuery object
          import_mq = @media_queries[import_media_query_id]

          imported_sheet.rules.each do |rule|
            next unless rule.is_a?(Rule)

            if rule.media_query_id
              # Rule already has a media query - need to combine them
              # Example: @import "mobile.css" screen; where mobile.css has @media (max-width: 768px)
              # Result: screen and (max-width: 768px)
              existing_mq = imported_sheet.media_queries[rule.media_query_id]

              # Parse combined media query to extract type and conditions
              # The type is always the import's type (leftmost)
              combined_type = import_mq.type
              combined_conditions = if import_mq.conditions && existing_mq.conditions
                                      "#{import_mq.conditions} and #{existing_mq.conditions}"
                                    elsif import_mq.conditions
                                      "#{import_mq.conditions} and #{existing_mq.text}"
                                    elsif existing_mq.conditions
                                      existing_mq.conditions
                                    else
                                      existing_mq.text
                                    end

              # Create combined MediaQuery
              combined_mq = MediaQuery.new(@_next_media_query_id, combined_type, combined_conditions)
              @media_queries << combined_mq
              rule.media_query_id = @_next_media_query_id
              @_next_media_query_id += 1
            else
              # Rule has no media query - just assign the import's media query
              rule.media_query_id = import_media_query_id
            end
          end
        end

        # Merge imported rules into this stylesheet
        # Insert at current position (before any remaining local rules)
        insert_position = import.id

        # Insert rules without modifying IDs (will renumber everything after all imports resolved)
        imported_sheet.rules.each_with_index do |rule, idx|
          @rules.insert(insert_position + idx, rule)
        end

        # Merge media index
        imported_sheet.instance_variable_get(:@media_index).each do |media_sym, rule_ids|
          if @media_index[media_sym]
            @media_index[media_sym].concat(rule_ids)
          else
            @media_index[media_sym] = rule_ids.dup
          end
        end

        # Merge selector_lists with offsetted IDs
        list_id_offset = @_next_selector_list_id
        imported_selector_lists = imported_sheet.instance_variable_get(:@_selector_lists)
        if imported_selector_lists && !imported_selector_lists.empty?
          imported_selector_lists.each do |list_id, rule_ids|
            new_list_id = list_id + list_id_offset
            @_selector_lists[new_list_id] = rule_ids.dup
          end
          @_next_selector_list_id = list_id_offset + imported_selector_lists.size
        end

        # Merge media_query_lists with offsetted IDs
        mq_list_id_offset = @_next_media_query_list_id
        imported_mq_lists = imported_sheet.instance_variable_get(:@_media_query_lists)
        if imported_mq_lists && !imported_mq_lists.empty?
          imported_mq_lists.each do |list_id, mq_ids|
            new_list_id = list_id + mq_list_id_offset
            @_media_query_lists[new_list_id] = mq_ids.dup
          end
          @_next_media_query_list_id = mq_list_id_offset + imported_mq_lists.size
        end

        # Merge charset (first one wins per CSS spec)
        @charset ||= imported_sheet.instance_variable_get(:@charset)

        # Mark as resolved
        import.resolved = true
      end

      # Renumber all rule IDs to be sequential in document order
      # This is O(n) and very fast (~1ms for 30k rules)
      # Only needed if we actually resolved imports
      return unless imports.length > 0

      # Single-pass renumbering: build old->new mapping while renumbering
      old_to_new_id = {}
      @rules.each_with_index do |rule, new_idx|
        if rule.is_a?(Rule) || rule.is_a?(ImportStatement)
          old_to_new_id[rule.id] = new_idx
          rule.id = new_idx
        end
      end

      # Update rule IDs in selector_lists (only if we have any)
      unless @_selector_lists.empty?
        @_selector_lists.each do |list_id, rule_ids|
          @_selector_lists[list_id] = rule_ids.map { |old_id| old_to_new_id[old_id] }
        end
      end

      # Update @_last_rule_id to reflect final count
      @_last_rule_id = @rules.length

      # Clear media_index so it gets rebuilt lazily when accessed
      @media_index = {}
    end

    # Check if a rule matches any of the requested media queries
    #
    # @param rule_id [Integer] Rule ID to check
    # @param query_media [Array<Symbol>] Media types to match
    # @return [Boolean] true if rule appears in any of the requested media index entries
    def rule_matches_media?(rule_id, query_media)
      query_media.any? { |m| media_index[m]&.include?(rule_id) }
    end

    # Check if a rule matches the specificity filter
    #
    # @param rule [Rule] Rule to check
    # @param specificity [Integer, Range] Specificity filter
    # @return [Boolean] true if rule matches specificity
    def rule_matches_specificity?(rule, specificity)
      # Skip rules with nil specificity (e.g., AtRule)
      return false if rule.specificity.nil?

      case specificity
      when Range
        specificity.cover?(rule.specificity)
      else
        specificity == rule.specificity
      end
    end

    # Clear memoized caches that can be lazily rebuilt.
    #
    # Call this method after any operation that modifies the stylesheet's rules
    # (e.g., add_block, remove_rules, merge). These caches will automatically
    # rebuild on next access.
    #
    # Clears:
    # - @selectors: Memoized list of all selectors
    # - @_custom_properties: Memoized custom properties organized by media context
    #
    # Should not add ivars here that don't rebuild themselves (i.e. @media_index)
    def clear_memoized_caches
      @selectors = nil
      @_custom_properties = nil
    end

    # Build custom properties hash organized by media context
    #
    # @return [Hash{Symbol => Hash{String => String}}] Media contexts mapped to custom properties
    def build_custom_properties
      props_by_media = {}

      # Build reverse lookup: rule_id => media_type
      rule_id_to_media = {}
      media_index.each do |media_type, rule_ids|
        rule_ids.each do |rule_id|
          rule_id_to_media[rule_id] = media_type
        end
      end

      # Collect custom properties from each rule
      @rules.each do |rule|
        next unless rule.selector? # Skip at-rules

        # Determine media context (:root for base-level rules)
        media_context = rule_id_to_media[rule.id] || :root

        # Collect custom properties from this rule
        rule.declarations.each do |decl|
          next unless decl.custom_property?

          props_by_media[media_context] ||= {}
          props_by_media[media_context][decl.property] = decl.value
        end
      end

      props_by_media
    end

    # Check if a rule has a declaration matching property and/or value
    #
    # @param rule [Rule] Rule to check (AtRule filtered out by each_selector)
    # @param property [String, nil] Property name to match
    # @param property_value [String, nil] Property value to match
    # @return [Boolean] true if rule has matching declaration
    def rule_matches_property?(rule, property, property_value)
      rule.declarations.any? do |decl|
        property_matches = property.nil? || decl.property == property
        value_matches = property_value.nil? || decl.value == property_value
        property_matches && value_matches
      end
    end
  end
end
