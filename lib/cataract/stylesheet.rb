# frozen_string_literal: true

module Cataract
  # Unified CSS stylesheet class - combines parsing, mutation, and querying
  # This merges the functionality of the old Parser and Stylesheet classes
  class Stylesheet
    attr_reader :charset

    # Create an empty stylesheet
    # Options:
    #   - import: false (default) or true/hash for @import resolution
    #   - io_exceptions: true (default) - raise exceptions on I/O errors
    def initialize(options = {})
      @options = {
        import: false,
        io_exceptions: true
      }.merge(options)

      # YJIT-friendly: define all instance variables upfront
      # @rule_groups is a hash: {media_query_string => {media_types: [...], rules: [...]}}
      @rule_groups = {}
      @charset = nil
    end

    # Class-level constructor: Parse CSS string
    #
    # @param css [String] CSS string to parse
    # @param options [Hash] Options (import:, io_exceptions:)
    # @return [NewStylesheet] Populated stylesheet
    #
    # @example
    #   sheet = NewStylesheet.parse("body { color: red; }")
    #   sheet = NewStylesheet.parse(css, imports: true)
    #
    def self.parse(css, **options)
      sheet = new(options)
      sheet.parse(css)
      sheet
    end

    # Class-level constructor: Load CSS from file
    #
    # @param filename [String] Path to CSS file
    # @param base_dir [String] Base directory for relative paths
    # @param options [Hash] Options (import:, io_exceptions:)
    # @return [NewStylesheet] Populated stylesheet
    #
    def self.load_file(filename, base_dir = '.', **options)
      sheet = new(options)
      sheet.load_file!(filename, base_dir)
      sheet
    end

    # Class-level constructor: Load CSS from URI
    #
    # @param uri [String] URI to load CSS from (http://, https://, file://)
    # @param options [Hash] Options (import:, io_exceptions:, base_uri:)
    # @return [NewStylesheet] Populated stylesheet
    #
    def self.load_uri(uri, **options)
      sheet = new(options)
      sheet.load_uri!(uri, options)
      sheet
    end

    # Parse CSS and merge into this stylesheet
    #
    # @param css_string [String] CSS to parse
    # @return [self] Returns self for chaining
    #
    def parse(css_string)
      # Resolve @import statements if configured in constructor
      css_to_parse = if @options[:import]
                       ImportResolver.resolve(css_string, @options[:import])
                     else
                       css_string
                     end

      result = Cataract.parse_css_internal(css_to_parse)
      # parse_css_internal returns {rules: {query_string => {media_types: [...], rules: [...]}}, charset: "..." | nil}

      # Store charset if not already set
      @charset ||= result[:charset]

      # Merge: if key exists, concatenate rules arrays; otherwise just add
      @rule_groups.merge!(result[:rules]) do |_key, old_group, new_group|
        # Merge rules arrays from both groups
        {
          media_types: old_group[:media_types], # Keep existing media types
          rules: old_group[:rules] + new_group[:rules]
        }
      end
      self
    end

    # Get declarations by selector.
    #
    # css_parser compatibility method. Uses each_selector internally.
    #
    # +media_types+ are optional, and can be a symbol or an array of symbols.
    # The default value is <tt>:all</tt>.
    #
    # ==== Examples
    #  find_by_selector('#content')
    #  => ['font-size: 13px', 'line-height: 1.2']
    #
    #  find_by_selector('#content', [:screen, :handheld])
    #  => ['font-size: 13px', 'line-height: 1.2']
    #
    #  find_by_selector('#content', :print)
    #  => ['font-size: 11pt', 'line-height: 1.2']
    #
    # Returns an array of declaration strings.
    def find_by_selector(selector, media_types = :all)
      matching_declarations = []

      each_selector(media: media_types) do |sel, declarations, _specificity, _media|
        matching_declarations << declarations if sel == selector
      end

      matching_declarations
    end
    alias [] find_by_selector

    # Iterate over each selector across all rules
    # Yields: selector, declarations_string, specificity, media_types
    #
    # @param media [Symbol, Array<Symbol>] Media type(s) to filter by (default: :all)
    # @param specificity [Integer, Range] Filter by specificity (exact value or range)
    # @param property [String] Filter by CSS property name (e.g., 'color', 'position')
    # @param property_value [String] Filter by CSS property value (e.g., 'relative', 'red')
    # @yield [selector, declarations_string, specificity, media_types]
    # @return [Enumerator] if no block given
    #
    # Examples:
    #   sheet.each_selector { |sel, decls, spec, media| ... }  # All selectors
    #   sheet.each_selector(media: :print) { |sel, decls, spec, media| ... }  # Only print media
    #   sheet.each_selector(specificity: 10) { |sel, decls, spec, media| ... }  # Exact specificity
    #   sheet.each_selector(specificity: 100..) { |sel, decls, spec, media| ... }  # High specificity (>= 100)
    #   sheet.each_selector(property: 'color') { |sel, decls, spec, media| ... }  # Any selector with 'color'
    #   sheet.each_selector(property_value: 'relative') { |sel, decls, spec, media| ... }  # Any property with value 'relative'
    #   sheet.each_selector(property: 'position', property_value: 'relative') { |sel, decls, spec, media| ... }  # Specific property-value
    #   sheet.each_selector(property: 'color', specificity: 100.., media: :print) { |sel, decls, spec, media| ... }  # Combined filters
    def each_selector(media: :all, specificity: nil, property: nil, property_value: nil)
      unless block_given?
        return enum_for(:each_selector, media: media, specificity: specificity, property: property,
                                        property_value: property_value)
      end

      query_media_types = Array(media).map(&:to_sym)

      @rule_groups.each_value do |group|
        # Filter by media types at group level
        group_media_types = group[:media_types] || []

        # :all matches everything
        # But specific media queries (like :screen, :print) should NOT match [:all] groups
        should_include = if query_media_types.include?(:all)
                           # :all means iterate everything
                           true
                         elsif group_media_types.include?(:all)
                           # Group is universal (no media query) - only include if querying for :all
                           false
                         else
                           # Check for intersection
                           group_media_types.intersect?(query_media_types)
                         end

        next unless should_include

        group[:rules].each do |rule|
          # Filter by specificity if provided
          if specificity
            rule_specificity = rule.specificity
            matches = case specificity
                      when Range
                        specificity.cover?(rule_specificity)
                      else
                        specificity == rule_specificity
                      end
            next unless matches
          end

          # Filter by property and/or property_value if provided
          if property || property_value
            has_match = false

            rule.declarations.each do |decl|
              # Check property name match (if specified)
              property_matches = property.nil? || decl.property == property

              # Check property value match (if specified)
              # Compare against raw value (without !important flag)
              value_matches = property_value.nil? || decl.value == property_value

              # If both filters specified, both must match
              # If only one specified, just that one must match
              if property_matches && value_matches
                has_match = true
                break
              end
            end

            next unless has_match
          end

          # Convert declarations to string using C function for performance
          declarations_str = Cataract.declarations_to_s(rule.declarations)

          # Return the group's media_types, not from the rule
          yield rule.selector, declarations_str, rule.specificity, group[:media_types]
        end
      end
    end

    # Add a block of CSS with optional auto-fixing
    #
    # Options:
    #   - fix_braces: Auto-close missing braces (default: false)
    #   - media_types: Force all rules to have specific media types (default: nil - use parsed media types)
    #
    # @return [self] Returns self for chaining
    #
    def add_block!(css_string, fix_braces: false, media_types: nil)
      css_to_parse = css_string

      if fix_braces
        # Count braces - if unbalanced, add missing closing braces
        open_braces = css_string.count('{')
        close_braces = css_string.count('}')
        css_to_parse = css_string + (' }' * (open_braces - close_braces)) if open_braces > close_braces
      end

      # Track rules count before parsing to identify newly added rules
      rules_before = @rule_groups.dup

      parse(css_to_parse)

      # Override media types if specified
      if media_types
        # Normalize media_types to array
        override_media_types = Array(media_types).map(&:to_sym)

        # Determine new media key for the overridden rules
        new_media_key = if override_media_types == [:all] || override_media_types.empty?
                          nil
                        else
                          override_media_types.map(&:to_s).join(', ')
                        end

        # Collect all rules that were added during this parse call
        new_rules = []
        @rule_groups.each do |query_string, group|
          # Skip groups that existed before
          if rules_before.key?(query_string)
            # Only take rules that weren't in the group before
            old_count = rules_before[query_string][:rules].length
            new_count = group[:rules].length
            if new_count > old_count
              new_rules.concat(group[:rules][old_count..])
              # Remove the newly added rules from their original group
              group[:rules] = group[:rules][0...old_count]
            end
          else
            # Entire group is new - take all its rules
            new_rules.concat(group[:rules])
            # Clear the group
            group[:rules].clear
          end
        end

        # Remove empty groups
        @rule_groups.delete_if { |_key, group| group[:rules].empty? }

        # Add all new rules to the override media type group
        unless new_rules.empty?
          @rule_groups[new_media_key] ||= { media_types: override_media_types, rules: [] }
          @rule_groups[new_media_key][:rules].concat(new_rules)
        end
      end

      self
    end

    alias load_string! add_block!

    def declarations
      # Flatten all rules for cascade
      all_rules = []
      @rule_groups.each_value { |group| all_rules.concat(group[:rules]) }
      @declarations ||= Cataract.apply_cascade(all_rules)
    end

    def add_rule!(selector:, declarations:, media_types: [:all])
      # Convert declarations to Declarations object if needed
      decls = declarations.is_a?(Declarations) ? declarations : Declarations.new(declarations)

      # Create Rule struct (no media_query field - stored at group level)
      rule = Cataract::Rule.new(
        selector.to_s,
        decls.to_a,
        nil # specificity calculated on demand
      )

      # Normalize media_types to array
      media_types_array = Array(media_types).map(&:to_sym)

      # Determine media query string key
      # For now, map media_types to simple strings
      # TODO: This is a simplified approach - may need enhancement
      media_key = if media_types_array == [:all] || media_types_array.empty?
                    nil # No media query
                  else
                    media_types_array.map(&:to_s).join(', ')
                  end

      # Get or create group
      @rule_groups[media_key] ||= { media_types: media_types_array, rules: [] }
      @rule_groups[media_key][:rules] << rule

      # Return RuleSet wrapper for user-facing API (css_parser compatibility)
      RuleSet.new(
        selector: rule.selector,
        declarations: Declarations.new(rule.declarations),
        media_types: media_types_array
      )
    end

    def rules(&block)
      return enum_for(:rules) unless block_given?

      # Iterate over all rules in all media query groups
      @rule_groups.each_value do |group|
        group[:rules].each(&block)
      end
    end

    def add_rule_set!(rule_set)
      # Convert RuleSet to Rule struct
      rule = Cataract::Rule.new(
        rule_set.selector,
        rule_set.declarations.to_a,
        rule_set.specificity
      )

      # Determine media query key
      media_key = if rule_set.media_types == [:all] || rule_set.media_types.empty?
                    nil
                  else
                    rule_set.media_types.map(&:to_s).join(', ')
                  end

      # Get or create group
      @rule_groups[media_key] ||= { media_types: Array(rule_set.media_types).map(&:to_sym), rules: [] }
      @rule_groups[media_key][:rules] << rule
      self
    end

    def remove_rule_set!(rule_set)
      # Iterate through each media query group
      @rule_groups.each_value do |group|
        group[:rules].reject! do |rule|
          rule.selector == rule_set.selector &&
            rule.declarations == rule_set.declarations.to_a
        end
      end
      # Clean up empty groups
      @rule_groups.delete_if { |_key, group| group[:rules].empty? }
      self
    end

    # Remove rules matching criteria
    def remove_rules!(selector: nil, media_types: nil)
      # Normalize media_types filter
      filter_media_types = (Array(media_types).map(&:to_sym) if media_types)

      @rule_groups.each_value do |group|
        # Skip groups that don't match media_types filter
        if filter_media_types
          group_media_types = group[:media_types] || []
          # Check if this group matches the filter
          next unless filter_media_types.include?(:all) ||
                      group_media_types.intersect?(filter_media_types)
        end

        # Remove matching rules from this group
        group[:rules].reject! do |rule|
          match = true
          match &&= (rule.selector == selector) if selector
          match
        end
      end

      # Clean up empty groups
      @rule_groups.delete_if { |_key, group| group[:rules].empty? }
      self
    end

    # Load CSS from a URI (http://, https://, or file://)
    #
    # Options:
    #   - base_uri: Base URI for resolving relative imports
    #   - media_types: Array of media types (e.g., [:screen, :print])
    #
    # @return [self] Returns self for chaining
    #
    def load_uri!(uri, options = {})
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
        if @options[:import] && @options[:import][:base_path].nil?
          file_dir = File.dirname(file_path)
          @options[:import] = @options[:import].merge(base_path: file_dir)
        end

        css_content = File.read(file_path)
      else
        raise ArgumentError, "Unsupported URI scheme: #{uri_obj.scheme}"
      end

      parse(css_content)
      self
    rescue Errno::ENOENT
      raise IOError, "File not found: #{uri}" if @options[:io_exceptions]

      self
    rescue StandardError => e
      raise IOError, "Error loading URI: #{uri} - #{e.message}" if @options[:io_exceptions]

      self
    end

    # Load CSS from a local file
    #
    # Arguments:
    #   - filename: Path to CSS file
    #   - base_dir: Base directory for resolving relative paths (default: current directory)
    #   - media_types: Media type symbol or array (not yet implemented for filtering)
    #
    # @return [self] Returns self for chaining
    #
    def load_file!(filename, base_dir = '.', _media_types = :all)
      # Normalize file path and convert to file:// URI
      file_path = File.expand_path(filename, base_dir)
      file_uri = "file://#{file_path}"

      # Delegate to load_uri! which handles imports and base_path
      load_uri!(file_uri)
    end

    # Convert to nested hash structure
    # Returns: { 'media_type' => { 'selector' => { 'property' => 'value' } } }
    def to_h
      result = {}

      @rule_groups.each_value do |group|
        group_media_types = group[:media_types] || [:all]

        group_media_types.each do |media_type|
          media_key = media_type.to_s
          result[media_key] ||= {}

          group[:rules].each do |rule|
            result[media_key][rule.selector] ||= {}

            # Iterate declarations array directly - no intermediate object
            rule.declarations.each do |decl|
              result[media_key][rule.selector][decl.property] =
                decl.important ? "#{decl.value} !important" : decl.value
            end
          end
        end
      end

      result
    end

    def size
      @rule_groups.values.sum { |group| group[:rules].length }
    end
    alias length size
    alias rules_count size

    def empty?
      @rule_groups.empty? || @rule_groups.values.all? { |group| group[:rules].empty? }
    end

    def clear!
      @rule_groups = {}
      @charset = nil
      self
    end

    # Get array of all selectors, optionally filtered by media type
    def selectors(media_types = :all)
      query_media_types = Array(media_types).map(&:to_sym)
      result = []

      @rule_groups.each_value do |group|
        # Filter by media types at group level
        group_media_types = group[:media_types] || []

        # :all matches everything
        next unless query_media_types.include?(:all) ||
                    (group_media_types.empty? && query_media_types.include?(:all)) ||
                    group_media_types.intersect?(query_media_types)

        result.concat(group[:rules].map(&:selector))
      end

      result
    end

    # Iterate through RuleSet objects.
    #
    # +media_types+ can be a symbol or an array of symbols.
    # Yields each rule set along with its media types.
    def each_rule_set(media_types = :all) # :yields: rule_set, media_types
      return enum_for(:each_rule_set, media_types) unless block_given?

      query_media_types = Array(media_types).map(&:to_sym)

      @rule_groups.each_value do |group|
        # Filter by media types at group level
        group_media_types = group[:media_types] || []

        # :all matches everything
        next unless query_media_types.include?(:all) ||
                    (group_media_types.empty? && query_media_types.include?(:all)) ||
                    group_media_types.intersect?(query_media_types)

        group[:rules].each do |rule|
          # Wrap Rule struct in RuleSet for user-facing API
          rule_set = RuleSet.new(
            selector: rule.selector,
            declarations: Declarations.new(rule.declarations),
            media_types: group_media_types,
            specificity: rule.specificity
          )
          yield rule_set, group_media_types
        end
      end
    end

    # Finds the rule sets that match the given selectors.
    #
    # +selectors+ is an array of selector strings.
    # +media_types+ can be a symbol or an array of symbols.
    #
    # Returns an array of RuleSet objects that match any of the given selectors.
    def find_rule_sets(selectors, media_types = :all)
      rule_sets = []
      # Normalize selectors for comparison
      normalized_selectors = Array(selectors).map { |s| s.gsub(/\s+/, ' ').strip }

      each_rule_set(media_types) do |rule_set, _media_types|
        # Normalize the rule set's selector for comparison
        normalized_rule_selector = rule_set.selector.gsub(/\s+/, ' ').strip
        if normalized_selectors.include?(normalized_rule_selector) && !rule_sets.include?(rule_set)
          rule_sets << rule_set
        end
      end

      rule_sets
    end

    # Expand shorthand properties in a declarations string
    # Returns a hash of longhand properties
    #
    # Example:
    #   Stylesheet.expand_shorthand("margin: 10px; margin-top: 20px;")
    #   => {"margin-top" => "20px", "margin-right" => "10px", "margin-bottom" => "10px", "margin-left" => "10px"}
    def self.expand_shorthand(declarations_string)
      # Parse the declarations string directly using C function
      raw_declarations = Cataract.parse_declarations(declarations_string)
      return {} if raw_declarations.empty?

      declarations = Declarations.new(raw_declarations)
      result = {}

      # Process declarations in order
      # For shorthands, expand them; for longhands, keep as-is
      # Later declarations override earlier ones (CSS cascade)
      declarations.each do |property, value, is_important|
        suffix = is_important ? ' !important' : ''
        full_value = "#{value}#{suffix}"

        # Map shorthand properties to their expansion methods
        expanded = case property
                   when 'margin'
                     Cataract.expand_margin(value)
                   when 'padding'
                     Cataract.expand_padding(value)
                   when 'border'
                     Cataract.expand_border(value)
                   when 'border-top'
                     Cataract.expand_border_side('top', value)
                   when 'border-right'
                     Cataract.expand_border_side('right', value)
                   when 'border-bottom'
                     Cataract.expand_border_side('bottom', value)
                   when 'border-left'
                     Cataract.expand_border_side('left', value)
                   when 'border-color'
                     Cataract.expand_border_color(value)
                   when 'border-style'
                     Cataract.expand_border_style(value)
                   when 'border-width'
                     Cataract.expand_border_width(value)
                   when 'font'
                     Cataract.expand_font(value)
                   when 'list-style'
                     Cataract.expand_list_style(value)
                   when 'background'
                     Cataract.expand_background(value)
                   end

        if expanded
          # This was a shorthand - merge all expanded properties
          expanded.each do |exp_prop, exp_value|
            exp_suffix = is_important ? ' !important' : ''
            result[exp_prop] = "#{exp_value}#{exp_suffix}"
          end
        else
          # This was a longhand - set it directly (overriding any previous value)
          result[property] = full_value
        end
      end

      result
    end

    def expand_shorthand(declarations_string)
      self.class.expand_shorthand(declarations_string)
    end

    # Compact format
    #
    # @param which_media [Symbol, Array<Symbol>] Media type filter (:all, :screen, :print, etc.)
    #   When :all (default), outputs ALL rules regardless of media type
    #   Can be an array to match multiple media types
    # @return [String] CSS stylesheet as a string
    def to_s(which_media = :all)
      serialize_with_media_filter(which_media, formatted: false)
    end

    # Multi-line format with 2-space indentation
    #
    # @param which_media [Symbol, Array<Symbol>] Media type filter (:all, :screen, :print, etc.)
    #   Can be an array to match multiple media types
    # @return [String] CSS stylesheet as a formatted string
    def to_formatted_s(which_media = :all)
      serialize_with_media_filter(which_media, formatted: true)
    end

    alias to_css to_s

    def inspect
      total_rules = size
      if total_rules.zero?
        '#<Cataract::Stylesheet empty>'
      else
        # Get first 3 rules across all groups
        preview_rules = []
        @rule_groups.each_value do |group|
          preview_rules.concat(group[:rules])
          break if preview_rules.length >= 3
        end
        preview = preview_rules.first(3).map(&:selector).join(', ')
        more = total_rules > 3 ? ', ...' : ''
        resolved_info = @resolved ? ", #{@resolved.length} declarations resolved" : ''
        "#<Cataract::Stylesheet #{total_rules} rules: #{preview}#{more}#{resolved_info}>"
      end
    end

    private

    # Helper to serialize stylesheet with optional media filtering
    #
    # @param which_media [Symbol, Array<Symbol>] Media type filter
    # @param formatted [Boolean] Whether to use formatted output
    # @return [String] Serialized CSS
    def serialize_with_media_filter(which_media, formatted:)
      if which_media == :all
        return formatted ? Cataract.stylesheet_to_formatted_s_c(@rule_groups, @charset) : Cataract.stylesheet_to_s_c(@rule_groups, @charset)
      end

      # Normalize to array for consistent filtering
      which_media_array = which_media.is_a?(Array) ? which_media : [which_media]

      # Filter rules by media type
      filtered_groups = {}
      @rule_groups.each do |media_query_string, group|
        media_types = group[:media_types]
        # Include if any of the requested media types match
        if media_types.intersect?(which_media_array)
          filtered_groups[media_query_string] = group
        end
      end

      formatted ? Cataract.stylesheet_to_formatted_s_c(filtered_groups, @charset) : Cataract.stylesheet_to_s_c(filtered_groups, @charset)
    end
  end
end
