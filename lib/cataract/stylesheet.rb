# frozen_string_literal: true

module Cataract
  # Represents a parsed CSS stylesheet with support for querying, mutation, and serialization.
  #
  # A Stylesheet contains CSS rules organized by media queries. It provides methods for:
  # - Parsing CSS from strings, files, or URIs
  # - Querying rules by selector, specificity, or property
  # - Adding and removing rules
  # - Serializing back to CSS strings
  #
  # Stylesheets are mutable - you can parse multiple CSS sources into the same stylesheet
  # and they will be merged together.
  #
  # @example Basic usage
  #   # Parse from string
  #   sheet = Stylesheet.parse("body { color: red; }")
  #
  #   # Query rules
  #   sheet.each_selector { |sel, decls, spec, media| puts "#{sel}: #{decls}" }
  #
  #   # Add more rules
  #   sheet.add_block("h1 { color: blue; }")
  #
  #   # Serialize back to CSS
  #   puts sheet.to_s
  #
  # @see Cataract.parse_css Convenience method for parsing
  # @see RuleSet Individual CSS rule representation
  class Stylesheet
    # @return [String, nil] The @charset declaration from the CSS, if present
    attr_reader :charset

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
    #
    # @example Create empty stylesheet
    #   sheet = Stylesheet.new
    #   sheet.parse("body { color: red; }")
    #
    # @example With import resolution
    #   sheet = Stylesheet.new(import: true)
    #   sheet.parse("@import 'style.css';")
    #
    # @example With custom import options
    #   sheet = Stylesheet.new(import: {
    #     allowed_schemes: ['https', 'file'],
    #     base_path: '/path/to/css'
    #   })
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

    # Parse a CSS string and return a new Stylesheet.
    #
    # This is a convenience class method that creates a new Stylesheet
    # and parses the CSS in one step.
    #
    # @param css [String] The CSS string to parse
    # @param options [Hash] Options passed to Stylesheet.new
    # @option options [Boolean, Hash] :import (false) Enable @import resolution
    # @option options [Boolean] :io_exceptions (true) Raise exceptions on I/O errors
    # @return [Stylesheet] A new Stylesheet containing the parsed CSS
    # @raise [IOError] If import resolution fails and io_exceptions is enabled
    #
    # @example Parse simple CSS
    #   sheet = Stylesheet.parse("body { color: red; }")
    #   sheet.size #=> 1
    #
    # @example Parse with imports
    #   sheet = Stylesheet.parse("@import 'style.css';", import: true)
    #
    # @see #parse Instance method for parsing into existing stylesheet
    def self.parse(css, **options)
      sheet = new(options)
      sheet.parse(css)
      sheet
    end

    # Load CSS from a file and return a new Stylesheet.
    #
    # Reads the file and parses its contents. If import resolution is enabled,
    # the file's directory is used as the base path for resolving relative imports.
    #
    # @param filename [String] Path to the CSS file
    # @param base_dir [String] Base directory for resolving the filename (default: '.')
    # @param options [Hash] Options passed to Stylesheet.new
    # @option options [Boolean, Hash] :import (false) Enable @import resolution
    # @option options [Boolean] :io_exceptions (true) Raise exceptions on I/O errors
    # @return [Stylesheet] A new Stylesheet containing the parsed CSS
    # @raise [IOError] If the file doesn't exist and io_exceptions is enabled
    #
    # @example Load a CSS file
    #   sheet = Stylesheet.load_file('style.css')
    #
    # @example Load with relative base directory
    #   sheet = Stylesheet.load_file('components/button.css', 'assets/css')
    #
    # @see #load_file Instance method for loading into existing stylesheet
    def self.load_file(filename, base_dir = '.', **options)
      sheet = new(options)
      sheet.load_file(filename, base_dir)
      sheet
    end

    # Load CSS from a URI and return a new Stylesheet.
    #
    # Supports http://, https://, and file:// URIs. Network requests use
    # open-uri with a 10 second timeout and follow redirects.
    #
    # @param uri [String] URI to load CSS from (http://, https://, or file://)
    # @param options [Hash] Options passed to Stylesheet.new
    # @option options [Boolean, Hash] :import (false) Enable @import resolution
    # @option options [Boolean] :io_exceptions (true) Raise exceptions on I/O errors
    # @return [Stylesheet] A new Stylesheet containing the parsed CSS
    # @raise [IOError] If the URI can't be loaded and io_exceptions is enabled
    # @raise [ArgumentError] If the URI scheme is not supported
    #
    # @example Load from HTTPS
    #   sheet = Stylesheet.load_uri('https://example.com/style.css')
    #
    # @example Load local file
    #   sheet = Stylesheet.load_uri('file:///path/to/style.css')
    #
    # @see #load_uri Instance method for loading into existing stylesheet
    def self.load_uri(uri, **options)
      sheet = new(options)
      sheet.load_uri(uri, options)
      sheet
    end

    # Parse CSS and merge into this stylesheet.
    #
    # Parses the CSS string and adds all rules to this stylesheet. If @import
    # resolution is enabled (via constructor options), imports will be resolved
    # before parsing.
    #
    # This method can be called multiple times to parse and accumulate CSS from
    # multiple sources into the same stylesheet.
    #
    # @param css_string [String] The CSS string to parse
    # @return [self] Returns self for method chaining
    # @raise [IOError] If import resolution fails and io_exceptions is enabled
    #
    # @example Parse CSS into existing stylesheet
    #   sheet = Stylesheet.new
    #   sheet.parse("body { color: red; }")
    #   sheet.parse("h1 { color: blue; }")
    #   sheet.size #=> 2
    #
    # @example Method chaining
    #   sheet = Stylesheet.new.parse("body { color: red; }").parse("h1 { color: blue; }")
    #
    # @see .parse Class method that creates a new stylesheet
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

    # Find all declaration blocks for a specific selector.
    #
    # Searches the stylesheet for rules matching the exact selector and returns
    # an array of Declarations objects. Useful for finding what styles apply to
    # a specific selector.
    #
    # @param selector [String] The CSS selector to search for (must match exactly)
    # @param media_types [Symbol, Array<Symbol>] Media type(s) to filter by (default: :all)
    #   Use :all to search all media queries, or specify :screen, :print, etc.
    # @return [Array<Declarations>] Array of Declarations objects
    #   Returns empty array if selector not found.
    #
    # @example Find styles for an ID selector
    #   decls = sheet.find_by_selector('#content').first
    #   decls['font-size']  #=> "13px"
    #   decls.to_s          #=> "font-size: 13px; line-height: 1.2;"
    #
    # @example Find styles in specific media types
    #   decls = sheet.find_by_selector('#content', [:screen, :handheld])
    #
    # @example Check if property exists
    #   decls = sheet.find_by_selector('body').first
    #   decls.key?('color')  #=> true
    #
    # @example Using array access syntax (alias)
    #   sheet['#content']  #=> [#<Declarations...>]
    #
    # @see #each_selector For more advanced filtering options
    def find_by_selector(selector, media_types = :all)
      matching_declarations = []

      each_selector(media: media_types) do |sel, declarations, _specificity, _media|
        matching_declarations << declarations if sel == selector
      end

      matching_declarations
    end
    alias [] find_by_selector

    # Iterate over each selector in the stylesheet with optional filtering.
    #
    # This is the primary method for querying CSS rules. It yields each selector
    # along with its declarations, specificity, and media types. Supports powerful
    # filtering by media type, specificity, property name, and property value.
    #
    # @param media [Symbol, Array<Symbol>] Media type(s) to filter by (default: :all)
    #   Use :all for all media types, or filter by :screen, :print, etc.
    # @param specificity [Integer, Range] Filter by specificity value
    #   Pass an integer for exact match, or a Range like 100.. for minimum specificity
    # @param property [String] Filter by CSS property name (e.g., 'color', 'position')
    #   Only yields selectors that have this property
    # @param property_value [String] Filter by CSS property value (e.g., 'relative', 'red')
    #   Only yields selectors that have this value (for any property)
    # @yield [selector, declarations, specificity, media_types] Yields for each matching rule
    # @yieldparam selector [String] The CSS selector (e.g., "body", ".class", "#id")
    # @yieldparam declarations [Declarations] Declarations object with all CSS properties
    # @yieldparam specificity [Integer] Specificity value (higher = more specific)
    # @yieldparam media_types [Array<Symbol>] Media types for this rule (e.g., [:screen, :print])
    # @return [Enumerator] If no block given, returns an Enumerator
    #
    # @example Iterate all selectors
    #   sheet.each_selector do |sel, decls, spec, media|
    #     puts "#{sel}: #{decls['color']}"
    #   end
    #
    # @example Access declaration properties
    #   sheet.each_selector do |sel, decls, spec, media|
    #     puts decls['color']        # Get value
    #     puts decls.key?('margin')  # Check existence
    #     puts decls.important?('color')  # Check !important
    #   end
    #
    # @example Filter by media type
    #   sheet.each_selector(media: :print) { |sel, decls, spec, media| ... }
    #
    # @example Filter by exact specificity
    #   sheet.each_selector(specificity: 10) { |sel, decls, spec, media| ... }
    #
    # @example Filter by minimum specificity (using Range)
    #   sheet.each_selector(specificity: 100..) { |sel, decls, spec, media| ... }
    #
    # @example Find selectors with a specific property
    #   sheet.each_selector(property: 'color') { |sel, decls, spec, media| ... }
    #
    # @example Find selectors with a specific value
    #   sheet.each_selector(property_value: 'relative') { |sel, decls, spec, media| ... }
    #
    # @example Iterate over declaration properties
    #   sheet.each_selector do |sel, decls, spec, media|
    #     decls.each { |prop, val, important| puts "#{prop}: #{val}" }
    #   end
    #
    # @example Combine filters
    #   sheet.each_selector(property: 'position', property_value: 'relative') { |sel, decls, spec, media| ... }
    #
    # @example Complex filter with multiple criteria
    #   sheet.each_selector(property: 'color', specificity: 100.., media: :print) { |sel, decls, spec, media| ... }
    #
    # @example Use as Enumerator
    #   selectors = sheet.each_selector(media: :print).to_a
    #
    # @see #find_by_selector For simpler selector lookup
    # @see Declarations For the declarations object API
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

          # Wrap declarations in Declarations object for user-facing API
          declarations_obj = Declarations.new(rule.declarations)

          # Return the group's media_types, not from the rule
          yield rule.selector, declarations_obj, rule.specificity, group[:media_types]
        end
      end
    end

    # Parse and add a CSS block to this stylesheet.
    #
    # This method parses a CSS string and adds all rules to the stylesheet.
    # Optionally auto-fixes malformed CSS and overrides media types.
    #
    # @param css_string [String] The CSS string to parse and add
    # @param fix_braces [Boolean] Auto-close missing closing braces (default: false)
    #   If true, automatically adds closing braces for unbalanced CSS blocks
    # @param media_types [Symbol, Array<Symbol>] Override media types for all added rules (default: nil)
    #   When nil, uses media types from CSS (e.g., @media queries)
    #   When specified, forces all rules to use these media types instead
    # @return [self] Returns self for method chaining
    #
    # @example Add CSS block
    #   sheet = Stylesheet.new
    #   sheet.add_block("body { color: red; }")
    #   sheet.add_block("h1 { color: blue; }")
    #
    # @example Fix malformed CSS
    #   sheet.add_block("body { color: red;", fix_braces: true)
    #   # Automatically closes the missing brace
    #
    # @example Override media types
    #   sheet.add_block("body { color: red; }", media_types: :print)
    #   # Rule is added as print media, even if CSS had no @media query
    #
    # @example Force all rules to specific media
    #   css = "@media screen { body { color: red; } }"
    #   sheet.add_block(css, media_types: :print)
    #   # Ignores @media screen, adds as print media instead
    #
    # @see #parse For parsing without auto-fixing
    # @see #load_string Alias for this method
    def add_block(css_string, fix_braces: false, media_types: nil)
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

    alias load_string add_block

    # Get all declarations from the stylesheet after applying CSS cascade rules.
    #
    # This method flattens all rules from all media queries and applies CSS
    # cascade rules (specificity, importance, order) to compute the final
    # declarations. The result is cached until the stylesheet is modified.
    #
    # @return [Array<Declarations::Value>] Array of declaration values after cascade
    #   Returns empty array if stylesheet is empty.
    #
    # @example Get all declarations
    #   sheet = Stylesheet.parse("body { color: red; } body { margin: 10px; }")
    #   decls = sheet.declarations
    #   # Returns declarations merged by cascade rules
    #
    # @example Declarations respect specificity
    #   sheet = Stylesheet.parse(".test { color: red; } #test { color: blue; }")
    #   decls = sheet.declarations
    #   # Blue color wins due to higher specificity
    #
    # @see Cataract.merge For direct access to merge functionality
    def declarations
      # Flatten all rules for cascade
      all_rules = []
      @rule_groups.each_value { |group| all_rules.concat(group[:rules]) }
      @declarations ||= Cataract.apply_cascade(all_rules)
    end

    # Add a single CSS rule to the stylesheet.
    #
    # This method creates and adds a rule with the specified selector and declarations.
    # Unlike add_block, this operates on structured data rather than parsing CSS strings.
    #
    # @param selector [String] The CSS selector (e.g., "body", ".class", "#id")
    # @param declarations [String, Declarations, Hash] The CSS declarations
    #   Can be a declaration string ("color: red; margin: 10px"),
    #   a Declarations object, or a Hash ({ "color" => "red" })
    # @param media_types [Symbol, Array<Symbol>] Media types for this rule (default: [:all])
    #   Use :all for no media query, or specify :screen, :print, etc.
    # @return [RuleSet] The created RuleSet object
    #
    # @example Add rule with string declarations
    #   sheet.add_rule(selector: "body", declarations: "color: red; margin: 10px")
    #
    # @example Add rule with hash declarations
    #   sheet.add_rule(selector: ".button", declarations: { "color" => "blue", "padding" => "10px" })
    #
    # @example Add rule with specific media types
    #   sheet.add_rule(selector: "body", declarations: "font-size: 12pt", media_types: :print)
    #
    # @example Add rule with multiple media types
    #   sheet.add_rule(selector: ".mobile", declarations: "width: 100%", media_types: [:screen, :handheld])
    #
    # @see #add_block For parsing CSS strings
    # @see #add_rule_set! For adding RuleSet objects
    def add_rule(selector:, declarations:, media_types: [:all])
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

    # Add a RuleSet object to the stylesheet.
    #
    # This method takes an existing RuleSet object (typically from another stylesheet
    # or created manually) and adds it to this stylesheet. The RuleSet's selector,
    # declarations, and media types are preserved.
    #
    # @param rule_set [RuleSet] The RuleSet object to add
    # @return [self] Returns self for method chaining
    #
    # @example Add RuleSet from another stylesheet
    #   sheet1 = Stylesheet.parse("body { color: red; }")
    #   sheet2 = Stylesheet.new
    #   sheet1.each_rule_set { |rs, _media| sheet2.add_rule_set!(rs) }
    #
    # @example Copy rules between stylesheets
    #   source = Stylesheet.parse("h1 { color: blue; } p { margin: 10px; }")
    #   target = Stylesheet.new
    #   source.each_rule_set { |rs| target.add_rule_set!(rs) }
    #
    # @see #add_rule For adding rules from raw data
    # @see #each_rule_set For iterating RuleSets
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

    # Remove a specific RuleSet from the stylesheet.
    #
    # Removes rules that match both the selector and declarations of the given
    # RuleSet. The comparison is exact - both selector and all declarations must match.
    #
    # @param rule_set [RuleSet] The RuleSet to remove
    # @return [self] Returns self for method chaining
    #
    # @example Remove a specific rule
    #   sheet = Stylesheet.parse("body { color: red; } h1 { color: blue; }")
    #   sheet.each_rule_set do |rs, _media|
    #     sheet.remove_rule_set!(rs) if rs.selector == "body"
    #   end
    #
    # @see #remove_rules! For removing by criteria (more flexible)
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

    # Remove rules matching the given criteria.
    #
    # This is a flexible method for removing rules based on selector and/or media types.
    # If multiple criteria are specified, rules must match ALL of them to be removed.
    #
    # @param selector [String, nil] Selector to match (exact match required)
    #   If nil, selector is not used as a filter
    # @param media_types [Symbol, Array<Symbol>, nil] Media type(s) to filter by
    #   If nil, all media types are searched
    #   Use :all to match rules with no media query
    # @return [self] Returns self for method chaining
    #
    # @example Remove all rules for a selector
    #   sheet.remove_rules!(selector: "body")
    #
    # @example Remove all print rules
    #   sheet.remove_rules!(media_types: :print)
    #
    # @example Remove specific selector in specific media
    #   sheet.remove_rules!(selector: "#header", media_types: :screen)
    #
    # @example Remove rules across multiple media types
    #   sheet.remove_rules!(selector: ".mobile-only", media_types: [:screen, :handheld])
    #
    # @see #remove_rule_set! For removing specific RuleSet objects
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

    # Load CSS from a URI and add to this stylesheet.
    #
    # Supports http://, https://, and file:// URIs. Network requests follow
    # redirects and have a timeout. If the stylesheet was created with import
    # resolution enabled, the URI's directory will be used as the base path.
    #
    # @param uri [String] URI to load CSS from (http://, https://, or file://)
    # @param options [Hash] Additional options
    # @option options [String] :base_uri Base URI for resolving relative imports (deprecated)
    # @option options [Symbol, Array<Symbol>] :media_types Media types (not currently implemented)
    # @return [self] Returns self for method chaining
    # @raise [IOError] If the URI can't be loaded and io_exceptions is enabled
    # @raise [ArgumentError] If the URI scheme is not supported
    #
    # @example Load from HTTPS
    #   sheet = Stylesheet.new
    #   sheet.load_uri('https://example.com/style.css')
    #
    # @example Load local file via file:// URI
    #   sheet.load_uri('file:///path/to/style.css')
    #
    # @example Load multiple URIs
    #   sheet.load_uri('https://example.com/base.css')
    #   sheet.load_uri('https://example.com/theme.css')
    #
    # @see .load_uri Class method that creates a new stylesheet
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

    # Load CSS from a local file and add to this stylesheet.
    #
    # Reads the file and parses its contents. If import resolution is enabled
    # (via constructor options), the file's directory is used as the base path
    # for resolving relative @import statements.
    #
    # @param filename [String] Path to the CSS file
    # @param base_dir [String] Base directory for resolving the filename (default: '.')
    #   The filename is resolved relative to this directory
    # @param _media_types [Symbol, Array<Symbol>] Media types (not currently implemented, reserved for future use)
    # @return [self] Returns self for method chaining
    # @raise [IOError] If the file doesn't exist and io_exceptions is enabled
    #
    # @example Load a CSS file
    #   sheet = Stylesheet.new
    #   sheet.load_file('style.css')
    #
    # @example Load with relative base directory
    #   sheet.load_file('components/button.css', 'assets/css')
    #   # Loads from assets/css/components/button.css
    #
    # @example Load multiple files
    #   sheet.load_file('base.css')
    #   sheet.load_file('theme.css')
    #   sheet.load_file('responsive.css')
    #
    # @see .load_file Class method that creates a new stylesheet
    def load_file(filename, base_dir = '.', _media_types = :all)
      # Normalize file path and convert to file:// URI
      file_path = File.expand_path(filename, base_dir)
      file_uri = "file://#{file_path}"

      # Delegate to load_uri which handles imports and base_path
      load_uri(file_uri)
    end

    # Convert stylesheet to nested hash structure.
    #
    # Returns a hash organized by media type, then selector, then property.
    # This is useful for inspecting the stylesheet structure or converting
    # to JSON for serialization.
    #
    # @return [Hash] Nested hash: { 'media_type' => { 'selector' => { 'property' => 'value' } } }
    #   Media types become top-level keys (as strings)
    #   Selectors become second-level keys
    #   Properties become third-level keys with their values
    #   Important declarations include ' !important' suffix
    #
    # @example Convert to hash
    #   sheet = Stylesheet.parse("body { color: red; } @media print { body { color: black; } }")
    #   sheet.to_h
    #   #=> {
    #   #     "all" => { "body" => { "color" => "red" } },
    #   #     "print" => { "body" => { "color" => "black" } }
    #   #   }
    #
    # @example Convert to JSON
    #   require 'json'
    #   sheet.to_h.to_json
    #
    # @see #to_s For CSS string serialization
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

    # Get the total number of rules in the stylesheet.
    #
    # Counts all rules across all media query groups.
    #
    # @return [Integer] The total number of rules
    #
    # @example Count rules
    #   sheet = Stylesheet.parse("body { color: red; } h1 { color: blue; }")
    #   sheet.size #=> 2
    #
    # @example Empty stylesheet
    #   Stylesheet.new.size #=> 0
    #
    # @see #empty? For checking if stylesheet has no rules
    # @see #length Alias for this method
    # @see #rules_count Alias for this method
    def size
      @rule_groups.values.sum { |group| group[:rules].length }
    end
    alias length size
    alias rules_count size

    # Check if the stylesheet has no rules.
    #
    # @return [Boolean] true if stylesheet has no rules, false otherwise
    #
    # @example Check if empty
    #   Stylesheet.new.empty? #=> true
    #   Stylesheet.parse("body { color: red; }").empty? #=> false
    #
    # @see #size For getting the number of rules
    def empty?
      @rule_groups.empty? || @rule_groups.values.all? { |group| group[:rules].empty? }
    end

    # Remove all rules from the stylesheet.
    #
    # Clears all rules and resets the @charset. The stylesheet can be reused
    # by parsing new CSS after calling this method.
    #
    # @return [self] Returns self for method chaining
    #
    # @example Clear stylesheet
    #   sheet = Stylesheet.parse("body { color: red; }")
    #   sheet.size #=> 1
    #   sheet.clear!
    #   sheet.size #=> 0
    #
    # @example Reuse after clearing
    #   sheet.clear!.parse("h1 { color: blue; }")
    #
    # @see #empty? For checking if empty
    def clear!
      @rule_groups = {}
      @charset = nil
      self
    end

    # Get array of all selectors, optionally filtered by media type.
    #
    # Returns a flat array of all selectors in the stylesheet. Unlike each_selector,
    # this does not return declarations or other metadata - just the selector strings.
    #
    # @param media_types [Symbol, Array<Symbol>] Media type(s) to filter by (default: :all)
    #   Use :all for all media types, or specify :screen, :print, etc.
    # @return [Array<String>] Array of selector strings
    #
    # @example Get all selectors
    #   sheet = Stylesheet.parse("body { color: red; } h1 { color: blue; }")
    #   sheet.selectors #=> ["body", "h1"]
    #
    # @example Get selectors for specific media
    #   sheet.selectors(:print) #=> ["body", "h1", ".print-only"]
    #
    # @example Get selectors for multiple media types
    #   sheet.selectors([:screen, :handheld]) #=> [".mobile", ".desktop"]
    #
    # @see #each_selector For iterating with full rule information
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

    # Iterate through RuleSet objects with optional media type filtering.
    #
    # This method yields RuleSet objects, which wrap the raw Rule structs with
    # a user-friendly API. Each RuleSet provides access to the selector,
    # declarations, specificity, and media types.
    #
    # @param media_types [Symbol, Array<Symbol>] Media type(s) to filter by (default: :all)
    #   Use :all for all media types, or specify :screen, :print, etc.
    # @yield [rule_set, media_types] Yields each RuleSet with its media types
    # @yieldparam rule_set [RuleSet] The RuleSet object
    # @yieldparam media_types [Array<Symbol>] Media types for this rule
    # @return [Enumerator] If no block given, returns an Enumerator
    #
    # @example Iterate all rule sets
    #   sheet.each_rule_set { |rs, media| puts "#{rs.selector} (#{media.join(', ')})" }
    #
    # @example Filter by media type
    #   sheet.each_rule_set(:print) { |rs, media| puts rs.to_s }
    #
    # @example Copy rules to another stylesheet
    #   source.each_rule_set { |rs| target.add_rule_set!(rs) }
    #
    # @example Use as Enumerator
    #   rule_sets = sheet.each_rule_set.to_a
    #
    # @see #each_selector For simpler iteration (yields strings instead of objects)
    # @see RuleSet For the RuleSet API
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

    # Find RuleSets matching any of the given selectors.
    #
    # Searches the stylesheet for rules with selectors that match any of the
    # provided selectors. Selectors are normalized (whitespace is collapsed)
    # before comparison.
    #
    # @param selectors [String, Array<String>] Selector(s) to search for
    #   Can be a single selector string or an array of selectors
    # @param media_types [Symbol, Array<Symbol>] Media type(s) to filter by (default: :all)
    # @return [Array<RuleSet>] Array of matching RuleSet objects (no duplicates)
    #
    # @example Find rules for a selector
    #   sheet.find_rule_sets("body")
    #   #=> [#<RuleSet selector="body" ...>]
    #
    # @example Find rules for multiple selectors
    #   sheet.find_rule_sets(["body", "h1", "p"])
    #   #=> [#<RuleSet ...>, #<RuleSet ...>, ...]
    #
    # @example Filter by media type
    #   sheet.find_rule_sets(["body", "h1"], :print)
    #
    # @see #find_by_selector For finding declaration strings
    # @see #each_rule_set For iterating all RuleSets
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

    # Serialize stylesheet to compact CSS string.
    #
    # Converts the stylesheet back to CSS format. All rules are on single lines
    # with minimal whitespace. Media queries are preserved. Optionally filter
    # by media type to export only specific media rules.
    #
    # @param which_media [Symbol, Array<Symbol>] Media type filter (default: :all)
    #   When :all, outputs ALL rules regardless of media type
    #   When specified, only outputs rules for matching media types
    #   Can be an array to match multiple media types
    # @return [String] CSS stylesheet as a compact string
    #
    # @example Serialize entire stylesheet
    #   sheet.to_s
    #   #=> "body{color:red;}h1{color:blue;}"
    #
    # @example Serialize only print styles
    #   sheet.to_s(:print)
    #   #=> "@media print{body{font-size:12pt;}}"
    #
    # @example Serialize multiple media types
    #   sheet.to_s([:screen, :handheld])
    #
    # @see #to_formatted_s For human-readable formatted output
    # @see #to_css Alias for this method
    def to_s(which_media = :all)
      serialize_with_media_filter(which_media, formatted: false)
    end

    # Serialize stylesheet to formatted CSS string with indentation.
    #
    # Converts the stylesheet to CSS format with human-readable formatting:
    # - Each rule on its own line
    # - Declarations indented with 2 spaces
    # - Media queries properly formatted
    # - Consistent spacing and line breaks
    #
    # @param which_media [Symbol, Array<Symbol>] Media type filter (default: :all)
    #   When :all, outputs ALL rules regardless of media type
    #   When specified, only outputs rules for matching media types
    #   Can be an array to match multiple media types
    # @return [String] CSS stylesheet as a formatted string
    #
    # @example Serialize with formatting
    #   sheet.to_formatted_s
    #   #=> "body {\n  color: red;\n}\n\nh1 {\n  color: blue;\n}\n"
    #
    # @example Format only print styles
    #   sheet.to_formatted_s(:print)
    #
    # @example Format multiple media types
    #   sheet.to_formatted_s([:screen, :handheld])
    #
    # @see #to_s For compact output without formatting
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

    # Expose rule groups for C merge implementation
    # @api private
    attr_reader :rule_groups

    private

    # Helper to serialize stylesheet with optional media filtering
    #
    # @param which_media [Symbol, Array<Symbol>] Media type filter
    # @param formatted [Boolean] Whether to use formatted output
    # @return [String] Serialized CSS
    def serialize_with_media_filter(which_media, formatted:)
      if which_media == :all
        return Cataract._stylesheet_to_formatted_s_c(@rule_groups, @charset) if formatted

        return Cataract._stylesheet_to_s_c(@rule_groups, @charset)
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

      if formatted
        Cataract._stylesheet_to_formatted_s_c(filtered_groups,
                                              @charset)
      else
        Cataract._stylesheet_to_s_c(filtered_groups, @charset)
      end
    end
  end
end
