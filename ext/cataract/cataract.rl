#include <ruby.h>
#include <stdio.h>

// Global reference to Declarations::Value struct class
static VALUE cDeclarationsValue;

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
            rb_hash_aset(RARRAY_AREF(inner_rules, i), ID2SYM(rb_intern("media_types")), rb_ary_dup(media_types));
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

            VALUE rule = rb_hash_new();
            rb_hash_aset(rule, ID2SYM(rb_intern("selector")), selector);
            rb_hash_aset(rule, ID2SYM(rb_intern("declarations")), rb_hash_new());
            rb_hash_aset(rule, ID2SYM(rb_intern("media_types")), rb_ary_new3(1, ID2SYM(rb_intern("all"))));
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
              declarations = rb_hash_aref(RARRAY_AREF(dummy_rules, 0), ID2SYM(rb_intern("declarations")));

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

              rule = rb_hash_new();
              rb_hash_aset(rule, ID2SYM(rb_intern("selector")), selector);
              rb_hash_aset(rule, ID2SYM(rb_intern("declarations")), declarations);
              rb_hash_aset(rule, ID2SYM(rb_intern("media_types")), rb_ary_new3(1, ID2SYM(rb_intern("all"))));
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
        while (pos < end && (*pos == ' ' || *pos == '\t' || *pos == '\n' || *pos == '\r' || *pos == ';')) {
          pos++;
        }
        if (pos >= end) break;

        // Find property (up to colon)
        const char *prop_start = pos;
        while (pos < end && *pos != ':') pos++;
        if (pos >= end) break;  // No colon found

        const char *prop_end = pos;
        // Trim trailing whitespace and newlines from property
        while (prop_end > prop_start && (*(prop_end-1) == ' ' || *(prop_end-1) == '\t' || *(prop_end-1) == '\n' || *(prop_end-1) == '\r')) {
          prop_end--;
        }
        // Trim leading whitespace and newlines from property
        while (prop_start < prop_end && (*prop_start == ' ' || *prop_start == '\t' || *prop_start == '\n' || *prop_start == '\r')) {
          prop_start++;
        }

        pos++;  // Skip colon

        // Skip whitespace after colon
        while (pos < end && (*pos == ' ' || *pos == '\t' || *pos == '\n' || *pos == '\r')) {
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
        while (val_end > val_start && (*(val_end-1) == ' ' || *(val_end-1) == '\t' || *(val_end-1) == '\n' || *(val_end-1) == '\r')) {
          val_end--;
        }

        // Check for !important
        int is_important = 0;
        const char *important_pos = val_end;
        // Look backwards for "!important"
        if (val_end - val_start >= 10) {  // strlen("!important") = 10
          const char *check = val_end - 10;
          while (check < val_end && (*check == ' ' || *check == '\t' || *check == '\n' || *check == '\r')) check++;
          if (check < val_end && *check == '!') {
            check++;
            while (check < val_end && (*check == ' ' || *check == '\t' || *check == '\n' || *check == '\r')) check++;
            if ((val_end - check) >= 9 && strncmp(check, "important", 9) == 0) {
              is_important = 1;
              important_pos = check - 1;
              while (important_pos > val_start && (*(important_pos-1) == ' ' || *(important_pos-1) == '\t' || *(important_pos-1) == '\n' || *(important_pos-1) == '\r' || *(important_pos-1) == '!')) {
                important_pos--;
              }
              val_end = important_pos;
            }
          }
        }

        // Final trim of trailing whitespace/newlines from value (after !important removal)
        while (val_end > val_start && (*(val_end-1) == ' ' || *(val_end-1) == '\t' || *(val_end-1) == '\n' || *(val_end-1) == '\r')) {
          val_end--;
        }

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
          VALUE rule = rb_hash_new();
          rb_hash_aset(rule, ID2SYM(rb_intern("selector")), sel);
          rb_hash_aset(rule, ID2SYM(rb_intern("declarations")), rb_ary_dup(current_declarations));

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

// Public wrapper for Ruby - starts at depth 0
static VALUE parse_css(VALUE self, VALUE css_string) {
    return parse_css_internal(self, css_string, 0);
}

// Helper: Lowercase a CSS property name (ASCII only, safe for CSS)
//
// SAFE FOR: Property names (color, margin-top), media types (screen, print)
// NOT SAFE FOR: Property values (content: "Unicode 你好"), selectors with attributes
//
// CSS property names are guaranteed ASCII per W3C spec, so simple A-Z → a-z is correct.
// Returns a new Ruby string with lowercased content.
static VALUE lowercase_property(VALUE property_str) {
    const char *str = StringValueCStr(property_str);
    long len = RSTRING_LEN(property_str);

    char lower[len];  // VLA - C99
    for (long i = 0; i < len; i++) {
        char c = str[i];
        lower[i] = (c >= 'A' && c <= 'Z') ? (c + 32) : c;
    }

    return rb_str_new(lower, len);
}

// Context for expanded property iteration
struct expand_context {
    VALUE properties_hash;
    int specificity;
    VALUE important;
    VALUE value_struct;
};

// Callback for rb_hash_foreach - process expanded properties and apply cascade
static int merge_expanded_callback(VALUE exp_prop, VALUE exp_value, VALUE ctx_val) {
    struct expand_context *ctx = (struct expand_context *)ctx_val;

    // Lowercase expanded property
    exp_prop = lowercase_property(exp_prop);

    int is_important = RTEST(ctx->important);

    // Apply cascade rules for expanded property
    VALUE existing = rb_hash_aref(ctx->properties_hash, exp_prop);

    if (NIL_P(existing)) {
        VALUE prop_data = rb_hash_new();
        rb_hash_aset(prop_data, ID2SYM(rb_intern("value")), exp_value);
        rb_hash_aset(prop_data, ID2SYM(rb_intern("specificity")), INT2NUM(ctx->specificity));
        rb_hash_aset(prop_data, ID2SYM(rb_intern("important")), ctx->important);
        rb_hash_aset(prop_data, ID2SYM(rb_intern("_struct_class")), ctx->value_struct);
        rb_hash_aset(ctx->properties_hash, exp_prop, prop_data);
    } else {
        VALUE existing_spec = rb_hash_aref(existing, ID2SYM(rb_intern("specificity")));
        VALUE existing_important = rb_hash_aref(existing, ID2SYM(rb_intern("important")));

        int existing_spec_int = NUM2INT(existing_spec);
        int existing_is_important = RTEST(existing_important);

        int should_replace = 0;
        if (is_important) {
            if (!existing_is_important || existing_spec_int <= ctx->specificity) {
                should_replace = 1;
            }
        } else {
            if (!existing_is_important && existing_spec_int <= ctx->specificity) {
                should_replace = 1;
            }
        }

        if (should_replace) {
            rb_hash_aset(existing, ID2SYM(rb_intern("value")), exp_value);
            rb_hash_aset(existing, ID2SYM(rb_intern("specificity")), INT2NUM(ctx->specificity));
            rb_hash_aset(existing, ID2SYM(rb_intern("important")), ctx->important);
        }
    }

    RB_GC_GUARD(exp_prop);
    RB_GC_GUARD(exp_value);
    return ST_CONTINUE;
}

// Callback for rb_hash_foreach - builds result array from properties hash
static int merge_build_result_callback(VALUE property, VALUE prop_data, VALUE result_ary) {
    // Get Declarations::Value struct class (cached in prop_data for efficiency)
    VALUE value_struct = rb_hash_aref(prop_data, ID2SYM(rb_intern("_struct_class")));
    VALUE value = rb_hash_aref(prop_data, ID2SYM(rb_intern("value")));
    VALUE important = rb_hash_aref(prop_data, ID2SYM(rb_intern("important")));

    // Create Declarations::Value struct
    VALUE decl_struct = rb_struct_new(value_struct, property, value, important);
    rb_ary_push(result_ary, decl_struct);

    return ST_CONTINUE;
}

// Merge CSS rules according to cascade rules
// Input: array of parsed rules from parse_css
// Output: array of Declarations::Value structs (merged and with shorthand recreated)
static VALUE cataract_merge(VALUE self, VALUE rules_array) {
    Check_Type(rules_array, T_ARRAY);

    long num_rules = RARRAY_LEN(rules_array);
    if (num_rules == 0) {
        return rb_ary_new();
    }

    // Get Declarations::Value struct class once
    VALUE cataract_module = rb_const_get(rb_cObject, rb_intern("Cataract"));
    VALUE declarations_class = rb_const_get(cataract_module, rb_intern("Declarations"));
    VALUE value_struct = rb_const_get(declarations_class, rb_intern("Value"));

    // Use Ruby hash for temporary storage: property => {value:, specificity:, important:, _struct_class:}
    VALUE properties_hash = rb_hash_new();

    // Iterate through each rule
    for (long i = 0; i < num_rules; i++) {
        VALUE rule = RARRAY_AREF(rules_array, i);
        Check_Type(rule, T_HASH);

        // Extract selector, declarations, specificity
        VALUE selector = rb_hash_aref(rule, ID2SYM(rb_intern("selector")));
        VALUE declarations = rb_hash_aref(rule, ID2SYM(rb_intern("declarations")));
        VALUE specificity_val = rb_hash_aref(rule, ID2SYM(rb_intern("specificity")));

        // Calculate specificity if not provided (lazy)
        int specificity = 0;
        if (NIL_P(specificity_val)) {
            specificity_val = calculate_specificity(Qnil, selector);
        }
        specificity = NUM2INT(specificity_val);

        // Process each declaration in this rule
        Check_Type(declarations, T_ARRAY);
        long num_decls = RARRAY_LEN(declarations);

        for (long j = 0; j < num_decls; j++) {
            VALUE decl = RARRAY_AREF(declarations, j);

            // Extract property, value, important from Declarations::Value struct
            VALUE property = rb_struct_aref(decl, INT2FIX(0)); // property
            VALUE value = rb_struct_aref(decl, INT2FIX(1));    // value
            VALUE important = rb_struct_aref(decl, INT2FIX(2)); // important

            // Lowercase property name (safe - CSS properties are ASCII)
            property = lowercase_property(property);
            int is_important = RTEST(important);

            // Expand shorthand properties if needed
            const char *prop_str = StringValueCStr(property);
            VALUE expanded = Qnil;

            if (strcmp(prop_str, "margin") == 0) {
                expanded = cataract_expand_margin(Qnil, value);
            } else if (strcmp(prop_str, "padding") == 0) {
                expanded = cataract_expand_padding(Qnil, value);
            } else if (strcmp(prop_str, "border") == 0) {
                expanded = cataract_expand_border(Qnil, value);
            } else if (strcmp(prop_str, "border-color") == 0) {
                expanded = cataract_expand_border_color(Qnil, value);
            } else if (strcmp(prop_str, "border-style") == 0) {
                expanded = cataract_expand_border_style(Qnil, value);
            } else if (strcmp(prop_str, "border-width") == 0) {
                expanded = cataract_expand_border_width(Qnil, value);
            } else if (strcmp(prop_str, "border-top") == 0) {
                expanded = cataract_expand_border_side(Qnil, value, rb_str_new_cstr("top"));
            } else if (strcmp(prop_str, "border-right") == 0) {
                expanded = cataract_expand_border_side(Qnil, value, rb_str_new_cstr("right"));
            } else if (strcmp(prop_str, "border-bottom") == 0) {
                expanded = cataract_expand_border_side(Qnil, value, rb_str_new_cstr("bottom"));
            } else if (strcmp(prop_str, "border-left") == 0) {
                expanded = cataract_expand_border_side(Qnil, value, rb_str_new_cstr("left"));
            } else if (strcmp(prop_str, "font") == 0) {
                expanded = cataract_expand_font(Qnil, value);
            } else if (strcmp(prop_str, "list-style") == 0) {
                expanded = cataract_expand_list_style(Qnil, value);
            } else if (strcmp(prop_str, "background") == 0) {
                expanded = cataract_expand_background(Qnil, value);
            }

            // If property was expanded, iterate and apply cascade using rb_hash_foreach
            if (!NIL_P(expanded)) {
                Check_Type(expanded, T_HASH);

                struct expand_context ctx;
                ctx.properties_hash = properties_hash;
                ctx.specificity = specificity;
                ctx.important = important;
                ctx.value_struct = value_struct;

                rb_hash_foreach(expanded, merge_expanded_callback, (VALUE)&ctx);

                RB_GC_GUARD(expanded);
                continue; // Skip processing the original shorthand property
            }

            // Apply CSS cascade rules
            VALUE existing = rb_hash_aref(properties_hash, property);

            if (NIL_P(existing)) {
                // New property - add it
                VALUE prop_data = rb_hash_new();
                rb_hash_aset(prop_data, ID2SYM(rb_intern("value")), value);
                rb_hash_aset(prop_data, ID2SYM(rb_intern("specificity")), INT2NUM(specificity));
                rb_hash_aset(prop_data, ID2SYM(rb_intern("important")), important);
                rb_hash_aset(prop_data, ID2SYM(rb_intern("_struct_class")), value_struct);
                rb_hash_aset(properties_hash, property, prop_data);
            } else {
                // Property exists - check cascade rules
                VALUE existing_spec = rb_hash_aref(existing, ID2SYM(rb_intern("specificity")));
                VALUE existing_important = rb_hash_aref(existing, ID2SYM(rb_intern("important")));

                int existing_spec_int = NUM2INT(existing_spec);
                int existing_is_important = RTEST(existing_important);

                int should_replace = 0;

                if (is_important) {
                    // New is !important - wins if existing is NOT important OR equal/higher specificity
                    if (!existing_is_important || existing_spec_int <= specificity) {
                        should_replace = 1;
                    }
                } else {
                    // New is NOT important - only wins if existing is also NOT important AND equal/higher specificity
                    if (!existing_is_important && existing_spec_int <= specificity) {
                        should_replace = 1;
                    }
                }

                if (should_replace) {
                    rb_hash_aset(existing, ID2SYM(rb_intern("value")), value);
                    rb_hash_aset(existing, ID2SYM(rb_intern("specificity")), INT2NUM(specificity));
                    rb_hash_aset(existing, ID2SYM(rb_intern("important")), important);
                }
            }

            RB_GC_GUARD(property);
            RB_GC_GUARD(value);
            RB_GC_GUARD(decl);
        }

        RB_GC_GUARD(selector);
        RB_GC_GUARD(declarations);
        RB_GC_GUARD(rule);
    }

    // Create shorthand from longhand properties
    // For each shorthand type, check if all required properties exist and create shorthand

    // Helper macro to extract property data
    #define GET_PROP_VALUE(hash, prop_name) \
        ({ VALUE pd = rb_hash_aref(hash, rb_str_new_cstr(prop_name)); \
           NIL_P(pd) ? Qnil : rb_hash_aref(pd, ID2SYM(rb_intern("value"))); })

    #define GET_PROP_DATA(hash, prop_name) \
        rb_hash_aref(hash, rb_str_new_cstr(prop_name))

    // Try to create margin shorthand
    VALUE margin_top = GET_PROP_VALUE(properties_hash, "margin-top");
    VALUE margin_right = GET_PROP_VALUE(properties_hash, "margin-right");
    VALUE margin_bottom = GET_PROP_VALUE(properties_hash, "margin-bottom");
    VALUE margin_left = GET_PROP_VALUE(properties_hash, "margin-left");

    if (!NIL_P(margin_top) && !NIL_P(margin_right) && !NIL_P(margin_bottom) && !NIL_P(margin_left)) {
        VALUE margin_props = rb_hash_new();
        rb_hash_aset(margin_props, rb_str_new_cstr("margin-top"), margin_top);
        rb_hash_aset(margin_props, rb_str_new_cstr("margin-right"), margin_right);
        rb_hash_aset(margin_props, rb_str_new_cstr("margin-bottom"), margin_bottom);
        rb_hash_aset(margin_props, rb_str_new_cstr("margin-left"), margin_left);

        VALUE margin_shorthand = cataract_create_margin_shorthand(Qnil, margin_props);
        if (!NIL_P(margin_shorthand)) {
            // Find max specificity and check if any are important
            VALUE top_data = GET_PROP_DATA(properties_hash, "margin-top");
            VALUE margin_important = rb_hash_aref(top_data, ID2SYM(rb_intern("important")));
            int margin_spec = NUM2INT(rb_hash_aref(top_data, ID2SYM(rb_intern("specificity"))));

            // Add shorthand
            VALUE margin_data = rb_hash_new();
            rb_hash_aset(margin_data, ID2SYM(rb_intern("value")), margin_shorthand);
            rb_hash_aset(margin_data, ID2SYM(rb_intern("specificity")), INT2NUM(margin_spec));
            rb_hash_aset(margin_data, ID2SYM(rb_intern("important")), margin_important);
            rb_hash_aset(margin_data, ID2SYM(rb_intern("_struct_class")), value_struct);
            rb_hash_aset(properties_hash, rb_str_new_cstr("margin"), margin_data);

            // Remove longhand properties
            rb_hash_delete(properties_hash, rb_str_new_cstr("margin-top"));
            rb_hash_delete(properties_hash, rb_str_new_cstr("margin-right"));
            rb_hash_delete(properties_hash, rb_str_new_cstr("margin-bottom"));
            rb_hash_delete(properties_hash, rb_str_new_cstr("margin-left"));
        }
        RB_GC_GUARD(margin_props);
        RB_GC_GUARD(margin_shorthand);
    }

    // Try to create padding shorthand
    VALUE padding_top = GET_PROP_VALUE(properties_hash, "padding-top");
    VALUE padding_right = GET_PROP_VALUE(properties_hash, "padding-right");
    VALUE padding_bottom = GET_PROP_VALUE(properties_hash, "padding-bottom");
    VALUE padding_left = GET_PROP_VALUE(properties_hash, "padding-left");

    if (!NIL_P(padding_top) && !NIL_P(padding_right) && !NIL_P(padding_bottom) && !NIL_P(padding_left)) {
        VALUE padding_props = rb_hash_new();
        rb_hash_aset(padding_props, rb_str_new_cstr("padding-top"), padding_top);
        rb_hash_aset(padding_props, rb_str_new_cstr("padding-right"), padding_right);
        rb_hash_aset(padding_props, rb_str_new_cstr("padding-bottom"), padding_bottom);
        rb_hash_aset(padding_props, rb_str_new_cstr("padding-left"), padding_left);

        VALUE padding_shorthand = cataract_create_padding_shorthand(Qnil, padding_props);
        if (!NIL_P(padding_shorthand)) {
            VALUE top_data = GET_PROP_DATA(properties_hash, "padding-top");
            VALUE padding_important = rb_hash_aref(top_data, ID2SYM(rb_intern("important")));
            int padding_spec = NUM2INT(rb_hash_aref(top_data, ID2SYM(rb_intern("specificity"))));

            VALUE padding_data = rb_hash_new();
            rb_hash_aset(padding_data, ID2SYM(rb_intern("value")), padding_shorthand);
            rb_hash_aset(padding_data, ID2SYM(rb_intern("specificity")), INT2NUM(padding_spec));
            rb_hash_aset(padding_data, ID2SYM(rb_intern("important")), padding_important);
            rb_hash_aset(padding_data, ID2SYM(rb_intern("_struct_class")), value_struct);
            rb_hash_aset(properties_hash, rb_str_new_cstr("padding"), padding_data);

            rb_hash_delete(properties_hash, rb_str_new_cstr("padding-top"));
            rb_hash_delete(properties_hash, rb_str_new_cstr("padding-right"));
            rb_hash_delete(properties_hash, rb_str_new_cstr("padding-bottom"));
            rb_hash_delete(properties_hash, rb_str_new_cstr("padding-left"));
        }
        RB_GC_GUARD(padding_props);
        RB_GC_GUARD(padding_shorthand);
    }

    // Create border-width from individual sides (border-{top,right,bottom,left}-width)
    VALUE border_top_width = GET_PROP_VALUE(properties_hash, "border-top-width");
    VALUE border_right_width = GET_PROP_VALUE(properties_hash, "border-right-width");
    VALUE border_bottom_width = GET_PROP_VALUE(properties_hash, "border-bottom-width");
    VALUE border_left_width = GET_PROP_VALUE(properties_hash, "border-left-width");

    if (!NIL_P(border_top_width) && !NIL_P(border_right_width) &&
        !NIL_P(border_bottom_width) && !NIL_P(border_left_width)) {
        VALUE width_props = rb_hash_new();
        rb_hash_aset(width_props, rb_str_new_cstr("border-top-width"), border_top_width);
        rb_hash_aset(width_props, rb_str_new_cstr("border-right-width"), border_right_width);
        rb_hash_aset(width_props, rb_str_new_cstr("border-bottom-width"), border_bottom_width);
        rb_hash_aset(width_props, rb_str_new_cstr("border-left-width"), border_left_width);

        VALUE border_width_short = cataract_create_border_width_shorthand(Qnil, width_props);
        if (!NIL_P(border_width_short)) {
            VALUE data = GET_PROP_DATA(properties_hash, "border-top-width");
            VALUE prop_data = rb_hash_new();
            rb_hash_aset(prop_data, ID2SYM(rb_intern("value")), border_width_short);
            rb_hash_aset(prop_data, ID2SYM(rb_intern("specificity")), rb_hash_aref(data, ID2SYM(rb_intern("specificity"))));
            rb_hash_aset(prop_data, ID2SYM(rb_intern("important")), rb_hash_aref(data, ID2SYM(rb_intern("important"))));
            rb_hash_aset(prop_data, ID2SYM(rb_intern("_struct_class")), value_struct);
            rb_hash_aset(properties_hash, rb_str_new_cstr("border-width"), prop_data);

            rb_hash_delete(properties_hash, rb_str_new_cstr("border-top-width"));
            rb_hash_delete(properties_hash, rb_str_new_cstr("border-right-width"));
            rb_hash_delete(properties_hash, rb_str_new_cstr("border-bottom-width"));
            rb_hash_delete(properties_hash, rb_str_new_cstr("border-left-width"));
        }
        RB_GC_GUARD(width_props);
        RB_GC_GUARD(border_width_short);
    }

    // Create border-style from individual sides
    VALUE border_top_style = GET_PROP_VALUE(properties_hash, "border-top-style");
    VALUE border_right_style = GET_PROP_VALUE(properties_hash, "border-right-style");
    VALUE border_bottom_style = GET_PROP_VALUE(properties_hash, "border-bottom-style");
    VALUE border_left_style = GET_PROP_VALUE(properties_hash, "border-left-style");

    if (!NIL_P(border_top_style) && !NIL_P(border_right_style) &&
        !NIL_P(border_bottom_style) && !NIL_P(border_left_style)) {
        VALUE style_props = rb_hash_new();
        rb_hash_aset(style_props, rb_str_new_cstr("border-top-style"), border_top_style);
        rb_hash_aset(style_props, rb_str_new_cstr("border-right-style"), border_right_style);
        rb_hash_aset(style_props, rb_str_new_cstr("border-bottom-style"), border_bottom_style);
        rb_hash_aset(style_props, rb_str_new_cstr("border-left-style"), border_left_style);

        VALUE border_style_short = cataract_create_border_style_shorthand(Qnil, style_props);
        if (!NIL_P(border_style_short)) {
            VALUE data = GET_PROP_DATA(properties_hash, "border-top-style");
            VALUE prop_data = rb_hash_new();
            rb_hash_aset(prop_data, ID2SYM(rb_intern("value")), border_style_short);
            rb_hash_aset(prop_data, ID2SYM(rb_intern("specificity")), rb_hash_aref(data, ID2SYM(rb_intern("specificity"))));
            rb_hash_aset(prop_data, ID2SYM(rb_intern("important")), rb_hash_aref(data, ID2SYM(rb_intern("important"))));
            rb_hash_aset(prop_data, ID2SYM(rb_intern("_struct_class")), value_struct);
            rb_hash_aset(properties_hash, rb_str_new_cstr("border-style"), prop_data);

            rb_hash_delete(properties_hash, rb_str_new_cstr("border-top-style"));
            rb_hash_delete(properties_hash, rb_str_new_cstr("border-right-style"));
            rb_hash_delete(properties_hash, rb_str_new_cstr("border-bottom-style"));
            rb_hash_delete(properties_hash, rb_str_new_cstr("border-left-style"));
        }
        RB_GC_GUARD(style_props);
        RB_GC_GUARD(border_style_short);
    }

    // Create border-color from individual sides
    VALUE border_top_color = GET_PROP_VALUE(properties_hash, "border-top-color");
    VALUE border_right_color = GET_PROP_VALUE(properties_hash, "border-right-color");
    VALUE border_bottom_color = GET_PROP_VALUE(properties_hash, "border-bottom-color");
    VALUE border_left_color = GET_PROP_VALUE(properties_hash, "border-left-color");

    if (!NIL_P(border_top_color) && !NIL_P(border_right_color) &&
        !NIL_P(border_bottom_color) && !NIL_P(border_left_color)) {
        VALUE color_props = rb_hash_new();
        rb_hash_aset(color_props, rb_str_new_cstr("border-top-color"), border_top_color);
        rb_hash_aset(color_props, rb_str_new_cstr("border-right-color"), border_right_color);
        rb_hash_aset(color_props, rb_str_new_cstr("border-bottom-color"), border_bottom_color);
        rb_hash_aset(color_props, rb_str_new_cstr("border-left-color"), border_left_color);

        VALUE border_color_short = cataract_create_border_color_shorthand(Qnil, color_props);
        if (!NIL_P(border_color_short)) {
            VALUE data = GET_PROP_DATA(properties_hash, "border-top-color");
            VALUE prop_data = rb_hash_new();
            rb_hash_aset(prop_data, ID2SYM(rb_intern("value")), border_color_short);
            rb_hash_aset(prop_data, ID2SYM(rb_intern("specificity")), rb_hash_aref(data, ID2SYM(rb_intern("specificity"))));
            rb_hash_aset(prop_data, ID2SYM(rb_intern("important")), rb_hash_aref(data, ID2SYM(rb_intern("important"))));
            rb_hash_aset(prop_data, ID2SYM(rb_intern("_struct_class")), value_struct);
            rb_hash_aset(properties_hash, rb_str_new_cstr("border-color"), prop_data);

            rb_hash_delete(properties_hash, rb_str_new_cstr("border-top-color"));
            rb_hash_delete(properties_hash, rb_str_new_cstr("border-right-color"));
            rb_hash_delete(properties_hash, rb_str_new_cstr("border-bottom-color"));
            rb_hash_delete(properties_hash, rb_str_new_cstr("border-left-color"));
        }
        RB_GC_GUARD(color_props);
        RB_GC_GUARD(border_color_short);
    }

    // Now create border shorthand from border-{width,style,color}
    VALUE border_width = GET_PROP_VALUE(properties_hash, "border-width");
    VALUE border_style = GET_PROP_VALUE(properties_hash, "border-style");
    VALUE border_color = GET_PROP_VALUE(properties_hash, "border-color");

    if (!NIL_P(border_width) || !NIL_P(border_style) || !NIL_P(border_color)) {
        VALUE border_props = rb_hash_new();
        if (!NIL_P(border_width)) rb_hash_aset(border_props, rb_str_new_cstr("border-width"), border_width);
        if (!NIL_P(border_style)) rb_hash_aset(border_props, rb_str_new_cstr("border-style"), border_style);
        if (!NIL_P(border_color)) rb_hash_aset(border_props, rb_str_new_cstr("border-color"), border_color);

        VALUE border_shorthand = cataract_create_border_shorthand(Qnil, border_props);
        if (!NIL_P(border_shorthand)) {
            // Use first available property's metadata
            VALUE border_data_src = !NIL_P(border_width) ? GET_PROP_DATA(properties_hash, "border-width") :
                                    !NIL_P(border_style) ? GET_PROP_DATA(properties_hash, "border-style") :
                                    GET_PROP_DATA(properties_hash, "border-color");
            VALUE border_important = rb_hash_aref(border_data_src, ID2SYM(rb_intern("important")));
            int border_spec = NUM2INT(rb_hash_aref(border_data_src, ID2SYM(rb_intern("specificity"))));

            VALUE border_data = rb_hash_new();
            rb_hash_aset(border_data, ID2SYM(rb_intern("value")), border_shorthand);
            rb_hash_aset(border_data, ID2SYM(rb_intern("specificity")), INT2NUM(border_spec));
            rb_hash_aset(border_data, ID2SYM(rb_intern("important")), border_important);
            rb_hash_aset(border_data, ID2SYM(rb_intern("_struct_class")), value_struct);
            rb_hash_aset(properties_hash, rb_str_new_cstr("border"), border_data);

            if (!NIL_P(border_width)) rb_hash_delete(properties_hash, rb_str_new_cstr("border-width"));
            if (!NIL_P(border_style)) rb_hash_delete(properties_hash, rb_str_new_cstr("border-style"));
            if (!NIL_P(border_color)) rb_hash_delete(properties_hash, rb_str_new_cstr("border-color"));
        }
        RB_GC_GUARD(border_props);
        RB_GC_GUARD(border_shorthand);
    }

    #undef GET_PROP_VALUE
    #undef GET_PROP_DATA

    // Build result array by iterating properties_hash using rb_hash_foreach
    VALUE result = rb_ary_new();
    rb_hash_foreach(properties_hash, merge_build_result_callback, result);

    RB_GC_GUARD(properties_hash);
    RB_GC_GUARD(result);
    RB_GC_GUARD(rules_array);

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

    rb_define_module_function(module, "parse_css", parse_css, 1);
    rb_define_module_function(module, "calculate_specificity", calculate_specificity, 1);
    rb_define_module_function(module, "merge_rules", cataract_merge, 1);
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

    // Export string allocation mode as a constant for verification in benchmarks
    #ifdef DISABLE_STR_BUF_OPTIMIZATION
        rb_define_const(module, "STRING_ALLOC_MODE", ID2SYM(rb_intern("dynamic")));
    #else
        rb_define_const(module, "STRING_ALLOC_MODE", ID2SYM(rb_intern("buffer")));
    #endif
}

// Include shorthand_expander implementation
#include "shorthand_expander.c"

