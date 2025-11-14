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
    #   - :base_path [String] Base directory for relative imports
    # @option options [Boolean] :io_exceptions (true) Whether to raise exceptions
    #   on I/O errors (file not found, network errors, etc.)
    def initialize(options = {})
      @options = {
        import: false,
        io_exceptions: true
      }.merge(options)

      @rules = [] # Flat array of Rule structs
      @_media_index = {} # Hash: Symbol => Array of rule IDs
      @charset = nil
      @imports = [] # Array of ImportStatement objects
      @_has_nesting = nil # Set by parser (nil or boolean)
      @_last_rule_id = nil # Tracks next rule ID for add_block
      @selectors = nil # Memoized cache of selectors
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
      @imports = source.instance_variable_get(:@imports).dup
      @_media_index = source.instance_variable_get(:@_media_index).transform_values(&:dup)
      @selectors = nil # Clear memoized cache
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
    # @return [StylesheetScope] Scope with property filter applied
    #
    # @example Find all rules with color property
    #   sheet.with_property('color').map(&:selector)
    #
    # @example Find rules with position: absolute
    #   sheet.with_property('position', 'absolute').to_a
    #
    # @example Chain with media filter
    #   sheet.with_media(:screen).with_property('z-index').to_a
    def with_property(property, value = nil)
      StylesheetScope.new(self, property: property, property_value: value)
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
      media_rule_ids = @_media_index.values.flatten.uniq
      @rules.select.with_index { |_rule, idx| !media_rule_ids.include?(idx) }
    end

    # Get all unique media query symbols
    #
    # @return [Array<Symbol>] Array of unique media query symbols
    def media_queries
      @_media_index.keys
    end

    # Get all selectors
    #
    # @return [Array<String>] Array of all selectors
    def selectors
      @selectors ||= @rules.map(&:selector)
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
        Cataract._stylesheet_to_s(@rules, @_media_index, @charset, @_has_nesting || false)
      else
        # Collect all rule IDs that match the requested media types
        matching_rule_ids = []
        which_media_array.each do |media_sym|
          if @_media_index[media_sym]
            matching_rule_ids.concat(@_media_index[media_sym])
          end
        end
        matching_rule_ids.uniq! # Dedupe: same rule can be in multiple media indexes

        # Build filtered rules array (keep original IDs, no recreation needed)
        filtered_rules = matching_rule_ids.sort.map! { |rule_id| @rules[rule_id] }

        # Build filtered media_index (keep original IDs, just filter to included rules)
        filtered_media_index = {}
        which_media_array.each do |media_sym|
          if @_media_index[media_sym]
            filtered_media_index[media_sym] = @_media_index[media_sym] & matching_rule_ids
          end
        end

        # C serialization with filtered data
        # Note: Filtered rules might still contain nesting, so pass the flag
        Cataract._stylesheet_to_s(filtered_rules, filtered_media_index, @charset, @_has_nesting || false)
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
        Cataract._stylesheet_to_formatted_s(@rules, @_media_index, @charset, @_has_nesting || false)
      else
        # Collect all rule IDs that match the requested media types
        matching_rule_ids = []

        # Include rules not in any media query (they apply to all media)
        media_rule_ids = @_media_index.values.flatten.uniq
        all_rule_ids = (0...@rules.length).to_a
        non_media_rule_ids = all_rule_ids - media_rule_ids
        matching_rule_ids.concat(non_media_rule_ids)

        # Include rules from requested media types
        which_media_array.each do |media_sym|
          if @_media_index[media_sym]
            matching_rule_ids.concat(@_media_index[media_sym])
          end
        end
        matching_rule_ids.uniq! # Dedupe: same rule can be in multiple media indexes

        # Build filtered rules array (keep original IDs, no recreation needed)
        filtered_rules = matching_rule_ids.sort.map! { |rule_id| @rules[rule_id] }

        # Build filtered media_index (keep original IDs, just filter to included rules)
        filtered_media_index = {}
        which_media_array.each do |media_sym|
          if @_media_index[media_sym]
            filtered_media_index[media_sym] = @_media_index[media_sym] & matching_rule_ids
          end
        end

        # C serialization with filtered data
        # Note: Filtered rules might still contain nesting, so pass the flag
        Cataract._stylesheet_to_formatted_s(filtered_rules, filtered_media_index, @charset, @_has_nesting || false)
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
      @_media_index.clear
      @charset = nil
      @selectors = nil # Clear memoized cache
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
          rule_media_types = @_media_index.select { |_media, ids| ids.include?(rule_id) }.keys
          # Extract individual media types from complex queries
          individual_types = rule_media_types.flat_map { |key| Cataract.parse_media_types(key) }.uniq

          # If rule is not in any media query (base rule), skip unless :all is specified
          if individual_types.empty?
            next unless filter_media.include?(:all)
          else
            # Check if rule's media types intersect with filter
            next unless individual_types.intersect?(filter_media)
          end
        end

        rule_ids_to_remove << rule_id
      end

      # Remove rules and update media_index (sort in reverse to maintain indices during deletion)
      rule_ids_to_remove.sort.reverse_each do |rule_id|
        @rules.delete_at(rule_id)

        # Remove from media_index and update IDs for rules after this one
        @_media_index.each_value do |ids|
          ids.delete(rule_id)
          # Decrement IDs greater than removed ID
          ids.map! { |id| id > rule_id ? id - 1 : id }
        end
      end

      # Clean up empty media_index entries
      @_media_index.delete_if { |_media, ids| ids.empty? }

      # Update rule IDs in remaining rules
      @rules.each_with_index { |rule, new_id| rule.id = new_id }

      # Clear memoized cache
      @selectors = nil

      self
    end

    # Add CSS block to stylesheet
    #
    # @param css [String] CSS string to add
    # @param fix_braces [Boolean] Automatically close missing braces
    # @param media_types [Symbol, Array<Symbol>] Optional media query to wrap CSS in
    # @return [self] Returns self for method chaining
    def add_block(css, fix_braces: false, media_types: nil)
      css += ' }' if fix_braces && !css.strip.end_with?('}')

      # Convenience wrapper: wrap in @media if media_types specified
      if media_types
        media_list = Array(media_types).join(', ')
        css = "@media #{media_list} { #{css} }"
      end

      # Get current rule ID offset
      offset = @_last_rule_id || 0

      # Parse CSS first (this extracts @import statements into result[:imports])
      result = Cataract._parse_css(css)

      # Merge rules with offsetted IDs
      new_rules = result[:rules]
      new_rules.each do |rule|
        rule.id += offset
        @rules << rule
      end

      # Merge media_index with offsetted IDs
      result[:_media_index].each do |media_sym, rule_ids|
        offsetted_ids = rule_ids.map { |id| id + offset }
        if @_media_index[media_sym]
          @_media_index[media_sym].concat(offsetted_ids)
        else
          @_media_index[media_sym] = offsetted_ids
        end
      end

      # Update last rule ID
      @_last_rule_id = offset + new_rules.length

      # Merge imports with offsetted IDs
      if result[:imports]
        new_imports = result[:imports]
        new_imports.each do |import|
          import.id += offset
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
          resolve_imports(new_imports, @options[:import], imported_urls: imported_urls, depth: depth)
        end
      end

      # Set charset if not already set
      @charset ||= result[:charset]

      # Track if we have any nesting (for serialization optimization)
      @_has_nesting = result[:_has_nesting]

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
      return false unless @_media_index == other.instance_variable_get(:@_media_index)

      true
    end
    alias eql? ==

    # Generate hash code for this stylesheet.
    #
    # Hash is based on rules and media_index to match equality semantics.
    #
    # @return [Integer] hash code
    def hash
      @_hash ||= [self.class, rules, @_media_index].hash # rubocop:disable Naming/MemoizedInstanceVariableName
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
      @_media_index = flattened.instance_variable_get(:@_media_index)
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
      other.instance_variable_get(:@_media_index).each do |media_sym, rule_ids|
        offsetted_ids = rule_ids.map { |id| id + offset }
        if @_media_index[media_sym]
          @_media_index[media_sym].concat(offsetted_ids)
        else
          @_media_index[media_sym] = offsetted_ids
        end
      end

      # Update nesting flag if other has nesting
      other_has_nesting = other.instance_variable_get(:@_has_nesting)
      @_has_nesting = true if other_has_nesting

      # Clear memoized cache
      @selectors = nil

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
        result.instance_variable_get(:@_media_index).each_value do |ids|
          ids.delete(idx)
          ids.map! { |id| id > idx ? id - 1 : id }
        end
      end

      # Re-index remaining rules
      result.rules.each_with_index { |rule, new_id| rule.id = new_id }

      # Clean up empty media_index entries
      result.instance_variable_get(:@_media_index).delete_if { |_media, ids| ids.empty? }

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
        media = import.media

        # Validate URL
        ImportResolver.validate_url(url, opts)

        # Check for circular references
        raise ImportError, "Circular import detected: #{url}" if imported_urls.include?(url)

        # Fetch imported CSS
        imported_css = fetcher.call(url, opts)

        # Parse imported CSS recursively
        imported_urls_copy = imported_urls.dup
        imported_urls_copy << url
        imported_sheet = Stylesheet.parse(imported_css, import: opts.merge(imported_urls: imported_urls_copy, depth: depth + 1))

        # Wrap rules in @media if import had media query
        if media
          imported_sheet.rules.each do |rule|
            # Find rule's current media (if any) from imported sheet's media index
            # A rule may be in multiple media entries (e.g., :screen and :"screen and (min-width: 768px)")
            # We want the most specific one (longest string)
            # TODO: Extract this logic to a helper method to keep it consistent across codebase
            rule_media = nil
            imported_sheet.instance_variable_get(:@_media_index).each do |m, ids|
              # Keep the longest/most specific media query
              if ids.include?(rule.id) && (rule_media.nil? || m.to_s.length > rule_media.to_s.length)
                rule_media = m
              end
            end

            # Combine media queries: "import_media and rule_media"
            combined_media = if rule_media
                               # Combine: "media and rule_media"
                               :"#{media} and #{rule_media}"
                             else
                               media
                             end

            # Update media index
            if @_media_index[combined_media]
              @_media_index[combined_media] << rule.id
            else
              @_media_index[combined_media] = [rule.id]
            end
          end
        end

        # Merge imported rules into this stylesheet
        # Insert at current position (before any remaining local rules)
        insert_position = import.id
        imported_sheet.rules.each_with_index do |rule, idx|
          @rules.insert(insert_position + idx, rule)
        end

        # Merge media index
        imported_sheet.instance_variable_get(:@_media_index).each do |media_sym, rule_ids|
          if @_media_index[media_sym]
            @_media_index[media_sym].concat(rule_ids)
          else
            @_media_index[media_sym] = rule_ids.dup
          end
        end

        # Merge charset (first one wins per CSS spec)
        @charset ||= imported_sheet.instance_variable_get(:@charset)

        # Mark as resolved
        import.resolved = true
      end
    end

    # Check if a rule matches any of the requested media queries
    #
    # @param rule_id [Integer] Rule ID to check
    # @param query_media [Array<Symbol>] Media types to match
    # @return [Boolean] true if rule appears in any of the requested media index entries
    def rule_matches_media?(rule_id, query_media)
      query_media.any? { |m| @_media_index[m]&.include?(rule_id) }
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
