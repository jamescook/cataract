module Cataract
  class Parser
    def initialize(options = {})
      @options = {
        import: false,
        io_exceptions: true
      }.merge(options)

      # YJIT-friendly: define all instance variables upfront
      @raw_rules = []
      @rich_rules = nil
      @css_source = nil
    end

    def parse(css_string)
      @css_source = css_string.dup.freeze

      if CATARACT_C_EXT
        @raw_rules = Cataract.parse_css(css_string)
      else
        raise
        parser = Cataract::PureRubyParser.new
        @raw_rules = parser.parse(css_string)
      end

      # Reset rich rules cache
      @rich_rules = nil

      self
    end
    
    alias_method :add_block!, :parse
    
    # Lazy conversion to rich objects
    def rules
      @rich_rules ||= convert_to_rich_objects(@raw_rules)
    end
    
    # Add a new rule (forces rich mode)
    def add_rule!(selector:, declarations:, media_types: [:all])
      # Ensure we're in rich mode
      rules
      
      new_rule = RuleSet.new(
        selector: selector,
        declarations: declarations,
        media_types: media_types
      )
      
      @rich_rules << new_rule
      @raw_rules = nil # Invalidate raw cache
      
      new_rule
    end
    
    # Remove rules matching criteria
    def remove_rules!(selector: nil, media_types: nil)
      rules.reject! do |rule|
        match = true
        match &&= (rule.selector == selector) if selector
        match &&= rule.applies_to_media?(media_types) if media_types
        match
      end
      
      @raw_rules = nil # Invalidate raw cache
    end
    
    # CSS-parser gem compatible API
    def each_selector(media_types = :all)
      return enum_for(:each_selector, media_types) unless block_given?
      
      rules.each do |rule|
        next unless rule.applies_to_media?(media_types)
        yield rule.selector, rule.declarations.to_s, rule.specificity
      end
    end
    
    def find_by_selector(selector, media_types = :all)
      matching_rules = rules.select do |rule|
        rule.selector == selector && rule.applies_to_media?(media_types)
      end
      matching_rules.map { |rule| rule.declarations.to_s }
    end
    
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
      rules.length
    end
    
    def selectors(media_types = :all)
      rules.select { |rule| rule.applies_to_media?(media_types) }
           .map(&:selector)
    end
    
    def using_c_extension?
      CATARACT_C_EXT
    end
    
    # Export back to CSS source
    def to_css
      to_s
    end
    
    # Check if parser has any rules
    def empty?
      rules.empty?
    end
    
    # Clear all rules
    def clear!
      @raw_rules = []
      @rich_rules = []
      @css_source = nil
    end
    
    private
    
    def convert_to_rich_objects(raw_rules)
      raw_rules.map do |raw_rule|
        RuleSet.new(
          selector: raw_rule[:selector],
          declarations: raw_rule[:declarations],
          media_types: [:all] # TODO: extract from raw_rule when we add media query support
        )
      end
    end
  end
end
