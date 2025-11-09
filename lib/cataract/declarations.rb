# frozen_string_literal: true

module Cataract
  # Container for CSS property declarations with merge and cascade support.
  #
  # The Declarations class provides a convenient Ruby interface for working with
  # CSS property-value pairs. It wraps an array of Declaration structs (defined in C)
  # and provides hash-like access, iteration, and merging capabilities.
  #
  # @example Create from hash
  #   decls = Cataract::Declarations.new('color' => 'red', 'margin' => '10px')
  #   decls['color'] #=> "red"
  #
  # @example Create from Declaration array
  #   rule = Cataract.parse_css("body { color: red; }").rules.first
  #   decls = Cataract::Declarations.new(rule.declarations)
  #   decls['color'] #=> "red"
  #
  # @example Create from CSS string
  #   decls = Cataract::Declarations.new("color: red; margin: 10px")
  #   decls.size #=> 2
  #
  # @example Work with !important
  #   decls = Cataract::Declarations.new('color' => 'red !important')
  #   decls.important?('color') #=> true
  #   decls['color'] #=> "red !important"
  class Declarations
    include Enumerable

    # Create a new Declarations container.
    #
    # @param properties [Hash, Array<Declaration>, String] Initial declarations
    #   - Hash: Property name => value pairs
    #   - Array: Array of Declaration structs from parser
    #   - String: CSS declaration block (e.g., "color: red; margin: 10px")
    # @return [Declarations] New Declarations instance
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

    # Get the value of a CSS property.
    #
    # Returns the property value with !important suffix if present.
    # Property names are case-insensitive.
    #
    # @param property [String, Symbol] The CSS property name
    # @return [String, nil] The property value with !important suffix, or nil if not found
    #
    # @example
    #   decls['color'] #=> "red"
    #   decls['Color'] #=> "red" (case-insensitive)
    #   decls['font-weight'] #=> "bold !important"
    def get_property(property)
      prop = normalize_property(property)
      val = find_value(prop)
      return nil if val.nil?

      suffix = val.important ? ' !important' : ''
      "#{val.value}#{suffix}"
    end
    alias [] get_property

    # Set the value of a CSS property.
    #
    # Property names are normalized to lowercase. Trailing semicolons are stripped.
    # The !important flag can be included in the value string.
    #
    # @param property [String, Symbol] The CSS property name
    # @param value [String] The property value (may include !important)
    # @return [void]
    #
    # @example
    #   decls['color'] = 'red'
    #   decls['margin'] = '10px !important'
    #   decls['Color'] = 'blue' # Overwrites 'color' (case-insensitive)
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

    # Check if a property is defined in this declaration block.
    #
    # @param property [String, Symbol] The CSS property name
    # @return [Boolean] true if the property exists
    #
    # @example
    #   decls.key?('color') #=> true
    #   decls.has_property?('font-size') #=> false
    def key?(property)
      !find_value(normalize_property(property)).nil?
    end
    alias has_property? key?

    # Check if a property has the !important flag.
    #
    # @param property [String, Symbol] The CSS property name
    # @return [Boolean] true if the property has !important, false otherwise
    #
    # @example
    #   decls['color'] = 'red !important'
    #   decls.important?('color') #=> true
    #   decls['margin'] = '10px'
    #   decls.important?('margin') #=> false
    def important?(property)
      val = find_value(normalize_property(property))
      val ? val.important : false
    end

    # Delete a property from the declaration block.
    #
    # @param property [String, Symbol] The CSS property name to delete
    # @return [Array<Declaration>] The modified declarations array
    #
    # @example
    #   decls.delete('color')
    #   decls.key?('color') #=> false
    def delete(property)
      prop = normalize_property(property)
      @values.delete_if { |v| v.property == prop }
    end

    # Iterate through each property-value pair.
    #
    # @yieldparam property [String] The property name
    # @yieldparam value [String] The property value (without !important)
    # @yieldparam important [Boolean] Whether the property has !important flag
    # @return [Enumerator, nil] Returns enumerator if no block given
    #
    # @example
    #   decls.each do |property, value, important|
    #     puts "#{property}: #{value}#{important ? ' !important' : ''}"
    #   end
    def each
      return enum_for(:each) unless block_given?

      @values.each do |val|
        yield val.property, val.value, val.important
      end
    end

    # Get the number of declarations.
    #
    # @return [Integer] Number of properties in the declaration block
    def size
      @values.size
    end
    alias length size

    # Check if the declaration block is empty.
    #
    # @return [Boolean] true if no properties are defined
    def empty?
      @values.empty?
    end

    # Convert declarations to CSS string.
    #
    # Implemented in C for performance.
    #
    # @return [String] CSS declaration block string
    #
    # @example
    #   decls.to_s #=> "color: red; margin: 10px !important;"

    # Enable implicit string conversion for comparisons
    alias to_str to_s

    # Convert to a hash of property => value pairs.
    #
    # Values include !important suffix if present.
    #
    # @return [Hash<String, String>] Hash of property names to values
    #
    # @example
    #   decls.to_h #=> {"color" => "red", "margin" => "10px !important"}
    def to_h
      result = {}
      each do |property, value, is_important|
        suffix = is_important ? ' !important' : ''
        result[property] = "#{value}#{suffix}"
      end
      result
    end

    # Convert to an array of Declaration structs.
    #
    # Returns the internal array of Declaration structs, which is useful
    # for creating Rule objects or passing to C functions.
    #
    # @return [Array<Declaration>] Array of Declaration structs
    def to_a
      @values
    end

    # Merge another set of declarations into this one (mutating).
    #
    # Properties from the other declarations will overwrite properties in this one.
    # The !important flag is preserved during merge.
    #
    # @param other [Declarations, Hash] Declarations to merge in
    # @return [self] Returns self for method chaining
    # @raise [ArgumentError] If other is not Declarations or Hash
    #
    # @example
    #   decls1 = Cataract::Declarations.new('color' => 'red')
    #   decls2 = Cataract::Declarations.new('margin' => '10px')
    #   decls1.merge!(decls2)
    #   decls1.to_h #=> {"color" => "red", "margin" => "10px"}
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

    # Merge another set of declarations (non-mutating).
    #
    # Creates a copy of this Declarations object and merges the other into it.
    #
    # @param other [Declarations, Hash] Declarations to merge
    # @return [Declarations] New Declarations with merged properties
    #
    # @example
    #   decls1 = Cataract::Declarations.new('color' => 'red')
    #   decls2 = Cataract::Declarations.new('margin' => '10px')
    #   merged = decls1.merge(decls2)
    #   merged.to_h #=> {"color" => "red", "margin" => "10px"}
    #   decls1.to_h #=> {"color" => "red"} (unchanged)
    def merge(other)
      dup.merge!(other)
    end

    # Create a shallow copy of this Declarations object.
    #
    # @return [Declarations] New Declarations with copied properties
    def dup
      new_decl = self.class.new
      each { |prop, value, important| new_decl[prop] = important ? "#{value} !important" : value }
      new_decl
    end

    # Compare this Declarations with another object.
    #
    # @param other [Declarations, String] Object to compare with
    # @return [Boolean] true if equal
    #
    # @example
    #   decls1 = Cataract::Declarations.new('color' => 'red')
    #   decls2 = Cataract::Declarations.new('color' => 'red')
    #   decls1 == decls2 #=> true
    #   decls1 == "color: red;" #=> true (string comparison)
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
