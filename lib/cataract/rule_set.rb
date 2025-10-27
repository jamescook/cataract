module Cataract
  class RuleSet
    attr_reader :selector, :declarations, :media_types

    # YJIT-friendly: define all instance variables upfront
    # Accepts both :selector and :selectors, both :declarations and :block for css_parser compatibility
    def initialize(selector: nil, selectors: nil, declarations: nil, block: nil, media_types: [:all], specificity: nil)
      # Handle both selector and selectors parameters (css_parser compatibility)
      selector_str = selector || selectors
      raise ArgumentError, "Must provide selector or selectors" if selector_str.nil?

      @selector = selector_str.to_s.strip
      @media_types = Array(media_types).map(&:to_sym)
      @specificity = specificity # Can be overridden, otherwise calculated

      # Handle both declarations and block parameters (css_parser compatibility)
      decl_input = declarations || block

      # Handle different declaration input types
      @declarations = case decl_input
                     when Declarations
                       decl_input.dup
                     when Hash
                       # User-provided hash: {'color' => 'red', 'background' => 'blue'}
                       Declarations.new(decl_input)
                     when Array
                       # Array of Cataract::Declarations::Value structs from C parser
                       Declarations.new(decl_input)
                     when String
                       parse_declaration_string(decl_input)
                     when nil
                       Declarations.new
                     else
                       raise ArgumentError, "Invalid declarations type: #{decl_input.class}"
                     end
    end
    
    # Selector specificity (cached)
    def specificity
      @specificity ||= calculate_specificity(@selector)
    end
    
    # Check if rule applies to given media types
    #
    # Note: :all has special meaning - it matches ALL rules regardless of their media type.
    # This matches css_parser gem behavior.
    def applies_to_media?(media_types)
      target_media = Array(media_types).map(&:to_sym)

      # If querying for :all, match ALL rules (css_parser behavior)
      return true if target_media.include?(:all)

      # If querying for specific media type(s), don't match :all rules
      # (non-media-specific rules don't match specific media queries in css_parser)
      return false if @media_types.include?(:all)

      # Check for intersection between rule's media types and query
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

    # css_parser compatibility: return array of individual selectors
    # "h1, h2, h3" => ["h1", "h2", "h3"]
    def selectors
      @selector.split(',').map(&:strip)
    end

    # css_parser compatibility: iterate over each individual selector with its declarations
    # For "h1, h2" with "color: red", yields:
    #   - ["h1", "color: red;", specificity_of_h1]
    #   - ["h2", "color: red;", specificity_of_h2]
    def each_selector
      return enum_for(:each_selector) unless block_given?

      selectors.each do |sel|
        spec = @specificity || calculate_specificity(sel)
        yield sel, @declarations.to_s, spec
      end
    end

    # css_parser compatibility: iterate over each declaration
    # Yields: property, value, is_important
    def each_declaration
      return enum_for(:each_declaration) unless block_given?

      @declarations.each do |property, value|
        is_important = @declarations.important?(property)
        yield property, value, is_important
      end
    end

    # css_parser compatibility: return declarations as string
    def declarations_to_s
      @declarations.to_s
    end

    private
    
    # Parse "color: red; background: blue" into Declarations
    # Also handles css_parser format with braces: "{ color: red }"
    def parse_declaration_string(str)
      # Use C function directly - no dummy wrapper needed!
      raw_declarations = Cataract.parse_declarations(str)
      Declarations.new(raw_declarations)
    end
    
    # Calculate CSS specificity using C extension
    def calculate_specificity(selector)
      Cataract.calculate_specificity(selector)
    end
  end
end
