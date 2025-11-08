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
  #   sheet.for_media(:print).first.selector #=> ".footer"
  #
  # @attr_reader [Array<Rule>] rules Array of parsed CSS rules
  # @attr_reader [String, nil] charset The @charset declaration if present
  class Stylesheet
    # @return [Array<Rule>] Array of parsed CSS rules
    attr_reader :rules

    # @return [String, nil] The @charset declaration if present
    attr_reader :charset

    # @private
    # Internal index mapping media query symbols to rule IDs
    # @return [Hash<Symbol, Array<Integer>>]
    attr_reader :media_index

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
      @media_index = {} # Hash: Symbol => Array of rule IDs
      @charset = nil
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

    # Query rules by media query symbol
    #
    # @param media_sym [Symbol] Media query symbol to filter by
    # @return [Array<Rule>] Matching rules
    def for_media(media_sym)
      rule_ids = @media_index[media_sym] || []
      rule_ids.map { |id| @rules[id] }
    end

    # Get all rules without media query (rules that apply to all media)
    #
    # @return [Array<Rule>] Rules with no media query
    def base_rules
      # Rules not in any media_index entry
      media_rule_ids = @media_index.values.flatten.uniq
      @rules.select.with_index { |_rule, idx| !media_rule_ids.include?(idx) }
    end

    # Get all unique media query symbols
    #
    # @return [Array<Symbol>] Array of unique media query symbols
    def media_queries
      @media_index.keys
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
    # @param which_media [Symbol, Array<Symbol>] Optional media filter (default: :all)
    #   - :all - Output all rules including base rules and all media queries
    #   - :screen, :print, etc. - Output only rules from specified media query
    #   - [:screen, :print] - Output rules from multiple media queries
    #
    # Important: When filtering to specific media types, base rules (rules not
    # inside any @media block) are NOT included. Only rules explicitly inside
    # the requested @media queries are output. Use :all to include base rules.
    #
    # @return [String] CSS string
    #
    # @example Get all CSS
    #   sheet.to_s        # => "body { color: black; } @media print { .footer { color: red; } }"
    #   sheet.to_s(:all)  # => "body { color: black; } @media print { .footer { color: red; } }"
    #
    # @example Filter to specific media type (excludes base rules)
    #   sheet.to_s(:print)  # => "@media print { .footer { color: red; } }"
    #   # Note: base rules like "body { color: black; }" are NOT included
    #
    # @example Filter to multiple media types
    #   sheet.to_s([:screen, :print])  # => "@media screen { ... } @media print { ... }"
    def to_s(which_media = :all)
      # Normalize to array for consistent filtering
      which_media_array = which_media.is_a?(Array) ? which_media : [which_media]

      # If :all is present, return everything (no filtering)
      if which_media_array.include?(:all)
        Cataract._stylesheet_to_s(@rules, @media_index, @charset)
      else

        # Collect all rule IDs that match the requested media types
        matching_rule_ids = Set.new
        which_media_array.each do |media_sym|
          if @media_index[media_sym]
            matching_rule_ids.merge(@media_index[media_sym])
          end
        end

        # Build filtered rules array (re-indexed from 0)
        filtered_rules = []
        old_to_new_id = {}
        matching_rule_ids.sort.each do |old_id|
          new_id = filtered_rules.length
          rule = @rules[old_id]
          filtered_rules << Cataract::Rule.new(new_id, rule.selector, rule.declarations, rule.specificity)
          old_to_new_id[old_id] = new_id
        end

        # Build filtered media_index with remapped IDs
        filtered_media_index = {}
        which_media_array.each do |media_sym|
          if @media_index[media_sym]
            filtered_media_index[media_sym] = @media_index[media_sym].filter_map { |old_id| old_to_new_id[old_id] }
          end
        end

        # C serialization with filtered data
        Cataract._stylesheet_to_s(filtered_rules, filtered_media_index, @charset)
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
    def to_formatted_s(which_media = :all)
      # Normalize to array for consistent filtering
      which_media_array = which_media.is_a?(Array) ? which_media : [which_media]

      # If :all is present, return everything (no filtering)
      if which_media_array.include?(:all)
        Cataract._stylesheet_to_formatted_s(@rules, @media_index, @charset)
      else
        # Collect all rule IDs that match the requested media types
        matching_rule_ids = Set.new
        which_media_array.each do |media_sym|
          if @media_index[media_sym]
            matching_rule_ids.merge(@media_index[media_sym])
          end
        end

        # Build filtered rules array (re-indexed from 0)
        filtered_rules = []
        old_to_new_id = {}
        matching_rule_ids.sort.each do |old_id|
          new_id = filtered_rules.length
          rule = @rules[old_id]
          filtered_rules << Cataract::Rule.new(new_id, rule.selector, rule.declarations, rule.specificity)
          old_to_new_id[old_id] = new_id
        end

        # Build filtered media_index with remapped IDs
        filtered_media_index = {}
        which_media_array.each do |media_sym|
          if @media_index[media_sym]
            filtered_media_index[media_sym] = @media_index[media_sym].filter_map { |old_id| old_to_new_id[old_id] }
          end
        end

        # C serialization with filtered data
        Cataract._stylesheet_to_formatted_s(filtered_rules, filtered_media_index, @charset)
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

    # Remove rules matching criteria
    #
    # @param selector [String, nil] Selector to match (nil matches all)
    # @param media_types [Symbol, Array<Symbol>, nil] Media types to filter by (nil matches all)
    # @return [self] Returns self for method chaining
    #
    # @example Remove all rules with a specific selector
    #   sheet.remove_rules!(selector: '.header')
    #
    # @example Remove rules from specific media type
    #   sheet.remove_rules!(selector: '.header', media_types: :screen)
    #
    # @example Remove all rules from a media type
    #   sheet.remove_rules!(media_types: :print)
    def remove_rules!(selector: nil, media_types: nil)
      # Normalize media_types to array
      filter_media = media_types ? Array(media_types).map(&:to_sym) : nil

      # Find rules to remove
      rules_to_remove = Set.new
      @rules.each_with_index do |rule, rule_id|
        # Check selector match
        next if selector && rule.selector != selector

        # Check media type match
        if filter_media
          rule_media_types = @media_index.select { |_media, ids| ids.include?(rule_id) }.keys
          # Extract individual media types from complex queries
          individual_types = rule_media_types.flat_map { |key| Cataract.parse_media_types(key) }.uniq

          # If rule is not in any media query (base rule), skip if filtering by media
          if individual_types.empty?
            next unless filter_media.include?(:all)
          else
            # Check if rule's media types intersect with filter
            next unless individual_types.intersect?(filter_media)
          end
        end

        rules_to_remove << rule_id
      end

      # Remove rules and update media_index
      rules_to_remove.sort.reverse_each do |rule_id|
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
    # TODO: Move to C?
    def add_block(css, fix_braces: false, media_types: nil)
      css += ' }' if fix_braces && !css.strip.end_with?('}')

      # Convenience wrapper: wrap in @media if media_types specified
      if media_types
        media_list = Array(media_types).join(', ')
        css = "@media #{media_list} { #{css} }"
      end

      # Resolve @import statements if configured in constructor
      css_to_parse = if @options[:import]
                       ImportResolver.resolve(css, @options[:import])
                     else
                       css
                     end

      # Get current rule ID offset
      offset = @_last_rule_id || 0

      # Parse CSS with C function (returns hash)
      result = Cataract._parse_css(css_to_parse)

      # Merge rules with offsetted IDs
      new_rules = result[:rules]
      new_rules.each do |rule|
        rule.id += offset
        @rules << rule
      end

      # Merge media_index with offsetted IDs
      result[:media_index].each do |media_sym, rule_ids|
        offsetted_ids = rule_ids.map { |id| id + offset }
        if @media_index[media_sym]
          @media_index[media_sym].concat(offsetted_ids)
        else
          @media_index[media_sym] = offsetted_ids
        end
      end

      # Update last rule ID
      @_last_rule_id = offset + new_rules.length

      # Set charset if not already set
      @charset ||= result[:charset]

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

    # Find rules by selector
    #
    # @param selector [String] Selector to search for
    # @param media [Symbol, Array<Symbol>] Optional media filter (default: :all)
    # @return [Array<Rule>] Array of matching rules
    def find_by_selector(selector, media: :all)
      # Normalize media to array
      media_array = media.is_a?(Array) ? media : [media]

      # Get rule IDs for the media query
      rule_ids = if media_array.include?(:all)
                   (0...@rules.length).to_a # All rule IDs
                 else
                   # Collect rule IDs from all requested media types
                   media_array.flat_map { |m| @media_index[m] || [] }.uniq
                 end

      # Filter by selector
      rule_ids.map { |id| @rules[id] }.select { |r| r.selector == selector }
    end
    alias [] find_by_selector

    # Iterate over each rule with optional filtering
    #
    # @param media [Symbol, Array<Symbol>] Filter by media query symbol(s) (default: :all for everything)
    # @param specificity [Integer, Range] Filter by specificity value or range
    # @param property [String] Filter by CSS property name
    # @param property_value [String] Filter by CSS property value
    # @yield [rule] Block to execute for each matching rule
    # @yieldparam rule [Rule] The matching rule object
    # @return [Enumerator, nil] Returns enumerator if no block given
    #
    # @example Iterate over all rules
    #   sheet.each_selector do |rule|
    #     puts "#{rule.selector} has #{rule.declarations.length} declarations"
    #   end
    #
    # @example Filter by media type
    #   sheet.each_selector(media: :print) do |rule|
    #     puts rule.selector
    #   end
    def each_selector(media: :all, specificity: nil, property: nil, property_value: nil)
      unless block_given?
        return enum_for(:each_selector, media: media, specificity: specificity,
                                        property: property, property_value: property_value)
      end

      # Normalize media to array once
      query_media = media.is_a?(Array) ? media : [media]
      check_media = !query_media.include?(:all)

      @rules.each_with_index do |rule, rule_id|
        # Skip at-rules (they're definitions, not selectors)
        next unless rule.supports_each_selector?

        # Apply filters
        next if check_media && !rule_matches_media?(rule_id, query_media)
        next if specificity && !rule_matches_specificity?(rule, specificity)
        next if (property || property_value) && !rule_matches_property?(rule, property, property_value)

        # Yield the rule object
        yield rule
      end
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

    # Merge all rules in this stylesheet according to CSS cascade rules
    #
    # Applies specificity and !important precedence rules to compute the final
    # set of declarations. Also recreates shorthand properties from longhand
    # properties where possible.
    #
    # @return [Stylesheet] New stylesheet with a single merged rule
    def merge
      # C function handles everything - returns new Stylesheet
      Cataract.merge(self)
    end

    private

    # Check if a rule matches any of the requested media queries
    #
    # @param rule_id [Integer] Rule ID to check
    # @param query_media [Array<Symbol>] Media types to match
    # @return [Boolean] true if rule appears in any of the requested media index entries
    def rule_matches_media?(rule_id, query_media)
      query_media.any? { |m| @media_index[m]&.include?(rule_id) }
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
