# frozen_string_literal: true

# Unit conversion extension for Cataract
#
# Provides methods to convert CSS length units across a stylesheet.
# Not loaded by default - require explicitly:
#   require 'cataract/unit_conversion'
#
# @example Convert px to rem
#   sheet = Cataract::Stylesheet.parse(css)
#   sheet.convert_units!(from: :px, to: :rem)
#
# @example Non-mutating conversion
#   result = sheet.convert_units(from: :px, to: :rem, base_font_size: 10)

module Cataract
  module UnitConversion
    # Byte constants for parsing
    BYTE_SPACE = 32       # ' '
    BYTE_TAB = 9          # '\t'
    BYTE_NEWLINE = 10     # '\n'
    BYTE_CR = 13          # '\r'
    BYTE_MINUS = 45       # '-'
    BYTE_PLUS = 43        # '+'
    BYTE_DOT = 46         # '.'
    BYTE_0 = 48           # '0'
    BYTE_9 = 57           # '9'
    BYTE_LPAREN = 40      # '('
    BYTE_C = 99           # 'c'
    BYTE_V = 118          # 'v'
    BYTE_M = 109          # 'm'
    BYTE_L = 108          # 'l'
    BYTE_A = 97           # 'a'
    BYTE_X = 120          # 'x'
    BYTE_I = 105          # 'i'
    BYTE_N = 110          # 'n'

    # W3C CSS Values and Units Module Level 3
    # https://www.w3.org/TR/css-values-3/
    #
    # Absolute unit conversion ratios:
    # 1in = 2.54cm = 96px
    # 1cm = 96px/2.54
    # 1mm = 1/10cm
    # 1pt = 1/72in
    # 1pc = 1/6in
    ABSOLUTE_UNIT_TO_PX = {
      px: 1.0,
      in: 96.0,
      cm: 96.0 / 2.54,
      mm: 96.0 / 25.4,
      pt: 96.0 / 72.0,
      pc: 96.0 / 6.0
    }.freeze

    # Units that require context (not supported)
    CONTEXT_DEPENDENT_UNITS = %i[percent % em ex ch vw vh vmin vmax].freeze

    # Supported unit conversions
    SUPPORTED_UNITS = (ABSOLUTE_UNIT_TO_PX.keys + %i[rem]).freeze

    # Properties that accept length units and are safe to convert
    # Based on W3C spec - properties where units can be converted without cascade concerns
    DEFAULT_CONVERTIBLE_PROPERTIES = %w[
      margin margin-top margin-right margin-bottom margin-left
      padding padding-top padding-right padding-bottom padding-left
      border-width border-top-width border-right-width border-bottom-width border-left-width
      width height
      min-width min-height
      max-width max-height
      font-size
      letter-spacing
      word-spacing
      text-indent
      outline-width
    ].freeze

    # Properties excluded by default (require explicit opt-in)
    # line-height: unitless has different cascade semantics than length values
    DEFAULT_EXCLUDED_PROPERTIES = %w[line-height].freeze

    # Precomputed Hash for default property lookups (O(1) instead of O(n) with Array)
    #
    # Pattern: Array#to_h { |element| [element, true] }
    # Converts ['foo', 'bar'] to {'foo' => true, 'bar' => true}
    #
    # We use `true` as the value since we only check key existence with Hash#key?
    # This is ~14x faster than Set for repeated lookups
    DEFAULT_CONVERTIBLE_HASH = DEFAULT_CONVERTIBLE_PROPERTIES.to_h { |property| [property, true] }.tap do |hash|
      DEFAULT_EXCLUDED_PROPERTIES.each { |property| hash.delete(property) }
    end.freeze

    # Convert CSS length units in the stylesheet (mutating)
    #
    # @param from [Symbol] Source unit (:px, :rem, :em, :cm, :mm, :in, :pt, :pc)
    # @param to [Symbol] Target unit (:px, :rem, :em, :cm, :mm, :in, :pt, :pc)
    # @param base_font_size [Numeric] Base font size in pixels (default: 16) for rem/em conversions
    # @param properties [Symbol, Array<String>] Properties to convert (:all or array of property names)
    # @param exclude_properties [Array<String>] Properties to skip
    # @param precision [Integer] Decimal places for rounding (default: 4)
    # @return [Stylesheet] self
    #
    # @example Basic conversion
    #   sheet.convert_units!(from: :px, to: :rem)
    #
    # @example Custom base font size
    #   sheet.convert_units!(from: :px, to: :rem, base_font_size: 10)
    #
    # @example Specific properties only
    #   sheet.convert_units!(from: :px, to: :rem, properties: ['font-size', 'margin'])
    #
    # @example Exclude properties
    #   sheet.convert_units!(from: :px, to: :rem, exclude_properties: ['border-width'])
    def convert_units!(from:, to:, base_font_size: 16, properties: nil, exclude_properties: nil, precision: 4)
      validate_conversion_params!(from, to)

      convertible_props = determine_convertible_properties(properties, exclude_properties)

      @rules.each do |rule|
        next unless rule.respond_to?(:declarations)

        rule.declarations.each do |decl|
          next unless should_convert_property?(decl.property, convertible_props)
          next if has_complex_expression?(decl.value)

          decl.value = convert_value(decl.value, from, to, base_font_size, precision)
        end
      end

      self
    end

    # Convert CSS length units in the stylesheet (non-mutating)
    #
    # Returns a new stylesheet with converted units. Original stylesheet unchanged.
    #
    # @param (see #convert_units!)
    # @return [Stylesheet] New stylesheet with converted units
    #
    # @example
    #   result = sheet.convert_units(from: :px, to: :rem)
    #   # sheet is unchanged, result has converted units
    def convert_units(from:, to:, base_font_size: 16, properties: nil, exclude_properties: nil, precision: 4)
      copy = Cataract::Stylesheet.parse(to_s)
      copy.convert_units!(
        from: from,
        to: to,
        base_font_size: base_font_size,
        properties: properties,
        exclude_properties: exclude_properties,
        precision: precision
      )
      copy
    end

    private

    # Validate conversion parameters
    def validate_conversion_params!(from, to)
      raise ArgumentError, 'from: parameter is required' if from.nil?
      raise ArgumentError, 'to: parameter is required' if to.nil?

      from_sym = from.to_sym
      to_sym = to.to_sym

      unless SUPPORTED_UNITS.include?(from_sym)
        raise ArgumentError, "Unsupported source unit: #{from}. Supported: #{SUPPORTED_UNITS.join(', ')}"
      end

      unless SUPPORTED_UNITS.include?(to_sym)
        raise ArgumentError, "Unsupported target unit: #{to}. Supported: #{SUPPORTED_UNITS.join(', ')}"
      end

      return unless CONTEXT_DEPENDENT_UNITS.include?(from_sym) || CONTEXT_DEPENDENT_UNITS.include?(to_sym)

      raise ArgumentError, "Context-dependent unit conversions not supported: #{from} -> #{to}"
    end

    # Determine which properties should be converted
    def determine_convertible_properties(properties, exclude_properties)
      if properties == :all
        :all_except_excluded
      elsif properties.is_a?(Array)
        # Convert array to Hash for O(1) lookups
        properties.to_h { |property| [property, true] }
      elsif exclude_properties.nil? || exclude_properties.empty?
        # Use precomputed Hash unless there are custom exclusions
        DEFAULT_CONVERTIBLE_HASH
      else
        # Build custom Hash with additional exclusions
        DEFAULT_CONVERTIBLE_PROPERTIES.to_h { |property| [property, true] }.tap do |hash|
          (DEFAULT_EXCLUDED_PROPERTIES + exclude_properties).each { |property| hash.delete(property) }
        end
      end
    end

    # Check if property should be converted
    def should_convert_property?(property, convertible_props)
      if convertible_props == :all_except_excluded
        true
      else
        convertible_props.key?(property)
      end
    end

    # Check for complex expressions using getbyte() scanning
    def has_complex_expression?(value)
      len = value.bytesize
      i = 0

      while i < len
        b = value.getbyte(i)

        # Check for 'c' -> calc(
        if b == BYTE_C && i + 4 < len
          return true if value.getbyte(i + 1) == BYTE_A && # rubocop:disable Style/SoleNestedConditional
                         value.getbyte(i + 2) == BYTE_L &&
                         value.getbyte(i + 3) == BYTE_C &&
                         value.getbyte(i + 4) == BYTE_LPAREN
        end

        # Check for 'v' -> var(
        if b == BYTE_V && i + 3 < len
          return true if value.getbyte(i + 1) == BYTE_A && # rubocop:disable Style/SoleNestedConditional
                         value.getbyte(i + 2) == 114 && # 'r'
                         value.getbyte(i + 3) == BYTE_LPAREN
        end

        # Check for 'm' -> min( or max(
        if b == BYTE_M && i + 3 < len
          b2 = value.getbyte(i + 1)
          if (b2 == BYTE_I || b2 == BYTE_A) && value.getbyte(i + 2) == BYTE_N && value.getbyte(i + 3) == BYTE_LPAREN
            return true
          end
          if b2 == BYTE_A && value.getbyte(i + 2) == BYTE_X && value.getbyte(i + 3) == BYTE_LPAREN
            return true
          end
        end

        # Check for 'c' -> clamp(
        if b == BYTE_C && i + 5 < len
          return true if value.getbyte(i + 1) == BYTE_L && # rubocop:disable Style/SoleNestedConditional
                         value.getbyte(i + 2) == BYTE_A &&
                         value.getbyte(i + 3) == BYTE_M &&
                         value.getbyte(i + 4) == 112 && # 'p'
                         value.getbyte(i + 5) == BYTE_LPAREN
        end

        i += 1
      end

      false
    end

    # Convert value using getbyte() parsing instead of regex
    def convert_value(value, from, to, base_font_size, precision)
      len = value.bytesize
      return value if len == 0

      result = String.new(capacity: len + 20)
      from_str = from.to_s
      i = 0

      while i < len
        # Skip whitespace
        while i < len && is_whitespace?(value.getbyte(i))
          result << value.getbyte(i).chr
          i += 1
        end

        break if i >= len

        # Try to parse a number
        start = i
        number, unit, new_i = parse_number_with_unit(value, i, len)

        if number
          # Check if this token should be converted
          if unit == from_str || (number == 0.0 && unit.nil?)
            converted = convert_number(number, from, to, base_font_size)
            result << format_number(converted, to, precision)
          else
            # Not the unit we're looking for, copy as-is
            result << value.byteslice(start, new_i - start)
          end
          i = new_i
        else
          # Not a number, copy one byte and continue
          result << value.getbyte(i).chr
          i += 1
        end
      end

      result
    end

    # Parse number with optional unit using getbyte()
    # Returns [number, unit, new_position] or [nil, nil, position] if not a number
    def parse_number_with_unit(value, start, len)
      i = start

      # Optional sign
      if i < len && (value.getbyte(i) == BYTE_MINUS || value.getbyte(i) == BYTE_PLUS)
        i += 1
      end

      # Must have at least one digit or decimal point
      has_digits = false

      # Integer part
      while i < len && is_digit?(value.getbyte(i))
        has_digits = true
        i += 1
      end

      # Decimal point
      if i < len && value.getbyte(i) == BYTE_DOT
        i += 1

        # Fractional part
        while i < len && is_digit?(value.getbyte(i))
          has_digits = true
          i += 1
        end
      end

      # Must have found digits
      return [nil, nil, start] unless has_digits

      # Extract number
      number = value.byteslice(start, i - start).to_f

      # Try to parse unit (1-2 characters typically: px, em, in, cm, mm, pt, pc, rem)
      unit_start = i
      while i < len && is_alpha?(value.getbyte(i))
        i += 1
      end

      unit = nil
      if i > unit_start
        unit = value.byteslice(unit_start, i - unit_start)
      end

      [number, unit, i]
    end

    def is_whitespace?(byte)
      byte == BYTE_SPACE || byte == BYTE_TAB || byte == BYTE_NEWLINE || byte == BYTE_CR
    end

    def is_digit?(byte)
      byte >= BYTE_0 && byte <= BYTE_9
    end

    def is_alpha?(byte)
      (byte >= 97 && byte <= 122) || (byte >= 65 && byte <= 90) # a-z or A-Z
    end

    # Convert a numeric value from one unit to another
    def convert_number(number, from, to, base_font_size)
      return 0.0 if number.zero?

      from_sym = from.to_sym
      to_sym = to.to_sym

      # Convert from -> px -> to
      if from_sym == :rem || from_sym == :em
        px_value = number * base_font_size
      elsif ABSOLUTE_UNIT_TO_PX.key?(from_sym)
        px_value = number * ABSOLUTE_UNIT_TO_PX[from_sym]
      else
        raise ArgumentError, "Unknown source unit: #{from}"
      end

      # Convert px -> target unit
      if to_sym == :rem || to_sym == :em
        px_value / base_font_size
      elsif ABSOLUTE_UNIT_TO_PX.key?(to_sym)
        px_value / ABSOLUTE_UNIT_TO_PX[to_sym]
      else
        raise ArgumentError, "Unknown target unit: #{to}"
      end
    end

    # Format the converted number with appropriate precision
    def format_number(number, unit, precision)
      return '0' if number.zero?

      rounded = number.round(precision)

      # Check if integer first to avoid formatting entirely for common case
      int_value = rounded.to_i
      if rounded == int_value
        return "#{int_value}#{unit}"
      end

      # Strip trailing zeros and decimal point using getbyte() instead of regex
      # Avoids regex overhead which shows up in profiling
      formatted = format('%.10f', rounded)
      len = formatted.bytesize

      # Trim trailing zeros
      while len > 0 && formatted.getbyte(len - 1) == BYTE_0
        len -= 1
      end

      # Trim decimal point if that's all that's left
      if len > 0 && formatted.getbyte(len - 1) == BYTE_DOT
        len -= 1
      end

      formatted = formatted.byteslice(0, len)

      "#{formatted}#{unit}"
    end
  end

  # Include unit conversion methods into Stylesheet
  class Stylesheet
    include UnitConversion
  end
end
