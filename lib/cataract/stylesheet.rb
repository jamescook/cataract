module Cataract
  # Stylesheet wraps an array of parsed CSS rules
  # This is analogous to CssParser::Parser
  class Stylesheet
    include Enumerable

    attr_reader :rules

    def initialize(rules)
      @rules = rules
      @resolved = nil
      @serialized = nil
    end

    def each(&block)
      @rules.each(&block)
    end

    def to_s
      @serialized ||= serialize_to_css
    end

    # Add more CSS to this stylesheet
    def add_block!(css)
      new_rules = Cataract.parse_css_internal(css)
      @rules.concat(new_rules)
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

    private

    # Serialize stylesheet to CSS string
    def serialize_to_css
      # Merge duplicate selectors before serializing
      merged_rules = merge_duplicate_selectors

      # Pre-allocate string buffer
      result = String.new(capacity: merged_rules.length * 100)
      styles_by_media_types = {}

      # Group by media type (still need hash for grouping)
      merged_rules.each do |rule|
        rule.media_query.each do |media_type|
          (styles_by_media_types[media_type] ||= []) << rule
        end
      end

      # Build string directly without intermediate array
      styles_by_media_types.each_pair do |media_type, rules|
        media_block = (media_type != :all)
        result << "@media #{media_type} {\n" if media_block

        rules.each do |rule|
          decls_str = Cataract.declarations_to_s(rule.declarations)
          result << (media_block ? "  " : "")
          result << rule.selector << " { " << decls_str << " }\n"
        end

        result << "}\n" if media_block
      end

      result
    end

    # Merge rules with duplicate selectors
    # Returns array of Rule structs with unique selectors
    def merge_duplicate_selectors
      # Group rules by selector + media_query
      groups = {}
      @rules.each do |rule|
        # Use array as key [selector, media_query]
        key = [rule.selector, rule.media_query]
        (groups[key] ||= []) << rule
      end

      # Merge each group and create result rules
      groups.map do |(selector, media_query), group_rules|
        # Merge declarations for this group
        merged_declarations = Cataract.merge_rules(group_rules)

        # Create new Rule struct with merged declarations
        Cataract::Rule.new(
          selector,
          merged_declarations,
          group_rules.first.specificity,
          media_query
        )
      end
    end
  end
end
