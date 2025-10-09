module Cataract
  class Declarations
    # YJIT-friendly: define all instance variables upfront
    def initialize(properties = {})
      @properties = {}
      @property_order = []
      @important_flags = {}
      
      # Add properties if provided
      properties.each { |prop, value| self[prop] = value } if properties
    end
    
    # Property access
    def [](property)
      @properties[normalize_property(property)]
    end
    
    def []=(property, value)
      prop = normalize_property(property)
      
      # Parse !important
      value_str = value.to_s
      is_important = value_str.end_with?('!important')
      clean_value = is_important ? value_str.sub(/\s*!important\s*$/, '').strip : value_str.strip
      
      # Store property
      unless @properties.key?(prop)
        @property_order << prop
      end
      
      @properties[prop] = clean_value
      @important_flags[prop] = is_important
    end
    
    # Check if property exists
    def key?(property)
      @properties.key?(normalize_property(property))
    end
    alias_method :has_property?, :key?
    
    # Important flag check
    def important?(property)
      @important_flags[normalize_property(property)] || false
    end
    
    # Remove property
    def delete(property)
      prop = normalize_property(property)
      @property_order.delete(prop)
      @important_flags.delete(prop)
      @properties.delete(prop)
    end
    
    # Iterate through properties in order
    def each
      return enum_for(:each) unless block_given?
      
      @property_order.each do |prop|
        value = @properties[prop]
        is_important = @important_flags[prop]
        yield prop, value, is_important
      end
    end
    
    # Get property count
    def size
      @properties.size
    end
    alias_method :length, :size
    
    # Check if empty
    def empty?
      @properties.empty?
    end
    
    # Convert to CSS string
    def to_s
      declarations = []
      each do |property, value, is_important|
        suffix = is_important ? ' !important' : ''
        declarations << "#{property}: #{value}#{suffix}"
      end
      declarations.join('; ')
    end
    
    # Convert to hash (for compatibility)
    def to_h
      result = {}
      each do |property, value, is_important|
        suffix = is_important ? ' !important' : ''
        result[property] = "#{value}#{suffix}"
      end
      result
    end
    
    # Merge with another Declarations object
    def merge!(other)
      case other
      when Declarations
        other.each { |prop, value, important| self[prop] = important ? "#{value} !important" : value }
      when Hash
        other.each { |prop, value| self[prop] = value }
      else
        raise ArgumentError, "Can only merge Declarations or Hash objects"
      end
      self
    end
    
    def merge(other)
      dup.merge!(other)
    end
    
    # Duplicate
    def dup
      new_decl = self.class.new
      each { |prop, value, important| new_decl[prop] = important ? "#{value} !important" : value }
      new_decl
    end
    
    # Equality
    def ==(other)
      return false unless other.is_a?(Declarations)
      @properties == other.instance_variable_get(:@properties) &&
        @important_flags == other.instance_variable_get(:@important_flags)
    end
    
    private
    
    def normalize_property(property)
      property.to_s.downcase.strip
    end
  end
end
