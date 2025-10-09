module Cataract
  class Parser
    def initialize(options = {})
      @options = {
        import: false,
        io_exceptions: true
      }.merge(options)

      # YJIT-friendly: define all instance variables upfront
      @raw_rules = []
      @css_source = nil
    end

    def parse(css_string)
      new_rules = Cataract.parse_css(css_string)
      # Append new rules to existing ones
      @raw_rules.concat(new_rules)
      self
    end

    # Add a block of CSS with optional auto-fixing
    # Options:
    #   - fix_braces: Auto-close missing braces (default: false)
    #   - media_types: Force all rules to have specific media types (default: nil - use parsed media types)
    def add_block!(css_string, fix_braces: false, media_types: nil)
      css_to_parse = css_string

      if fix_braces
        # Count braces - if unbalanced, add missing closing braces
        open_braces = css_string.count('{')
        close_braces = css_string.count('}')
        if open_braces > close_braces
          css_to_parse = css_string + (' }' * (open_braces - close_braces))
        end
      end

      # Track how many rules we had before parsing
      rules_before = @raw_rules.length

      parse(css_to_parse)

      # If media_types specified, update all just-added rules
      if media_types
        media_types_array = Array(media_types).map(&:to_sym)
        # Update only the newly added rules
        @raw_rules[rules_before..-1].each do |raw_rule|
          raw_rule[:media_types] = media_types_array
        end
      end

      self
    end

    alias_method :load_string!, :add_block!

    # Load CSS from a URI (http://, https://, or file://)
    # Options:
    #   - base_uri: Base URI for resolving relative imports
    #   - media_types: Array of media types (e.g., [:screen, :print])
    def load_uri!(uri, options = {})
      require 'uri'
      require 'net/http'

      uri_obj = URI(uri)
      css_content = nil

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
        css_content = File.read(File.expand_path(path))
      else
        raise ArgumentError, "Unsupported URI scheme: #{uri_obj.scheme}"
      end

      parse(css_content)
      self
    rescue Errno::ENOENT => e
      raise IOError, "File not found: #{uri}" if @options[:io_exceptions]
      self
    rescue => e
      raise IOError, "Error loading URI: #{uri} - #{e.message}" if @options[:io_exceptions]
      self
    end

    # Load CSS from a local file
    # Arguments:
    #   - filename: Path to CSS file
    #   - base_dir: Base directory for resolving relative paths (default: current directory)
    #   - media_types: Media type symbol or array (not yet implemented for filtering)
    def load_file!(filename, base_dir = '.', media_types = :all)
      file_path = File.expand_path(filename, base_dir)
      css_content = File.read(file_path)
      parse(css_content)
      self
    rescue Errno::ENOENT => e
      raise IOError, "File not found: #{file_path}" if @options[:io_exceptions]
      self
    rescue => e
      raise IOError, "Error loading file: #{file_path} - #{e.message}" if @options[:io_exceptions]
      self
    end

    # Lazy map over raw rules, converting to RuleSet objects on demand
    def rules
      return enum_for(:rules) unless block_given?

      @raw_rules.each do |raw_rule|
        yield convert_raw_rule_to_rich(raw_rule)
      end
    end

    # Add a new rule
    def add_rule!(selector:, declarations:, media_types: [:all])
      new_rule = RuleSet.new(
        selector: selector,
        declarations: declarations,
        media_types: media_types
      )

      # Add to raw rules array as a hash
      @raw_rules << {
        selector: new_rule.selector,
        declarations: new_rule.declarations.to_h,
        media_types: new_rule.media_types
      }

      new_rule
    end

    # Add a RuleSet directly
    def add_rule_set!(rule_set)
      @raw_rules << {
        selector: rule_set.selector,
        declarations: rule_set.declarations.to_h,
        media_types: rule_set.media_types
      }
      self
    end

    # Remove a RuleSet
    def remove_rule_set!(rule_set)
      @raw_rules.reject! do |raw_rule|
        raw_rule[:selector] == rule_set.selector &&
          raw_rule[:declarations] == rule_set.declarations.to_h &&
          raw_rule[:media_types] == rule_set.media_types
      end
      self
    end

    # Remove rules matching criteria
    def remove_rules!(selector: nil, media_types: nil)
      @raw_rules.reject! do |raw_rule|
        # Convert to rich object for matching
        rule = convert_raw_rule_to_rich(raw_rule)
        match = true
        match &&= (rule.selector == selector) if selector
        match &&= rule.applies_to_media?(media_types) if media_types
        match
      end
    end
    
    # CSS-parser gem compatible API
    # Yields: selector, declarations, specificity, media_types
    def each_selector(media_types = :all)
      return enum_for(:each_selector, media_types) unless block_given?

      rules.each do |rule|
        next unless rule.applies_to_media?(media_types)
        yield rule.selector, rule.declarations.to_s, rule.specificity, rule.media_types
      end
    end

    # Get declarations by selector.
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
      matching_rules = rules.select do |rule|
        rule.selector == selector && rule.applies_to_media?(media_types)
      end
      matching_rules.map { |rule| rule.declarations.to_s }
    end
    alias [] find_by_selector

    # Iterate through RuleSet objects.
    #
    # +media_types+ can be a symbol or an array of symbols.
    # Yields each rule set along with its media types.
    def each_rule_set(media_types = :all) # :yields: rule_set, media_types
      return enum_for(:each_rule_set, media_types) unless block_given?

      rules.each do |rule|
        next unless rule.applies_to_media?(media_types)
        yield rule, rule.media_types
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

    # Output CSS rules as a stylesheet
    #
    # Note: When which_media is :all (default), this outputs ALL rules regardless of their
    # media type. This differs from find_by_selector(:all) which only returns non-media-specific
    # rules. This matches css_parser gem behavior but can be confusing.
    #
    # The semantic difference:
    # - to_s(:all) / each_selector(:all) -> iterate ALL rules (for output/inspection)
    # - find_by_selector(selector, :all) -> find non-media-specific rules (for querying)
    def to_s(which_media = :all)
      out = []
      styles_by_media_types = {}

      # Special case: :all means iterate through ALL rules for output
      # We iterate manually instead of using each_selector to avoid filtering
      rules.each do |rule|
        # Skip filtering when which_media is :all
        next unless which_media == :all || rule.applies_to_media?(which_media)

        rule.media_types.each do |media_type|
          styles_by_media_types[media_type] ||= []
          styles_by_media_types[media_type] << [rule.selector, rule.declarations.to_s]
        end
      end

      styles_by_media_types.each_pair do |media_type, media_styles|
        media_block = (media_type != :all)
        out << "@media #{media_type} {" if media_block

        media_styles.each do |media_style|
          if media_block
            out.push("  #{media_style[0]} { #{media_style[1]} }")
          else
            out.push("#{media_style[0]} { #{media_style[1]} }")
          end
        end

        out << '}' if media_block
      end

      out << ''
      out.join("\n")
    end
    
    # Utility methods
    def rules_count
      @raw_rules.length
    end

    def selectors(media_types = :all)
      rules.select { |rule| rule.applies_to_media?(media_types) }
           .map(&:selector)
    end

    # Export back to CSS source
    def to_css
      to_s
    end

    # Convert to nested hash structure
    # Returns: { 'media_type' => { 'selector' => { 'property' => 'value' } } }
    def to_h
      result = {}

      rules.each do |rule|
        rule.media_types.each do |media_type|
          media_key = media_type.to_s
          result[media_key] ||= {}
          result[media_key][rule.selector] ||= {}
          result[media_key][rule.selector].merge!(rule.declarations.to_h)
        end
      end

      result
    end

    # Check if parser has any rules
    def empty?
      rules_count == 0
    end

    # Clear all rules
    def clear!
      @raw_rules = []
      @css_source = nil
    end

    private

    # Convert a single raw rule to a RuleSet object
    def convert_raw_rule_to_rich(raw_rule)
      RuleSet.new(
        selector: raw_rule[:selector],
        declarations: raw_rule[:declarations],
        media_types: raw_rule[:media_types] || [:all] # Extract from raw_rule when available
      )
    end
  end
end
