# frozen_string_literal: true

module Cataract
  # Container for CSS property declarations with merge and cascade support
  class Declarations
    def initialize(properties = {})
      case properties
      when Array
        # Array of Declarations::Value structs from C parser - store directly
        @values = properties
      when Hash
        # Hash from user - convert to internal storage
        @values = []
        properties.each { |prop, value| self[prop] = value }
      when String
        # String "color: red; background: blue" - parse it
        @values = parse_declaration_string(properties)
      else
        @values = []
      end
    end

    # Property access
    # Returns value with trailing semicolon (css_parser compatibility)
    def get_property(property)
      prop = normalize_property(property)
      val = find_value(prop)
      return nil if val.nil?

      # css_parser includes trailing semicolon in values
      suffix = val.important ? ' !important' : ''
      "#{val.value}#{suffix};"
    end
    alias [] get_property

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

      # Find existing value or create new one
      # Properties from C parser are already normalized, so direct comparison
      existing_index = @values.find_index { |v| v.property == prop }

      # Create a new Value struct
      new_val = Declarations::Value.new(prop, clean_value, is_important)

      if existing_index
        @values[existing_index] = new_val
      else
        @values << new_val
      end
    end
    alias []= set_property

    def key?(property)
      !find_value(normalize_property(property)).nil?
    end
    alias has_property? key?

    def important?(property)
      val = find_value(normalize_property(property))
      val ? val.important : false
    end

    def delete(property)
      prop = normalize_property(property)
      @values.delete_if { |v| v.property == prop }
    end

    # Iterate through properties in order
    def each
      return enum_for(:each) unless block_given?

      @values.each do |val|
        yield val.property, val.value, val.important
      end
    end

    def size
      @values.size
    end
    alias length size

    def empty?
      @values.empty?
    end

    # Convert to CSS string
    # css_parser format: includes trailing semicolon
    def to_s
      return '' if empty?

      declarations = []
      each do |property, value, is_important|
        suffix = is_important ? ' !important' : ''
        declarations << "#{property}: #{value}#{suffix}"
      end
      "#{declarations.join('; ')};"
    end

    def to_h
      result = {}
      each do |property, value, is_important|
        suffix = is_important ? ' !important' : ''
        result[property] = "#{value}#{suffix}"
      end
      result
    end

    # Return array of Declarations::Value structs (for creating Rule structs)
    def to_a
      @values
    end

    def merge!(other)
      case other
      when Declarations
        other.each { |prop, value, important| self[prop] = important ? "#{value} !important" : value }
      when Hash
        other.each { |prop, value| self[prop] = value }
      else
        raise ArgumentError, 'Can only merge Declarations or Hash objects'
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

      @values == other.instance_variable_get(:@values)
    end

    private

    # Normalize user-provided property names for case-insensitive lookup
    # Note: Properties from C parser are already normalized
    def normalize_property(property)
      property.to_s.strip.downcase
    end

    # Find a Value struct by normalized property name
    def find_value(normalized_property)
      @values.find { |v| v.property == normalized_property }
    end

    # Parse "color: red; background: blue" string into array of Value structs
    def parse_declaration_string(str)
      # Use C function directly - no dummy wrapper needed!
      Cataract.parse_declarations(str)
    end
  end
end
