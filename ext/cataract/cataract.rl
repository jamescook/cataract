#include <ruby.h>
#include <stdio.h>

// Uncomment to enable debug output (adds overhead, use only for development)
// #define CATARACT_DEBUG 1

#ifdef CATARACT_DEBUG
  #define DEBUG_PRINTF(...) printf(__VA_ARGS__)
#else
  #define DEBUG_PRINTF(...) ((void)0)
#endif

%%{
  machine css_parser;
  
  # Actions that build Ruby objects
  action mark_start {
    mark = p;
    DEBUG_PRINTF("[@media] mark_start: mark set to %ld\n", mark - RSTRING_PTR(css_string));
  }
  action mark_prop { prop_mark = p; }
  action mark_val { val_mark = p; }
  action mark_media { media_mark = p; }

  action start_compound_selector {
    // Mark the start of a compound selector
    // Uses global 'mark' variable (safe since selectors don't overlap with @media content extraction)
    mark = p;
    DEBUG_PRINTF("[selector] start_compound_selector: mark=%ld\n", mark - RSTRING_PTR(css_string));
  }

  action capture_compound_selector {
    // Capture the entire compound selector when we've reached the end
    // Using @ (finishing) operator ensures this only fires when reaching specific end tokens
    // (comma or opening brace), not in the middle of the compound selector
    if (mark != NULL) {
      // Strip trailing whitespace by finding the last non-whitespace character
      const char *end = p;
      while (end > mark && (*(end-1) == ' ' || *(end-1) == '\t' || *(end-1) == '\n' || *(end-1) == '\r')) {
        end--;
      }
      selector = rb_str_new(mark, end - mark);
      DEBUG_PRINTF("[selector] capture_compound_selector: '%s' at p=%ld\n", RSTRING_PTR(selector), p - RSTRING_PTR(css_string));
      if (NIL_P(current_selectors)) {
        current_selectors = rb_ary_new();
      }
      rb_ary_push(current_selectors, selector);
      // Reset mark to NULL so we don't capture again on subsequent @ firings
      mark = NULL;
    }
  }

  action reset_for_next_selector {
    // Reset mark when starting a new selector after comma
    mark = NULL;
    DEBUG_PRINTF("[selector] reset_for_next_selector\n");
  }

  action capture_media_type {
    // Convert media type string directly to symbol
    ID media_id = rb_intern2(media_mark, p - media_mark);
    VALUE media_sym = ID2SYM(media_id);
    rb_ary_push(current_media_types, media_sym);
    DEBUG_PRINTF("[@media] captured media type: %.*s\n", (int)(p - media_mark), media_mark);
  }

  action init_depth {
    brace_depth = 1;  // We just entered the opening brace
    // Save the position of the opening '{' for @media content extraction
    // Since this is a $ (all transition) action, p is at the '{'
    media_content_start = p;
    DEBUG_PRINTF("[@media] init_depth: depth=%d at pos=%ld, media_content_start=%ld char='%c'\n", brace_depth, p - RSTRING_PTR(css_string), media_content_start - RSTRING_PTR(css_string), *p);
  }

  action inc_depth {
    brace_depth++;
    DEBUG_PRINTF("[@media] inc_depth: depth=%d at pos=%ld char='%c'\n", brace_depth, p - RSTRING_PTR(css_string), *p);
  }

  action dec_depth {
    brace_depth--;
    DEBUG_PRINTF("[@media] dec_depth: depth=%d at pos=%ld char='%c'\n", brace_depth, p - RSTRING_PTR(css_string), *p);
    if (brace_depth == 0) {
      // We've found the matching closing brace
      // Extract content between the braces (media_content_start points to '{', p points to '}')
      DEBUG_PRINTF("[@media] Matched closing brace at media_content_start=%ld p=%ld\n", media_content_start - RSTRING_PTR(css_string), p - RSTRING_PTR(css_string));

      VALUE media_content_str = rb_str_new(media_content_start + 1, p - media_content_start - 1);
      DEBUG_PRINTF("[@media] Content to parse: %s\n", RSTRING_PTR(media_content_str));

      // Recursively parse the content
      VALUE inner_rules = parse_css(Qnil, media_content_str);
      DEBUG_PRINTF("[@media] Parsed %ld inner rules\n", RARRAY_LEN(inner_rules));

      // Add media types to all inner rules
      if (!NIL_P(current_media_types) && RARRAY_LEN(current_media_types) > 0) {
        long len = RARRAY_LEN(inner_rules);
        for (long i = 0; i < len; i++) {
          VALUE rule = RARRAY_AREF(inner_rules, i);
          rb_hash_aset(rule, ID2SYM(rb_intern("media_types")), rb_ary_dup(current_media_types));
        }
      }

      // Add all inner rules to the main rules array
      // Manual iteration is faster than rb_funcall(concat)
      long inner_len = RARRAY_LEN(inner_rules);
      for (long i = 0; i < inner_len; i++) {
        rb_ary_push(rules_array, RARRAY_AREF(inner_rules, i));
      }

      current_media_types = Qnil;
      inside_media_block = 0;  // Clear flag when done with media block
      // Use fgoto to jump back to main state and continue parsing
      fgoto main;
    }
  }

  action start_media_block {
    // Initialize media types array for this block
    current_media_types = rb_ary_new();
    // Clear any partially-matched selectors/declarations from outer parse
    // This prevents spurious rules from being created while scanning media content
    current_selectors = Qnil;
    current_declarations = Qnil;
    // Set flag to prevent outer parse from creating rules while scanning media content
    inside_media_block = 1;
    DEBUG_PRINTF("[@media] start_media_block: captured %ld media types\n", RARRAY_LEN(current_media_types));
  }

  action capture_property {
    property = rb_str_new(prop_mark, p - prop_mark);
  }

  action capture_value {
    // Strip leading and trailing whitespace from value at C level (avoids rb_funcall overhead)
    const char *start = val_mark;
    const char *end = p;

    // Strip leading whitespace
    while (start < end && (*start == ' ' || *start == '\t' || *start == '\n' || *start == '\r')) {
      start++;
    }

    // Strip trailing whitespace
    while (end > start && (*(end-1) == ' ' || *(end-1) == '\t' || *(end-1) == '\n' || *(end-1) == '\r')) {
      end--;
    }

    value = rb_str_new(start, end - start);
  }

  action finish_declaration {
    if (NIL_P(current_declarations)) {
      current_declarations = rb_hash_new();
    }
    rb_hash_aset(current_declarations, property, value);
  }

  action finish_rule {
    // Skip if we're scanning media block content (will be parsed recursively)
    if (!inside_media_block) {
      // Create one rule for each selector in the list
      if (!NIL_P(current_selectors) && !NIL_P(current_declarations)) {
        long len = RARRAY_LEN(current_selectors);
        DEBUG_PRINTF("[finish_rule] Creating %ld rule(s)\n", len);
        for (long i = 0; i < len; i++) {
          VALUE sel = RARRAY_AREF(current_selectors, i);
          DEBUG_PRINTF("[finish_rule] Rule %ld: selector='%s'\n", i, RSTRING_PTR(sel));
          VALUE rule = rb_hash_new();
          rb_hash_aset(rule, ID2SYM(rb_intern("selector")), sel);
          rb_hash_aset(rule, ID2SYM(rb_intern("declarations")), rb_hash_dup(current_declarations));

          // Add media types if we're inside a @media block
          if (!NIL_P(current_media_types) && RARRAY_LEN(current_media_types) > 0) {
            rb_hash_aset(rule, ID2SYM(rb_intern("media_types")), rb_ary_dup(current_media_types));
            DEBUG_PRINTF("[finish_rule] Added media types to rule\n");
          }

          rb_ary_push(rules_array, rule);
        }
      }
    } else {
      DEBUG_PRINTF("[finish_rule] SKIPPED (inside media block)\n");
    }
    current_selectors = Qnil;
    current_declarations = Qnil;
    // Reset mark for next rule (in case it wasn't reset by capture action)
    mark = NULL;
  }
  
  # ============================================================================
  # BASIC TOKENS (CSS1)
  # ============================================================================
  ws = [ \t\n\r];
  comment = '/*' any* '*/';
  ident = alpha (alpha | digit | '-')*;
  number = digit+ ('.' digit+)?;
  dstring = '"' (any - '"')* '"';
  sstring = "'" (any - "'")* "'";
  string = dstring | sstring;

  # ============================================================================
  # VALUES (CSS1)
  # ============================================================================
  # Simple value that captures everything until ; or }
  # This is intentionally permissive - we don't validate value syntax
  value = (any - [;}])+;

  # CSS1/2/3: Value syntax is validated by browsers, not by this parser
  # We capture the raw string and let the browser handle validation

  # ============================================================================
  # SELECTORS
  # ============================================================================

  # CSS1/CSS2 Selector Components (building blocks - no actions)
  class_part = '.' ident;
  id_part = '#' ident;
  type_part = ident;
  universal_part = '*';

  # CSS2 Attribute Selectors
  # CSS2: [attr], [attr=value], [attr~=value], [attr|=value]
  # CSS3: TODO - Add ^=, $=, *= operators
  attr_operator = '=' | '~=' | '|=';
  attr_part = '[' ws* ident ws* (attr_operator ws* (ident | string) ws*)? ']';

  # Simple selector sequence: optional type/universal, followed by class/id/attr modifiers
  # Examples: div, div.class, div#id, .class, #id, [attr], *.class
  # The key insight: order matters in alternation (|). Put more specific patterns first.
  # Type/universal with modifiers should match before standalone modifiers
  simple_selector_sequence =
    (type_part | universal_part) (class_part | id_part | attr_part)* |
    (class_part | id_part | attr_part)+;

  # CSS2 Combinators (have zero specificity)
  child_combinator = ws* '>' ws*;
  adjacent_sibling_combinator = ws* '+' ws*;
  general_sibling_combinator = ws* '~' ws*;
  descendant_combinator = ws+;
  combinator = child_combinator | adjacent_sibling_combinator | general_sibling_combinator | descendant_combinator;

  # Compound selector: simple selectors connected by combinators
  # Examples: div p, div > p, h1 + p, div.container > p.intro
  #
  # CRITICAL: Capturing compound selectors requires careful action placement
  # Problem: The leaving operator (%) fires on EVERY leaving transition in the pattern,
  #          not just once at the end. For "div > p", % fires when leaving "div" AND when leaving "p".
  #
  # Solution: Use @ (finishing) operator which fires ONLY on transitions to final states:
  #   1. Mark start with > (entering) operator when entering compound_selector
  #   2. Capture with @ (finishing) operator on tokens that END a selector (comma ',' or opening brace '{')
  #   3. Strip trailing whitespace from captured selectors (occurs before '{')
  #   4. Reset mark after comma to prepare for next selector in list
  #
  # This ensures "div > p" is captured as one string after the entire pattern matches,
  # not as "div" and "p" separately.
  compound_selector = simple_selector_sequence (combinator simple_selector_sequence)*;

  # CSS1 Selector Lists (comma-separated compound selectors)
  # Use @ operator on ',' and '{' to capture only when compound_selector is truly complete
  selector_list = compound_selector >start_compound_selector (ws* ',' @capture_compound_selector ws* >reset_for_next_selector compound_selector >start_compound_selector)* ws*;

  # CSS1: TODO - Add pseudo-classes (:link, :visited, :active)
  # CSS2: ✓ Universal selector (*) - IMPLEMENTED
  # CSS2: ✓ Combinators (>, +, ~, descendant space) - IMPLEMENTED
  # CSS2: TODO - Add pseudo-classes (:hover, :focus, :first-child, :lang())
  # CSS2: TODO - Add pseudo-elements (::before, ::after, ::first-line, ::first-letter)
  # CSS3: TODO - Add structural pseudo-classes (:nth-child(), :nth-of-type(), etc.)
  # CSS3: TODO - Add UI pseudo-classes (:enabled, :disabled, :checked)
  # CSS3: TODO - Add negation pseudo-class (:not())

  # ============================================================================
  # DECLARATIONS (CSS1)
  # ============================================================================
  property = ident >mark_prop %capture_property;
  declaration = property ws* ':' ws* (value >mark_val %capture_value) %finish_declaration;
  declaration_list = declaration (ws* ';' ws* declaration)* (ws* ';')?;

  # CSS2: TODO - Add !important flag parsing (currently handled in Ruby layer)

  # ============================================================================
  # RULES (CSS1)
  # ============================================================================
  rule_body = '{' @capture_compound_selector ws* declaration_list ws* '}' %finish_rule;
  rule = selector_list rule_body;

  # ============================================================================
  # AT-RULES (CSS2)
  # ============================================================================

  # @media Rules - Implementation Notes and Pitfalls
  # ================================================
  #
  # CRITICAL: The @ symbol in Ragel is a special operator (finishing transition)
  # Use [@] character class for literal @ matching, NOT '@' or '\@' or "\@"
  #
  # Architecture:
  # 1. Parse @media TYPE_LIST { ... } by counting brace depth
  # 2. Extract content between braces as a substring
  # 3. Recursively call parse_css() on the extracted content
  # 4. Tag all inner rules with media_types array
  # 5. Use fgoto main to continue parsing after the media block
  #
  # Key Variables:
  # - brace_depth: Tracks nesting level (starts at 1 when entering opening '{')
  # - media_content_start: Position of opening '{' (for content extraction)
  # - inside_media_block: Flag to prevent spurious rule creation during scan
  #
  # Pitfalls Encountered & Solutions:
  #
  # 1. PITFALL: Using '@' or '\@' instead of [@]
  #    REASON: @ is Ragel finishing transition operator (see operator precedence)
  #    SOLUTION: Use character class [@] for literal @ symbol
  #
  # 2. PITFALL: Variable collision - reusing 'mark' variable
  #    REASON: mark is used by selector capture, conflicts with media content extraction
  #    SOLUTION: Use dedicated media_content_start variable for @media blocks
  #
  # 3. PITFALL: Spurious "y" selector appearing in results
  #    REASON: While scanning media_char*, the outer state machine ALSO tries to
  #            match type_sel pattern, triggering >mark_start and %capture_selector
  #            actions on characters inside the media block (e.g., "body" -> captures "y")
  #    SOLUTION: Set inside_media_block=1 flag and guard finish_rule action to skip
  #              rule creation when flag is set. Clear flag after media block completes.
  #
  # 4. PITFALL: Using fbreak stops entire parse, missing rules after @media block
  #    REASON: fbreak exits the %% write exec loop entirely, not just media_content
  #    ATTEMPTED: Removing fbreak -> media_char* keeps matching, hits next '{',
  #               increments depth again, parses wrong content
  #    SOLUTION: Use 'fgoto main' instead of 'fbreak' to jump back to main state
  #              and continue parsing from current position
  #
  # 5. PITFALL: Recursive parse_css() shares C function variables
  #    REASON: Inner call modifies mark, current_selectors, etc. from outer call
  #    SOLUTION: Clear current_selectors/current_declarations in start_media_block
  #              to prevent contamination between outer and inner parses
  #
  # Flow:
  # @media print { body { margin: 0 } } .header { color: blue }
  #        ^^^^^ captured as media types
  #               ^^^^^^^^^^^^^^^^^^^^  extracted and parsed recursively
  #                                      ^^^^^^^^^^^^^^^^^^^^^^^^ continues parsing
  #
  # The inside_media_block flag prevents the outer parse from creating rules
  # while scanning through media content character-by-character.

  media_type = ident >mark_media %capture_media_type;
  media_list = media_type (ws* ',' ws* media_type)*;

  # Media block - use a simple character-by-character scan
  # We increment depth on '{' and decrement on '}', stopping at depth 0
  media_char = ( any - [{}] ) | ( '{' $inc_depth ) | ( '}' $dec_depth );
  media_content = media_char*;
  media_block = [@] 'media' ws+ media_list >start_media_block ws* '{' $init_depth
                media_content;

  # CSS2: TODO - Add @import rules
  # CSS2: TODO - Add media query features: @media screen and (min-width: 500px)
  # CSS3: TODO - Add @keyframes for animations
  # CSS3: TODO - Add @font-face for custom fonts
  # CSS3: TODO - Add @supports for feature queries

  # ============================================================================
  # STYLESHEET (CSS1)
  # ============================================================================
  stylesheet = (media_block | rule | comment | ws)*;
  main := stylesheet;
}%%

%% machine css_parser; write data;

%%{
  # ============================================================================
  # SPECIFICITY COUNTER MACHINE
  # ============================================================================
  # This machine counts selector components to calculate CSS specificity.
  # It reuses the same pattern definitions as the css_parser machine but
  # attaches counting actions instead of capturing actions.
  #
  # W3C Specificity Rules:
  # - ID selectors (#id): 100 points each
  # - Class selectors (.class), attribute selectors ([attr]), pseudo-classes (:hover): 10 points each
  # - Element selectors (div), pseudo-elements (::before): 1 point each
  # - Universal selector (*): 0 points
  # - Combinators (>, +, ~, space): 0 points

  machine specificity_counter;

  # Reuse basic token definitions
  ws = [ \t\n\r];
  ident = alpha (alpha | digit | '-')*;
  dstring = '"' (any - '"')* '"';
  sstring = "'" (any - "'")* "'";
  string = dstring | sstring;

  # Counting actions (increment counters instead of capturing)
  action count_id { id_count++; }
  action count_class { class_count++; }
  action count_attr { attr_count++; }
  action count_pseudo_class { pseudo_class_count++; }
  action count_pseudo_element { pseudo_element_count++; }
  action count_element { element_count++; }

  # Selector patterns with counting actions
  # Attribute operators
  attr_operator = '=' | '~=' | '|=';

  # Pattern definitions without actions
  class_sel_pattern = '.' ident;
  id_sel_pattern = '#' ident;
  type_sel_pattern = ident;
  universal_sel_pattern = '*';
  attr_sel_pattern = '[' ws* ident ws* (attr_operator ws* (ident | string) ws*)? ']';
  pseudo_element_pattern = '::' ident ('(' (any - ')')* ')')?;
  pseudo_class_pattern = ':' ident ('(' (any - ')')* ')')?;

  # Apply actions to complete patterns
  class_sel = class_sel_pattern %count_class;
  id_sel = id_sel_pattern %count_id;
  type_sel = type_sel_pattern %count_element;
  universal_sel = universal_sel_pattern;  # Universal selector has specificity 0, so no action needed
  attr_sel = attr_sel_pattern %count_attr;
  pseudo_element = pseudo_element_pattern %count_pseudo_element;
  pseudo_class = pseudo_class_pattern %count_pseudo_class;

  # Simple selector (can have multiple components)
  # First component can be universal or type, followed by optional class/id/attr/pseudo
  simple_selector_sequence = (universal_sel | type_sel)? (class_sel | id_sel | attr_sel | pseudo_element | pseudo_class)*;
  simple_selector = simple_selector_sequence;

  # Combinators (have no specificity value)
  combinator = ws+ | (ws* '>' ws*) | (ws* '+' ws*) | (ws* '~' ws*);

  # Compound selector (simple selectors separated by combinators)
  compound_selector = simple_selector (combinator simple_selector)*;

  # Allow optional whitespace before/after
  main := ws* compound_selector ws*;
}%%

%% machine specificity_counter; write data;

static VALUE parse_css(VALUE self, VALUE css_string) {
    // Ragel state variables
    char *p, *pe, *eof;
    char *mark = NULL, *prop_mark = NULL, *val_mark = NULL, *media_mark = NULL, *media_content_start = NULL;
    int cs;
    int brace_depth = 0;  // Track brace nesting for @media blocks
    int inside_media_block = 0;  // Flag to prevent creating rules while scanning media content

    // Ruby variables for building result
    VALUE rules_array, current_selectors, current_declarations, current_media_types;
    VALUE selector, property, value;

    // Setup input
    Check_Type(css_string, T_STRING);
    p = RSTRING_PTR(css_string);
    pe = p + RSTRING_LEN(css_string);
    eof = pe;

    // Initialize result array and working variables
    rules_array = rb_ary_new();
    current_selectors = Qnil;
    current_declarations = Qnil;
    current_media_types = Qnil;

    %% machine css_parser; write init;
    %% machine css_parser; write exec;

    if (cs >= css_parser_first_final) {
        return rules_array;
    } else {
        rb_raise(rb_eRuntimeError, "Parse error at position %ld", p - RSTRING_PTR(css_string));
    }
}

// Calculate CSS specificity for a selector string
// Uses the specificity_counter Ragel machine to count selector components
static VALUE calculate_specificity(VALUE self, VALUE selector_string) {
    // Counters for selector components
    int id_count = 0;
    int class_count = 0;
    int attr_count = 0;
    int pseudo_class_count = 0;
    int pseudo_element_count = 0;
    int element_count = 0;

    // Ragel state variables
    char *p, *pe, *eof;
    int cs;

    // Setup input
    Check_Type(selector_string, T_STRING);
    p = RSTRING_PTR(selector_string);
    pe = p + RSTRING_LEN(selector_string);
    eof = pe;

    %% machine specificity_counter; write init;
    %% machine specificity_counter; write exec;

    // Calculate specificity using W3C formula:
    // IDs * 100 + (classes + attributes + pseudo-classes) * 10 + (elements + pseudo-elements) * 1
    int specificity = (id_count * 100) +
                      ((class_count + attr_count + pseudo_class_count) * 10) +
                      ((element_count + pseudo_element_count) * 1);

    return INT2NUM(specificity);
}

// Ruby extension initialization
void Init_cataract() {
    VALUE module = rb_define_module("Cataract");
    rb_define_module_function(module, "parse_css", parse_css, 1);
    rb_define_module_function(module, "calculate_specificity", calculate_specificity, 1);
}
