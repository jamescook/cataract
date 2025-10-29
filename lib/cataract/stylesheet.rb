module Cataract
  # Stylesheet wraps parsed CSS rules grouped by media query
  # Structure: {query_string => {media_types: [...], rules: [...]}}
  # This is analogous to CssParser::Parser
  class Stylesheet
    include Enumerable

    attr_reader :rule_groups, :charset

    def initialize(rule_groups, charset = nil)
      @rule_groups = rule_groups  # Hash: {query_string => {media_types: [...], rules: [...]}}
      @charset = charset
      @resolved = nil
      @serialized = nil
    end

    # Iterate over all rules across all media query groups
    def each(&block)
      return enum_for(:each) unless block_given?
      @rule_groups.each_value do |group|
        group[:rules].each(&block)
      end
    end

    # Alias for compatibility
    def rules
      each
    end

    def to_s
      # TODO: Use C implementation once stylesheet_to_s_c is updated for new structure
      # For now, use Ruby implementation with merging
      out = []

      # Emit @charset first if present (must be first per W3C spec)
      if @charset
        out << "@charset \"#{@charset}\";"
      end

      @rule_groups.each do |query_string, group|
        # Group rules by selector within this media query group
        rules_by_selector = {}
        group[:rules].each do |rule|
          rules_by_selector[rule.selector] ||= []
          rules_by_selector[rule.selector] << rule
        end

        # Merge rules with the same selector
        merged_rules = rules_by_selector.map do |selector, rules|
          if rules.length == 1
            rules.first
          else
            # Multiple rules with same selector - merge them
            merged_decls = Cataract.merge_rules(rules)
            Cataract::Rule.new(selector, merged_decls, rules.first.specificity)
          end
        end

        if query_string.nil?
          # No media query - output rules directly
          merged_rules.each do |rule|
            decls_str = Cataract.declarations_to_s(rule.declarations)
            out << "#{rule.selector} { #{decls_str} }"
          end
        else
          # Has media query - output all rules in single @media block
          out << "@media #{query_string} {"
          merged_rules.each do |rule|
            decls_str = Cataract.declarations_to_s(rule.declarations)
            out << "  #{rule.selector} { #{decls_str} }"
          end
          out << "}"
        end
      end

      out.join("\n")
    end

    # Add more CSS to this stylesheet
    def add_block!(css)
      result = Cataract.parse_css_internal(css)
      # parse_css_internal returns {rules: {query_string => {media_types: [...], rules: [...]}}, charset: "..." | nil}
      # Merge rule groups
      result[:rules].each do |query_string, new_group|
        existing_group = @rule_groups[query_string]
        if existing_group
          # Merge rules arrays
          existing_group[:rules].concat(new_group[:rules])
        else
          @rule_groups[query_string] = new_group
        end
      end
      @resolved = nil
      @serialized = nil
      self
    end

    def declarations
      # Flatten all rules for cascade
      all_rules = []
      @rule_groups.each_value { |group| all_rules.concat(group[:rules]) }
      @resolved ||= Cataract.apply_cascade(all_rules)
    end

    # Iterate over each selector across all rules
    # Yields: selector, declarations_string, specificity, media_types
    def each_selector(media_types = :all)
      return enum_for(:each_selector, media_types) unless block_given?

      query_media_types = Array(media_types).map(&:to_sym)

      @rule_groups.each do |query_string, group|
        # Filter by media types at group level
        group_media_types = group[:media_types] || []

        # :all matches everything
        # But specific media queries (like :screen, :print) should NOT match [:all] groups
        if query_media_types.include?(:all)
          # :all means iterate everything
          should_include = true
        elsif group_media_types.include?(:all)
          # Group is universal (no media query) - only include if querying for :all
          should_include = false
        else
          # Check for intersection
          should_include = !(group_media_types & query_media_types).empty?
        end

        next unless should_include

        group[:rules].each do |rule|
          declarations_str = rule.declarations.map do |decl|
            val = decl.important ? "#{decl.value} !important" : decl.value
            "#{decl.property}: #{val}"
          end.join("; ")

          # Return the group's media_types, not from the rule
          yield rule.selector, declarations_str, rule.specificity, group[:media_types]
        end
      end
    end

    def size
      @rule_groups.values.sum { |group| group[:rules].length }
    end
    alias_method :length, :size

    def empty?
      @rule_groups.empty? || @rule_groups.values.all? { |group| group[:rules].empty? }
    end

    def inspect
      total_rules = size
      if total_rules == 0
        "#<Cataract::Stylesheet empty>"
      else
        # Get first 3 rules across all groups
        preview_rules = []
        @rule_groups.each_value do |group|
          preview_rules.concat(group[:rules])
          break if preview_rules.length >= 3
        end
        preview = preview_rules.first(3).map { |r| r.selector }.join(", ")
        more = total_rules > 3 ? ", ..." : ""
        resolved_info = @resolved ? ", #{@resolved.length} declarations resolved" : ""
        "#<Cataract::Stylesheet #{total_rules} rules: #{preview}#{more}#{resolved_info}>"
      end
    end
  end
end
