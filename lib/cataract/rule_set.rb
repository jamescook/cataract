module Cataract
  class RuleSet
    attr_reader :selector, :declarations, :media_types
    
    # YJIT-friendly: define all instance variables upfront
    def initialize(selector:, declarations: nil, media_types: [:all])
      @selector = selector.to_s.strip
      @media_types = Array(media_types).map(&:to_sym)
      @specificity = nil # Cached specificity
      
      # Handle different declaration input types
      @declarations = case declarations
                     when Declarations
                       declarations.dup
                     when Hash
                       Declarations.new(declarations)
                     when String
                       parse_declaration_string(declarations)
                     when nil
                       Declarations.new
                     else
                       raise ArgumentError, "Invalid declarations type: #{declarations.class}"
                     end
    end
    
    # Selector specificity (cached)
    def specificity
      @specificity ||= calculate_specificity(@selector)
    end
    
    # Check if rule applies to given media types
    def applies_to_media?(media_types)
      target_media = Array(media_types).map(&:to_sym)
      target_media.include?(:all) || @media_types.include?(:all) || 
        !(@media_types & target_media).empty?
    end
    
    # Property access delegation
    def [](property)
      @declarations[property]
    end
    
    def []=(property, value)
      @declarations[property] = value
    end
    
    def has_property?(property)
      @declarations.key?(property)
    end
    
    def delete_property(property)
      @declarations.delete(property)
    end
    
    # Check if rule is empty
    def empty?
      @declarations.empty?
    end
    
    # Convert to CSS string
    def to_s
      return "" if empty?
      "#{@selector} { #{@declarations.to_s} }"
    end
    
    # Convert to hash (for compatibility with current tests)
    def to_h
      {
        selector: @selector,
        declarations: @declarations.to_h,
        media_types: @media_types,
        specificity: specificity
      }
    end
    
    # Duplicate rule
    def dup
      self.class.new(
        selector: @selector,
        declarations: @declarations.dup,
        media_types: @media_types.dup
      )
    end
    
    # Equality
    def ==(other)
      return false unless other.is_a?(RuleSet)
      @selector == other.selector &&
        @declarations == other.declarations &&
        @media_types == other.media_types
    end
    
    # Merge declarations from another rule (for same selector)
    def merge!(other)
      case other
      when RuleSet
        @declarations.merge!(other.declarations)
      when Declarations
        @declarations.merge!(other)
      when Hash
        @declarations.merge!(other)
      else
        raise ArgumentError, "Can only merge RuleSet, Declarations, or Hash objects"
      end
      self
    end
    
    def merge(other)
      dup.merge!(other)
    end
    
    private
    
    # Parse "color: red; background: blue" into Declarations
    def parse_declaration_string(str)
      declarations = Declarations.new
      
      # Simple parsing - split on semicolons, then on first colon
      str.split(';').each do |decl|
        next if decl.strip.empty?
        
        parts = decl.split(':', 2)
        next unless parts.length == 2
        
        property = parts[0].strip
        value = parts[1].strip
        declarations[property] = value
      end
      
      declarations
    end
    
    # Calculate CSS specificity
    def calculate_specificity(selector)
      specificity = 0
      
      # ID selectors = 100 each
      specificity += selector.scan(/#[\w-]+/).length * 100
      
      # Class selectors and attribute selectors = 10 each  
      specificity += selector.scan(/\.[\w-]+/).length * 10
      specificity += selector.scan(/\[[^\]]+\]/).length * 10
      
      # Element selectors = 1 each
      # Simple heuristic: if no other selectors found, assume it's an element
      if specificity == 0
        specificity = 1
      end
      
      specificity
    end
  end
end
