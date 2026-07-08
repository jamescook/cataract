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

    # @return [Array<ConditionalGroup>] Array of conditional-group objects (@supports/@layer/@container/@scope)
    attr_reader :conditional_groups

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

      # Which backend (Cataract::Backends::Native / ::Pure) produced this
      # stylesheet - defaults to whichever this process picked as active.
      # Not part of the public options contract (used internally by
      # Backends::Native.parse / Backends::Pure.parse), so it's popped off
      # before @options is built.
      @backend = options.delete(:backend) || Cataract::Backends.active

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
      @conditional_groups = [] # Array of ConditionalGroup objects (@supports/@layer/@container/@scope)
      @_next_conditional_group_id = 0 # Counter for ConditionalGroup IDs
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
      @backend = source.backend
      @options = source.options.dup
      @rules = source.rules.dup
      @media_queries = source.media_queries.dup
      @_next_media_query_id = source.next_media_query_id
      @media_index = source.media_index_cache.transform_values(&:dup)
      @imports = source.imports.dup
      @_selector_lists = source.selector_lists.transform_values(&:dup)
      @_next_selector_list_id = source.next_selector_list_id
      @_media_query_lists = source.media_query_lists.transform_values(&:dup)
      @_next_media_query_list_id = source.next_media_query_list_id
      @conditional_groups = source.conditional_groups.dup
      @_next_conditional_group_id = source.next_conditional_group_id
      @parser_options = source.parser_options.dup
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
    # @param options [Hash] Options passed to Stylesheet.new, and to load_file
    #   (e.g. dangerous_path_prefixes: [] to load a path load_file blocks by default)
    # @return [Stylesheet] A new Stylesheet containing the parsed CSS
    def self.load_file(filename, base_dir = '.', **options)
      sheet = new(options)
      sheet.load_file(filename, base_dir, options)
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
    #   - :screen, :print, etc. - Output base rules plus rules from the specified media query
    #   - [:screen, :print] - Output base rules plus rules from multiple media queries
    #
    # Important: When filtering to specific media types, base rules (rules not
    # inside any @media block) are always included, since they apply regardless
    # of media context. Only rules from OTHER @media queries are excluded.
    # @return [String] CSS string
    #
    # @example Get all CSS
    #   sheet.to_s                 # => "body { color: black; } @media print { .footer { color: red; } }"
    #   sheet.to_s(media: :all)    # => "body { color: black; } @media print { .footer { color: red; } }"
    #
    # @example Filter to specific media type (base rules still included)
    #   sheet.to_s(media: :print)  # => "body { color: black; } @media print { .footer { color: red; } }"
    #   # Note: base rules like "body { color: black; }" apply during print too, so they're kept
    #
    # @example Filter to multiple media types
    #   sheet.to_s(media: [:screen, :print])  # => "@media screen { ... } @media print { ... }"
    def to_s(media: :all)
      @backend.stylesheet_to_s(filter_rules_by_media(media), @charset, @_has_nesting || false, @_selector_lists, @media_queries, @_media_query_lists,
                               @conditional_groups)
    end
    alias to_css to_s

    # Serialize to formatted CSS string with indentation and newlines.
    #
    # Converts the stylesheet to a human-readable CSS string with proper indentation.
    # Rules are formatted with each declaration on its own line, and media queries
    # are properly indented. Optionally filters output to specific media queries.
    #
    # @param media [Symbol, Array<Symbol>] Optional media filter (default: :all)
    #   - :all - Output all rules including base rules and all media queries
    #   - :screen, :print, etc. - Output base rules plus rules from the specified media query
    #   - [:screen, :print] - Output base rules plus rules from multiple media queries
    #
    # @return [String] Formatted CSS string
    #
    # @example Get all CSS formatted
    #   sheet.to_formatted_s
    #   # => "body {\n  color: black;\n}\n@media print {\n  .footer {\n    color: red;\n  }\n}\n"
    #
    # @example Filter to specific media type (base rules still included)
    #   sheet.to_formatted_s(media: :print)
    #
    # @see #to_s For compact single-line output
    def to_formatted_s(media: :all)
      @backend.stylesheet_to_formatted_s(filter_rules_by_media(media), @charset, @_has_nesting || false, @_selector_lists, @media_queries, @_media_query_lists,
                                         @conditional_groups)
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
    # @param options [Hash] Passed through to load_uri (e.g. dangerous_path_prefixes: [])
    # @return [self] Returns self for method chaining
    def load_file(filename, base_dir = '.', options = {})
      # Normalize file path and convert to file:// URI
      file_path = File.expand_path(filename, base_dir)
      file_uri = "file://#{file_path}"

      # Delegate to load_uri which handles imports and base_path
      load_uri(file_uri, options)
    end

    # Load CSS from a URI and add to this stylesheet.
    #
    # @param uri [String] URI to load CSS from (http://, https://, or file://)
    # @param options [Hash] Additional options
    # @return [self] Returns self for method chaining
    def load_uri(uri, options = {})
      require 'uri'

      uri_obj = URI(uri)
      # Reuse the same validation and fetch collaborator @import resolution
      # uses (ImportResolver, via DefaultFetcher/open-uri) instead of a
      # second, separate Net::HTTP implementation with no validation at all -
      # that duplicate implementation also didn't follow redirects, unlike
      # this one. LOAD_DEFAULTS (rather than SAFE_DEFAULTS) reflects that the
      # caller chose this exact URI themselves, so http/any-extension are
      # allowed by default; dangerous_path_prefixes still applies unless the
      # caller overrides it (e.g. dangerous_path_prefixes: []).
      opts = ImportResolver.normalize_options(options, defaults: ImportResolver::LOAD_DEFAULTS)
      fetcher = opts[:fetcher] || @options[:import_fetcher] || ImportResolver::DefaultFetcher.new
      css_content = nil
      file_path = nil

      case uri_obj.scheme
      when 'http', 'https'
        ImportResolver.validate_url(uri, opts)
        css_content = fetcher.call(uri, opts)
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

        file_uri = "file://#{file_path}"
        ImportResolver.validate_url(file_uri, opts)
        css_content = fetcher.call(file_uri, opts)
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

      compact_media_queries!

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

      parse_options = build_parse_options(effective_base_uri, effective_absolute_paths)

      # Parse CSS first (this extracts @import statements into result[:imports])
      result = @backend.parse(css, parse_options)

      merge_parsed_block!(result, effective_base_uri, effective_base_dir)

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
    # and the same media queries and conditional groups. Rule equality uses
    # shorthand-aware comparison. Order matters because CSS cascade depends
    # on rule order.
    #
    # Charset is ignored since it's file encoding metadata, not semantic content.
    #
    # @param other [Object] Object to compare with
    # @return [Boolean] true if stylesheets are equal
    def ==(other)
      return false unless other.is_a?(Stylesheet)
      return false unless rules == other.rules
      return false unless @media_queries == other.media_queries
      return false unless @conditional_groups == other.conditional_groups

      true
    end
    alias eql? ==

    # Generate hash code for this stylesheet.
    #
    # Hash is based on rules, media_queries, and conditional_groups to match
    # equality semantics.
    #
    # @return [Integer] hash code
    def hash
      @_hash ||= [self.class, rules, @media_queries, @conditional_groups].hash # rubocop:disable Naming/MemoizedInstanceVariableName
    end

    # Flatten all rules in this stylesheet according to CSS cascade rules.
    #
    # Applies specificity and !important precedence rules to compute the final
    # set of declarations. Also recreates shorthand properties from longhand
    # properties where possible.
    #
    # @return [Stylesheet] New stylesheet with cascade applied
    def flatten
      result = @backend.flatten(self)
      result.backend = @backend
      result
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
      flattened = @backend.flatten(self)
      @rules = flattened.rules
      @media_index = flattened.media_index_cache
      @_has_nesting = flattened.has_nesting
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

      # Get the current offset for rule/media-query/selector-list IDs
      offset = @rules.length
      list_id_offset = merge_selector_lists!(other.selector_lists, rule_id_offset: offset)
      mq_id_offset = merge_media_queries!(other.media_queries)
      merge_media_query_lists!(other.media_query_lists, mq_id_offset: mq_id_offset)
      cg_id_offset = merge_conditional_groups!(other.conditional_groups)

      # Add rules with updated IDs and cross-references
      other.rules.each do |rule|
        new_rule = rule.dup
        rebase_rule!(new_rule, rule_id_offset: offset, list_id_offset: list_id_offset, mq_id_offset: mq_id_offset,
                               cg_id_offset: cg_id_offset)
        @rules << new_rule
      end

      merge_media_index!(other.media_index_cache, rule_id_offset: offset)

      # Update nesting flag if other has nesting
      @_has_nesting = true if other.has_nesting

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
        result.media_index_cache.each_value do |ids|
          ids.delete(idx)
          ids.map! { |id| id > idx ? id - 1 : id }
        end
      end

      # Re-index remaining rules
      result.rules.each_with_index { |rule, new_id| rule.id = new_id }

      # Clean up empty media_index entries
      result.media_index_cache.delete_if { |_media, ids| ids.empty? }

      result.send(:compact_media_queries!)

      # Clear memoized cache
      result.send(:clear_memoized_caches)
      result._hash = nil

      result
    end

    protected

    # Internal accessors for another Stylesheet instance's private state.
    # Protected (not public) so this stays reachable from sibling instances
    # within this class (dup/clone, concat, resolve_imports, -) without
    # becoming part of the public API - and not plain attr_readers, since
    # several ivar names would collide with unrelated public methods
    # (notably #media_index, which lazily rebuilds rather than exposing the
    # raw cache these need).

    attr_reader :options, :parser_options
    attr_accessor :backend

    def next_media_query_id
      @_next_media_query_id
    end

    def next_conditional_group_id
      @_next_conditional_group_id
    end

    def next_selector_list_id
      @_next_selector_list_id
    end

    def next_media_query_list_id
      @_next_media_query_list_id
    end

    # @return [Hash{Symbol => Array<Integer>}] the raw cached media index,
    #   without triggering the public #media_index reader's lazy rebuild
    def media_index_cache
      @media_index
    end

    def has_nesting
      @_has_nesting
    end

    def selector_lists
      @_selector_lists
    end

    def media_query_lists
      @_media_query_lists
    end

    attr_writer :_hash

    private

    # Offset and append MediaQuery objects into @media_queries, without
    # mutating the source objects (a caller may still hold its own
    # references to them, e.g. concat's `other`). Returns the id offset
    # applied, so callers can rebase any rule/import media_query_id that
    # pointed into the source collection.
    #
    # @param source_media_queries [Array<MediaQuery>, nil]
    # @return [Integer] id offset applied to each merged MediaQuery
    def merge_media_queries!(source_media_queries)
      mq_id_offset = @_next_media_query_id
      return mq_id_offset if source_media_queries.nil? || source_media_queries.empty?

      source_media_queries.each do |mq|
        new_mq = mq.dup
        new_mq.id += mq_id_offset
        @media_queries << new_mq
      end
      @_next_media_query_id += source_media_queries.size

      mq_id_offset
    end

    # Offset and append ConditionalGroup objects into @conditional_groups,
    # without mutating the source objects. Unlike merge_media_queries!,
    # each group's own parent_id (pointing at another ConditionalGroup, for
    # nesting) must also be rebased by the same offset.
    #
    # @param source_groups [Array<ConditionalGroup>, nil]
    # @return [Integer] id offset applied to each merged ConditionalGroup
    def merge_conditional_groups!(source_groups)
      cg_id_offset = @_next_conditional_group_id
      return cg_id_offset if source_groups.nil? || source_groups.empty?

      source_groups.each do |group|
        new_group = group.dup
        new_group.id += cg_id_offset
        new_group.parent_id += cg_id_offset if new_group.parent_id
        @conditional_groups << new_group
      end
      @_next_conditional_group_id += source_groups.size

      cg_id_offset
    end

    # Offset and merge a selector_lists hash (list_id => [rule_ids]) into
    # @_selector_lists. List ids are always rebased onto the next available
    # id; rule ids are rebased by rule_id_offset (0 when the caller defers
    # rule-id fixups to a later bulk renumber).
    #
    # @param source_lists [Hash{Integer => Array<Integer>}, nil]
    # @param rule_id_offset [Integer]
    # @return [Integer] id offset applied to the source's list ids
    def merge_selector_lists!(source_lists, rule_id_offset: 0)
      list_id_offset = @_next_selector_list_id
      return list_id_offset if source_lists.nil? || source_lists.empty?

      source_lists.each do |list_id, rule_ids|
        @_selector_lists[list_id + list_id_offset] = rule_ids.map { |id| id + rule_id_offset }
      end
      @_next_selector_list_id = list_id_offset + source_lists.size

      list_id_offset
    end

    # Same shape as merge_selector_lists!, for @_media_query_lists
    # (list_id => [media_query_ids]).
    #
    # @param source_lists [Hash{Integer => Array<Integer>}, nil]
    # @param mq_id_offset [Integer]
    # @return [Integer] id offset applied to the source's list ids
    def merge_media_query_lists!(source_lists, mq_id_offset: 0)
      list_id_offset = @_next_media_query_list_id
      return list_id_offset if source_lists.nil? || source_lists.empty?

      source_lists.each do |list_id, mq_ids|
        @_media_query_lists[list_id + list_id_offset] = mq_ids.map { |id| id + mq_id_offset }
      end
      @_next_media_query_list_id = list_id_offset + source_lists.size

      list_id_offset
    end

    # Merge a media_index hash (media_sym => [rule_ids]) into @media_index,
    # offsetting the rule ids.
    #
    # @param source_index [Hash{Symbol => Array<Integer>}, nil]
    # @param rule_id_offset [Integer]
    # @return [void]
    def merge_media_index!(source_index, rule_id_offset:)
      return if source_index.nil? || source_index.empty?

      source_index.each do |media_sym, rule_ids|
        offsetted_ids = rule_ids.map { |id| id + rule_id_offset }
        if @media_index[media_sym]
          @media_index[media_sym].concat(offsetted_ids)
        else
          @media_index[media_sym] = offsetted_ids
        end
      end
    end

    # Rebase a rule/at-rule's own id and its cross-references (Rule's
    # selector_list_id, and media_query_id/conditional_group_id on both Rule
    # and AtRule) by the given offsets, mutating it in place. Callers
    # merging from a live Stylesheet they don't own (e.g. concat) must dup
    # the rule first.
    #
    # @param rule [Rule, AtRule]
    # @param rule_id_offset [Integer]
    # @param list_id_offset [Integer]
    # @param mq_id_offset [Integer]
    # @param cg_id_offset [Integer]
    # @return [void]
    def rebase_rule!(rule, rule_id_offset:, list_id_offset: 0, mq_id_offset: 0, cg_id_offset: 0)
      rule.id += rule_id_offset
      rule.media_query_id += mq_id_offset if rule.media_query_id
      rule.conditional_group_id += cg_id_offset if rule.conditional_group_id
      return unless rule.is_a?(Rule)

      rule.selector_list_id += list_id_offset if rule.selector_list_id
    end

    # Build parser options for a block, enabling relative -> absolute URL
    # conversion when both absolute_paths and a base_uri are in effect.
    #
    # @return [Hash] Parser options
    def build_parse_options(effective_base_uri, effective_absolute_paths)
      parse_options = @parser_options.dup
      if effective_absolute_paths && effective_base_uri
        parse_options[:base_uri] = effective_base_uri
        parse_options[:absolute_paths] = true
        parse_options[:uri_resolver] = @options[:uri_resolver] || Cataract::DEFAULT_URI_RESOLVER
      end
      parse_options
    end

    # Merge a freshly parsed CSS block's result into this stylesheet's
    # rules, media queries, selector/media-query lists, and index, then
    # resolve any @import statements it contained.
    #
    # @param result [Hash] Return value of the backend's parse
    # @return [void]
    def merge_parsed_block!(result, effective_base_uri, effective_base_dir)
      offset = @_last_rule_id || 0

      list_id_offset = merge_selector_lists!(result[:_selector_lists], rule_id_offset: offset)
      mq_id_offset = merge_media_queries!(result[:media_queries])
      merge_media_query_lists!(result[:_media_query_lists], mq_id_offset: mq_id_offset)
      cg_id_offset = merge_conditional_groups!(result[:conditional_groups])

      new_rules = result[:rules]
      new_rules.each do |rule|
        rebase_rule!(rule, rule_id_offset: offset, list_id_offset: list_id_offset, mq_id_offset: mq_id_offset,
                           cg_id_offset: cg_id_offset)
        @rules << rule
      end
      @_last_rule_id = offset + new_rules.length

      merge_media_index!(result[:_media_index], rule_id_offset: offset)
      merge_block_imports!(result[:imports], offset, mq_id_offset, effective_base_uri, effective_base_dir)

      @charset ||= result[:charset]
      @_has_nesting = result[:_has_nesting]

      clear_memoized_caches
    end

    # Merge a freshly parsed block's @import statements into @imports (with
    # offsetted IDs), then kick off import resolution if enabled.
    #
    # @return [void]
    def merge_block_imports!(new_imports, offset, mq_id_offset, effective_base_uri, effective_base_dir)
      return unless new_imports

      new_imports.each do |import|
        import.id += offset
        import.media_query_id += mq_id_offset if import.media_query_id
        @imports << import
      end

      return unless @options[:import]

      if @options[:import].is_a?(Hash)
        imported_urls = @options[:import][:imported_urls] || []
        depth = @options[:import][:depth] || 0
      else
        imported_urls = []
        depth = 0
      end

      import_opts = @options[:import].is_a?(Hash) ? @options[:import].dup : {}
      import_opts[:base_uri] = effective_base_uri if effective_base_uri
      import_opts[:base_path] = effective_base_dir if effective_base_dir

      resolve_imports(new_imports, import_opts, imported_urls: imported_urls, depth: depth)
    end

    # Remove MediaQuery objects no longer referenced by any rule, renumbering
    # the ones that remain so mq.id keeps matching its position in
    # @media_queries. Lookups elsewhere (parser, serializer) treat
    # @media_queries[id] as positional, so simply compacting the array
    # without renumbering would desync mq.id from rule.media_query_id and
    # @_media_query_lists as soon as an earlier entry gets removed.
    #
    # Shared by #remove_rules! (via self) and #- (via result.send, since it
    # operates on a separate Stylesheet instance).
    #
    # @return [void]
    def compact_media_queries!
      # Rule and AtRule both define media_query_id directly (it's a member of
      # both structs), so every element of @rules responds to it - no need
      # for a respond_to?/is_a? guard here. filter_map keeps only rules that
      # actually have one set (i.e. are scoped to a media query).
      used_mq_ids = @rules.filter_map(&:media_query_id).to_set

      old_to_new_mq_id = {}
      kept_mqs = []
      @media_queries.each do |mq|
        next unless used_mq_ids.include?(mq.id)

        old_to_new_mq_id[mq.id] = kept_mqs.size
        mq.id = kept_mqs.size
        kept_mqs << mq
      end
      @media_queries = kept_mqs

      @rules.each do |rule|
        rule.media_query_id = old_to_new_mq_id[rule.media_query_id] if rule.media_query_id
      end

      @_media_query_lists.each_value { |mq_ids| mq_ids.map! { |mq_id| old_to_new_mq_id[mq_id] }.compact! }
      @_media_query_lists.delete_if { |_list_id, mq_ids| mq_ids.empty? }
    end

    # Filter rules down to those relevant for the given media type(s).
    #
    # Shared by #to_s and #to_formatted_s so both serialize the same rule set
    # for a given filter. Base rules (not inside any @media block) always
    # apply regardless of media context, so they're included alongside any
    # explicitly requested media types.
    #
    # @param media [Symbol, Array<Symbol>] Media type(s) to filter to
    # @return [Array<Rule>] Filtered rules, in original order
    def filter_rules_by_media(media)
      which_media_array = media.is_a?(Array) ? media : [media]
      return @rules if which_media_array.include?(:all)

      mi = media_index # Build media_index if needed

      # Base rules (not in any media query) apply to all media contexts.
      # Built as a Set so the membership check below is O(1) per rule instead
      # of the O(n) scan an Array#- would do, and to avoid materializing a
      # separate 0..N array of every rule id just to subtract from it.
      media_rule_id_set = Set.new
      mi.each_value { |ids| media_rule_id_set.merge(ids) }
      matching_rule_ids = (0...@rules.length).reject { |rule_id| media_rule_id_set.include?(rule_id) }

      # Include rules from requested media types
      which_media_array.each do |media_sym|
        matching_rule_ids.concat(mi[media_sym]) if mi[media_sym]
      end
      matching_rule_ids.uniq! # Dedupe: same rule can be in multiple media indexes

      matching_rule_ids.sort!.map! { |rule_id| @rules[rule_id] }
    end

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

        resolve_single_import!(import, opts, fetcher, imported_urls, depth)
      end

      # Renumber all rule IDs to be sequential in document order.
      # This is O(n) and very fast (~1ms for 30k rules). Only needed if we
      # actually resolved imports.
      renumber_after_import_resolution! if imports.length > 0
    end

    # Fetch, parse, and merge one @import statement's target stylesheet into
    # this one, inserted at the import's original document position.
    #
    # @return [void]
    def resolve_single_import!(import, opts, fetcher, imported_urls, depth)
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
        parser: @parser_options.dup, # Inherit parent's parser options (including selector_lists)
        backend: @backend # Imported stylesheets are produced by the same backend as their parent
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

      merge_imported_sheet!(imported_sheet, import)

      # Merge charset (first one wins per CSS spec)
      @charset ||= imported_sheet.charset

      # Mark as resolved
      import.resolved = true
    end

    # Merge an already-parsed imported stylesheet's media queries, rules,
    # and selector/media-query lists into this one. Rules are inserted at
    # the importing @import statement's original document position; rule
    # ids (and selector_lists' rule-id references) are left unoffset here
    # and fixed up in one bulk pass once all imports are resolved, since
    # positional insertion shifts everything after it anyway.
    #
    # @return [void]
    def merge_imported_sheet!(imported_sheet, import)
      mq_id_offset = merge_media_queries!(imported_sheet.media_queries)
      cg_id_offset = merge_conditional_groups!(imported_sheet.conditional_groups)
      rebase_imported_rules!(imported_sheet.rules, mq_id_offset, cg_id_offset, import.media_query_id)

      insert_position = import.id
      imported_sheet.rules.each_with_index do |rule, idx|
        @rules.insert(insert_position + idx, rule)
      end

      merge_selector_lists!(imported_sheet.selector_lists)
      merge_media_query_lists!(imported_sheet.media_query_lists, mq_id_offset: mq_id_offset)
    end

    # Rebase every imported rule/at-rule's media_query_id and
    # conditional_group_id onto this stylesheet's own @media_queries/
    # @conditional_groups (now that the imported sheet's own copies have
    # been merged in), then, if the @import statement itself had a media
    # qualifier, combine it with (or assign it to) each rule's media
    # context.
    #
    # @return [void]
    def rebase_imported_rules!(imported_rules, mq_id_offset, cg_id_offset, import_media_query_id)
      imported_rules.each { |rule| rebase_rule!(rule, rule_id_offset: 0, mq_id_offset: mq_id_offset, cg_id_offset: cg_id_offset) }

      return unless import_media_query_id

      import_mq = @media_queries[import_media_query_id]

      imported_rules.each do |rule|
        next unless rule.is_a?(Rule)

        if rule.media_query_id
          # Rule already has a media query - need to combine them
          # Example: @import "mobile.css" screen; where mobile.css has @media (max-width: 768px)
          # Result: screen and (max-width: 768px)
          existing_mq = @media_queries[rule.media_query_id]

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

    # After all imports for this call are resolved, renumber every rule
    # (including at-rules) and import statement placeholder to sequential
    # ids matching final document order, and propagate the same mapping to
    # selector_lists' rule-id references.
    #
    # @return [void]
    def renumber_after_import_resolution!
      # Single-pass renumbering: build old->new mapping while renumbering
      old_to_new_id = {}
      @rules.each_with_index do |rule, new_idx|
        old_to_new_id[rule.id] = new_idx
        rule.id = new_idx
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
  end
end
