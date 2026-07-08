# frozen_string_literal: true

# Pure Ruby CSS parser - Serialization
# NO REGEXP ALLOWED - char-by-char parsing only

module Cataract
  module Backends
    class PureImpl
      # Serializes one stylesheet's rules to a CSS string, compact or formatted.
      # One instance per #stylesheet_to_s / #stylesheet_to_formatted_s call - the
      # accumulating result, the rules/media being serialized, and the
      # compact-vs-formatted knobs all live on ivars instead of being threaded
      # through every helper as parameters.
      class Serializer
        def initialize(rules, charset, has_nesting, selector_lists, media_queries, media_query_lists, formatted:,
                       conditional_groups: [])
          @rules = rules
          @charset = charset
          @has_nesting = has_nesting
          @selector_lists = selector_lists || {}
          @media_queries = media_queries || []
          @media_query_lists = media_query_lists || {}
          @conditional_groups = conditional_groups || []
          @formatted = formatted
          @result = +''

          if formatted
            @opening_brace = " {\n"
            @closing_brace = "}\n"
            @media_indent = '  '
            @decl_indent_base = '  '
            @decl_indent_media = '    '
            @add_blank_lines = true
          else
            @opening_brace = ' { '
            @closing_brace = " }\n"
            @media_indent = ''
            @decl_indent_base = nil
            @decl_indent_media = nil
            @add_blank_lines = false
          end
        end

        # Serialize the stylesheet to a CSS string (compact or formatted,
        # depending on how this Serializer was constructed).
        #
        # @return [String] CSS string
        def to_s
          @result << "@charset \"#{@charset}\";\n" unless @charset.nil?

          build_mq_id_to_list_id!

          if @has_nesting
            @formatted ? serialize_with_nesting_formatted : serialize_with_nesting_compact
          else
            serialize_with_grouping
          end

          @result
        end

        private

        # Build reverse map: media_query_id => list_id (used by both the
        # nesting-aware and selector-list-grouping paths)
        def build_mq_id_to_list_id!
          @mq_id_to_list_id = {}
          @media_query_lists.each do |list_id, mq_ids|
            mq_ids.each { |mq_id| @mq_id_to_list_id[mq_id] = list_id }
          end
        end

        # Build id => rule lookup (used only by the selector-list-grouping
        # path). @rules is NOT guaranteed to satisfy rules[i].id == i here -
        # that invariant only holds for the full, freshly-parsed rules array;
        # Stylesheet#to_s(media: ...) passes a filtered subset whenever the
        # media filter isn't :all, so a plain array index would silently
        # fetch the wrong rule (or even an AtRule, which has no
        # #declarations) once any rule has been filtered out.
        def build_rules_by_id!
          @rules_by_id = {}
          @rules.each { |rule| @rules_by_id[rule.id] = rule }
        end

        # Build parent-child relationships (used only by the nesting-aware path)
        def build_rule_children!
          @rule_children = {}
          @rules.each do |rule|
            parent_rule_id = rule_parent_id(rule)
            next unless parent_rule_id

            parent_id = parent_rule_id.is_a?(Integer) ? parent_rule_id : parent_rule_id.to_i
            @rule_children[parent_id] ||= []
            @rule_children[parent_id] << rule
          end
        end

        # Read a rule's parent_rule_id, guarding against AtRule (which has no
        # such member - only Rule participates in CSS nesting, AtRule never is
        # nested via '&' nesting). Calling .parent_rule_id directly on an AtRule
        # raises NoMethodError.
        def rule_parent_id(rule)
          rule.is_a?(Rule) ? rule.parent_rule_id : nil
        end

        # Build media query string from a MediaQuery object or list.
        # @param media_query [MediaQuery] The MediaQuery object
        # @param media_query_list_id [Integer, nil] Optional list ID if this is part of a comma-separated list
        # @return [String] e.g. "screen", "screen, print", "screen and (min-width: 768px)"
        def build_media_query_string(media_query, media_query_list_id)
          if media_query_list_id
            mq_ids = @media_query_lists[media_query_list_id]
            mq_ids.map do |mq_id|
              mq = @media_queries[mq_id]
              if mq.conditions
                mq.type == :all ? mq.conditions : "#{mq.type} and #{mq.conditions}"
              else
                mq.type.to_s
              end
            end.join(', ')
          elsif media_query.conditions
            media_query.type == :all ? media_query.conditions : "#{media_query.type} and #{media_query.conditions}"
          else
            media_query.type.to_s
          end
        end

        # A rule's conditional-group wrapping chain, outermost first, found
        # by walking parent_id from its own conditional_group_id up to the
        # root. Only @supports currently populates conditional_group_id (see
        # the parser), but this walks whatever's there generically.
        #
        # @param conditional_group_id [Integer, nil]
        # @return [Array<ConditionalGroup>] empty if not in any conditional group
        def conditional_group_chain(conditional_group_id)
          chain = []
          id = conditional_group_id
          while id
            group = @conditional_groups[id]
            break unless group

            chain.unshift(group)
            id = group.parent_id
          end
          chain
        end

        # Reconcile the currently-open conditional-group blocks with the
        # ones a rule needs, like diffing two paths down a tree: close
        # whatever's open past where the chains diverge (innermost first),
        # then open whatever the target chain adds from that point on.
        # Nested entirely inside whatever media block is currently open
        # (conditional groups don't affect media context).
        #
        # @param current_chain [Array<ConditionalGroup>] currently-open chain, outermost first
        # @param target_chain [Array<ConditionalGroup>] the chain the next rule needs
        # @param indent [String]
        # @return [Array<ConditionalGroup>] target_chain, for the caller to track as current
        def sync_conditional_group_chain!(current_chain, target_chain, indent)
          common = 0
          common += 1 while common < current_chain.size && common < target_chain.size &&
                            current_chain[common].id == target_chain[common].id

          close_conditional_groups!(current_chain.size - common, indent)

          target_chain[common..].each do |group|
            @result << indent << "@#{group.type} #{group.condition} {\n"
          end

          target_chain
        end

        def close_conditional_groups!(count, indent)
          count.times { @result << indent << "}\n" }
        end

        # Does the rule's media query differ from the currently open media
        # block, requiring a new "@media ... {" to be opened? Comma-separated
        # lists are compared by list id; single queries are compared by content
        # (type + conditions), since two separately-parsed queries with the same
        # content should still be grouped under one block.
        def needs_new_media_block?(current_media_query, current_media_query_list_id, rule_media_query,
                                   rule_media_query_list_id)
          if rule_media_query_list_id
            current_media_query_list_id != rule_media_query_list_id
          else
            !current_media_query ||
              current_media_query.type != rule_media_query.type ||
              current_media_query.conditions != rule_media_query.conditions
          end
        end

        # ---- Nesting-aware path (has_nesting == true), compact format ----

        def serialize_with_nesting_compact
          build_rule_children!

          current_media_query_list_id = nil
          current_media_query = nil
          in_media_block = false

          @rules.each do |rule|
            next if rule_parent_id(rule)

            rule_media_query_id = rule.media_query_id
            rule_media_query = rule_media_query_id ? @media_queries[rule_media_query_id] : nil
            rule_media_query_list_id = rule_media_query_id ? @mq_id_to_list_id[rule_media_query_id] : nil

            if rule_media_query.nil?
              if in_media_block
                @result << "}\n"
                in_media_block = false
                current_media_query = nil
                current_media_query_list_id = nil
              end
            else
              needs_new_block = needs_new_media_block?(current_media_query, current_media_query_list_id,
                                                       rule_media_query, rule_media_query_list_id)

              if needs_new_block
                @result << "}\n" if in_media_block
                current_media_query = rule_media_query
                current_media_query_list_id = rule_media_query_list_id

                media_query_string = build_media_query_string(rule_media_query, rule_media_query_list_id)
                @result << "@media #{media_query_string} {\n"
                in_media_block = true
              end
            end

            serialize_rule_with_nesting(rule)
          end

          @result << "}\n" if in_media_block
        end

        def serialize_rule_with_nesting(rule)
          # AtRule can never have nested children of its own via @rule_children
          # (only Rule participates in CSS nesting), so it always serializes the
          # same way regardless of has_nesting.
          if rule.is_a?(AtRule)
            serialize_at_rule(rule)
            return
          end

          @result << "#{rule.selector} { "

          has_declarations = !rule.declarations.empty?
          serialize_declarations(rule.declarations) if has_declarations

          serialize_children(rule.selector, @rule_children[rule.id] || [], has_declarations)

          @result << " }\n"
        end

        # Recursively serialize a rule's nested children. CSS nesting can go as
        # deep as the parser allows (MAX_PARSE_DEPTH), so this recurses rather
        # than hand-unrolling a fixed number of levels - a nested rule's own
        # nested rules are found the same way its parent's were, via
        # @rule_children[id].
        def serialize_children(parent_selector, children, parent_has_declarations)
          children.each_with_index do |child, index|
            # Add space before nested content - always if the parent had
            # declarations, otherwise between nested rules (not before the first).
            @result << ' ' if parent_has_declarations || index > 0

            if child.nesting_style.nil? && child.media_query_id && @media_queries[child.media_query_id]
              # Nested @media rule (parent_rule_id present but nesting_style is nil)
              mq = @media_queries[child.media_query_id]
              media_query_string = build_media_query_string(mq, nil)
              @result << "@media #{media_query_string} { "
              serialize_declarations(child.declarations)

              media_children = @rule_children[child.id] || []
              media_children.each_with_index do |media_child, media_idx|
                @result << ' ' if media_idx > 0 || !child.declarations.empty?

                nested_media_selector = reconstruct_nested_selector(
                  child.selector, media_child.selector, media_child.nesting_style
                )

                @result << "#{nested_media_selector} { "
                serialize_declarations(media_child.declarations)
                @result << ' }'
              end

              @result << ' }'
            else
              # Regular nested selector - reconstruct it with & if needed
              nested_selector = reconstruct_nested_selector(parent_selector, child.selector, child.nesting_style)

              @result << "#{nested_selector} { "
              serialize_declarations(child.declarations)

              serialize_children(child.selector, @rule_children[child.id] || [], !child.declarations.empty?)

              @result << ' }'
            end
          end
        end

        # Reconstruct nested selector representation.
        # If nesting_style == 1 (explicit), try to use & notation.
        # If nesting_style == 0 (implicit), use plain selector.
        def reconstruct_nested_selector(parent_selector, child_selector, nesting_style)
          return child_selector if nesting_style.nil?

          if nesting_style == 1 # NESTING_STYLE_EXPLICIT
            # ".parent .child" with parent ".parent" => "& .child"
            # ".parent:hover" with parent ".parent" => "&:hover"
            if child_selector.start_with?(parent_selector)
              rest = child_selector[parent_selector.length..-1]
              return "&#{rest}"
            end
            # More complex cases like ".parent .foo .child"
            child_selector.sub(parent_selector, '&')
          else # NESTING_STYLE_IMPLICIT
            # ".parent .child" with parent ".parent" => ".child"
            if child_selector.start_with?(parent_selector)
              rest = child_selector[parent_selector.length..-1]
              return rest.lstrip
            end
            child_selector
          end
        end

        # ---- Selector-list-grouping path (has_nesting == false) ----
        # Shared between compact and formatted output - all formatting behavior
        # is controlled by ivars set in #initialize, so there's no mode-flag
        # kwarg pile to keep in sync.

        def serialize_with_grouping
          @processed_rule_ids = {}
          grouping_enabled = @selector_lists && !@selector_lists.empty?
          build_rules_by_id! if grouping_enabled

          current_media_query_list_id = nil
          current_media_query = nil
          in_media_block = false
          current_cg_chain = []
          rule_index = 0

          @rules.each do |rule|
            next if @processed_rule_ids[rule.id]

            rule_media_query_id = rule.media_query_id
            rule_media_query = rule_media_query_id ? @media_queries[rule_media_query_id] : nil
            rule_media_query_list_id = rule_media_query_id ? @mq_id_to_list_id[rule_media_query_id] : nil
            is_first_rule = (rule_index == 0)
            rule_cg_chain = conditional_group_chain(rule.conditional_group_id)

            if rule_media_query.nil?
              if in_media_block
                current_cg_chain = sync_conditional_group_chain!(current_cg_chain, [], @media_indent)
                @result << "}\n"
                in_media_block = false
                current_media_query = nil
                current_media_query_list_id = nil
              end

              @result << "\n" if @add_blank_lines && !is_first_rule

              current_cg_chain = sync_conditional_group_chain!(current_cg_chain, rule_cg_chain, '')
              indent = current_cg_chain.empty? ? '' : @media_indent

              if grouping_enabled && rule.is_a?(Rule) && rule.selector_list_id
                selectors = find_groupable_selectors(rule, rule_media_query_id)

                @result << indent << selectors.join(', ') << @opening_brace
                if @decl_indent_base
                  serialize_declarations_formatted(rule.declarations, @decl_indent_base)
                else
                  serialize_declarations(rule.declarations)
                end
                @result << indent << @closing_brace
              else
                if @decl_indent_base
                  serialize_rule_formatted(rule, indent, true)
                else
                  serialize_rule(rule)
                end
                @processed_rule_ids[rule.id] = true
              end
            else
              needs_new_block = needs_new_media_block?(current_media_query, current_media_query_list_id,
                                                       rule_media_query, rule_media_query_list_id)

              if needs_new_block
                current_cg_chain = sync_conditional_group_chain!(current_cg_chain, [], @media_indent)
                @result << "}\n" if in_media_block
                @result << "\n" if @add_blank_lines && !is_first_rule

                current_media_query = rule_media_query
                current_media_query_list_id = rule_media_query_list_id

                media_query_string = build_media_query_string(rule_media_query, rule_media_query_list_id)
                @result << "@media #{media_query_string} {\n"
                in_media_block = true
              end

              current_cg_chain = sync_conditional_group_chain!(current_cg_chain, rule_cg_chain, @media_indent)

              if grouping_enabled && rule.is_a?(Rule) && rule.selector_list_id
                selectors = find_groupable_selectors(rule, rule_media_query_id)

                @result << @media_indent << selectors.join(', ') << @opening_brace
                if @decl_indent_media
                  serialize_declarations_formatted(rule.declarations, @decl_indent_media)
                else
                  serialize_declarations(rule.declarations)
                end
                @result << @media_indent << @closing_brace
              else
                if @decl_indent_media
                  serialize_rule_formatted(rule, @media_indent, true)
                else
                  serialize_rule(rule)
                end
                @processed_rule_ids[rule.id] = true
              end
            end

            rule_index += 1
          end

          close_conditional_groups!(current_cg_chain.size, in_media_block ? @media_indent : '')

          @result << "}\n" if in_media_block
        end

        # Find all selectors from the same selector list with matching
        # declarations (and the same media context). Returns the array of
        # selectors that can be grouped, marking them processed as it goes.
        def find_groupable_selectors(rule, current_media_query_id)
          list_id = rule.selector_list_id
          rule_ids_in_list = @selector_lists[list_id]

          if rule_ids_in_list.nil? || rule_ids_in_list.size <= 1
            @processed_rule_ids[rule.id] = true
            return [rule.selector]
          end

          matching_selectors = []
          rule_ids_in_list.each do |rid|
            other_rule = @rules_by_id[rid]
            next unless other_rule
            next if @processed_rule_ids[rid]
            next if other_rule.media_query_id != current_media_query_id

            if declarations_equal?(rule.declarations, other_rule.declarations)
              matching_selectors << other_rule.selector
              @processed_rule_ids[rid] = true
            end
          end

          matching_selectors
        end

        def declarations_equal?(decls1, decls2)
          return false if decls1.size != decls2.size

          decls1.each_with_index do |d1, i|
            d2 = decls2[i]
            return false if d1.property != d2.property
            return false if d1.value != d2.value
            return false if d1.important != d2.important
          end

          true
        end

        def serialize_rule(rule)
          if rule.is_a?(AtRule)
            serialize_at_rule(rule)
            return
          end

          @result << "#{rule.selector} { "
          serialize_declarations(rule.declarations)
          @result << " }\n"
        end

        # Declarations, compact (single line)
        def serialize_declarations(declarations)
          declarations.each_with_index do |decl, i|
            important_suffix = decl.important ? ' !important;' : ';'
            separator = i < declarations.length - 1 ? ' ' : ''
            @result << "#{decl.property}: #{decl.value}#{important_suffix}#{separator}"
          end
        end

        # Declarations, formatted (one per line)
        def serialize_declarations_formatted(declarations, indent)
          declarations.each do |decl|
            @result << indent
            @result << decl.property
            @result << ': '
            @result << decl.value
            @result << ' !important' if decl.important
            @result << ";\n"
          end
        end

        # An at-rule (@keyframes, @font-face, etc), compact
        def serialize_at_rule(at_rule)
          @result << "#{at_rule.selector} {\n"

          if at_rule.content.length > 0
            first = at_rule.content[0]

            if first.is_a?(Rule)
              at_rule.content.each do |nested_rule|
                @result << "  #{nested_rule.selector} { "
                serialize_declarations(nested_rule.declarations)
                @result << " }\n"
              end
            else
              @result << '  '
              serialize_declarations(at_rule.content)
              @result << "\n"
            end
          end

          @result << "}\n"
        end

        # ---- Nesting-aware path (has_nesting == true), formatted ----

        def serialize_with_nesting_formatted
          build_rule_children!

          current_media_query_list_id = nil
          current_media_query = nil
          in_media_block = false

          @rules.each do |rule|
            next if rule_parent_id(rule)

            rule_media_query_id = rule.media_query_id
            rule_media_query = rule_media_query_id ? @media_queries[rule_media_query_id] : nil
            rule_media_query_list_id = rule_media_query_id ? @mq_id_to_list_id[rule_media_query_id] : nil

            if rule_media_query.nil?
              if in_media_block
                @result << "}\n"
                in_media_block = false
                current_media_query = nil
                current_media_query_list_id = nil
              end

              # Blank line before a base rule if we just closed a media block (ends with "}\n")
              if @result.length > 1 && @result.getbyte(-1) == BYTE_NEWLINE && @result.getbyte(-2) == BYTE_RBRACE
                @result << "\n"
              end

              serialize_rule_with_nesting_formatted(rule, '')
            else
              needs_new_block = needs_new_media_block?(current_media_query, current_media_query_list_id,
                                                       rule_media_query, rule_media_query_list_id)

              if needs_new_block
                if in_media_block
                  @result << "}\n"
                elsif @result.length > 0
                  @result << "\n"
                end
                current_media_query = rule_media_query
                current_media_query_list_id = rule_media_query_list_id
                media_query_string = build_media_query_string(rule_media_query, rule_media_query_list_id)
                @result << "@media #{media_query_string} {\n"
                in_media_block = true
              end

              serialize_rule_with_nesting_formatted(rule, '  ')
            end
          end

          @result << "}\n" if in_media_block
        end

        def serialize_rule_with_nesting_formatted(rule, indent)
          if rule.is_a?(AtRule)
            serialize_at_rule_formatted(rule, indent)
            return
          end

          @result << indent
          @result << rule.selector
          @result << " {\n"

          serialize_declarations_formatted(rule.declarations, "#{indent}  ") unless rule.declarations.empty?

          serialize_children_formatted(rule.selector, @rule_children[rule.id] || [], "#{indent}  ")

          @result << indent
          @result << "}\n"
        end

        # Recursively serialize a rule's nested children with indentation. CSS
        # nesting can go as deep as the parser allows (MAX_PARSE_DEPTH), so this
        # recurses rather than hand-unrolling a fixed number of levels - a nested
        # rule's own nested rules are found the same way its parent's were, via
        # @rule_children[id], with the indent growing by one level each call.
        def serialize_children_formatted(parent_selector, children, indent)
          children.each do |child|
            if child.nesting_style.nil? && child.media_query_id && @media_queries[child.media_query_id]
              mq = @media_queries[child.media_query_id]
              media_query_string = build_media_query_string(mq, nil)
              @result << indent
              @result << "@media #{media_query_string} {\n"

              serialize_declarations_formatted(child.declarations, "#{indent}  ") unless child.declarations.empty?

              media_children = @rule_children[child.id] || []
              media_children.each do |media_child|
                nested_media_selector = reconstruct_nested_selector(
                  child.selector, media_child.selector, media_child.nesting_style
                )

                @result << indent
                @result << "  #{nested_media_selector} {\n"
                unless media_child.declarations.empty?
                  serialize_declarations_formatted(media_child.declarations, "#{indent}    ")
                end
                @result << indent
                @result << "  }\n"
              end

              @result << indent
              @result << "}\n"
            else
              nested_selector = reconstruct_nested_selector(parent_selector, child.selector, child.nesting_style)

              @result << indent
              @result << "#{nested_selector} {\n"

              serialize_declarations_formatted(child.declarations, "#{indent}  ") unless child.declarations.empty?

              serialize_children_formatted(child.selector, @rule_children[child.id] || [], "#{indent}  ")

              @result << indent
              @result << "}\n"
            end
          end
        end

        def serialize_rule_formatted(rule, indent, is_last_rule = false)
          if rule.is_a?(AtRule)
            serialize_at_rule_formatted(rule, indent)
            return
          end

          @result << indent
          @result << rule.selector
          @result << " {\n"

          serialize_declarations_formatted(rule.declarations, "#{indent}  ")

          # Closing brace - double newline for all except last rule
          @result << indent
          @result << (is_last_rule ? "}\n" : "}\n\n")
        end

        def serialize_at_rule_formatted(at_rule, indent)
          @result << indent
          @result << at_rule.selector
          @result << " {\n"

          if at_rule.content.length > 0
            first = at_rule.content[0]

            if first.is_a?(Rule)
              at_rule.content.each do |nested_rule|
                @result << indent
                @result << '  '
                @result << nested_rule.selector
                @result << " {\n"

                serialize_declarations_formatted(nested_rule.declarations, "#{indent}    ")

                @result << indent
                @result << "  }\n"
              end
            else
              serialize_declarations_formatted(at_rule.content, "#{indent}  ")
            end
          end

          @result << indent
          @result << "}\n"
        end
      end

      # Serialize stylesheet to compact CSS string.
      #
      # @param rules [Array<Rule>] Array of rules
      # @param charset [String, nil] @charset value
      # @param has_nesting [Boolean] Whether any nested rules exist
      # @param selector_lists [Hash] Selector list ID => array of rule IDs (for grouping)
      # @param media_queries [Array<MediaQuery>] Array of MediaQuery objects
      # @param media_query_lists [Hash] List ID => array of MediaQuery IDs (for comma-separated queries)
      # @param conditional_groups [Array<ConditionalGroup>] Array of ConditionalGroup objects (@supports/@layer/@container/@scope)
      # @return [String] Compact CSS string
      def stylesheet_to_s(rules, charset, has_nesting, selector_lists = {}, media_queries = [], media_query_lists = {},
                          conditional_groups = [])
        Serializer.new(rules, charset, has_nesting, selector_lists, media_queries, media_query_lists,
                       formatted: false, conditional_groups: conditional_groups).to_s
      end

      # Serialize stylesheet to formatted CSS string (with indentation).
      #
      # @param rules [Array<Rule>] Array of rules
      # @param charset [String, nil] @charset value
      # @param has_nesting [Boolean] Whether any nested rules exist
      # @param selector_lists [Hash] Selector list ID => array of rule IDs (for grouping)
      # @param media_queries [Array<MediaQuery>] Array of MediaQuery objects
      # @param media_query_lists [Hash] List ID => array of MediaQuery IDs (for comma-separated queries)
      # @param conditional_groups [Array<ConditionalGroup>] Array of ConditionalGroup objects (@supports/@layer/@container/@scope)
      # @return [String] Formatted CSS string
      def stylesheet_to_formatted_s(rules, charset, has_nesting, selector_lists = {}, media_queries = [],
                                    media_query_lists = {}, conditional_groups = [])
        Serializer.new(rules, charset, has_nesting, selector_lists, media_queries, media_query_lists,
                       formatted: true, conditional_groups: conditional_groups).to_s
      end
    end
  end
end
