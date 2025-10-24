module Cataract
  class Declarations
    def initialize(properties = {})
      @properties = {}
      @property_order = []
      @important_flags = {}

      # Add properties if provided
      properties.each { |prop, value| self[prop] = value } if properties
    end

    # Property access
    # Returns value with trailing semicolon (css_parser compatibility)
    def get_property(property)
      prop = normalize_property(property)
      value = @properties[prop]
      return nil if value.nil?

      # css_parser includes trailing semicolon in values
      is_important = @important_flags[prop]
      suffix = is_important ? ' !important' : ''
      "#{value}#{suffix};"
    end
    alias_method :[], :get_property

    def set_property(property, value)
      prop = normalize_property(property)

      # Parse !important and strip trailing semicolons (css_parser compatibility)
      value_str = value.to_s.strip
      # Remove trailing semicolons (guard to avoid allocation when no semicolon present)
      value_str = value_str.sub(/;+$/, '') if value_str.end_with?(';')

      is_important = value_str.end_with?('!important')
      clean_value = is_important ? value_str.sub(/\s*!important\s*$/, '').strip : value_str.strip

      # Reject malformed declarations with no value (e.g., "color: !important")
      # css_parser silently ignores these
      return if clean_value.empty?

      # Store property
      unless @properties.key?(prop)
        @property_order << prop
      end

      @properties[prop] = clean_value
      @important_flags[prop] = is_important
    end
    alias_method :[]=, :set_property

    def key?(property)
      @properties.key?(normalize_property(property))
    end
    alias_method :has_property?, :key?
    
    def important?(property)
      @important_flags[normalize_property(property)] || false
    end
    
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

    def empty?
      @properties.empty?
    end

    # Convert to CSS string
    # css_parser format: includes trailing semicolon
    def to_s
      return "" if empty?
      declarations = []
      each do |property, value, is_important|
        suffix = is_important ? ' !important' : ''
        declarations << "#{property}: #{value}#{suffix}"
      end
      declarations.join('; ') + ';'
    end

    def to_h
      result = {}
      each do |property, value, is_important|
        suffix = is_important ? ' !important' : ''
        result[property] = "#{value}#{suffix}"
      end
      result
    end

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

    def dup
      new_decl = self.class.new
      each { |prop, value, important| new_decl[prop] = important ? "#{value} !important" : value }
      new_decl
    end

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
