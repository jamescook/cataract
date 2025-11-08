# frozen_string_literal: true

module Cataract
  # Container for CSS property declarations with merge and cascade support
  # Works with Declaration structs from the new parser
  class Declarations
    include Enumerable

    def initialize(properties = {})
      case properties
      when Array
        # Array of Declaration structs from C parser - store directly
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
    # Returns value without trailing semicolon
    def get_property(property)
      prop = normalize_property(property)
      val = find_value(prop)
      return nil if val.nil?

      suffix = val.important ? ' !important' : ''
      "#{val.value}#{suffix}"
    end
    alias [] get_property

    def set_property(property, value)
      prop = normalize_property(property)

      # Parse !important and strip trailing semicolons (css_parser compatibility)
      clean_value = value.to_s.strip
      # Remove trailing semicolons (guard to avoid allocation when no semicolon present)
      # value_str = value_str.sub(/;+$/, '') if value_str.end_with?(';')
      clean_value.sub!(/;+$/, '') if clean_value.end_with?(';')

      is_important = clean_value.end_with?('!important')
      if is_important
        clean_value.sub!(/\s*!important\s*$/, '').strip!
      else
        clean_value.strip!
      end

      # Reject malformed declarations with no value (e.g., "color: !important")
      # css_parser silently ignores these
      return if clean_value.empty?

      # Find existing value or create new one
      # Properties from C parser are already normalized, so direct comparison
      existing_index = @values.find_index { |v| v.property == prop }

      # Create a new Declaration struct
      new_val = Cataract::Declaration.new(prop, clean_value, is_important)

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
    # Implemented in C for performance (see ext/cataract/cataract.c)
    # Format: "color: red; margin: 10px !important;"
    # Note: C implementation defined via rb_define_method

    # Enable implicit string conversion for comparisons
    alias to_str to_s

    def to_h
      result = {}
      each do |property, value, is_important|
        suffix = is_important ? ' !important' : ''
        result[property] = "#{value}#{suffix}"
      end
      result
    end

    # Return array of Declaration structs (for creating Rule structs)
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
      case other
      when Declarations
        # Compare arrays of Declaration structs
        to_a == other.to_a
      when String
        # Allow string comparison for convenience
        to_s == other
      else
        false
      end
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

    # Parse "color: red; background: blue" string into array of Declaration structs
    def parse_declaration_string(str)
      Cataract.parse_declarations(str)
    end
  end
end
