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

    alias_method :add_block!, :parse
    alias_method :load_string!, :parse

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
    def each_selector(media_types = :all)
      return enum_for(:each_selector, media_types) unless block_given?

      rules.each do |rule|
        next unless rule.applies_to_media?(media_types)
        yield rule.selector, rule.declarations.to_s, rule.specificity
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
    
    def to_s(media_types = :all)
      output = []
      
      # Group by media type
      by_media = rules.group_by { |rule| rule.media_types }
      
      by_media.each do |media_list, media_rules|
        # Filter rules by requested media types
        filtered_rules = media_rules.select { |rule| rule.applies_to_media?(media_types) }
        next if filtered_rules.empty?
        
        if media_list == [:all]
          # No @media wrapper needed
          filtered_rules.each { |rule| output << rule.to_s }
        else
          # Wrap in @media
          media_query = media_list.join(', ')
          output << "@media #{media_query} {"
          filtered_rules.each { |rule| output << "  #{rule.to_s}" }
          output << "}"
        end
      end
      
      output.join("\n")
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
