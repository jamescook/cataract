module Cataract
  # Stylesheet wraps an array of parsed CSS rules
  # This is analogous to CssParser::Parser
  class Stylesheet
    include Enumerable

    attr_reader :rules

    def initialize(rules)
      @rules = rules
      @resolved = nil
    end

    def each(&block)
      @rules.each(&block)
    end

    def to_s
      Cataract.rules_to_s(@rules)
    end

    # Add more CSS to this stylesheet
    def add_block!(css)
      new_rules = Cataract.parse_css_internal(css)
      @rules.concat(new_rules)
      @resolved = nil
      self
    end

    def declarations
      @resolved ||= Cataract.apply_cascade(@rules)
    end

    # Iterate over each selector across all rules
    # Yields: selector, declarations_string, specificity, media_types
    def each_selector(media_types = :all)
      return enum_for(:each_selector, media_types) unless block_given?

      @rules.each do |rule|
        # TODO: Filter by media_types if not :all
        # For now, yield all rules
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
