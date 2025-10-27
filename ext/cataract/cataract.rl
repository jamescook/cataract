#include <ruby.h>
#include <stdio.h>

// Global references to struct classes
static VALUE cDeclarationsValue;
static VALUE cRule;

// Error class references
static VALUE eCataractError;
static VALUE eParseError;
static VALUE eDepthError;
static VALUE eSizeError;

// Forward declarations
VALUE cataract_split_value(VALUE self, VALUE value);
VALUE cataract_expand_margin(VALUE self, VALUE value);
VALUE cataract_expand_padding(VALUE self, VALUE value);
VALUE cataract_expand_border_color(VALUE self, VALUE value);
VALUE cataract_expand_border_style(VALUE self, VALUE value);
VALUE cataract_expand_border_width(VALUE self, VALUE value);
VALUE cataract_expand_border(VALUE self, VALUE value);
VALUE cataract_expand_border_side(VALUE self, VALUE side, VALUE value);
VALUE cataract_expand_font(VALUE self, VALUE value);
VALUE cataract_expand_list_style(VALUE self, VALUE value);
VALUE cataract_expand_background(VALUE self, VALUE value);

// Shorthand creation (inverse of expansion) - forward declarations
VALUE cataract_create_margin_shorthand(VALUE self, VALUE properties);
VALUE cataract_create_padding_shorthand(VALUE self, VALUE properties);
VALUE cataract_create_border_width_shorthand(VALUE self, VALUE properties);

// Helper macros and functions for string trimming
#define IS_WHITESPACE(c) ((c) == ' ' || (c) == '\t' || (c) == '\n' || (c) == '\r')

// Trim leading whitespace - modifies start pointer
static inline void trim_leading(const char **start, const char *end) {
    while (*start < end && IS_WHITESPACE(**start)) {
        (*start)++;
    }
}

// Trim trailing whitespace - modifies end pointer
static inline void trim_trailing(const char *start, const char **end) {
    while (*end > start && IS_WHITESPACE(*(*end - 1))) {
        (*end)--;
    }
}

VALUE cataract_create_border_style_shorthand(VALUE self, VALUE properties);
VALUE cataract_create_border_color_shorthand(VALUE self, VALUE properties);
VALUE cataract_create_border_shorthand(VALUE self, VALUE properties);
VALUE cataract_create_background_shorthand(VALUE self, VALUE properties);
VALUE cataract_create_font_shorthand(VALUE self, VALUE properties);
VALUE cataract_create_list_style_shorthand(VALUE self, VALUE properties);

// Helper functions
static VALUE lowercase_property(VALUE property_str);

// Uncomment to enable debug output (adds overhead, use only for development)
// #define CATARACT_DEBUG 1

#ifdef CATARACT_DEBUG
  #define DEBUG_PRINTF(...) printf(__VA_ARGS__)
#else
  #define DEBUG_PRINTF(...) ((void)0)
#endif

// String allocation optimization (enabled by default)
// Uses rb_str_buf_new for pre-allocation when building selector strings
//
// Disable for benchmarking baseline:
//   Development: DISABLE_STR_BUF_OPTIMIZATION=1 rake compile
//   Gem install: gem install cataract -- --disable-str-buf-optimization
//
//
#ifndef DISABLE_STR_BUF_OPTIMIZATION
  #define STR_NEW_WITH_CAPACITY(capacity) rb_str_buf_new(capacity)
  #define STR_NEW_CSTR(str) rb_str_new_cstr(str)
#else
  #define STR_NEW_WITH_CAPACITY(capacity) rb_str_new_cstr("")
  #define STR_NEW_CSTR(str) rb_str_new_cstr(str)
#endif

// Sanity limits for CSS properties and values
// These prevent crashes from pathological inputs (fuzzer-found edge cases)
// Override at compile time if needed: -DMAX_PROPERTY_NAME_LENGTH=512
#ifndef MAX_PROPERTY_NAME_LENGTH
  #define MAX_PROPERTY_NAME_LENGTH 256  // Reasonable max for property names (e.g., "background-position-x")
#endif

#ifndef MAX_PROPERTY_VALUE_LENGTH
  #define MAX_PROPERTY_VALUE_LENGTH 32768  // 32KB - handles large data URLs and complex values
#endif

#ifndef MAX_AT_RULE_BLOCK_LENGTH
  #define MAX_AT_RULE_BLOCK_LENGTH 1048576  // 1MB - max size for @media, @supports, etc. block content
#endif

#ifndef MAX_PARSE_DEPTH
  #define MAX_PARSE_DEPTH 10  // Max recursion depth for nested @media/@supports blocks
#endif

%%{
  machine css_parser;
  
  # Actions that build Ruby objects
  action mark_start {
    mark = p;
    DEBUG_PRINTF("[@media] mark_start: mark set to %ld\n", mark - RSTRING_PTR(css_string));
  }
  action mark_decl_start {
    // Mark the start of declaration block content (after opening brace)
    decl_start = p;
    DEBUG_PRINTF("[mark_decl_start] Marked at position %ld\n", p - RSTRING_PTR(css_string));
  }
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

  action handle_eof {
    // Accept EOF in non-final states - this allows ** to terminate gracefully
    DEBUG_PRINTF("[@eof] Reached end of input, accepting\n");
  }

  action mark_at_rule_name {
    // Only mark if we're not already inside an at-rule block
    // (prevents nested at-rules from overwriting outer markers)
    if (brace_depth == 0 && at_rule_depth == 0) {
      at_rule_name_start = p;
      DEBUG_PRINTF("[@at-rule] mark_at_rule_name at pos=%ld\n", p - RSTRING_PTR(css_string));
    } else {
      DEBUG_PRINTF("[@at-rule] mark_at_rule_name SKIPPED (inside block, brace=%d at=%d)\n", brace_depth, at_rule_depth);
    }
  }

  action mark_prelude_start {
    // Only mark if we're not already inside an at-rule block
    if (brace_depth == 0 && at_rule_depth == 0) {
      at_rule_prelude_start = p;
      DEBUG_PRINTF("[@at-rule] mark_prelude_start at pos=%ld\n", p - RSTRING_PTR(css_string));
    } else {
      DEBUG_PRINTF("[@at-rule] mark_prelude_start SKIPPED (inside block)\n");
    }
  }

  action mark_prelude_end {
    // Only mark if we're not already inside an at-rule block
    if (brace_depth == 0 && at_rule_depth == 0) {
      media_content_start = p;  // Mark end of prelude (start of block)
      DEBUG_PRINTF("[@at-rule] mark_prelude_end at pos=%ld\n", p - RSTRING_PTR(css_string));
    } else {
      DEBUG_PRINTF("[@at-rule] mark_prelude_end SKIPPED (inside block)\n");
    }
  }

  action at_rule_init_depth {
    // Check if this is @media by examining the at-rule name
    const char *name_end = at_rule_prelude_start;
    while (name_end > at_rule_name_start && (*(name_end-1) == ' ' || *(name_end-1) == '\t' || *(name_end-1) == '\n')) {
      name_end--;
    }
    int is_media = (name_end - at_rule_name_start == 5 && strncmp(at_rule_name_start, "media", 5) == 0);

    if (is_media) {
      // @media: use brace_depth
      // Only initialize if we're not already inside a media block (top-level @media only)
      if (brace_depth == 0) {
        brace_depth = 1;
        media_content_start = p;
        inside_at_rule_block = 1;
        DEBUG_PRINTF("[@media] init_depth: depth=1, content_start=%ld\n", p - RSTRING_PTR(css_string));
      } else {
        // Nested @media - shouldn't happen in same parse, will be handled in recursive parse
        DEBUG_PRINTF("[@media] init_depth: SKIPPED (already inside media, depth=%d)\n", brace_depth);
      }
    } else {
      // Other at-rules: use at_rule_depth
      // Only initialize if not inside any at-rule block
      if (at_rule_depth == 0 && brace_depth == 0) {
        at_rule_depth = 1;
        at_rule_block_start = p;
        inside_at_rule_block = 1;
        DEBUG_PRINTF("[@at-rule] init_depth: depth=1\n");
      } else {
        DEBUG_PRINTF("[@at-rule] init_depth: SKIPPED (already inside block, at_depth=%d brace_depth=%d)\n", at_rule_depth, brace_depth);
      }
    }
  }

  action at_rule_inc_depth {
    // Branch based on which depth counter is active
    if (brace_depth > 0) {
      brace_depth++;
      DEBUG_PRINTF("[@media] inc_depth: depth=%d\n", brace_depth);
    } else {
      at_rule_depth++;
      DEBUG_PRINTF("[@at-rule] inc_depth: depth=%d\n", at_rule_depth);
    }
  }

  action at_rule_dec_depth {
    // Branch based on which depth counter is active
    if (brace_depth > 0) {
      brace_depth--;
      DEBUG_PRINTF("[@media] dec_depth: depth=%d\n", brace_depth);

      if (brace_depth == 0) {
        // @media block closed - recursively parse content
        const char *prelude_end = media_content_start;
        while (prelude_end > at_rule_prelude_start && (*(prelude_end-1) == ' ' || *(prelude_end-1) == '\t')) {
          prelude_end--;
        }
        VALUE media_types = parse_media_query(at_rule_prelude_start, prelude_end - at_rule_prelude_start);

        // Extract media block content (bounds check for empty/oversized blocks)
        long media_block_len = p - media_content_start - 1;
        VALUE inner_rules = Qnil;

        VALUE media_content_str = Qnil;
        if (media_block_len > MAX_AT_RULE_BLOCK_LENGTH) {
          rb_raise(eSizeError,
                   "@media block too large: %ld bytes (max %d bytes)",
                   media_block_len, MAX_AT_RULE_BLOCK_LENGTH);
        } else if (media_block_len > 0) {
          media_content_str = rb_str_new(media_content_start + 1, media_block_len);
          inner_rules = parse_css_internal(Qnil, media_content_str, depth + 1);
        } else {
          inner_rules = rb_ary_new();  // Empty array for empty block
        }

        if (!NIL_P(media_types) && RARRAY_LEN(media_types) > 0) {
          for (long i = 0; i < RARRAY_LEN(inner_rules); i++) {
            VALUE rule = RARRAY_AREF(inner_rules, i);
            // Set media_query field (index 3) on the Rule struct
            rb_struct_aset(rule, INT2FIX(3), rb_ary_dup(media_types));
          }
        }
        for (long i = 0; i < RARRAY_LEN(inner_rules); i++) {
          rb_ary_push(rules_array, RARRAY_AREF(inner_rules, i));
        }

        RB_GC_GUARD(media_types);        // Protect from GC - must be at end of scope
        RB_GC_GUARD(media_content_str);  // Protect from GC - must be at end of scope
        RB_GC_GUARD(inner_rules);        // Protect from GC - must be at end of scope

        inside_at_rule_block = 0;
        fgoto main;  // Jump back to main state and continue parsing
      }
    } else {
      at_rule_depth--;
      DEBUG_PRINTF("[@at-rule] dec_depth: depth=%d\n", at_rule_depth);

      if (at_rule_depth == 0) {
        // Other at-rule block closed - process it
        if (at_rule_name_start != NULL && at_rule_prelude_start != NULL && at_rule_block_start != NULL) {
          const char *name_end = at_rule_prelude_start;
          while (name_end > at_rule_name_start && (*(name_end-1) == ' ' || *(name_end-1) == '\t')) {
            name_end--;
          }
          VALUE at_name = rb_str_new(at_rule_name_start, name_end - at_rule_name_start);
          const char *name_cstr = StringValueCStr(at_name);

          if (strcmp(name_cstr, "supports") == 0) {
            // Extract block content (bounds check for empty/oversized blocks)
            long block_len = p - at_rule_block_start - 1;
            if (block_len > MAX_AT_RULE_BLOCK_LENGTH) {
              rb_raise(eSizeError,
                       "@supports block too large: %ld bytes (max %d bytes)",
                       block_len, MAX_AT_RULE_BLOCK_LENGTH);
            } else if (block_len > 0) {
              VALUE block_content = rb_str_new(at_rule_block_start + 1, block_len);
              VALUE inner_rules = parse_css_internal(Qnil, block_content, depth + 1);
              for (long i = 0; i < RARRAY_LEN(inner_rules); i++) {
                rb_ary_push(rules_array, RARRAY_AREF(inner_rules, i));
              }
              RB_GC_GUARD(block_content);  // Protect from GC - must be at end of scope
              RB_GC_GUARD(inner_rules);    // Protect from GC - must be at end of scope
            }
          } else if (strncmp(name_cstr, "keyframes", 9) == 0 || strstr(name_cstr, "-keyframes") != NULL) {
            const char *prelude_end = media_content_start;
            while (prelude_end > at_rule_prelude_start && (*(prelude_end-1) == ' ' || *(prelude_end-1) == '\t')) {
              prelude_end--;
            }
            VALUE animation_name = rb_str_new(at_rule_prelude_start, prelude_end - at_rule_prelude_start);
            animation_name = rb_funcall(animation_name, rb_intern("strip"), 0);

            // Build selector: "@" + name + " " + animation_name
            long name_len = strlen(name_cstr);
            long anim_len = RSTRING_LEN(animation_name);
            VALUE selector = STR_NEW_WITH_CAPACITY(1 + name_len + 1 + anim_len);
            rb_str_cat2(selector, "@");
            rb_str_cat2(selector, name_cstr);
            rb_str_cat2(selector, " ");
            rb_str_append(selector, animation_name);

            VALUE rule = rb_struct_new(cRule,
                selector,                                    // selector
                rb_ary_new(),                               // declarations (empty array)
                Qnil,                                        // specificity (calculated on demand)
                rb_ary_new3(1, ID2SYM(rb_intern("all")))   // media_query
            );
            rb_ary_push(rules_array, rule);

            RB_GC_GUARD(animation_name);  // Protect from GC - must be at end of scope
            RB_GC_GUARD(selector);        // Protect from GC - must be at end of scope
            RB_GC_GUARD(rule);            // Protect from GC - must be at end of scope
          } else if (strcmp(name_cstr, "font-face") == 0 || strcmp(name_cstr, "property") == 0 ||
                     strcmp(name_cstr, "page") == 0 || strcmp(name_cstr, "counter-style") == 0) {
            // Descriptor-based at-rules: @font-face, @property, @page, @counter-style
            // These contain descriptors (not rules), so parse as dummy selector to extract declarations
            long block_len = p - at_rule_block_start - 1;
            if (block_len <= 0) {
              // Empty block, skip
              goto at_rule_cleanup;
            }
            if (block_len > MAX_AT_RULE_BLOCK_LENGTH) {
              rb_raise(eSizeError,
                       "@%s block too large: %ld bytes (max %d bytes)",
                       name_cstr, block_len, MAX_AT_RULE_BLOCK_LENGTH);
            }
            VALUE block_content = rb_str_new(at_rule_block_start + 1, block_len);

            // Wrap content for parsing: "* { " + content + " }"
            long content_len = RSTRING_LEN(block_content);
            VALUE wrapped = STR_NEW_WITH_CAPACITY(4 + content_len + 2);  // "* { " (4) + content + " }" (2)
            rb_str_cat2(wrapped, "* { ");
            rb_str_append(wrapped, block_content);
            rb_str_cat2(wrapped, " }");

            VALUE dummy_rules = parse_css_internal(Qnil, wrapped, depth + 1);
            VALUE declarations = Qnil;
            VALUE prelude_val = Qnil;
            VALUE selector = Qnil;
            VALUE rule = Qnil;

            if (!NIL_P(dummy_rules) && RARRAY_LEN(dummy_rules) > 0) {
              VALUE first_rule = RARRAY_AREF(dummy_rules, 0);
              // Get declarations field (index 1) from Rule struct
              declarations = rb_struct_aref(first_rule, INT2FIX(1));

              // Compute prelude first to know total size for pre-allocation
              const char *prelude_end = media_content_start;
              while (prelude_end > at_rule_prelude_start && (*(prelude_end-1) == ' ' || *(prelude_end-1) == '\t')) {
                prelude_end--;
              }
              long prelude_len = prelude_end - at_rule_prelude_start;
              long stripped_prelude_len = 0;
              if (prelude_len > 0) {
                prelude_val = rb_str_new(at_rule_prelude_start, prelude_len);
                prelude_val = rb_funcall(prelude_val, rb_intern("strip"), 0);
                stripped_prelude_len = RSTRING_LEN(prelude_val);
              }

              // Build selector: "@" + name + [" " + prelude]
              long name_len = strlen(name_cstr);
              long total_capacity = 1 + name_len + (stripped_prelude_len > 0 ? 1 + stripped_prelude_len : 0);
              selector = STR_NEW_WITH_CAPACITY(total_capacity);
              rb_str_cat2(selector, "@");
              rb_str_cat2(selector, name_cstr);

              // Add prelude if present (e.g., "@property --my-color", "@page :first")
              if (stripped_prelude_len > 0) {
                rb_str_cat2(selector, " ");
                rb_str_append(selector, prelude_val);
              }

              rule = rb_struct_new(cRule,
                  selector,                                    // selector
                  declarations,                                // declarations
                  Qnil,                                        // specificity (calculated on demand)
                  rb_ary_new3(1, ID2SYM(rb_intern("all")))   // media_query
              );
              rb_ary_push(rules_array, rule);
            }

            RB_GC_GUARD(block_content);  // Protect from GC - must be at end of scope
            RB_GC_GUARD(wrapped);        // Protect from GC - must be at end of scope
            RB_GC_GUARD(dummy_rules);    // Protect from GC - must be at end of scope
            RB_GC_GUARD(declarations);   // Protect from GC - must be at end of scope
            RB_GC_GUARD(prelude_val);    // Protect from GC - must be at end of scope
            RB_GC_GUARD(selector);       // Protect from GC - must be at end of scope
            RB_GC_GUARD(rule);           // Protect from GC - must be at end of scope
          } else {
            // Default: treat as conditional group rule (like @supports, @layer, @container, @scope, etc.)
            // Recursively parse block content (bounds check for empty/oversized blocks)
            long block_len = p - at_rule_block_start - 1;
            if (block_len > MAX_AT_RULE_BLOCK_LENGTH) {
              rb_raise(eSizeError,
                       "@%s block too large: %ld bytes (max %d bytes)",
                       name_cstr, block_len, MAX_AT_RULE_BLOCK_LENGTH);
            } else if (block_len > 0) {
              VALUE block_content = rb_str_new(at_rule_block_start + 1, block_len);
              VALUE inner_rules = parse_css_internal(Qnil, block_content, depth + 1);
              for (long i = 0; i < RARRAY_LEN(inner_rules); i++) {
                rb_ary_push(rules_array, RARRAY_AREF(inner_rules, i));
              }
              RB_GC_GUARD(block_content);  // Protect from GC - must be at end of scope
              RB_GC_GUARD(inner_rules);    // Protect from GC - must be at end of scope
            }
          }

          at_rule_cleanup:
          RB_GC_GUARD(at_name);  // Protect from GC - must be at end of scope after all name_cstr usage
          at_rule_name_start = NULL;
          at_rule_prelude_start = NULL;
          media_content_start = NULL;
          at_rule_block_start = NULL;
        }

        inside_at_rule_block = 0;
        fgoto main;
      }
    }
  }


  action finish_parse {
    // No-op: EOF reached, parsing complete
  }

  action capture_declarations {
    // Guard against multiple firings - only process if decl_start is set
    if (decl_start != NULL) {
      // Parse declaration block content in C
      // Input: "color: red; background: blue !important"
      // Output: Array of Declarations::Value structs
      if (NIL_P(current_declarations)) {
        current_declarations = rb_ary_new();
      }

      const char *start = decl_start;
      const char *end = p;

      DEBUG_PRINTF("[capture_declarations] Parsing declarations from %ld to %ld: '%.*s'\n",
                   decl_start - RSTRING_PTR(css_string), p - RSTRING_PTR(css_string),
                   (int)(end - start), start);

      // Simple C-level parser for declarations
      const char *pos = start;
      while (pos < end) {
        // Skip whitespace and semicolons
        while (pos < end && (IS_WHITESPACE(*pos) || *pos == ';')) {
          pos++;
        }
        if (pos >= end) break;

        // Find property (up to colon)
        const char *prop_start = pos;
        while (pos < end && *pos != ':') pos++;
        if (pos >= end) break;  // No colon found

        const char *prop_end = pos;
        // Trim whitespace from property
        trim_trailing(prop_start, &prop_end);
        trim_leading(&prop_start, prop_end);

        pos++;  // Skip colon

        // Skip whitespace after colon
        while (pos < end && IS_WHITESPACE(*pos)) {
          pos++;
        }

        // Find value (up to semicolon or end)
        // Handle parentheses: semicolons inside () don't terminate the value
        const char *val_start = pos;
        int paren_depth = 0;
        while (pos < end) {
          if (*pos == '(') {
            paren_depth++;
          } else if (*pos == ')') {
            paren_depth--;
          } else if (*pos == ';' && paren_depth == 0) {
            break;  // Found terminating semicolon
          }
          pos++;
        }
        const char *val_end = pos;

        // Trim trailing whitespace from value
        trim_trailing(val_start, &val_end);

        // Check for !important
        int is_important = 0;
        const char *important_pos = val_end;
        // Look backwards for "!important"
        if (val_end - val_start >= 10) {  // strlen("!important") = 10
          const char *check = val_end - 10;
          while (check < val_end && IS_WHITESPACE(*check)) check++;
          if (check < val_end && *check == '!') {
            check++;
            while (check < val_end && IS_WHITESPACE(*check)) check++;
            if ((val_end - check) >= 9 && strncmp(check, "important", 9) == 0) {
              is_important = 1;
              important_pos = check - 1;
              while (important_pos > val_start && (IS_WHITESPACE(*(important_pos-1)) || *(important_pos-1) == '!')) {
                important_pos--;
              }
              val_end = important_pos;
            }
          }
        }

        // Final trim of trailing whitespace/newlines from value (after !important removal)
        trim_trailing(val_start, &val_end);

        // Skip if value is empty (e.g., "color: !important" with no actual value)
        if (val_end > val_start) {
          // Sanity check: property name length
          long prop_len = prop_end - prop_start;
          if (prop_len > MAX_PROPERTY_NAME_LENGTH) {
            DEBUG_PRINTF("[capture_declarations] Skipping property: name too long (%ld > %d)\n",
                         prop_len, MAX_PROPERTY_NAME_LENGTH);
            continue;
          }

          // Sanity check: value length
          long val_len = val_end - val_start;
          if (val_len > MAX_PROPERTY_VALUE_LENGTH) {
            DEBUG_PRINTF("[capture_declarations] Skipping property: value too long (%ld > %d)\n",
                         val_len, MAX_PROPERTY_VALUE_LENGTH);
            continue;
          }

          // Create property string and lowercase it (CSS property names are ASCII-only)
          VALUE property_raw = rb_str_new(prop_start, prop_len);
          VALUE property = lowercase_property(property_raw);
          VALUE value = rb_str_new(val_start, val_end - val_start);

          DEBUG_PRINTF("[capture_declarations] Found: property='%s' value='%s' important=%d\n",
                       RSTRING_PTR(property), RSTRING_PTR(value), is_important);

          // Create Declarations::Value struct
          VALUE decl = rb_struct_new(
            cDeclarationsValue,
            property,
            value,
            is_important ? Qtrue : Qfalse
          );

          rb_ary_push(current_declarations, decl);

          // Protect temporaries from GC (in case compiler optimizes them to registers)
          RB_GC_GUARD(property);
          RB_GC_GUARD(value);
          RB_GC_GUARD(decl);
        } else {
          DEBUG_PRINTF("[capture_declarations] Skipping empty value for property at pos %ld\n", prop_start - RSTRING_PTR(css_string));
        }

        if (pos < end && *pos == ';') pos++;  // Skip semicolon if present
      }

      decl_start = NULL;  // Reset for next rule
    } else {
      DEBUG_PRINTF("[capture_declarations] SKIPPED: decl_start is NULL\n");
    }
  }

  action finish_rule {
    // Skip if we're scanning at-rule block content (will be parsed recursively)
    if (!inside_at_rule_block) {
      // Create one rule for each selector in the list
      if (!NIL_P(current_selectors) && !NIL_P(current_declarations)) {
        long len = RARRAY_LEN(current_selectors);
        DEBUG_PRINTF("[finish_rule] Creating %ld rule(s)\n", len);
        for (long i = 0; i < len; i++) {
          VALUE sel = RARRAY_AREF(current_selectors, i);
          DEBUG_PRINTF("[finish_rule] Rule %ld: selector='%s'\n", i, RSTRING_PTR(sel));

          // Determine media query: use current_media_types if inside @media block, otherwise default to [:all]
          VALUE media_query;
          if (!NIL_P(current_media_types) && RARRAY_LEN(current_media_types) > 0) {
            media_query = rb_ary_dup(current_media_types);
            DEBUG_PRINTF("[finish_rule] Using current media types\n");
          } else {
            media_query = rb_ary_new3(1, ID2SYM(rb_intern("all")));
          }

          VALUE rule = rb_struct_new(cRule,
              sel,                                // selector
              rb_ary_dup(current_declarations),   // declarations
              Qnil,                               // specificity (calculated on demand)
              media_query                         // media_query
          );

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
  ident = ('-'? '-'? alpha (alpha | digit | '-')*);  # Allow vendor prefixes (-webkit) and custom properties (--)
  number = digit+ ('.' digit+)?;
  dstring = '"' (any - '"')* '"';
  sstring = "'" (any - "'")* "'";
  string = dstring | sstring;

  # ============================================================================
  # VALUES (CSS1)
  # ============================================================================
  # CSS value parsing with special handling for parentheses
  # Key insight: Semicolons inside parentheses (like in data URIs) should NOT end the declaration
  # Example: url(data:image/png;base64,ABC) - the semicolon is part of the value
  #
  # Strategy: Simple one-level parenthesis matching
  # - Inside ( ... ), allow any characters including semicolons
  # - Outside parens, semicolons end the declaration
  # This handles the common case of url(...) and other CSS functions

  # Content inside parentheses - can include semicolons
  # We don't allow nested parens to keep the state machine small
  paren_content = (any - [()])*;
  paren_group = '(' paren_content ')';

  # Regular value characters (outside parens) - no semicolons, braces, open parens, or exclamation marks
  # Exclamation mark is excluded because it's only valid in CSS as part of "!important"
  # which is handled separately by the important_flag pattern
  value_char = (any - [;{}(!]);

  # Complete value: just grab everything that's NOT a terminator
  # Terminators are: semicolon, closing brace, or exclamation (for !important)
  # Use + (one or more) instead of ** to avoid multiple action firings
  value = [^;{}!]+;

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
  # CSS3: [attr^=value], [attr$=value], [attr*=value]
  attr_operator = '^=' | '$=' | '*=' | '~=' | '|=' | '=';
  attr_part = '[' ws* ident ws* (attr_operator ws* (ident | string) ws*)? ']';

  # CSS2 Pseudo-classes and Pseudo-elements
  # Pseudo-classes (single colon): :hover, :focus, :first-child, :link, :visited, :active, :lang()
  # Pseudo-elements (double colon): ::before, ::after, ::first-line, ::first-letter
  # Note: CSS2 allowed single colon for pseudo-elements for backwards compat, but we prefer double colon
  pseudo_element_part = '::' ident ('(' (any - ')')* ')')?;
  pseudo_class_part = ':' ident ('(' (any - ')')* ')')?;

  # Simple selector sequence: optional type/universal, followed by class/id/attr/pseudo modifiers
  # Examples: div, div.class, div#id, .class, #id, [attr], *.class, a:hover, p::before, ::before
  # Also: .form-range::-webkit-slider-thumb:active (pseudo-class AFTER pseudo-element)
  # The key insight: order matters in alternation (|). Put more specific patterns first.
  # Type/universal with modifiers should match before standalone modifiers
  # Note: Some browsers allow pseudo-classes after pseudo-elements (e.g., ::before:hover)
  simple_selector_sequence =
    (type_part | universal_part) (class_part | id_part | attr_part | pseudo_class_part | pseudo_element_part)* |
    (class_part | id_part | attr_part | pseudo_class_part | pseudo_element_part)+ |
    pseudo_element_part (pseudo_class_part)*;

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

  # CSS1: ✓ Basic pseudo-classes (:link, :visited, :active) - IMPLEMENTED
  # CSS2: ✓ Universal selector (*) - IMPLEMENTED
  # CSS2: ✓ Combinators (>, +, ~, descendant space) - IMPLEMENTED
  # CSS2: ✓ Pseudo-classes (:hover, :focus, :first-child, :lang()) - IMPLEMENTED
  # CSS2: ✓ Pseudo-elements (::before, ::after, ::first-line, ::first-letter) - IMPLEMENTED
  # CSS3: ✓ Negation pseudo-class (:not()) - IMPLEMENTED
  # CSS3: ✓ Structural pseudo-classes (:nth-child(), :nth-of-type(), :first-of-type, :last-child, etc.) - IMPLEMENTED
  # CSS3: ✓ UI pseudo-classes (:enabled, :disabled, :checked) - IMPLEMENTED

  # ============================================================================
  # DECLARATIONS (CSS1)
  # ============================================================================
  # Simplified: Just capture everything between braces and parse in C
  # This handles all edge cases: !important, shorthand properties, data URIs, etc.
  # No need for complex Ragel patterns with tricky operator semantics

  # ============================================================================
  # RULES (CSS1)
  # ============================================================================
  rule_body = '{' @capture_compound_selector %mark_decl_start (any - '}')* ('}' >capture_declarations) %finish_rule;
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

  # ============================================================================
  # AT-RULES (W3C CSS Syntax Module Level 3)
  # ============================================================================
  # Per spec: @<name> <prelude> { <block> } or @<name> <prelude> ;
  # Universal pattern handles @media, @font-face, @keyframes, @supports, etc.
  #
  # NESTED @MEDIA TRACE (test_nested_media_complex):
  # Input:
  #   @media screen {
  #     .outer { color: blue; }
  #
  #     @media (min-width: 768px) {
  #       .inner { color: red; }
  #     }
  #   }
  #
  # Expected flow:
  # Line                                  | p   | brace_depth | at_rule_depth | inside_at_rule_block | Action
  # --------------------------------------|-----|-------------|---------------|----------------------|------------------
  # @media screen {                       | 14  | 0→1         | 0             | 0→1                  | init: set depth=1, mark content_start=14
  #   (whitespace/newline)                | 15  | 1           | 0             | 1                    |
  #   .outer { color: blue; }             | ... | 1→2→1       | 0             | 1                    | inc on {, dec on }, skip finish_rule
  #   @media (min-width: 768px) {         | 71  | 1 (skip!)   | 0             | 1                    | init SKIPPED (already depth=1)
  #   (opening {)                          | 72  | 1→2         | 0             | 1                    | inc: depth 2
  #     .inner { color: red; }            | ... | 2→3→2       | 0             | 1                    | inc on {, dec on }, skip finish_rule
  #   }                                   | 98  | 2→1         | 0             | 1                    | dec: depth 1, continue
  # }                                     | 105 | 1→0         | 0             | 1→0                  | dec: depth 0, PROCESS!
  #                                       |     |             |               |                      | Extract content[14+1..105-1]
  #                                       |     |             |               |                      | Recursive parse finds .outer AND nested @media
  #                                       |     |             |               |                      | Nested @media recursively parses and finds .inner
  #                                       |     |             |               |                      | Returns 2 rules total
  #
  # KEY INSIGHT: The nested @media's init is SKIPPED because brace_depth > 0.
  # So the nested media's { and } just increment/decrement the same brace_depth counter.
  # Only when brace_depth reaches 0 (outer media closes) do we extract and recursively parse.

  # At-rule name (ident after @, can start with - for vendor prefixes)
  at_rule_name = ('-'? alpha (alpha | digit | '-')*) >mark_at_rule_name;

  # Prelude is everything before '{' or ';'
  at_rule_prelude = (any - [{};])* >mark_prelude_start %mark_prelude_end;

  # Single unified at-rule pattern - actions check if it's @media and branch accordingly
  at_rule_char = ( any - [{}] ) | ( '{' $at_rule_inc_depth ) | ( '}' $at_rule_dec_depth );
  at_rule_block = '{' $at_rule_init_depth at_rule_char*;
  at_rule = [@] at_rule_name ws* at_rule_prelude ws* (at_rule_block | ';');

  # CSS2: TODO - Add @import rules
  # CSS2: ✓ Media query features (and, min-width, max-width, etc.) - IMPLEMENTED
  # CSS3: ✓ @keyframes for animations - IMPLEMENTED
  # CSS3: ✓ @font-face for custom fonts - IMPLEMENTED
  # CSS3: ✓ @supports for feature queries - IMPLEMENTED
  # CSS3: ✓ Negation pseudo-class (:not()) - IMPLEMENTED

  # ============================================================================
  # STYLESHEET (CSS1)
  # ============================================================================
  # Single at_rule pattern - actions detect @media and use appropriate depth tracking
  stylesheet_item = at_rule | rule | comment | ws;
  stylesheet = stylesheet_item*;
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
  ident = ('-'? '-'? alpha (alpha | digit | '-')*);  # Allow vendor prefixes and custom properties
  dstring = '"' (any - '"')* '"';
  sstring = "'" (any - "'")* "'";
  string = dstring | sstring;

  # Counting actions (increment counters instead of capturing)
  action count_id { id_count++; }
  action count_class { class_count++; }
  action count_attr { attr_count++; }

  action mark_pseudo_start { pseudo_mark = p; }
  action mark_pseudo_end { pseudo_end = p; }

  action count_pseudo_class {
    // Check if this is a legacy pseudo-element with single-colon syntax
    // CSS2.1 allows :before, :after, :first-line, :first-letter, :selection
    // These should count as pseudo-elements (1 point), not pseudo-classes (10 points)
    //
    // W3C Spec: "The negation pseudo-class itself does not count as a pseudo-class"
    // So :not() contributes 0 to specificity (but selectors inside it do count)
    int len = pseudo_end - pseudo_mark;
    int is_legacy_pseudo_element =
      (len == 6 && strncmp(pseudo_mark, "before", 6) == 0) ||
      (len == 5 && strncmp(pseudo_mark, "after", 5) == 0) ||
      (len == 10 && strncmp(pseudo_mark, "first-line", 10) == 0) ||
      (len == 12 && strncmp(pseudo_mark, "first-letter", 12) == 0) ||
      (len == 9 && strncmp(pseudo_mark, "selection", 9) == 0);

    int is_not_pseudo_class = (len == 3 && strncmp(pseudo_mark, "not", 3) == 0);

    if (is_legacy_pseudo_element) {
      pseudo_element_count++;
    } else if (!is_not_pseudo_class) {
      // Only count if it's not :not()
      pseudo_class_count++;
    } else {
      // For :not(), mark that we need to process its content
      // The pattern already consumed :not(...)
      // We need to find the parentheses and extract the content
      not_pseudo_mark = pseudo_mark;  // Save position for later processing
    }
  }

  action count_pseudo_element { pseudo_element_count++; }
  action count_element { element_count++; }

  # Selector patterns with counting actions
  # Attribute operators (CSS2 and CSS3)
  attr_operator = '^=' | '$=' | '*=' | '~=' | '|=' | '=';

  # Attribute value can be an identifier, string, or number
  # CSS allows unquoted values that start with digits (e.g., [data-id=123])
  number = digit+ ('.' digit+)?;
  attr_value = ident | string | number;

  # Pattern definitions without actions
  class_sel_pattern = '.' ident;
  id_sel_pattern = '#' ident;
  type_sel_pattern = ident;
  universal_sel_pattern = '*';
  attr_sel_pattern = '[' ws* ident ws* (attr_operator ws* attr_value ws*)? ']';
  pseudo_element_pattern = '::' ident ('(' (any - ')')* ')')?;
  pseudo_class_pattern = ':' ident >mark_pseudo_start %mark_pseudo_end ('(' (any - ')')* ')')?;

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

%%{
  # ============================================================================
  # MEDIA QUERY PARSER MACHINE
  # ============================================================================
  # This machine parses media query strings to extract media types
  # Based on W3C Media Queries spec (see summary in main machine comments)
  #
  # Input: "screen and (min-width: 768px)" or "print" or "screen, print"
  # Output: Array of media type symbols (e.g., [:screen] or [:screen, :print])
  #
  # Strategy: Match identifiers, skip keywords (and, or, not, only)

  machine media_query_parser;

  # Reuse basic token definitions
  ws = [ \t\n\r];
  ident = ('-'? '-'? alpha (alpha | digit | '-')*);  # Allow vendor prefixes and custom properties

  # Action to capture media type
  action capture_mq_type {
    // Check if this is a keyword we should skip
    int len = p - mq_mark;
    int is_keyword = (len == 3 && (strncmp(mq_mark, "and", 3) == 0 || strncmp(mq_mark, "not", 3) == 0)) ||
                     (len == 2 && strncmp(mq_mark, "or", 2) == 0) ||
                     (len == 4 && strncmp(mq_mark, "only", 4) == 0);

    if (!is_keyword) {
      ID media_id = rb_intern2(mq_mark, len);
      VALUE media_sym = ID2SYM(media_id);
      rb_ary_push(mq_types, media_sym);
      DEBUG_PRINTF("[mq_parser] captured media type: %.*s\n", len, mq_mark);
    } else {
      DEBUG_PRINTF("[mq_parser] skipped keyword: %.*s\n", len, mq_mark);
    }
  }

  # Media type - an identifier that's not inside parens
  # We'll match all identifiers and filter keywords in the action
  media_type_token = ident >{ mq_mark = p; } %capture_mq_type;

  # Non-identifier characters (spaces, parens, operators, numbers, etc.)
  media_other = (any - [a-zA-Z0-9\-])+;

  # Main pattern: use LONGEST-MATCH KLEENE STAR (**) to force matching complete idents!
  # This prioritizes staying in the machine vs wrapping around
  main := (media_type_token | media_other)**;
}%%

%% machine media_query_parser; write data;

// Parse media query string and return array of media types
// Example: "screen and (min-width: 768px)" -> [:screen]
// Example: "screen, print" -> [:screen, :print]
static VALUE parse_media_query(const char *query_str, long query_len) {
    // Ragel variables for media query parser
    char *p, *pe, *eof;
    char *mq_mark = NULL;
    int cs;
    VALUE mq_types = rb_ary_new();

    // Setup input
    p = (char *)query_str;
    pe = p + query_len;
    eof = pe;

    %% machine media_query_parser; write init;
    %% machine media_query_parser; write exec;

    return mq_types;
}

static VALUE parse_css_internal(VALUE self, VALUE css_string, int depth) {
    // Check recursion depth to prevent stack overflow and memory exhaustion
    if (depth > MAX_PARSE_DEPTH) {
        rb_raise(eDepthError,
                 "CSS nesting too deep: exceeded maximum depth of %d",
                 MAX_PARSE_DEPTH);
    }

    // Ragel state variables
    char *p, *pe, *eof;
    char *mark = NULL, *media_content_start = NULL;
    char *decl_start = NULL;  // Track start of declaration block content
    char *at_rule_name_start = NULL;   // Track start of at-rule name
    char *at_rule_prelude_start = NULL; // Track start of at-rule prelude
    char *at_rule_block_start = NULL;  // Track start of at-rule block content
    char *at_rule_block_end = NULL;    // Track end of at-rule block content
    int cs;
    int brace_depth = 0;  // Track brace nesting for @media blocks
    int inside_at_rule_block = 0;  // Flag to prevent creating rules while scanning at-rule content
    int at_rule_depth = 0;  // Track brace nesting for generic at-rules

    // Ruby variables for building result
    VALUE rules_array, current_selectors, current_declarations, current_media_types;
    VALUE selector;

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

    // GC Guard: Prevent compiler from optimizing away VALUE variables before function returns
    // Ruby's conservative GC scans the C stack, but compiler optimizations might remove
    // variables after their last "use". RB_GC_GUARD ensures they stay on stack until return.
    // Critical for: css_string (we only use its pointer), and incrementally-built objects
    RB_GC_GUARD(css_string);
    RB_GC_GUARD(rules_array);
    RB_GC_GUARD(current_selectors);
    RB_GC_GUARD(current_declarations);
    RB_GC_GUARD(current_media_types);

    if (cs >= css_parser_first_final) {
        return rules_array;
    } else {
        long pos = p - RSTRING_PTR(css_string);
        long len = RSTRING_LEN(css_string);
        const char *context_start = (pos >= 20) ? (p - 20) : RSTRING_PTR(css_string);
        long context_len = (pos >= 20) ? 20 : pos;

        rb_raise(eParseError,
                 "Parse error at position %ld (length %ld, state %d). Context: ...%.*s<<<HERE",
                 pos, len, cs, (int)context_len, context_start);
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
    char *pseudo_mark = NULL;  // Mark start of pseudo-class/element name
    char *pseudo_end = NULL;   // Mark end of pseudo-class/element name
    char *not_pseudo_mark = NULL;  // Mark position of :not() for content extraction
    int cs;

    // Setup input
    Check_Type(selector_string, T_STRING);
    p = RSTRING_PTR(selector_string);
    pe = p + RSTRING_LEN(selector_string);
    eof = pe;

    %% machine specificity_counter; write init;
    %% machine specificity_counter; write exec;

    // Handle :not() pseudo-class (CSS Selectors Level 3)
    // W3C Spec: "The negation pseudo-class itself does not count as a pseudo-class"
    // But the simple selector inside :not() does count toward specificity
    //
    // CSS Selectors Level 3: :not() accepts only simple selectors (no nesting, no combinators)
    // CSS Selectors Level 4: :not() accepts selector lists and complex selectors
    // This implementation supports Level 3 (simple selectors only)
    if (not_pseudo_mark != NULL) {
        // Find the opening paren after :not
        const char *paren_start = not_pseudo_mark + 3;  // Skip "not"
        while (paren_start < pe && *paren_start != '(') paren_start++;

        if (paren_start < pe && *paren_start == '(') {
            // Find matching closing paren
            const char *paren_end = paren_start + 1;
            int paren_depth = 1;
            while (paren_end < pe && paren_depth > 0) {
                if (*paren_end == '(') paren_depth++;
                else if (*paren_end == ')') paren_depth--;
                paren_end++;
            }

            // Extract content between parens and recursively calculate its specificity
            long content_len = paren_end - paren_start - 2;  // -2 to skip the parens themselves
            if (content_len > 0) {
                VALUE not_content = rb_str_new(paren_start + 1, content_len);
                VALUE not_spec = calculate_specificity(self, not_content);
                int not_content_specificity = NUM2INT(not_spec);

                // Break down the specificity and add to our counters
                // Specificity is calculated as: a*100 + b*10 + c*1
                int additional_a = not_content_specificity / 100;
                int additional_b = (not_content_specificity % 100) / 10;
                int additional_c = not_content_specificity % 10;

                id_count += additional_a;
                class_count += additional_b;
                element_count += additional_c;
            }
        }
    }

    // Calculate specificity using W3C formula:
    // IDs * 100 + (classes + attributes + pseudo-classes) * 10 + (elements + pseudo-elements) * 1
    int specificity = (id_count * 100) +
                      ((class_count + attr_count + pseudo_class_count) * 10) +
                      ((element_count + pseudo_element_count) * 1);

    return INT2NUM(specificity);
}

/*
 * Parse declarations string into array of Declarations::Value structs
 * Extracted from capture_declarations action - same logic, reusable
 *
 * @param start Pointer to start of declarations string
 * @param end Pointer to end of declarations string
 * @return Array of Declarations::Value structs
 */
static VALUE parse_declarations_string(const char *start, const char *end) {
    VALUE declarations = rb_ary_new();

    const char *pos = start;
    while (pos < end) {
        // Skip whitespace and semicolons
        while (pos < end && (IS_WHITESPACE(*pos) || *pos == ';')) pos++;
        if (pos >= end) break;

        // Find property (up to colon)
        const char *prop_start = pos;
        while (pos < end && *pos != ':') pos++;
        if (pos >= end) break;  // No colon found

        const char *prop_end = pos;
        trim_trailing(prop_start, &prop_end);
        trim_leading(&prop_start, prop_end);

        pos++;  // Skip colon
        trim_leading(&pos, end);

        // Find value (up to semicolon or end), handling parentheses
        const char *val_start = pos;
        int paren_depth = 0;
        while (pos < end) {
            if (*pos == '(') paren_depth++;
            else if (*pos == ')') paren_depth--;
            else if (*pos == ';' && paren_depth == 0) break;
            pos++;
        }
        const char *val_end = pos;
        trim_trailing(val_start, &val_end);

        // Check for !important
        int is_important = 0;
        if (val_end - val_start >= 10) {  // strlen("!important") = 10
            const char *check = val_end - 10;
            while (check < val_end && IS_WHITESPACE(*check)) check++;
            if (check < val_end && *check == '!') {
                check++;
                while (check < val_end && IS_WHITESPACE(*check)) check++;
                if ((val_end - check) >= 9 && strncmp(check, "important", 9) == 0) {
                    is_important = 1;
                    const char *important_pos = check - 1;
                    while (important_pos > val_start && (IS_WHITESPACE(*(important_pos-1)) || *(important_pos-1) == '!')) {
                        important_pos--;
                    }
                    val_end = important_pos;
                    trim_trailing(val_start, &val_end);
                }
            }
        }

        // Skip if value is empty
        if (val_end > val_start) {
            long prop_len = prop_end - prop_start;
            if (prop_len > MAX_PROPERTY_NAME_LENGTH) continue;

            long val_len = val_end - val_start;
            if (val_len > MAX_PROPERTY_VALUE_LENGTH) continue;

            // Create property string and lowercase it
            VALUE property_raw = rb_str_new(prop_start, prop_len);
            VALUE property = lowercase_property(property_raw);
            VALUE value = rb_str_new(val_start, val_len);

            // Create Declarations::Value struct
            VALUE decl = rb_struct_new(cDeclarationsValue,
                property, value, is_important ? Qtrue : Qfalse);

            rb_ary_push(declarations, decl);
        }
    }

    return declarations;
}

/*
 * Ruby-facing wrapper for parse_declarations
 *
 * @param declarations_string [String] CSS declarations like "color: red; margin: 10px"
 * @return [Array<Declarations::Value>] Array of parsed declaration structs
 */
static VALUE parse_declarations(VALUE self, VALUE declarations_string) {
    Check_Type(declarations_string, T_STRING);

    const char *input = RSTRING_PTR(declarations_string);
    long input_len = RSTRING_LEN(declarations_string);

    // Strip outer braces and whitespace (css_parser compatibility)
    const char *start = input;
    const char *end = input + input_len;

    while (start < end && (IS_WHITESPACE(*start) || *start == '{')) start++;
    while (end > start && (IS_WHITESPACE(*(end-1)) || *(end-1) == '}')) end--;

    VALUE result = parse_declarations_string(start, end);

    RB_GC_GUARD(result);
    return result;
}

// Public wrapper for Ruby - starts at depth 0
static VALUE parse_css(VALUE self, VALUE css_string) {
    // Verify that cRule was initialized in Init_cataract
    if (cRule == Qnil || cRule == 0) {
        rb_raise(rb_eRuntimeError, "cRule struct class not initialized - Init_cataract may have failed");
    }
    return parse_css_internal(self, css_string, 0);
}


// CSS merge implementation (cascade resolution, shorthand creation)
#include "merge.c"

/*
 * Convert array of Rule structs to full CSS string
 * Format: "selector { prop: value; }\nselector2 { prop: value; }"
 */
static VALUE rules_to_s(VALUE self, VALUE rules_array) {
    Check_Type(rules_array, T_ARRAY);

    long len = RARRAY_LEN(rules_array);
    if (len == 0) {
        return rb_str_new_cstr("");
    }

    // Estimate: ~100 chars per rule (selector + declarations)
    VALUE result = rb_str_buf_new(len * 100);

    for (long i = 0; i < len; i++) {
        VALUE rule = rb_ary_entry(rules_array, i);

        // Validate this is a Rule struct
        if (!RB_TYPE_P(rule, T_STRUCT)) {
            rb_raise(rb_eTypeError,
                     "Expected array of Rule structs, got %s at index %ld",
                     rb_obj_classname(rule), i);
        }

        // Extract: selector, declarations, specificity, media_query
        VALUE selector = rb_struct_aref(rule, INT2FIX(0));
        VALUE declarations = rb_struct_aref(rule, INT2FIX(1));

        // Append selector
        rb_str_buf_append(result, selector);
        rb_str_buf_cat2(result, " { ");

        // Serialize each declaration
        long decl_len = RARRAY_LEN(declarations);
        for (long j = 0; j < decl_len; j++) {
            VALUE decl = rb_ary_entry(declarations, j);

            VALUE property = rb_struct_aref(decl, INT2FIX(0));
            VALUE value = rb_struct_aref(decl, INT2FIX(1));
            VALUE important = rb_struct_aref(decl, INT2FIX(2));

            rb_str_buf_append(result, property);
            rb_str_buf_cat2(result, ": ");
            rb_str_buf_append(result, value);

            if (RTEST(important)) {
                rb_str_buf_cat2(result, " !important");
            }

            rb_str_buf_cat2(result, "; ");
        }

        rb_str_buf_cat2(result, "}\n");

        RB_GC_GUARD(rule);
        RB_GC_GUARD(selector);
        RB_GC_GUARD(declarations);
    }

    RB_GC_GUARD(result);
    return result;
}

/*
 * Convert array of Declarations::Value structs to CSS string (internal)
 * Format: "prop: value; prop2: value2 !important; "
 */
static VALUE declarations_to_s(VALUE self, VALUE declarations_array) {
    Check_Type(declarations_array, T_ARRAY);

    long len = RARRAY_LEN(declarations_array);
    if (len == 0) {
        return rb_str_new_cstr("");
    }

    // Use rb_str_buf_new for efficient string building
    VALUE result = rb_str_buf_new(len * 32); // Estimate 32 chars per declaration

    for (long i = 0; i < len; i++) {
        VALUE decl = rb_ary_entry(declarations_array, i);

        // Validate this is a Declarations::Value struct
        if (!RB_TYPE_P(decl, T_STRUCT) || rb_obj_class(decl) != cDeclarationsValue) {
            rb_raise(rb_eTypeError,
                     "Expected array of Declarations::Value structs, got %s at index %ld",
                     rb_obj_classname(decl), i);
        }

        // Extract struct fields
        VALUE property = rb_struct_aref(decl, INT2FIX(0));
        VALUE value = rb_struct_aref(decl, INT2FIX(1));
        VALUE important = rb_struct_aref(decl, INT2FIX(2));

        // Append: "property: value"
        rb_str_buf_append(result, property);
        rb_str_buf_cat2(result, ": ");
        rb_str_buf_append(result, value);

        // Append " !important" if needed
        if (RTEST(important)) {
            rb_str_buf_cat2(result, " !important");
        }

        rb_str_buf_cat2(result, "; ");

        RB_GC_GUARD(decl);
        RB_GC_GUARD(property);
        RB_GC_GUARD(value);
        RB_GC_GUARD(important);
    }

    // Strip trailing space
    rb_str_set_len(result, RSTRING_LEN(result) - 1);

    RB_GC_GUARD(result);
    return result;
}

void Init_cataract() {
    VALUE module = rb_define_module("Cataract");

    // Define error class hierarchy
    eCataractError = rb_define_class_under(module, "Error", rb_eStandardError);
    eParseError = rb_define_class_under(module, "ParseError", eCataractError);
    eDepthError = rb_define_class_under(module, "DepthError", eCataractError);
    eSizeError = rb_define_class_under(module, "SizeError", eCataractError);

    // Define Cataract::Declarations class (Ruby side will add methods)
    VALUE cDeclarations = rb_define_class_under(module, "Declarations", rb_cObject);

    // Define Cataract::Declarations::Value = Struct.new(:property, :value, :important)
    cDeclarationsValue = rb_struct_define_under(
        cDeclarations,
        "Value",
        "property",
        "value",
        "important",
        NULL
    );

    // Define Cataract::Rule = Struct.new(:selector, :declarations, :specificity, :media_query)
    cRule = rb_struct_define_under(
        module,
        "Rule",
        "selector",
        "declarations",
        "specificity",
        "media_query",
        NULL
    );

    rb_define_module_function(module, "parse_css", parse_css, 1);
    rb_define_module_function(module, "parse_declarations", parse_declarations, 1);
    rb_define_module_function(module, "calculate_specificity", calculate_specificity, 1);
    rb_define_module_function(module, "merge_rules", cataract_merge, 1);
    rb_define_module_function(module, "apply_cascade", cataract_merge, 1);  // Alias with better name
    rb_define_module_function(module, "rules_to_s", rules_to_s, 1);
    rb_define_module_function(module, "split_value", cataract_split_value, 1);
    rb_define_module_function(module, "expand_margin", cataract_expand_margin, 1);
    rb_define_module_function(module, "expand_padding", cataract_expand_padding, 1);
    rb_define_module_function(module, "expand_border_color", cataract_expand_border_color, 1);
    rb_define_module_function(module, "expand_border_style", cataract_expand_border_style, 1);
    rb_define_module_function(module, "expand_border_width", cataract_expand_border_width, 1);
    rb_define_module_function(module, "expand_border", cataract_expand_border, 1);
    rb_define_module_function(module, "expand_border_side", cataract_expand_border_side, 2);
    rb_define_module_function(module, "expand_font", cataract_expand_font, 1);
    rb_define_module_function(module, "expand_list_style", cataract_expand_list_style, 1);
    rb_define_module_function(module, "expand_background", cataract_expand_background, 1);

    // Shorthand creation (inverse of expansion)
    rb_define_module_function(module, "create_margin_shorthand", cataract_create_margin_shorthand, 1);
    rb_define_module_function(module, "create_padding_shorthand", cataract_create_padding_shorthand, 1);
    rb_define_module_function(module, "create_border_width_shorthand", cataract_create_border_width_shorthand, 1);
    rb_define_module_function(module, "create_border_style_shorthand", cataract_create_border_style_shorthand, 1);
    rb_define_module_function(module, "create_border_color_shorthand", cataract_create_border_color_shorthand, 1);
    rb_define_module_function(module, "create_border_shorthand", cataract_create_border_shorthand, 1);
    rb_define_module_function(module, "create_background_shorthand", cataract_create_background_shorthand, 1);
    rb_define_module_function(module, "create_font_shorthand", cataract_create_font_shorthand, 1);
    rb_define_module_function(module, "create_list_style_shorthand", cataract_create_list_style_shorthand, 1);

    // Serialization
    rb_define_module_function(module, "declarations_to_s", declarations_to_s, 1);

    // Export string allocation mode as a constant for verification in benchmarks
    #ifdef DISABLE_STR_BUF_OPTIMIZATION
        rb_define_const(module, "STRING_ALLOC_MODE", ID2SYM(rb_intern("dynamic")));
    #else
        rb_define_const(module, "STRING_ALLOC_MODE", ID2SYM(rb_intern("buffer")));
    #endif
}

// Include shorthand_expander implementation
#include "shorthand_expander.c"

