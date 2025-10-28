module Cataract
  # Stylesheet wraps an array of parsed CSS rules
  # This is analogous to CssParser::Parser
  class Stylesheet
    include Enumerable

    attr_reader :rules, :charset

    def initialize(rules, charset = nil)
      @rules = rules
      @charset = charset
      @resolved = nil
      @serialized = nil
    end

    def each(&block)
      @rules.each(&block)
    end

    def to_s
      @serialized ||= Cataract.stylesheet_to_s_c(@rules, @charset)
    end

    # Add more CSS to this stylesheet
    def add_block!(css)
      result = Cataract.parse_css_internal(css)
      # parse_css_internal returns {rules: [...], charset: "..." | nil}
      @rules.concat(result[:rules])
      @resolved = nil
      @serialized = nil
      self
    end

    def declarations
      @resolved ||= Cataract.apply_cascade(@rules)
    end

    # Iterate over each selector across all rules
    # Yields: selector, declarations_string, specificity, media_types
    def each_selector(media_types = :all)
      return enum_for(:each_selector, media_types) unless block_given?

      media_array = Array(media_types).map(&:to_sym)

      @rules.each do |rule|
        # Filter by media types using the same logic as Rule#applies_to_media?
        next unless rule.applies_to_media?(media_array)

        declarations_str = rule.declarations.map do |decl|
          val = decl.important ? "#{decl.value} !important" : decl.value
          "#{decl.property}: #{val}"
        end.join("; ")

        yield rule.selector, declarations_str, rule.specificity, rule.media_query
      end
    end

    def size
      @rules.length
    end
    alias_method :length, :size

    def empty?
      @rules.empty?
    end

    def inspect
      if @rules.empty?
        "#<Cataract::Stylesheet empty>"
      else
        preview = @rules.first(3).map { |r| r.selector }.join(", ")
        more = @rules.length > 3 ? ", ..." : ""
        resolved_info = @resolved ? ", #{@resolved.length} declarations resolved" : ""
        "#<Cataract::Stylesheet #{@rules.length} rules: #{preview}#{more}#{resolved_info}>"
      end
    end
  end
end
